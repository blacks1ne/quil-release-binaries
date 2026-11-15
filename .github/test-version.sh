#!/usr/bin/env bash
# test-version.sh: fixtures for version.sh. pick and at run against a
# local git history through a stub gh. VERSION_SH overrides the script
# under test (mutation controls).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
vsh=${VERSION_SH:-$here/version.sh}
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

# expect NAME WANT CMD...: CMD prints WANT; WANT "!" means it fails.
expect() {
  local name=$1 want=$2 got rc=0
  shift 2
  got=$("$@" 2> "$w/err") || rc=$?
  if [ "$want" = "!" ]; then
    if [ "$rc" != 0 ] && grep -q '::error::' "$w/err"; then ok "$name"; else bad "$name" "want failure, got rc=$rc '$got'"; fi
  elif [ "$rc" = 0 ] && [ "$got" = "$want" ]; then ok "$name"
  else bad "$name" "want '$want', got rc=$rc '$got' $(cat "$w/err")"
  fi
}

vrs() { printf '/// Release.\npub const VERSION_STRING: &str = "%s";\n%s' "$1" "${2:-}"; }

# derive on files
d=$w/d
mkdir -p "$d"
vrs 2.1.0.25 > "$d/v"
printf '121\n' > "$d/sub"
expect "derive: subpatch" 2.1.0.25.121 bash "$vsh" derive "$d/sub" "$d/v"
expect "derive: no subpatch file" 2.1.0.25 bash "$vsh" derive "$d/none" "$d/v"
: > "$d/empty"
expect "derive: empty subpatch" 2.1.0.25 bash "$vsh" derive "$d/empty" "$d/v"
printf ' \n\n' > "$d/blank"
expect "derive: blank subpatch" 2.1.0.25 bash "$vsh" derive "$d/blank" "$d/v"
printf '12a\n' > "$d/garbage"
expect "derive: garbage subpatch fails" ! bash "$vsh" derive "$d/garbage" "$d/v"
printf '1 2\n' > "$d/spaced"
expect "derive: inner space fails" ! bash "$vsh" derive "$d/spaced" "$d/v"
echo 'pub const VERSION: [u8; 3] = [2, 1, 0];' > "$d/nov"
expect "derive: no VERSION_STRING fails" ! bash "$vsh" derive "$d/sub" "$d/nov"
vrs 2.1.0.25 'pub const VERSION_STRING: &str = "2.1.0.26";' > "$d/two"
expect "derive: two VERSION_STRINGs fail" ! bash "$vsh" derive "$d/sub" "$d/two"
vrs 'two.1' > "$d/word"
expect "derive: garbage VERSION_STRING fails" ! bash "$vsh" derive "$d/sub" "$d/word"
expect "derive: missing version.rs fails" ! bash "$vsh" derive "$d/sub" "$d/missing"

# Stub gh: answers the endpoints version.sh uses from git repo $FIX.
mkdir -p "$w/bin"
cat > "$w/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cd "$FIX"
[ "$1" = api ] || { echo "stub gh: $*" >&2; exit 2; }
shift
jqx= ep=
while [ $# -gt 0 ]; do
  case $1 in
    -H) shift 2 ;;
    --jq) jqx=$2; shift 2 ;;
    *) ep=$1; shift ;;
  esac
