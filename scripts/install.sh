#!/usr/bin/env bash
# JClaude Island — one-line installer
# Usage:  curl -fsSL https://raw.githubusercontent.com/DKJTR/JClaude-Island/main/scripts/install.sh | bash
#
# What it does:
#   1. Downloads the latest .dmg from GitHub Releases
#   2. Mounts it and copies "JClaude Island.app" to /Applications
#   3. Drops the Claude Code hook script into ~/.claude/hooks/
#   4. Merges the hook entries into ~/.claude/settings.json (without clobbering yours)
#   5. Launches the app
#
# Re-running is safe: existing files are backed up with a .bak suffix.
set -euo pipefail

REPO="DKJTR/JClaude-Island"
APP_NAME="JClaude Island"
HOOK_NAME="claude-island-state.py"
HOOK_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
INSTALL_DIR="/Applications"
TMP_DIR="$(mktemp -d -t jclaude-install)"
trap 'rm -rf "$TMP_DIR"' EXIT

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
info() { printf "  \033[36m→\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; exit 1; }

# ─── 0. Sanity ────────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || fail "macOS only — this app lives in the notch."
command -v curl     >/dev/null || fail "curl missing"
command -v hdiutil  >/dev/null || fail "hdiutil missing (macOS install)"
command -v python3  >/dev/null || fail "python3 missing — install from https://www.python.org/downloads/"

bold "Installing $APP_NAME"

# ─── 1. Find the latest DMG asset ─────────────────────────────────────────────
info "Looking up latest release"
api_url="https://api.github.com/repos/$REPO/releases/latest"
release_json=$(curl -fsSL "$api_url") || fail "Could not reach GitHub API"
dmg_url=$(printf '%s' "$release_json" \
    | grep -Eo '"browser_download_url":\s*"[^"]+\.dmg"' \
    | head -1 \
    | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/')
[[ -n "${dmg_url:-}" ]] || fail "No .dmg asset on the latest release. Try the manual download."
ok "Found $(basename "$dmg_url")"

# ─── 2. Download + mount + copy ───────────────────────────────────────────────
dmg_path="$TMP_DIR/jclaude-island.dmg"
info "Downloading"
curl -fsSL --progress-bar "$dmg_url" -o "$dmg_path"
ok "Downloaded $(du -h "$dmg_path" | cut -f1)"

info "Mounting DMG"
mount_out=$(hdiutil attach -nobrowse -quiet "$dmg_path")
mount_point=$(printf '%s\n' "$mount_out" | awk -F'\t' '$1 ~ /Apple_HFS|Apple_APFS/ {print $NF}' | tail -1)
[[ -d "$mount_point" ]] || fail "Could not mount DMG"

src_app="$mount_point/$APP_NAME.app"
[[ -d "$src_app" ]] || src_app="$(find "$mount_point" -maxdepth 2 -name '*.app' -print -quit)"
[[ -d "$src_app" ]] || { hdiutil detach -quiet "$mount_point" || true; fail "App not found inside the DMG"; }

dest_app="$INSTALL_DIR/$APP_NAME.app"
if [[ -d "$dest_app" ]]; then
    info "Replacing existing $APP_NAME.app (quitting if running)"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    rm -rf "$dest_app"
fi

info "Copying to /Applications"
cp -R "$src_app" "$dest_app"
hdiutil detach -quiet "$mount_point" || true
ok "Installed $APP_NAME.app"

# Strip macOS quarantine so Gatekeeper doesn't ask twice
xattr -dr com.apple.quarantine "$dest_app" 2>/dev/null || true

# ─── 3. Hook script ───────────────────────────────────────────────────────────
info "Installing Claude Code hook"
mkdir -p "$HOOK_DIR"
hook_dest="$HOOK_DIR/$HOOK_NAME"
hook_url="https://raw.githubusercontent.com/$REPO/main/hooks/$HOOK_NAME"

if curl -fsSL "$hook_url" -o "$hook_dest.new"; then
    if [[ -f "$hook_dest" ]] && ! cmp -s "$hook_dest" "$hook_dest.new"; then
        mv "$hook_dest" "$hook_dest.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    mv "$hook_dest.new" "$hook_dest"
    chmod +x "$hook_dest"
    ok "Hook at $hook_dest"
else
    fail "Could not download $HOOK_NAME from the repo"
fi

# ─── 4. Merge hook entries into ~/.claude/settings.json ───────────────────────
info "Wiring hooks into $SETTINGS_FILE"
mkdir -p "$(dirname "$SETTINGS_FILE")"
[[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"

# Use python (stdlib) so we don't depend on jq
python3 - "$SETTINGS_FILE" "$hook_dest" <<'PY'
import json, sys, shutil, datetime, os
path, hook_path = sys.argv[1], sys.argv[2]
with open(path) as f:
    try: data = json.load(f)
    except json.JSONDecodeError: data = {}

events = [
    "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionRequest", "PermissionDenied", "Notification",
    "Stop", "StopFailure", "SubagentStart", "SubagentStop",
    "SessionStart", "SessionEnd", "PreCompact", "PostCompact",
]

cmd = f"python3 '{hook_path}'"
hooks = data.setdefault("hooks", {})
changed = False
for ev in events:
    bucket = hooks.setdefault(ev, [])
    # Skip if our command is already wired up under any matcher
    already = any(
        any(h.get("command") == cmd for h in entry.get("hooks", []))
        for entry in bucket
    )
    if already:
        continue
    timeout = 86400 if ev in ("PermissionRequest", "PreToolUse") else None
    hook_obj = {"type": "command", "command": cmd}
    if timeout: hook_obj["timeout"] = timeout
    bucket.append({"matcher": "*", "hooks": [hook_obj]})
    changed = True

if changed:
    backup = path + ".bak." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, backup)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"updated (backup at {os.path.basename(backup)})")
else:
    print("already configured")
PY
ok "Hooks configured"

# ─── 5. Launch ────────────────────────────────────────────────────────────────
info "Launching $APP_NAME"
open "$dest_app"
sleep 1

bold "Done"
echo
echo "  Open the notch with a click. First launch may ask for:"
echo "    • Bluetooth permission (battery levels)"
echo "    • Apple Events (sending text to Terminal/iTerm)"
echo "    • Accessibility (sending text to Cursor/VS Code/Warp)"
echo
echo "  Restart any running Claude Code session so the hooks pick up."
