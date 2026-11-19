#!/usr/bin/env bash
# public.sh: the official release listing as a manifest, and what a
# change in it builds. The listing is BASE/release (node) and
# BASE/qclient-release: one file name per line, each binary followed by
# its <file>.dgst ("SHA3-256(<file>)= <hex>") and .dgst.sig.<n> files.
#
#   public.sh manifest BASE      one "<file> <sha3-256>" line per listed
#       binary, sorted; a listing or digest file that cannot be read or
#       is malformed fails
#   public.sh version MANIFEST   the version of its node binaries
#   public.sh changed STATE NEW  "changed" unless STATE (absent: empty)
#       lists the same files with the same digests as NEW, else "same"
#   public.sh target PUBLIC TIP_SHA TIP_VERSION RELEASED   what a changed
#       listing builds: "record" when RELEASED has a release built at
#       TIP_SHA, "follow" when TIP_VERSION is PUBLIC or PUBLIC.<subpatch>,
#       else "notice"
#   public.sh detect BASE STATE RELEASED UPSTREAM BRANCH NEW   writes the
#       manifest to NEW and prints "same <public version>" or
#       "<target> <public version> <tip> <tip version>" for BRANCH's tip
#
# detect reads UPSTREAM through gh api and version.sh (VERSION_SH
# overrides it).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
die() { echo "::error::$*" >&2; exit 1; }
VER='[0-9]+(\.[0-9]+)+'
LINE_RE="^(node|qclient)-$VER-[a-z0-9]+-[a-z0-9]+ [0-9a-f]{64}\$"
DGST_RE='^SHA3-256\(([^)]*)\)= ([0-9a-f]{64})$'

get() { curl -fsS --max-time 60 --retry 2 "$1" || die "cannot read $1"; }

manifest() {
  local base=$1 list kind body f d bins=() dgsts=() out=()
  for list in release qclient-release; do
    kind=node
    [ "$list" = release ] || kind=qclient
    body=$(get "$base/$list")
    bins=() dgsts=()
    while IFS= read -r f || [ -n "$f" ]; do
      f=${f%$'\r'}
      [ -n "$f" ] || continue
      if [[ $f =~ ^$kind-$VER-[a-z0-9]+-[a-z0-9]+$ ]]; then bins+=("$f")
      elif [[ $f =~ ^$kind-$VER-[a-z0-9]+-[a-z0-9]+\.dgst$ ]]; then dgsts+=("${f%.dgst}")
      elif [[ ! $f =~ ^$kind-$VER-[a-z0-9]+-[a-z0-9]+\.dgst\.sig\.[0-9]+$ ]]; then
        die "$list lists '$f', not a $kind release file"
      fi
    done <<< "$body"
    [ "${#bins[@]}" -gt 0 ] || die "$list lists no $kind binary"
    for f in "${bins[@]}"; do
      printf '%s\n' "${dgsts[@]}" | grep -qxF -- "$f" || die "$list lists $f without $f.dgst"
      d=$(get "$base/$f.dgst")
      d=${d%$'\r'}
      [[ $d =~ $DGST_RE ]] || die "$f.dgst is not a SHA3-256 digest line: '${d:0:120}'"
      [ "${BASH_REMATCH[1]}" = "$f" ] || die "$f.dgst names ${BASH_REMATCH[1]}"
      out+=("$f ${BASH_REMATCH[2]}")
    done
  done
  printf '%s\n' "${out[@]}" | LC_ALL=C sort -u > "$tmp/m"
  [ "$(wc -l < "$tmp/m")" = "${#out[@]}" ] || die "the listings name a binary twice"
  cat "$tmp/m"
}

# lines FILE: FILE's non-empty lines, each a manifest line.
lines() {
  local l
  [ -e "$1" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    [ -n "$l" ] || continue
    [[ $l =~ $LINE_RE ]] || die "$1 has a malformed line: '${l:0:120}'"
    printf '%s\n' "$l"
  done < "$1"
}

version() {
  local vs
  vs=$(lines "$1" | sed -n 's/^node-\([0-9.]*\)-[a-z0-9]*-[a-z0-9]* .*/\1/p' | sort -u)
  [ -n "$vs" ] || die "$1 lists no node binary"
  [ "$(wc -l <<< "$vs")" = 1 ] || die "$1 lists node binaries of more than one version: $(tr '\n' ' ' <<< "$vs")"
  echo "$vs"
}

changed() {
  local old new
  old=$(lines "$1")
  new=$(lines "$2")
  [ -n "$new" ] || die "$2 lists no binary"
  if [ "$old" = "$new" ]; then echo same; else echo changed; fi
}

target() {
  local p=$1 sha=$2 v=$3 released=$4
  [[ $p =~ ^$VER$ ]] || die "public version '$p' is not a version"
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || die "tip '$sha' is not a commit hash"
  [[ $v =~ ^$VER$ ]] || die "tip version '$v' is not a version"
  if [ -e "$released" ] && awk -v s="$sha" '$2 == s {f = 1} END {exit !f}' "$released"; then echo record
  elif [ "$v" = "$p" ] || [[ $v == "$p".* && ${v#"$p".} =~ ^[0-9]+$ ]]; then echo follow
  else echo notice
  fi
}

detect() {
  local base=$1 state=$2 released=$3 up=$4 branch=$5 new=$6 pv c tip tv t
  manifest "$base" > "$new"
  pv=$(version "$new")
  c=$(changed "$state" "$new")
  if [ "$c" = same ]; then echo "same $pv"; return 0; fi
  tip=$(gh api "repos/$up/commits/$branch" --jq .sha)
  tv=$(bash "${VERSION_SH:-$here/version.sh}" at "$up" "$tip")
  t=$(target "$pv" "$tip" "$tv" "$released")
  echo "$t $pv $tip $tv"
}

cmd=${1:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case $cmd in
  manifest) [ $# = 2 ] || die "usage: public.sh manifest BASE"; manifest "$2" ;;
  version) [ $# = 2 ] || die "usage: public.sh version MANIFEST"; version "$2" ;;
  changed) [ $# = 3 ] || die "usage: public.sh changed STATE NEW"; changed "$2" "$3" ;;
  target) [ $# = 5 ] || die "usage: public.sh target PUBLIC TIP_SHA TIP_VERSION RELEASED"; target "$2" "$3" "$4" "$5" ;;
  detect) [ $# = 7 ] || die "usage: public.sh detect BASE STATE RELEASED UPSTREAM BRANCH NEW"; detect "${@:2}" ;;
  *) die "usage: public.sh manifest|version|changed|target|detect ..." ;;
esac
