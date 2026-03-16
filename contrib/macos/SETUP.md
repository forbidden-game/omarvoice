# macOS Setup Guide

## Prerequisites

```bash
brew install node ffmpeg
brew install --cask hammerspoon
```

Grant **Accessibility** to Hammerspoon: System Settings → Privacy & Security → Accessibility.

## Build

```bash
cd /path/to/ohmyvoice
npm ci && npm run build
```

## Configure Hammerspoon

Copy the example config into Hammerspoon:

```bash
cp contrib/macos/ohmyvoice.lua ~/.hammerspoon/init.lua
```

Edit `~/.hammerspoon/init.lua`:

1. Set `projectDir` to your ohmyvoice checkout path.
2. Set `VOICE_ENDPOINT` to your ASR backend URL.
3. Uncomment and adjust optional env vars as needed (model, audio device, sounds).

Reload: menubar Hammerspoon icon → **Reload Config**.

## Why Hammerspoon manages the daemon

macOS LaunchAgents run in a restricted session context. ffmpeg's AVFoundation audio capture requires a full AudioSession (tied to the window server) to function correctly. Without it, audio is captured at ~1/10 the expected bitrate, producing sped-up, noisy recordings.

Hammerspoon is a GUI application with a window server connection. Processes it spawns inherit a proper AudioSession, so ffmpeg records normally.

## Hotkey

**Hold Right Command** to record, release to stop.

To change the key, edit the `keyCode` check in `ohmyvoice.lua`:

| Key | keyCode |
|-----|---------|
| Right Command | 54 |
| Left Command | 55 |
| Right Option | 61 |
| F1 | 122 |
| F5 | 96 |

For modifier keys (Command, Option), the eventtap listens to `flagsChanged`.
For function keys, switch to `keyDown`/`keyUp` events — see the git history for an F1 example.

## Audio device selection

Default is `:default` (system default input). If a virtual audio device (e.g. Oray/SunLogin) is installed and set as default, override explicitly:

```bash
# List devices
ffmpeg -f avfoundation -list_devices true -i ""

# Set in Hammerspoon env, e.g. device index 1 = MacBook microphone
VOICE_RECORD_ARGS = "-f avfoundation -i :1 -ac 1 -flush_packets 1 -y"
```

## Clipboard encoding

Set `LANG = "en_US.UTF-8"` in the daemon environment (already in the example config). Without it, `pbcopy` may corrupt non-ASCII text.

## Prompt sounds

Override via environment variables. Available system sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.

```lua
VOICE_START_SOUND_ARGS = "-v 0.6 /System/Library/Sounds/Funk.aiff",
VOICE_STOP_SOUND_ARGS  = "-v 0.6 /System/Library/Sounds/Glass.aiff",
```

Volume range: `0.0` – `1.0`. Default is `0.35`.

## Verify

```bash
node dist/cli.js status
```

## Troubleshooting

- **No sound / sped-up audio**: Daemon must be launched from Hammerspoon, not LaunchAgent. Check audio device index.
- **Clipboard garbled**: Ensure `LANG=en_US.UTF-8` is set in daemon environment.
- **Hotkey not working**: Check Accessibility permission for Hammerspoon. Reload config after edits.
- **Microphone permission**: Run the daemon once from an interactive terminal first to trigger the macOS permission prompt.
- **ffmpeg not found**: Ensure `PATH` includes `/opt/homebrew/bin` in the daemon environment.
