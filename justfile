# justfile
# ─────────────────────────────────────────
# Usage examples
#   just np "My Cool Post"
#   just preview
#   just publish
# ─────────────────────────────────────────

# new-post
np TITLE='?' :                # ':' ← this is the bit that was missing
    ./scripts/new-post.sh "{{TITLE}}"

preview:
    quarto preview

publish:
    ./scripts/publish.sh