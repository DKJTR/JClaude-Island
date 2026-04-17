<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="JClaude Island" width="80" height="80">
  <h1>JClaude Island</h1>
  <p><strong>One notch to rule them all.</strong></p>
  <p>Claude Code + Spotify + Apple Music + Bluetooth in a single macOS Dynamic Island.</p>
  <br />
  <img src="hero-banner.png" alt="Hero" width="600">
</div>

---

Stop juggling [Claude Island](https://github.com/farouqaldori/claude-island), [Alcove](https://tryalcove.com/), and [Vibe Island](https://vibeisland.app/). JClaude Island merges AI agent monitoring with media controls and device tracking into one notch app that gets out of your way.

<div align="center">
  <img src="feature-showcase.png" alt="Feature Showcase" width="800">
</div>

## How It Works

**Closed notch** adapts to what's happening:

| State | Left Wing | Right Wing |
|-------|-----------|------------|
| Claude processing | Crab icon | Orange spinner |
| Spotify playing | Album art + track | Waveform bars |
| Both active | Claude takes priority | Expand to see both |
| Nothing | Notch hides | |

**Expanded notch** shows everything stacked:
- Claude session rows with token usage bars and tool approval
- Spotify/Apple Music compact player with seekable progress bar
- AskUserQuestion prompts with pickable options

## Features

**Claude Code**
- Multi-session monitoring with per-session token usage bars
- Tool permission approval directly from the notch
- AskUserQuestion prompts with clickable option buttons
- Stale session detection (auto-idle after 30s without events)
- Session titles sync with `/rename`

**Now Playing**
- Spotify and Apple Music via AppleScript (no private API dependency)
- Play / pause / next / previous from the notch
- Seekable progress bar with time labels
- Album art with smooth crossfade on track change

**Bluetooth**
- Connected device list with battery levels
- AirPods Left / Right / Case breakdown
- Auto-refresh every 30 seconds

**Visual Polish** (inspired by [Alcove](https://tryalcove.com/))
- 5-bar organic waveform animation
- Frosted glass blur behind expanded panel
- Context-aware hover glow (green for media, orange for Claude)
- Mode-switch bounce animation

## Install

**Requirements:** macOS 15.0+, Xcode, Claude Code CLI

```bash
git clone https://github.com/DKJTR/JClaude-Island.git
cd JClaude-Island
xcodebuild -scheme ClaudeIsland -configuration Release build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-"
```

Copy to Applications:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/JClaude\ Island.app /Applications/
```

Or open `ClaudeIsland.xcodeproj` in Xcode and hit **Cmd+R**.

Hooks auto-install on first launch. No configuration needed.

## Architecture

```
Claude Code hooks
    --> Python script (~/.claude/hooks/)
    --> Unix socket (/tmp/dynamic-island.sock)
    --> Swift app (NotchView + SessionStore + MediaRemoteService)
    --> macOS notch overlay (NSPanel, non-activating, click-through)

Spotify / Apple Music
    --> AppleScript polling (2s interval)
    --> NSWorkspace process check (never launches apps)

Bluetooth
    --> IOBluetooth + IOKit (30s polling)
```

## Known Limitations

- **Chrome / YouTube not supported.** AppleScript can't query Chrome media state. Only Spotify and Apple Music.
- **Token count is approximate.** Uses JSONL-parsed input/output tokens, not the internal context window percentage from Claude Code.
- **Ad-hoc signing only.** Uses AppleScript automation, so it can't be distributed via the Mac App Store.
- **macOS 26 (Tahoe):** MediaRemote private API is blocked for ad-hoc signed apps. JClaude Island uses AppleScript as the primary media backend.

## Credits

- [Claude Island](https://github.com/farouqaldori/claude-island) by Farouq Aldori -- the foundation this is built on
- [Alcove](https://tryalcove.com/) -- inspiration for waveform, blur, and polish
- [Vibe Island](https://vibeisland.app/) -- inspiration for multi-agent notch UX

## License

Apache 2.0 (same as upstream Claude Island)
