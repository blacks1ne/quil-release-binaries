#!/usr/bin/env bash
# record.sh MESSAGE FILE...: commit FILEs to main with MESSAGE and push,
# rebasing on commits that land meanwhile; nothing when they are
# unchanged.
set -euo pipefail
msg=$1
shift
git config user.name "Black Swan"
git config user.email "q.blacks1ne@gmail.com"
git add -- "$@"
if git diff --cached --quiet; then echo "nothing to record"; exit 0; fi
git commit -q -m "$msg"
for i in 1 2 3 4 5; do
  git push -q origin HEAD && exit 0
  [ "$i" = 5 ] && break
  git pull -q --rebase origin main
done
echo "::error::could not push: $msg" >&2
exit 1
