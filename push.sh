#!/bin/bash
set -e
cd /c/Users/Ay/last-used-tracker-publish
git config --global init.defaultBranch main
git branch -m master main 2>/dev/null || true
git commit -m "init: add last-used-tracker" || true
# Store GitHub credentials
cat > /c/Users/Ay/.git-credentials <<EOF
https://pupontech:***@github.com
EOF
git config --global credential.helper store
git push -u origin main
