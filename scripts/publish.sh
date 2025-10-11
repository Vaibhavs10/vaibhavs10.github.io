#!/usr/bin/env bash
set -e
git add .
git commit -m "${1:-chore: publish}" || true   # no error if nothing to commit
git push origin main
echo "🚀  Pushed. GitHub Pages will rebuild in ~1 min."