done
out() { if [ -n "$jqx" ]; then jq -r "$jqx"; else cat; fi; }
nf() { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
commit() { git rev-parse -q --verify "$1^{commit}" > /dev/null || nf; }
ep=${ep#repos/up/x/}
case $ep in
  contents/*)
    p=${ep#contents/}; ref=${p#*\?ref=}; p=${p%%\?*}
    commit "$ref"; git cat-file -e "$ref:$p" 2> /dev/null || nf; git show "$ref:$p" ;;
  commits\?*)
    q=${ep#commits?}; b= path= n=30
    IFS='&' read -ra kv <<< "$q"
    for x in "${kv[@]}"; do
      case $x in sha=*) b=${x#sha=} ;; path=*) path=${x#path=} ;; per_page=*) n=${x#per_page=} ;; esac
    done
    git log -n "$n" --format='%H %P' "$b" -- "$path" \
      | jq -Rn '[inputs | split(" ") | {sha: .[0], parents: [.[1:][] | select(. != "") | {sha: .}]}]' | out ;;
  commits/*/pulls)
    s=${ep#commits/}; s=${s%/pulls}; commit "$s"
    if git rev-list --first-parent "$FIX_BRANCH" | grep -qx "$s"; then echo '[]' | out
    else
      mc=$(git rev-list --first-parent --ancestry-path "$s..$FIX_BRANCH" | tail -1)
      jq -n --arg mc "$mc" --arg b "$FIX_BRANCH" '[{merged_at: "2026-01-01T00:00:00Z", base: {ref: $b}, merge_commit_sha: $mc}]' | out
    fi ;;
  commits/*)
    s=${ep#commits/}; commit "$s"
    git log -1 --format='%H %P' "$s" \
      | jq -R 'split(" ") | {sha: .[0], parents: [.[1:][] | select(. != "") | {sha: .}]}' | out ;;
  compare/*)
    r=${ep#compare/}; a=${r%%...*}; b=${r#*...}; commit "$a"; commit "$b"
    if [ "$(git rev-parse "$a")" = "$(git rev-parse "$b")" ]; then st=identical
    elif git merge-base --is-ancestor "$a" "$b"; then st=ahead
    elif git merge-base --is-ancestor "$b" "$a"; then st=behind
    else st=diverged; fi
    jq -n --arg s "$st" '{status: $s}' | out ;;
  *) echo "stub gh: unknown endpoint $ep" >&2; exit 2 ;;
esac
STUB
chmod +x "$w/bin/gh"

export FIX=$w/up
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$FIX" "$@"; }
c() { g add -A; g commit -q -m "$1"; g rev-parse HEAD; }
V=crates/quil-config/src/version.rs
mkdir -p "$FIX/crates/quil-config/src"
g init -q -b rel

vrs 2.1.0.25 > "$FIX/$V"; echo 120 > "$FIX/subpatch"; c init > /dev/null
echo a > "$FIX/a"; c other > /dev/null
echo 121 > "$FIX/subpatch"; c1=$(c "bump subpatch")
echo b > "$FIX/a"; c other > /dev/null
g branch s-sub
vrs 2.1.0.25 '// formatted' > "$FIX/$V"; c fmt > /dev/null
g branch s-fmt
vrs 2.1.0.26 '// formatted' > "$FIX/$V"; c2=$(c "VERSION_STRING only")
g branch s-vs
g rm -q subpatch; c3=$(c "drop subpatch")
g branch s-nosub
g checkout -q -b pr
vrs 2.1.0.27 > "$FIX/$V"; c pr-version > /dev/null
g checkout -q rel
echo c > "$FIX/a"; c other > /dev/null
g merge -q --no-ff -m "Merge pull request" pr; c4=$(g rev-parse HEAD)
g branch s-merge
printf '12a\n' > "$FIX/subpatch"; c5=$(c "garbage subpatch")

run() { FIX_BRANCH=$1 PATH="$w/bin:$PATH" bash "$vsh" "${@:2}"; }
expect "pick: subpatch bump" "$c1" run s-sub pick up/x s-sub
expect "at: subpatch bump" 2.1.0.25.121 run s-sub at up/x "$c1"
expect "pick: version.rs touch without a version change" "$c1" run s-fmt pick up/x s-fmt
expect "pick: VERSION_STRING-only bump" "$c2" run s-vs pick up/x s-vs
expect "at: VERSION_STRING-only bump" 2.1.0.26.121 run s-vs at up/x "$c2"
expect "pick: subpatch file removed" "$c3" run s-nosub pick up/x s-nosub
expect "at: no subpatch file" 2.1.0.26 run s-nosub at up/x "$c3"
expect "pick: merged pull request" "$c4" run s-merge pick up/x s-merge
expect "at: merged pull request" 2.1.0.27 run s-merge at up/x "$c4"
expect "pick: garbage subpatch" "$c5" run rel pick up/x rel
expect "at: garbage subpatch fails" ! run rel at up/x "$c5"
expect "at: unknown commit fails" ! run rel at up/x 0000000000000000000000000000000000000000

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
