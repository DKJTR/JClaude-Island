<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">JClaude Island</h3>
  <p align="center">
    A unified macOS notch app: Claude Code + Spotify/Apple Music + Bluetooth in one Dynamic Island.
    <br />
    Fork of <a href="https://github.com/farouqaldori/claude-island">Claude Island</a> with media integration.
  </p>
</div>

## What's different from Claude Island

JClaude Island combines Claude Code monitoring with media controls and Bluetooth device tracking, so you don't need separate notch apps (like Alcove) that fight for the same space.

**Closed notch:**
- Claude active: crab icon + processing spinner
- Music playing (Claude idle): album art + track name + waveform animation
- Both: Claude takes priority; expand to see both

**Expanded notch:**
- Claude session rows (stacked, with token usage bars)
- Spotify/Apple Music compact player (album art, controls, seekable progress bar)
- Bluetooth device list with AirPods L/R/Case battery
- AskUserQuestion prompts with pickable options

## Features

Everything from Claude Island, plus:

- **Now Playing** -- Spotify and Apple Music track info, controls, seekable progress bar
- **Bluetooth Devices** -- Connected devices with battery levels (AirPods L/R/Case)
- **Stacked Layout** -- Claude sessions + media player visible simultaneously
- **Token Usage Bar** -- Vertical gradient bar per session showing context usage
- **AskUserQuestion UI** -- See Claude's questions and pick options from the notch
- **Visual Polish** -- 5-bar waveform, frosted glass blur, hover glow, album art crossfade, mode-switch bounce

## Requirements

- macOS 15.0+
- MacBook with notch (or external display with simulated notch)
- Claude Code CLI
- Spotify or Apple Music (for media features)

## Install

Build from source:

```bash
git clone https://github.com/DKJTR/DynamicIsland.git
cd DynamicIsland
xcodebuild -scheme ClaudeIsland -configuration Release build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-"
```

Then copy the built app to `/Applications/`:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/JClaude\ Island.app /Applications/
```

Or open `ClaudeIsland.xcodeproj` in Xcode and press Cmd+R.

## How It Works

Same hook system as Claude Island: installs a Python script into `~/.claude/hooks/` that communicates via Unix socket (`/tmp/dynamic-island.sock`).

Media integration uses AppleScript to query Spotify/Apple Music (MediaRemote private API is blocked on macOS 26 for ad-hoc signed apps).

## Known Limitations

- **Chrome/YouTube not supported** -- AppleScript can't query Chrome media state
- **Token count is approximate** -- Uses JSONL-parsed input/output tokens, not the internal context window percentage
- **No App Store distribution** -- Uses AppleScript automation (requires ad-hoc or Developer ID signing)

## Credits

- [Claude Island](https://github.com/farouqaldori/claude-island) by Farouq Aldori (Apache 2.0)
- Inspired by [Alcove](https://tryalcove.com/) and [Vibe Island](https://vibeisland.app/)

## License

Apache 2.0 (same as upstream)
