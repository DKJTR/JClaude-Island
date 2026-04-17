<div align="center">
  <img src="feature-showcase.png" alt="JClaude Island" width="700">
</div>

---

JClaude Island is a macOS notch app that brings Claude Code sessions, music playback, and Bluetooth device info into one place. Built on top of the excellent [Claude Island](https://github.com/farouqaldori/claude-island), with media and device integrations added.

## How It Works

**Closed notch** adapts to context:

| State | Left Wing | Right Wing |
|-------|-----------|------------|
| Claude processing | Crab icon | Orange spinner |
| Music playing (Claude idle) | Album art + track | Waveform animation |
| BT device just paired | Device name | Green checkmark (4s) |
| Both Claude + Music active | Claude takes priority | Expand to see both |

**Expanded notch** shows a stacked layout that sizes to content:
- Claude session rows with token usage bars showing `50%(200K)` or `38%(1M)`
- Spotify / Apple Music compact player with seekable progress bar
- Bluetooth device list with battery levels (AirPods L/R/Case, headphones, trackpad)
- AskUserQuestion prompts with pickable option buttons
- Click track name to open the music app

**Pagination** keeps things tidy:
- Max 5 Claude sessions visible, `< >` navigation for more
- Max 3 Bluetooth devices visible, `< >` navigation for more
- Panel height adjusts dynamically to content

## Features

**Claude Code**
- Multi-session monitoring with vertical token % bars (green to red gradient)
- Tool permission approval directly from the notch
- AskUserQuestion prompts with clickable options
- Stale session detection (auto-idle after 30s without events)
- Session titles sync with `/rename`

**Now Playing**
- Spotify and Apple Music support via AppleScript
- Play / pause / next / previous controls
- Seekable progress bar with time labels
- Album art with smooth crossfade on track change
- Click track name to open the music app

**Bluetooth**
- Connected device list with battery levels
- AirPods Left / Right / Case breakdown
- Headphone support (JLAB, Bose, Sony, Jabra, Sennheiser)
- "N/A" for devices without battery data
- 5-second poll interval for fast connection detection
- Brief animation in closed notch when a device pairs

**Visual Polish**
- 5-bar organic waveform animation
- Frosted glass blur behind expanded panel
- Context-aware hover glow (green for media, orange for Claude)
- Mode-switch bounce animation
- Dynamic panel height (no wasted space)

## Install

**Requirements:** macOS 15.0+, Claude Code CLI, Python 3 (system Python is fine).

### One-line install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/DKJTR/JClaude-Island/main/scripts/install.sh | bash
```

This downloads the latest signed `.dmg`, copies the app to `/Applications`, drops the Claude Code hook into `~/.claude/hooks/`, merges the hook entries into `~/.claude/settings.json`, and launches the app. Re-run any time to update.

### Build from source

```bash
git clone https://github.com/DKJTR/JClaude-Island.git
cd JClaude-Island
xcodebuild -scheme ClaudeIsland -configuration Release build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-"
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/JClaude\ Island.app /Applications/
```

Or open `ClaudeIsland.xcodeproj` in Xcode and hit **Cmd+R**. Then run `scripts/install.sh` once to wire the Claude Code hooks (or copy `hooks/claude-island-state.py` and update `~/.claude/settings.json` manually).

First launch may ask for **Bluetooth**, **Apple Events** (Terminal/iTerm send), and **Accessibility** (Cursor/VS Code/Warp send) permissions.

## Architecture

```
Claude Code hooks --> Python (~/.claude/hooks/) --> Unix socket --> SwiftUI notch overlay
Spotify/Apple Music --> AppleScript polling (2s) --> Now Playing state
Bluetooth --> IOBluetooth + IOKit (5s polling) --> Device list
```

## Known Limitations

- Chrome / YouTube not supported (AppleScript limitation)
- Token count is approximate (JSONL-parsed, not internal context %)
- Some BT devices don't report battery (shown as "N/A")
- Ad-hoc signing only (uses AppleScript automation)

## Acknowledgments

Built on [Claude Island](https://github.com/farouqaldori/claude-island) by Farouq Aldori. Learned from [Alcove](https://tryalcove.com/) and [Vibe Island](https://vibeisland.app/) for UX patterns.

## License

Apache 2.0
