#!/usr/bin/env bash
# Usage: ./scripts/new-post.sh  "My Great New Post"

set -euo pipefail

# ── 1. Get the title ───────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  read -rp "Post title: " TITLE
else
  TITLE="$*"
fi

# ── 2. Build slug, paths & files ───────────────────────────────────
DATE="$(date +%Y-%m-%d)"
SLUG="$(echo "$TITLE" | iconv -t ascii//TRANSLIT |
              tr '[:upper:]' '[:lower:]' |
              sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
DIR="posts/$SLUG"
FILE="$DIR/index.qmd"
BRANCH="post/$SLUG"

if [[ -e "$DIR" ]]; then
  echo "❌  Folder $DIR already exists – aborting."
  exit 1
fi

mkdir -p "$DIR"

cat > "$FILE" <<EOF
---
title: "$TITLE"
author: "VB"
date: "$DATE"
categories: []
draft: true      # flip to false when ready
---

<!-- Start writing below this line -->
EOF

# ── 3. Create / switch to branch, commit, push ─────────────────────
git checkout -b "$BRANCH"
git add "$DIR"
git commit -m "post($SLUG): start draft"
git push -u origin "$BRANCH"

# ── 4. Open the folder in Cursor ───────────────────────────────────
# Cursor CLI is usually installed as `cursor`; fall back to `open -a`.
if command -v cursor &>/dev/null; then
  cursor "$DIR" &
else
  open -a "Cursor" "$DIR" &
fi

echo "✅  Draft ready in $DIR on branch $BRANCH."