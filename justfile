# justfile
np     TITLE="?"      # usage: just np "My title"
        ./scripts/new-post.sh {{TITLE}}

preview:
        quarto preview --watch

publish:
        ./scripts/publish.sh