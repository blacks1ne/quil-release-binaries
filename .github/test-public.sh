#!/usr/bin/env bash
# test-public.sh: fixtures for public.sh. Listings are local directories
# read through file:// URLs; detect reads upstream through a stub gh and
# a stub version.sh. PUBLIC_SH overrides the script under test (mutation
# controls).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
psh=${PUBLIC_SH:-$here/public.sh}
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

dg() { printf '%s%s' "$1" "$(printf '%0*d' 64 0)" | sha256sum | cut -c1-64; }

# listing DIR VERSION [SALT]: a well-formed listing of node and qclient
# for two platforms; SALT changes every digest.
listing() {
  local d=$1 v=$2 salt=${3:-} k p f n
  rm -rf "$d"
  mkdir -p "$d"
  for k in node qclient; do
    n=$d/release
    [ "$k" = node ] || n=$d/qclient-release
    : > "$n"
    for p in darwin-arm64 linux-amd64; do
      f=$k-$v-$p
      printf '%s\n%s.dgst\n%s.dgst.sig.1\n%s.dgst.sig.13\n' "$f" "$f" "$f" "$f" >> "$n"
      printf 'SHA3-256(%s)= %s\n' "$f" "$(dg "$f$salt")" > "$d/$f.dgst"
    done
  done
}
pm() { bash "$psh" manifest "file://$1"; }

L=$w/l
listing "$L" 2.1.0.25
want=$(for f in node-2.1.0.25-darwin-arm64 node-2.1.0.25-linux-amd64 qclient-2.1.0.25-darwin-arm64 qclient-2.1.0.25-linux-amd64; do echo "$f $(dg "$f")"; done)
expect "manifest: well-formed listing" "$want" pm "$L"
sed -i 's/$/\r/' "$L/release" "$L/node-2.1.0.25-linux-amd64.dgst"
expect "manifest: CRLF line ends" "$want" pm "$L"

# Malformed listings fail.
listing "$L" 2.1.0.25
echo '<html>not found</html>' >> "$L/release"
expect "manifest: malformed listing line fails" ! pm "$L"
listing "$L" 2.1.0.25
echo 'qclient-2.1.0.25-linux-amd64' >> "$L/release"
expect "manifest: qclient in the node listing fails" ! pm "$L"
listing "$L" 2.1.0.25
: > "$L/qclient-release"
expect "manifest: empty listing fails" ! pm "$L"
listing "$L" 2.1.0.25
rm "$L/release"
expect "manifest: missing listing fails" ! pm "$L"
listing "$L" 2.1.0.25
sed -i '/^node-2.1.0.25-linux-amd64.dgst$/d' "$L/release"
expect "manifest: binary without a listed digest fails" ! pm "$L"
listing "$L" 2.1.0.25
rm "$L/node-2.1.0.25-linux-amd64.dgst"
expect "manifest: missing digest file fails" ! pm "$L"
listing "$L" 2.1.0.25
echo 'SHA3-256(node-2.1.0.25-linux-amd64)= 12ab' > "$L/node-2.1.0.25-linux-amd64.dgst"
expect "manifest: short digest fails" ! pm "$L"
listing "$L" 2.1.0.25
cp "$L/node-2.1.0.25-darwin-arm64.dgst" "$L/node-2.1.0.25-linux-amd64.dgst"
expect "manifest: digest of another file fails" ! pm "$L"
listing "$L" 2.1.0.25
printf '<html>moved</html>\n' > "$L/qclient-2.1.0.25-darwin-arm64.dgst"
expect "manifest: digest file not a digest line fails" ! pm "$L"
listing "$L" 2.1.0.25
sed -n 1,4p "$L/release" > "$w/dup"
cat "$w/dup" >> "$L/release"
expect "manifest: binary listed twice fails" ! pm "$L"

# version
m=$w/m
listing "$L" 2.1.0.25
pm "$L" > "$m"
expect "version: node version" 2.1.0.25 bash "$psh" version "$m"
sed '1s/2\.1\.0\.25/2.1.0.26/' "$m" > "$w/m2"
expect "version: two node versions fail" ! bash "$psh" version "$w/m2"
grep '^qclient' "$m" > "$w/m3"
expect "version: no node binary fails" ! bash "$psh" version "$w/m3"

