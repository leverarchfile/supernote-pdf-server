# supernote-pdf-server

A self-hosted pipeline for Supernote users who want to access their notes as PDFs on other devices. It uses [supernote-tool](https://github.com/jya-dev/supernote-tool) to convert `.note` files to PDFs automatically, and serves them via a web interface with a bundled [PDF.js](https://github.com/mozilla/pdf.js) viewer, giving automated, self-hosted access to your notes from any browser.

Conversion is incremental: only `.note` files that have changed or been added since the last run are converted, so the cron job is lightweight even with a large note library.

**Flow:** Supernote device → sync to server → PDF conversion → web server → browser

## Features

- Converts `.note` files that are new or have changed since the last run
- Mirrors source directory structure
- Grey background post-processing for reduced eye strain, closer to the e-ink appearance (configurable)
- PDF.js viewer bundled for in-browser viewing (some mobile browsers download PDFs rather than displaying them inline; PDF.js solves this)
- Static HTML index page auto-generated after each conversion run
- Orphaned PDF archiving when `.note` files are moved or deleted
- Concurrency guard prevents overlapping cron runs

## Requirements

- Linux (uses `flock`, `sort -z`, and other GNU utilities)
- [supernote-tool](https://github.com/jya-dev/supernote-tool) — install via uv, pipx, or a manual venv
- ImageMagick (`convert`)
- A web server that can serve static files (Caddy, nginx, Apache, etc.)
- A way to sync `.note` files to the server (Syncthing, rsync, etc.)

## Installation

**1. Clone the repository:**

```bash
git clone https://github.com/yourusername/supernote-pdf-server.git
cd supernote-pdf-server
```

**2. Install dependencies:**

supernote-tool (PyPI package: `supernotelib`):
```bash
uv tool install supernotelib   # or: pipx install supernotelib
```

ImageMagick:
```
Arch:          sudo pacman -S imagemagick
Debian/Ubuntu: sudo apt install imagemagick
Fedora:        sudo dnf install ImageMagick
```

**3. Create and edit the config file:**

```bash
cp supernote-pdf-server.conf.example supernote-pdf-server.conf
```

Edit `supernote-pdf-server.conf` and set your directory paths (the defaults are placeholders). As a minimum, you need to set `NOTE_DIR`, `PDF_DIR`, and confirm `SN_TOOL` points to your supernote-tool binary.

**4. Make the scripts executable:**

```bash
chmod +x supernote-pdf-convert.sh generate-index-page.sh
```

**5. Add the cron entry:**

```bash
crontab -e
```

Add:
```
* * * * * /path/to/supernote-pdf-server/supernote-pdf-convert.sh
```

## Web server

Any static file server pointed at `PDF_DIR` will work. Minimal Caddy example:

```
http://supernote.example.internal {
    bind 192.168.1.100        # bind to a private network interface
    root * /path/to/pdf/dir
    file_server
}
```

Nginx, Apache, or any other static file server is equally suitable.

## Configuration

All options are documented in `supernote-pdf-server.conf.example`. Key settings:

| Variable | Default | Description |
|---|---|---|
| `NOTE_DIR` | — | Source `.note` files (synced from device) |
| `PDF_DIR` | — | PDF output directory (served by web server) |
| `SN_TOOL` | `~/.local/bin/supernote-tool` | Path to supernote-tool binary |
| `ARCHIVE_ENABLED` | `true` | Archive orphaned PDFs instead of deleting |
| `ARCHIVE_PDF_DIR` | — | Destination for archived PDFs |
| `DENSITY` | `232` | ImageMagick DPI for PDF output (see below) |
| `BG_COLOR` | `#d0d0d0` | Background colour substitution |
| `STRIP_LINKS` | `true` | Strip links between notes from PDFs |
| `LOGGING_ENABLED` | `true` | Log conversion events |
| `LOG` | `~/.local/state/supernote-pdf-server.log` | Log file path |

### DPI / DENSITY setting

The `DENSITY` value must match your device's screen resolution divided by the physical page size, so that PDFs render at the correct zoom level:

| Device | Screen | Page size | DENSITY |
|---|---|---|---|
| Supernote Manta | 1920×2560 px | A4 (8.27 in wide) | 232 |
| Supernote Nomad | 1404×1872 px | A5 (5.83 in wide) | 241 |

Without the correct density, ImageMagick defaults to 72 DPI and produces oversized pages with incorrect zoom behaviour.

### Background colour

The conversion pipeline replaces white pixels with `BG_COLOR` using ImageMagick:

```
-fuzz 2% -fill '<BG_COLOR>' -opaque white
```

The 2% fuzz tolerance catches near-white pixels without affecting other greyscale tones. Note that white strokes inside heading boxes are also affected, which more closely matches the actual e-ink device appearance. Set `BG_COLOR="#ffffff"` to disable colour substitution entirely.

### Links between notes

supernote-tool preserves links by default, but links to other note files are broken in this serving context — PDFs are served as independent files, not as an integrated notebook. `STRIP_LINKS=true` passes `--no-link` to supernote-tool, which removes all links from the converted PDF. Set `STRIP_LINKS=false` to preserve them.

## Archiving

When `ARCHIVE_ENABLED=true`, PDFs whose source `.note` file no longer exists are moved to `ARCHIVE_PDF_DIR` rather than deleted. This handles notes that have been renamed, moved, or deleted on the device.

If you sync `ARCHIVE_PDF_DIR` back to the device (e.g. to an SD card via Syncthing), configure that folder as send-only from the server and receive-only on the device, so the server remains the source of truth.

## Logging

With `LOGGING_ENABLED=true`, each run appends to the log file:

```
[2026-04-11 08:32:43] converted   computing/2026-computing.note
[2026-04-11 08:32:48] ERROR       notes/broken.note
[2026-04-11 08:33:01] archived    old/note.pdf
```

The log is not rotated automatically. Use `logrotate` if it grows too large.

## Acknowledgements

- [supernote-tool](https://github.com/jya-dev/supernote-tool) by jya-dev
- [PDF.js](https://github.com/mozilla/pdf.js) by Mozilla
