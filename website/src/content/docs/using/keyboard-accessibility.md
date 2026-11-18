---
title: Keyboard and accessibility
description: Control Hush from the keyboard and with VoiceOver, and how it follows your accessibility settings.
---

## Keyboard

| Action | How |
|---|---|
| Raise or lower the focused fader, slider or tile by 5% | **↑** / **↓**, or **→** / **←** |
| Move between controls | **Tab** / **Shift-Tab** |
| Mute or unmute (mute button focused) | **Space** |

This works the same in every [layout](/Hush/using/mixer/#layouts). In the tiles layout, the tile itself is the slider and takes focus; its mute button is the next stop.

If **Tab** skips the faders and buttons, turn on **Keyboard navigation** in **System Settings → Keyboard**.

Hush doesn't have a global keyboard shortcut for opening the mixer.

## Mouse and trackpad

- Scroll over a fader, slider or tile to change it in 5% steps. Scrolling up always raises the level, whatever your natural-scrolling setting. In classic rows and tiles, scroll over the names or the space between apps to scroll the list instead.
- Double-click a fader's knob (or anywhere on a tile), or Option-click it, to reset the app to 100%.
- In the tiles layout, click an app's icon to mute or unmute it.

## VoiceOver

Every control has a spoken label:

| Element | VoiceOver reads |
|---|---|
| Menu bar icon | "Hush", or "Hush, update available" when there's a new version |
| Output pill | "Output: *device name*" |
| Fader, slider or tile | "*App* volume", with the value "*62* percent". It's adjustable: use VoiceOver's increment and decrement commands to change it in 5% steps. Every layout reads the same. |
| Mute button | "Mute *App*", or "Unmute *App*" when muted |
| Warning badge | "Warning:" followed by the problem, for example "Hush couldn't control this app's audio, so it's playing normally." |
| Gear button | "Settings" |

The level meters (and the tiles' green glow) are decorative and hidden from VoiceOver, as is the small layout preview in Settings. VoiceOver reads the level even when **Show percentages** is off.

When controls are disabled, because Hush doesn't have permission or the app isn't running, they ignore every kind of input, including VoiceOver adjustments.

## Display settings

- **Reduce motion:** strips and the update banner no longer animate when they're added, removed or reordered.
- **Increase contrast:** fader tracks, the 100% tick, meter backgrounds, tile outlines and the mute button get stronger outlines and fills, and the system accent colour (if you chose it) is darkened further in light mode.
- **Colour:** states never rely on colour alone. A muted app also reads **Muted** with a slashed speaker, and a boosted app shows its percentage.
