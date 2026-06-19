#!/usr/bin/env bash
# ============================================================
#  Auto-Unzip Downloads — Installer
#  Watches ~/Downloads for new .zip files, verifies they are
#  safe, extracts them into a same-named folder, then deletes
#  the original zip.
#
#  Requirements: macOS + Homebrew
#  Install:  bash install.sh
#  Uninstall: launchctl unload ~/Library/LaunchAgents/com.username.auto-unzip-downloads.plist
# ============================================================

set -euo pipefail

LABEL="com.username.auto-unzip-downloads"
SCRIPT_DIR="$HOME/.local/bin"
SCRIPT_PATH="$SCRIPT_DIR/auto_unzip_downloads.sh"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/AutoUnzip"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Auto-Unzip Downloads — Installer"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Check Homebrew ───────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    error "Homebrew not found. Install it first: https://brew.sh"
    exit 1
fi
info "Homebrew found."

# ── Install Homebrew bash (macOS ships with bash 3.2 which is too old) ──
if [[ ! -f /opt/homebrew/bin/bash ]]; then
    warn "Homebrew bash not found — installing..."
    brew install bash
fi
info "Homebrew bash ready."

# ── Install fswatch ──────────────────────────────────────────
if ! command -v fswatch &>/dev/null; then
    warn "fswatch not found — installing..."
    brew install fswatch
fi
info "fswatch ready."

# ── Create directories ───────────────────────────────────────
mkdir -p "$SCRIPT_DIR" "$PLIST_DIR" "$LOG_DIR"
info "Directories ready."

# ── Write the watcher script ─────────────────────────────────
cat > "$SCRIPT_PATH" << 'WATCHER_SCRIPT'
#!/opt/homebrew/bin/bash
# ============================================================
#  auto_unzip_downloads.sh
#  Watches ~/Downloads for new .zip files, runs safety checks,
#  extracts to a same-named folder, deletes the zip.
# ============================================================

WATCH_DIR="$HOME/Downloads"
LOG_FILE="$HOME/Library/Logs/AutoUnzip/auto_unzip.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
mkdir -p "$(dirname "$LOG_FILE")"
log "=== Watcher started. Monitoring: $WATCH_DIR ==="

process_zip() {
    local ZIP_PATH="$1"
    sleep 5  # Wait for download to fully complete

    [[ -f "$ZIP_PATH" ]] || return

    # Only handle .zip files (case-insensitive)
    local ZIP_LOWER
    ZIP_LOWER="$(echo "$ZIP_PATH" | tr '[:upper:]' '[:lower:]')"
    [[ "$ZIP_LOWER" == *.zip ]] || return

    local ZIP_NAME
    ZIP_NAME="$(basename "$ZIP_PATH" .zip)"
    local DEST_DIR="$WATCH_DIR/$ZIP_NAME"

    log "Detected zip: $ZIP_PATH"

    # ── Safety check 1: Must be a real ZIP at binary level ───
    local FILE_TYPE
    FILE_TYPE="$(file --brief "$ZIP_PATH" 2>/dev/null || true)"
    if [[ "$FILE_TYPE" != *"Zip archive"* && "$FILE_TYPE" != *"zip"* ]]; then
        log "SKIPPED (not a real zip — file type: $FILE_TYPE): $ZIP_PATH"
        return
    fi

    # ── Safety check 2: macOS quarantine / Gatekeeper flag ──
    # Flag 0081 = macOS has detected this file as potentially malicious
    local QUARANTINE
    QUARANTINE="$(xattr -p com.apple.quarantine "$ZIP_PATH" 2>/dev/null || echo "none")"
    if [[ "$QUARANTINE" == *"0081"* ]]; then
        log "BLOCKED (macOS flagged as malicious): $ZIP_PATH"
        osascript -e "display notification \"Blocked unsafe zip: $(basename "$ZIP_PATH")\" with title \"Auto-Unzip\" sound name \"Basso\""
        return
    fi

    # ── Safety check 3: ZIP integrity ───────────────────────
    if ! /usr/bin/unzip -t "$ZIP_PATH" &>/dev/null; then
        log "SKIPPED (corrupt or invalid zip): $ZIP_PATH"
        return
    fi

    # ── Safety check 4: Zip bomb protection (max 5 GB uncompressed) ──
    local UNCOMPRESSED_SIZE
    UNCOMPRESSED_SIZE="$(unzip -l "$ZIP_PATH" 2>/dev/null | tail -1 | awk '{print $1}')"
    local MAX_BYTES=5368709120
    if [[ -n "$UNCOMPRESSED_SIZE" && "$UNCOMPRESSED_SIZE" -gt "$MAX_BYTES" ]] 2>/dev/null; then
        log "SKIPPED (exceeds 5 GB uncompressed limit): $ZIP_PATH"
        osascript -e "display notification \"Zip skipped — too large (>5 GB): $(basename "$ZIP_PATH")\" with title \"Auto-Unzip\" sound name \"Basso\""
        return
    fi

    # ── Extract ──────────────────────────────────────────────
    local FINAL_DEST="$DEST_DIR"
    local COUNT=1
    while [[ -e "$FINAL_DEST" ]]; do
        FINAL_DEST="${DEST_DIR}_${COUNT}"
        ((COUNT++))
    done

    log "Extracting to: $FINAL_DEST"

    if /usr/bin/unzip -q "$ZIP_PATH" -d "$FINAL_DEST"; then
        rm -f "$ZIP_PATH"
        log "SUCCESS: Extracted → $FINAL_DEST (zip deleted)"
        osascript -e "display notification \"Unzipped → $(basename "$FINAL_DEST")\" with title \"Auto-Unzip\" sound name \"Glass\""
    else
        log "ERROR: Extraction failed for $ZIP_PATH (zip kept)"
        osascript -e "display notification \"Unzip failed: $(basename "$ZIP_PATH")\" with title \"Auto-Unzip\" sound name \"Basso\""
    fi
}

/opt/homebrew/bin/fswatch -0 --event=Created --event=Renamed "$WATCH_DIR" | while IFS= read -r -d '' FILE; do
    FILE_LOWER="$(echo "$FILE" | tr '[:upper:]' '[:lower:]')"
    [[ "$FILE_LOWER" == *.zip ]] || continue
    process_zip "$FILE" &
done
WATCHER_SCRIPT

chmod +x "$SCRIPT_PATH"
info "Watcher script written."

# ── Write the launchd plist ───────────────────────────────────
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/bash</string>
        <string>${SCRIPT_PATH}</string>
    </array>

    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST

info "Launch Agent plist written."

# ── Load ─────────────────────────────────────────────────────
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
info "Launch Agent loaded and running."

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Done! Drop a .zip into ~/Downloads to test it."
echo ""
echo "  Logs:    tail -f $LOG_DIR/auto_unzip.log"
echo "  Stop:    launchctl unload $PLIST_PATH"
echo "  Restart: launchctl load $PLIST_PATH"
echo "══════════════════════════════════════════════════════"
echo ""
