<div align="center">
  <img src="feature-showcase.png" alt="JClaude Island" width="700">
  <h1>JClaude Island</h1>
  <p><strong>Answer Claude. Play music. Watch your battery. Without leaving the notch.</strong></p>
  <p>
    <a href="https://github.com/DKJTR/JClaude-Island/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/DKJTR/JClaude-Island?style=flat-square&color=e87848"></a>
    <a href="#install"><img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square"></a>
    <a href="https://github.com/DKJTR/JClaude-Island/blob/main/LICENSE.md"><img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue?style=flat-square"></a>
    <a href="https://github.com/DKJTR/JClaude-Island/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/DKJTR/JClaude-Island?style=flat-square"></a>
  </p>
</div>

---

JClaude Island is a macOS notch app for the people who live in Claude Code. It puts your active sessions, the question Claude is waiting on, your music, and your AirPods battery in the one place you're always looking — the notch. No window management. No alt-tab. No checking five different surfaces.

## What's new in v1.4

> **AskUserQuestion in the notch — for real.** When Claude asks a question, the option chips render right in the island row. Click one and the terminal picker auto-submits. Mirror mode keeps both UIs in sync — answer in either place, the other clears.

> **Multi-terminal send.** The chat input now writes into tmux, Terminal.app, iTerm2, **Cursor**, **VS Code**, **Warp**, **Ghostty** — anywhere a Claude Code session can run. Auto-detected per session.

> **Differentiated indicators.** Permission prompts get a purple blinking pixel `?`. Questions get a static orange `?`. Both at once → the indicator alternates. You always know what kind of attention Claude needs.

> **One-line install.** `curl ... | bash` downloads the signed DMG, copies the app, wires the Claude Code hooks, and launches. Updates use the same line.

