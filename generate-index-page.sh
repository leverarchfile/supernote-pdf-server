#!/usr/bin/env bash
# Generates a static HTML index page for a directory of PDFs.
# Links open each PDF in the bundled PDF.js viewer (for mobile compatibility).
# Called automatically by supernote-pdf-convert.sh, but can also be run
# directly to force a rebuild of the index page.
#
# See supernote-pdf-server.conf.example for configuration and setup instructions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/supernote-pdf-server.conf"

# Load configuration
if [ ! -f "$CONF" ]; then
    printf 'Error: config file not found: %s\n' "$CONF" >&2
    printf 'Copy supernote-pdf-server.conf.example to supernote-pdf-server.conf and edit it.\n' >&2
    exit 1
fi
# shellcheck source=supernote-pdf-server.conf
. "$CONF"

if [ ! -d "$PDF_DIR" ]; then
    printf 'Error: PDF_DIR not found: %s\n' "$PDF_DIR" >&2
    exit 1
fi

tmp="$PDF_DIR/.index.tmp"
{
cat <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Notes</title>
<style>
  body {
    font-family: sans-serif;
    max-width: 720px;
    margin: 0 auto;
    padding: 1.5rem 1rem;
    color: #222;
  }
  h1 { margin-top: 0; }
  a {
    display: block;
    padding: 0.5rem 0.25rem;
    color: #2563eb;
    text-decoration: none;
    border-bottom: 1px solid #e5e7eb;
  }
  a:hover { color: #1d4ed8; text-decoration: underline; }
  .meta {
    color: #999;
    font-size: 0.75rem;
    margin-top: 2rem;
  }
</style>
</head>
<body>
<h1>Notes</h1>
HTML

# Links sorted alphabetically, routed through the bundled PDF.js viewer.
# The viewer is at pdfjs/web/viewer.html; ../../ goes back up to PDF_DIR root.
# Note: sort -z is GNU-specific and requires a Linux system.
find "$PDF_DIR" -name '*.pdf' -print0 | sort -z | while IFS= read -r -d '' pdf; do
    rel="${pdf#"$PDF_DIR"/}"
    # URL-encode the relative path for use as the ?file= query parameter.
    encoded=$(printf '%s' "$rel" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g; s/&/%26/g')
    href="pdfjs/web/viewer.html?file=../../${encoded}"
    # HTML-escape the display name (strip .pdf extension).
    display=$(printf '%s' "${rel%.pdf}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    printf '<a href="%s" target="_blank">%s</a>\n' "$href" "$display"
done

printf '<p class="meta">Last updated: %s</p>\n' "$(date '+%Y-%m-%d %H:%M')"

cat <<'HTML'
</body>
</html>
HTML
} > "$tmp"
mv "$tmp" "$PDF_DIR/index.html"
