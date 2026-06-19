# mac-automations

A collection of macOS background automations built with `launchd` + `fswatch`. Each one runs silently in the background, starts on login, and sends a macOS notification when it does something.

**Requirements:** macOS (Apple Silicon) + [Homebrew](https://brew.sh)

---

## Automations

### 1. Auto-Unzip Downloads

Watches `~/Downloads` for new `.zip` files. Runs safety checks, extracts to a same-named folder, and deletes the zip automatically.

**Safety checks:**
- Verifies the file is actually a ZIP at the binary level (not just by extension)
- Reads the macOS quarantine/Gatekeeper flag — blocks files macOS has flagged as malicious
- Tests ZIP integrity before extracting
- Blocks zip bombs (rejects anything that would unpack to more than 5 GB)

**Install:**
```bash
cd auto-unzip-downloads && bash install.sh
```

**Logs:** `~/Library/Logs/AutoUnzip/auto_unzip.log`

---

### 2. Screenshot & Recording Organizer

Watches `~/Desktop` for new screenshots and screen recordings. Renames them with a clean timestamp and moves them into organized folders under `~/Documents`.

**Output structure:**

**Install:**
```bash
cd screenshot-organizer && bash install.sh
```

**Logs:** `~/Library/Logs/ScreenshotOrganizer/organizer.log`

---

## Useful commands

```bash
# Check status (middle column should be 0)
launchctl list | grep com.username

# View logs live
tail -f ~/Library/Logs/AutoUnzip/auto_unzip.log
tail -f ~/Library/Logs/ScreenshotOrganizer/organizer.log

# Stop
launchctl unload ~/Library/LaunchAgents/com.username.auto-unzip-downloads.plist
launchctl unload ~/Library/LaunchAgents/com.username.screenshot-organizer.plist

# Start
launchctl load ~/Library/LaunchAgents/com.username.auto-unzip-downloads.plist
launchctl load ~/Library/LaunchAgents/com.username.screenshot-organizer.plist
```