> **Hardened.** Peer-PID socket auth. Atomic settings write. AppleScript injection-safe. Path traversal blocked. Privacy log redaction. Full review in [SECURITY notes](#security--privacy).

## How it works

**Closed notch** adapts to whatever needs your attention:

| State | Left wing | Right wing |
|---|---|---|
| Claude processing | Walking crab | Orange spinner |
| Permission needed | Crab + **purple blinking `?`** | Spinner |
| Question pending | Crab + **orange static `?`** | Spinner |
| Both pending | Crab + **alternating `?`** | Spinner |
| Music playing (Claude idle) | Album art + track | 5-bar waveform |
| BT device just paired | Device name | Green check (4s) |

**Expanded notch** stacks everything in one panel:

- **Claude rows** — token usage bar (50%(200K) etc.), tool name when waiting for approval, **inline option chips** when waiting for an answer. Single-click to open chat.
- **Now Playing** — Spotify or Apple Music with seekable progress, controls, album crossfade. Click the track name to open the app.
- **Bluetooth** — connected devices with battery (AirPods L/R/Case, headphones, trackpad). Clean SF Symbol icons.

Pagination keeps it tidy: max 5 Claude sessions and 3 BT devices visible at once with `< >` to page.

## Features in depth

### Claude Code
- **AskUserQuestion mirror** — option chips inline in the row. Click → arrow-key keystrokes drive the terminal picker → auto-submits. Works for single-question and multi-question batches.
- **Permission approvals** — Allow / Deny right from the notch. Hook timeout is 24 hours so it'll wait as long as you do.
- **Multi-session** — up to 5 visible, paginate the rest. Sessions ordered by attention priority.
- **Token usage bar** — vertical 4px gradient (green → yellow → orange → red), with `%(context-size)` label.
- **Multi-terminal text input** — TerminalRouter detects host and routes via tmux send-keys, AppleScript (Terminal.app / iTerm2), or CGEvent (Cursor / VS Code / Warp / Ghostty).
- **Sound alerts** — your chosen system sound plays when a new permission or question lands and the host terminal isn't visible.

### Now Playing
- Spotify and Apple Music via AppleScript (no music app launched on its own).
- Play / pause / next / prev. Seekable progress bar. Album crossfade on track change.
- Toggle off in settings to hide entirely.

### Bluetooth
- IOBluetooth + IOKit polling every 5s.
- AirPods L/R/Case battery breakdown. Headphones, keyboards, trackpads.
- Brief 4-second animation in the closed notch when something pairs.
- Toggle off in settings to hide entirely.

### Visual polish
- 5-bar organic waveform.
- Frosted glass blur behind the expanded panel.
- Hover glow tint matches what's active (green = media, orange = Claude).
- Mode-switch bounce.
- Dynamic panel height — no wasted space.

## Install

**Requirements:** macOS 15.0+, Claude Code CLI, Python 3 (system Python is fine).

### One-line install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/DKJTR/JClaude-Island/main/scripts/install.sh | bash
```

What it does, in order:
1. Looks up the latest release on GitHub
2. Downloads the DMG (verifies SHA-256 if the release notes publish one)
3. Mounts it, copies `JClaude Island.app` to `/Applications`, runs Gatekeeper assessment
4. Drops `claude-island-state.py` into `~/.claude/hooks/`
5. Merges hook entries into `~/.claude/settings.json` — backs up your existing config first, never clobbers
6. Launches the app

Re-run any time to update. Existing settings.json is preserved.

### Build from source

```bash
git clone https://github.com/DKJTR/JClaude-Island.git
cd JClaude-Island
xcodebuild -scheme ClaudeIsland -configuration Release build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-"
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/JClaude\ Island.app /Applications/
```

Or open `ClaudeIsland.xcodeproj` in Xcode and hit **Cmd+R**, then run `scripts/install.sh` once to wire the Claude Code hooks.

### First-launch permissions

| Permission | Why | Where |
|---|---|---|
| **Bluetooth** | Read battery levels of connected devices | System Settings → Privacy & Security → Bluetooth |
| **Apple Events** | Send messages to Claude Code in Terminal.app / iTerm2 | First time you click "Send" — system dialog appears |
| **Accessibility** | Type messages into Cursor / VS Code / Warp / Ghostty | First time you click "Send" to a non-AppleScript app |

Skip any you don't need — the relevant features just won't fire.

## Architecture

```
Claude Code hooks ──▶ python3 (~/.claude/hooks/) ──▶ AF_UNIX socket ──▶ SwiftUI notch
                                  ▲                                          │
                                  └────  hookSpecificOutput JSON  ◀──────────┘
                                                (decisions, answers)

Spotify / Apple Music  ──▶  AppleScript polling (2s)  ──▶  Now Playing state
Bluetooth devices      ──▶  IOBluetooth + IOKit (5s)  ──▶  Device list
```

The notch app and Claude Code communicate over a per-user AF_UNIX socket at `/tmp/dynamic-island.sock` (mode `0600`). Connections are gated by **peer-PID auth** — the socket only accepts clients whose ancestor chain includes a `claude` binary.

## Security & privacy

**No data leaves the box.** No telemetry, no analytics, no crash reporter. The app makes outbound calls to exactly two places: Sparkle's appcast for update checks, and GitHub URLs you click in the menu. Tool inputs, JSONL conversation logs, file paths, env vars — all stay on your machine.

Defenses currently in place:

- **Per-process socket auth** — connections rejected unless the peer's ancestor chain contains a Claude Code binary.
- **AppleScript injection-safe** — newlines + quotes escaped before any `keystroke "..."` literal.
- **Atomic settings write** — backup taken before first overwrite; mid-write crash can't lose your config.
- **Path traversal blocked** — `sessionId` regex-validated, JSONL paths must resolve inside `~/.claude/projects/`.
- **No payload in logs** — failed-parse events log byte counts, not contents.
- **Sandboxed AppleScript targets** — only Terminal, iTerm2, Spotify, and Apple Music can be addressed.

## Known limitations

- Chrome / YouTube media not detected (AppleScript can't reach them).
- Token usage is JSONL-parsed, not the model's internal context counter (close enough for the bar).
- Some BT devices don't report battery → shown as `N/A`.
- v1.4.0 DMG is ad-hoc signed; Developer-ID notarization tracked for v1.5.

## Roadmap

- [ ] Developer-ID notarized DMG + Sparkle EdDSA-signed updates
- [ ] Multi-select question support (currently first-pick only goes through; users can finish multi-select in terminal)
- [ ] Optional voice notification ("Claude needs you") via macOS speech synth
- [ ] Customizable indicator colors

## Acknowledgments

Built on [Claude Island](https://github.com/farouqaldori/claude-island) by Farouq Aldori. UX patterns inspired by [Alcove](https://tryalcove.com/) and [Vibe Island](https://vibeisland.app/).

## Support

If JClaude Island makes your day easier, [sponsor the work](https://github.com/sponsors/DKJTR). Free will always be free.

## License

Apache 2.0 — same as upstream.
