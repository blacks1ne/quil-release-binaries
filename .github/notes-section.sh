#!/usr/bin/env bash
# notes-section.sh VERSION: print the release-notes section for VERSION
# (notes/<VERSION>.md without its first line, the version), or nothing.
set -euo pipefail
f="notes/$1.md"
[ -s "$f" ] || exit 0
printf '\n<!-- notes -->\n## Release notes\n\n'
tail -n +2 "$f" | sed -e '/./,$!d'
