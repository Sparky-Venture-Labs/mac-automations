#!/usr/bin/env bash
# ============================================================
#  Screenshot & Recording Organizer — Installer
#  Watches ~/Desktop for new screenshots and screen recordings,
#  renames them with a clean timestamp, and moves them into
#  organized folders under ~/Documents by type, year, and month.
#
#  Requirements: macOS + Homebrew
#  Install:  bash install.sh
#  Uninstall: launchctl unload ~/Library/LaunchAgents/com.username.screenshot-organizer.plist
# ============================================================

set -euo pipefail

LABEL="com.username.screenshot-organizer"
SCRIPT_DIR="$HOME/.local/bin"
SCRIPT_PATH="$SCRIPT_DIR/screenshot_organizer.sh"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/ScreenshotOrganizer"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Screenshot & Recording Organizer — Installer"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Check Homebrew ───────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    error "Homebrew not found. Install it first: https://brew.sh"
    exit 1
fi
info "Homebrew found."

# ── Install Homebrew bash ────────────────────────────────────
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
mkdir -p "$HOME/Documents/Screenshots"
mkdir -p "$HOME/Documents/Screen Recordings"
info "Directories ready."

# ── Write the watcher script ─────────────────────────────────
cat > "$SCRIPT_PATH" << 'WATCHER_SCRIPT'
#!/opt/homebrew/bin/bash
# ============================================================
#  screenshot_organizer.sh
#  Watches ~/Desktop for screenshots and screen recordings.
#  Renames with clean timestamp and organizes by type/year/month.
#
#  Output structure:
#    ~/Documents/Screenshots/2026/June/screenshot_2026-06-19_14-45-00.png
#    ~/Documents/Screen Recordings/2026/June/recording_2026-06-19_14-45-00.mov
# ============================================================

WATCH_DIR="$HOME/Desktop"
SCREENSHOT_BASE="$HOME/Documents/Screenshots"
RECORDING_BASE="$HOME/Documents/Screen Recordings"
LOG_FILE="$HOME/Library/Logs/ScreenshotOrganizer/organizer.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
mkdir -p "$(dirname "$LOG_FILE")"
log "=== Screenshot Organizer started. Monitoring: $WATCH_DIR ==="

process_file() {
    local FILE_PATH="$1"
    sleep 1

    [[ -f "$FILE_PATH" ]] || return

    local FILENAME EXT EXT_LOWER TYPE DEST_BASE PREFIX
    FILENAME="$(basename "$FILE_PATH")"
    EXT="${FILENAME##*.}"
    EXT_LOWER="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"

    # macOS names screenshots "Screenshot ..." and recordings "Screen Recording ..."
    if [[ "$FILENAME" == Screenshot* && "$EXT_LOWER" == "png" ]]; then
        TYPE="screenshot"; DEST_BASE="$SCREENSHOT_BASE"; PREFIX="screenshot"
    elif [[ "$FILENAME" == "Screen Recording"* && ( "$EXT_LOWER" == "mov" || "$EXT_LOWER" == "mp4" ) ]]; then
        TYPE="recording"; DEST_BASE="$RECORDING_BASE"; PREFIX="recording"
    else
        return
    fi

    local TIMESTAMP YEAR MONTH
    TIMESTAMP="$(date -r "$FILE_PATH" '+%Y-%m-%d_%H-%M-%S')"
    YEAR="$(date -r "$FILE_PATH" '+%Y')"
    MONTH="$(date -r "$FILE_PATH" '+%B')"

    local DEST_DIR="$DEST_BASE/$YEAR/$MONTH"
    mkdir -p "$DEST_DIR"

    local CLEAN_NAME="${PREFIX}_${TIMESTAMP}.${EXT_LOWER}"
    local DEST_PATH="$DEST_DIR/$CLEAN_NAME"

    # Handle name collision
    local COUNT=1
    while [[ -e "$DEST_PATH" ]]; do
        DEST_PATH="$DEST_DIR/${PREFIX}_${TIMESTAMP}_${COUNT}.${EXT_LOWER}"
        ((COUNT++))
    done

    if mv "$FILE_PATH" "$DEST_PATH"; then
        log "MOVED [$TYPE]: $FILENAME → $DEST_PATH"
        osascript -e "display notification \"Saved → $YEAR/$MONTH/$CLEAN_NAME\" with title \"Screenshot Organizer\" sound name \"Tink\""
    else
        log "ERROR: Failed to move $FILE_PATH"
    fi
}

/opt/homebrew/bin/fswatch -0 --event=Created --event=Renamed "$WATCH_DIR" | while IFS= read -r -d '' FILE; do
    FILE_LOWER="$(echo "$FILE" | tr '[:upper:]' '[:lower:]')"
    [[ "$FILE_LOWER" == *.png || "$FILE_LOWER" == *.mov || "$FILE_LOWER" == *.mp4 ]] || continue
    process_file "$FILE" &
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

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
info "Launch Agent loaded and running."

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Done! Take a screenshot (Cmd+Shift+3) to test it."
echo ""
echo "  Screenshots → ~/Documents/Screenshots/YEAR/Month/"
echo "  Recordings  → ~/Documents/Screen Recordings/YEAR/Month/"
echo ""
echo "  Logs:    tail -f $LOG_DIR/organizer.log"
echo "  Stop:    launchctl unload $PLIST_PATH"
echo "  Restart: launchctl load $PLIST_PATH"
echo "══════════════════════════════════════════════════════"
echo ""
