#!/bin/bash
# ================================================================
# Run this to push Zynr.Cloud v5.1.0 to your GitHub
# Usage: bash PUSH_TO_GITHUB.sh ghp_yourTokenHere
# ================================================================

TOKEN="${1:?Usage: bash PUSH_TO_GITHUB.sh ghp_yourTokenHere}"
REPO="XDgamer100/zynr"
DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR"
git remote add origin "https://${TOKEN}@github.com/${REPO}.git" 2>/dev/null || \
  git remote set-url origin "https://${TOKEN}@github.com/${REPO}.git"

echo "Pushing Zynr.Cloud v5.1.0 to github.com/$REPO ..."
git push -u origin main --force

echo ""
echo "[OK] Done! Check: https://github.com/$REPO"
