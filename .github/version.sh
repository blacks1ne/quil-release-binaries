#!/usr/bin/env bash
# version.sh: an upstream commit's release version, and the commit to
# build. The version mirrors crates/quil-config/build.rs: VERSION_STRING,
# plus ".<subpatch>" unless the subpatch file is missing or blank;
# anything else fails.
#
#   version.sh derive SUBPATCH_FILE VERSION_RS   version from two files
#   version.sh at UPSTREAM SHA                   version at SHA
#   version.sh pick UPSTREAM BRANCH              newest commit on BRANCH
#       that changes subpatch or VERSION_STRING; a side commit of a
#       merged pull request maps to its merge commit
#
# at and pick read UPSTREAM through gh api.
set -euo pipefail

VRS=crates/quil-config/src/version.rs
die() { echo "::error::$*" >&2; exit 1; }

derive() {
  local sub="" base
  if [ -e "$1" ]; then
    sub=$(<"$1")
    sub=${sub#"${sub%%[![:space:]]*}"}
    sub=${sub%"${sub##*[![:space:]]}"}
    [[ -z $sub || $sub =~ ^[0-9]+$ ]] || die "subpatch is not a number: '$sub'"
  fi
  base=$(sed -n 's/^pub const VERSION_STRING: &str = "\(.*\)";$/\1/p' "$2" 2>/dev/null || true)
  [[ $base =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "no single VERSION_STRING in $VRS: '$base'"
  echo "$base${sub:+.$sub}"
}

# fetch PATH REF: PATH at REF into $tmp/<name>; nothing when absent.
fetch() {
  local out
  out="$tmp/$(basename "$1")"
  rm -f "$out"
  if gh api -H 'Accept: application/vnd.github.raw' "repos/$U/contents/$1?ref=$2" > "$out" 2> "$tmp/err"; then
    return 0
  fi
  rm -f "$out"
  grep -q 'HTTP 404' "$tmp/err" || { cat "$tmp/err" >&2; die "cannot read $1 at $2"; }
}

at() {
  fetch subpatch "$1"
  fetch "$VRS" "$1"
  derive "$tmp/subpatch" "$tmp/version.rs"
}

# key PATH REF: the part of PATH the version reads.
key() {
  local f
  f="$tmp/$(basename "$1")"
  fetch "$1" "$2"
  if [ ! -e "$f" ]; then echo absent
  elif [ "$1" = subpatch ]; then echo "=$(<"$f")"
  else echo "=$(sed -n '/VERSION_STRING: &str/p' "$f")"
  fi
}

# last_change PATH: newest of the last 30 commits touching PATH that
# changes its key; nothing if none of fewer than 30 does.
last_change() {
  local list sha parent prev n=0
  list=$(gh api "repos/$U/commits?sha=$B&path=$1&per_page=30" --jq '.[] | "\(.sha) \(.parents[0].sha // "")"')
  while read -r sha parent; do
    [ -n "$sha" ] || continue
    n=$((n + 1))
    prev=absent
    if [ -n "$parent" ]; then prev=$(key "$1" "$parent"); fi
    if [ "$(key "$1" "$sha")" != "$prev" ]; then echo "$sha"; return 0; fi
  done <<< "$list"
  [ "$n" -lt 30 ] || die "none of the last 30 commits touching $1 on $B changes it"
}

# landed SHA: the merge commit that brought SHA onto BRANCH, else SHA.
landed() {
  local mc parents
  mc=$(gh api "repos/$U/commits/$1/pulls" --jq "[.[] | select(.merged_at != null and .base.ref == \"$B\")][0].merge_commit_sha // \"\"")
  if [ -n "$mc" ] && [ "$mc" != "$1" ]; then
    parents=$(gh api "repos/$U/commits/$mc" --jq '.parents | length')
    if [ "$parents" -gt 1 ]; then echo "$mc"; return 0; fi
  fi
  echo "$1"
}

pick() {
  local s v status
  s=$(last_change subpatch)
  v=$(last_change "$VRS")
  if [ -n "$s" ]; then s=$(landed "$s"); fi
  if [ -n "$v" ]; then v=$(landed "$v"); fi
  if [ -z "$s$v" ]; then die "no commit on $B changes subpatch or VERSION_STRING"; fi
  if [ -z "$v" ] || [ "$s" = "$v" ]; then echo "$s"; return 0; fi
  if [ -z "$s" ]; then echo "$v"; return 0; fi
  status=$(gh api "repos/$U/compare/$s...$v" --jq .status)
  case $status in
    ahead) echo "$v" ;;
    behind) echo "$s" ;;
    *) die "cannot order $s and $v on $B: $status" ;;
  esac
}

cmd=${1:-}
case $cmd in
  derive) [ $# = 3 ] || die "usage: version.sh derive SUBPATCH_FILE VERSION_RS"; derive "$2" "$3" ;;
  at|pick)
    [ $# = 3 ] || die "usage: version.sh $cmd UPSTREAM SHA|BRANCH"
    U=$2
    B=$3
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    "$cmd" "$3"
    ;;
  *) die "usage: version.sh derive|at|pick ..." ;;
esac
