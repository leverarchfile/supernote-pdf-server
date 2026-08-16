#!/usr/bin/env bash
# Converts changed Supernote .note files to PDFs and optionally archives
# orphaned PDFs. Calls generate-index-page.sh at the end to rebuild the
# HTML index page. Runs every minute via cron.
#
# Crontab entry:
#   * * * * * /path/to/supernote-pdf-convert.sh
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

# Logging (no-op when disabled)
_log() {
    [ "${LOGGING_ENABLED:-true}" = true ] || return 0
    [ -n "${LOG:-}" ] || return 0
    printf '[%s] %-10s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG"
}

# Append captured command output (stderr) to the log, indented, so a failure
# records why it failed rather than just that it failed.
_log_detail() {
    [ "${LOGGING_ENABLED:-true}" = true ] || return 0
    [ -n "${LOG:-}" ] || return 0
    [ -s "$1" ] || return 0
    tail -n 15 "$1" | sed 's/^/    /' >> "$LOG"
}

# Errors go to both stderr and the log; under cron, stderr is discarded.
_err() {
    printf 'Error: %s\n' "$1" >&2
    _log "ERROR" "$1"
}

# Preflight checks
_preflight_error=0
_require_file() {
    if [ ! -f "$1" ]; then
        _err "required file not found: $1"
        _preflight_error=1
    fi
}

_require_file "$SN_TOOL"

# ImageMagick 7 ships 'magick', ImageMagick 6 ships 'convert'.
IM=$(command -v magick || command -v convert)
if [ -z "$IM" ]; then
    _err "required command not found: magick or convert (ImageMagick)"
    _preflight_error=1
fi

[ "$_preflight_error" -eq 0 ] || exit 1

(
# Stop silently if another instance is already running.
flock -x -n 200 || exit 0

[ -d "$NOTE_DIR" ] || { _err "NOTE_DIR not found: $NOTE_DIR"; exit 1; }
mkdir -p "$PDF_DIR"

# Build the ImageMagick color-substitution arguments.
# If BG_COLOR is white, skip substitution entirely.
_imagick_color_args=()
if [ "${BG_COLOR:-#d0d0d0}" != "#ffffff" ]; then
    _imagick_color_args=(-fuzz 2% -fill "${BG_COLOR:-#d0d0d0}" -opaque white)
fi

# Build the supernote-tool link flag.
_sn_link_flag=()
if [ "${STRIP_LINKS:-true}" = true ]; then
    _sn_link_flag=(--no-link)
fi

# Convert .note files that are newer than their corresponding PDF.
find "$NOTE_DIR" -name '*.note' -print0 | while IFS= read -r -d '' note; do
    rel="${note#"$NOTE_DIR"/}"               # relative path, preserving subdirs
    pdf="$PDF_DIR/${rel%.note}.pdf"          # mirror structure, swap extension
    marker="${pdf}.failed"                   # records a previous failed attempt

    [ "$note" -nt "$pdf" ] || continue       # skip if PDF is up to date

    # A previous run already failed on this exact version of the note; retry
    # only once the note itself changes, so a broken note is logged once
    # rather than every minute. Delete the marker to force a retry.
    [ -e "$marker" ] && ! [ "$note" -nt "$marker" ] && continue

    mkdir -p "$(dirname "$pdf")"

    # Write to a temp file in the same directory so the final mv is atomic,
    # preventing Syncthing or the web server from seeing a partial PDF.
    pdf_tmp=$(mktemp "${pdf}.tmp.XXXXXX")

    # stderr is captured rather than discarded so failures can be diagnosed
    # from the log. timeout stops a hung command from holding the lock.
    tmpdir=$(mktemp -d)
    err="$tmpdir/stderr"
    # The output argument must be a filename ending in .png, not a directory:
    # supernote-tool derives each page's name from it with os.path.splitext,
    # inserting _<n> before the extension (page_00.png, page_01.png, ...).
    # -t png does not supply an extension, so a bare directory would yield
    # extensionless files named _00, _01, ... and the *.png glob below would
    # match nothing.
    timeout 300 "$SN_TOOL" convert -t png -a "${_sn_link_flag[@]}" \
        "$note" "$tmpdir/page.png" >/dev/null 2>"$err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        timeout 300 "$IM" "$tmpdir"/*.png -density "${DENSITY:-232}" \
            "${_imagick_color_args[@]}" "$pdf_tmp" >/dev/null 2>"$err"
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        mv "$pdf_tmp" "$pdf" 2>"$err"
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        rm -f "$marker"
        _log "converted" "$rel"
    else
        rm -f "$pdf_tmp"
        touch -r "$note" "$marker"           # marker carries the note's mtime
        if [ "$rc" -eq 124 ]; then
            _log "TIMEOUT" "$rel"
        else
            _log "ERROR" "$rel"
            _log_detail "$err"
        fi
    fi
    rm -rf "$tmpdir"
done

# Handle orphaned PDFs (source .note no longer exists).
find "$PDF_DIR" -name '*.pdf' -print0 | while IFS= read -r -d '' pdf; do
    rel="${pdf#"$PDF_DIR"/}"
    [ -f "$NOTE_DIR/${rel%.pdf}.note" ] && continue

    if [ "${ARCHIVE_ENABLED:-true}" = true ]; then
        mkdir -p "$ARCHIVE_PDF_DIR"
        archive_dest="$ARCHIVE_PDF_DIR/$rel"
        mkdir -p "$(dirname "$archive_dest")"
        mv "$pdf" "$archive_dest"
        _log "archived" "$rel"
    else
        rm -f "$pdf"
        _log "removed" "$rel"
    fi
done

# Drop failure markers whose source .note no longer exists.
find "$PDF_DIR" -name '*.pdf.failed' -print0 | while IFS= read -r -d '' marker; do
    rel="${marker#"$PDF_DIR"/}"
    [ -f "$NOTE_DIR/${rel%.pdf.failed}.note" ] || rm -f "$marker"
done

# Remove temp files left behind by a run that was killed mid-conversion.
find "$PDF_DIR" -name '*.pdf.tmp.*' -mmin +60 -delete

find "$PDF_DIR" -mindepth 1 -type d -empty -delete

# Regenerate the HTML index page.
"$SCRIPT_DIR/generate-index-page.sh"

) 200>/tmp/supernote-pdf-convert.lock
