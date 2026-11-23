# Ferro

A macOS app that turns the notch into an interactive "dynamic island" with a ferrofluid animation.

## Features

- **Music**: shows what's playing in Music or Spotify, with playback controls and lyrics.
- **Shelf**: drag files onto the notch to keep them close at hand.
- **Clipboard**: clipboard history (skips items that password managers mark as concealed).
- **Claude**: a live view of Claude Code while it works, styled like its terminal: the current prompt, each tool call and its result, the task list, and the spinner with elapsed time and tokens. The collapsed notch shows a live activity while Claude is working and flashes "Done" when it finishes. It reads the session logs Claude Code already keeps in `~/.claude/projects`, so it needs no setup.
- **Tools**: a camera mirror (active only while it's open) and other utilities.
- Launch at login, toggled from the menu bar icon.

## Requirements

- macOS 26 or later
- Swift 6.2

## Build

```bash
./build.sh
```

This produces `build/Ferro.app` (ad-hoc signed). Double-click it to open, or run:

```bash
open build/Ferro.app
```

## Developer flags

```bash
build/Ferro.app/Contents/MacOS/Ferro --snapshot <dir>   # render every tab to PNGs offscreen
open build/Ferro.app --args --open claude              # launch with the island open on a tab
```