# changed: the recorded state against a fresh manifest.
cp "$m" "$w/state"
expect "changed: unchanged digests" same bash "$psh" changed "$w/state" "$m"
printf '\n' >> "$w/state"
expect "changed: blank lines ignored" same bash "$psh" changed "$w/state" "$m"
listing "$L" 2.1.0.25 rebuilt
pm "$L" > "$w/new"
expect "changed: digest changed, same version" changed bash "$psh" changed "$w/state" "$w/new"
sed '1s/ .*/ '"$(dg rebuilt)"'/' "$m" > "$w/one"
expect "changed: one digest changed" changed bash "$psh" changed "$w/state" "$w/one"
expect "changed: no state yet" changed bash "$psh" changed "$w/none" "$m"
echo 'garbage' > "$w/bad"
expect "changed: malformed state fails" ! bash "$psh" changed "$w/bad" "$m"
: > "$w/empty"
expect "changed: empty manifest fails" ! bash "$psh" changed "$w/state" "$w/empty"

# target
T=1111111111111111111111111111111111111111
printf 'v2.1.0.25.121 %s 2026-11-14T19:45:00Z\n' 2222222222222222222222222222222222222222 > "$w/released"
expect "target: tip at the public version plus subpatch" follow bash "$psh" target 2.1.0.25 "$T" 2.1.0.25.122 "$w/released"
expect "target: tip at the public version" follow bash "$psh" target 2.1.0.25 "$T" 2.1.0.25 "$w/released"
expect "target: tip at a newer VERSION_STRING" notice bash "$psh" target 2.1.0.25 "$T" 2.1.0.26.1 "$w/released"
expect "target: tip at a version that only shares a prefix" notice bash "$psh" target 2.1.0.25 "$T" 2.1.0.250 "$w/released"
expect "target: tip older than the public version" notice bash "$psh" target 2.1.0.26 "$T" 2.1.0.25.122 "$w/released"
printf 'v2.1.0.25.122 %s 2026-11-17T12:28:44Z\n' "$T" >> "$w/released"
expect "target: tip already released" record bash "$psh" target 2.1.0.25 "$T" 2.1.0.25.122 "$w/released"
expect "target: bad tip fails" ! bash "$psh" target 2.1.0.25 1234 2.1.0.25.122 "$w/released"

# detect, through a stub gh and version.sh.
mkdir -p "$w/bin"
cat > "$w/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2 $3 $4" = "api repos/up/x/commits/develop --jq .sha" ] || { echo "stub gh: $*" >&2; exit 2; }
echo "$TIP"
STUB
cat > "$w/vsh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2 $3" = "at up/x $TIP" ] || { echo "::error::stub version.sh: $*" >&2; exit 1; }
echo "$TIP_VERSION"
STUB
chmod +x "$w/bin/gh"
det() { PATH="$w/bin:$PATH" VERSION_SH=$w/vsh TIP=$T TIP_VERSION=$1 bash "$psh" detect "file://$L" "$w/state" "$w/released" up/x develop "$w/out"; }
listing "$L" 2.1.0.25
pm "$L" > "$w/state"
expect "detect: unchanged listing builds nothing" "same 2.1.0.25" det 2.1.0.25.123
expect "detect: writes the manifest" "$(cat "$w/state")" cat "$w/out"
listing "$L" 2.1.0.25 rebuilt
T=3333333333333333333333333333333333333333
expect "detect: rebuilt binaries, same version" "follow 2.1.0.25 $T 2.1.0.25.123" det 2.1.0.25.123
expect "detect: tip at another version" "notice 2.1.0.25 $T 2.1.0.26" det 2.1.0.26
echo '<html>' >> "$L/release"
expect "detect: malformed listing fails" ! det 2.1.0.25.123
listing "$L" 2.1.0.25 rebuilt
expect "detect: tip without a version fails" ! det ''

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
