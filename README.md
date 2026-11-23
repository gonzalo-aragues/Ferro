# Ferro

A macOS menu bar app that turns the notch into an interactive "island" with a ferrofluid animation.

## Features

- **Music**: shows what's playing in Music or Spotify, with playback controls and lyrics.
- **Shelf**: drag files onto the notch to keep them close at hand.
- **Clipboard**: clipboard history (skips items that password managers mark as concealed).
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
