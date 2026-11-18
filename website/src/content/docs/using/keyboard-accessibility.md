---
title: Keyboard and accessibility
description: Control Hush from the keyboard and with VoiceOver, and how it follows your accessibility settings.
---

## Keyboard

| Action | How |
|---|---|
| Open or close the mixer from any app | The shortcut you set in [Settings → General → Keyboard shortcut](/Hush/using/settings/#keyboard-shortcut) (none by default) |
| Raise or lower the focused fader, slider or tile by 5% | **↑** / **↓**, or **→** / **←** |
| Move between controls | **Tab** / **Shift-Tab** |
| Mute or unmute (mute button focused) | **Space** |
| Open the output menu (output pill focused) | **Space**, then **↑** / **↓** and **Return** to choose |
| Close the mixer | **Esc** |
| Open Settings or quit, with the [quick menu](/Hush/using/mixer/#quick-menu) open | **⌘,** or **⌘Q** (or **↑** / **↓** and **Return**) |

This works the same in every [layout](/Hush/using/mixer/#layouts). In the tiles layout, the tile itself is the slider and takes focus; its mute button is the next stop.

If **Tab** skips the faders and buttons, turn on **Keyboard navigation** in **System Settings → Keyboard**.

### Opening the mixer with a shortcut

Hush has no global shortcut until you choose one, so it never takes over a key combination you use elsewhere. Set one in [Settings → General → Keyboard shortcut](/Hush/using/settings/#keyboard-shortcut). Pressing it anywhere works like clicking the Hush icon: it opens the mixer, or closes it if it's open. The mixer opens from the icon, so while the Hush icon can't be seen the shortcut does nothing. That happens when it's turned off in **System Settings → Menu Bar**, and while the menu bar is hidden, such as in a full-screen app.

Hush warns you about combinations that macOS itself uses, and ones another app has claimed exclusively. It can't detect every other app's shortcuts, so pick a combination you don't use elsewhere.

The shortcut doesn't need Accessibility or Input Monitoring permission: macOS tells Hush only when that one combination is pressed, and Hush never sees your other key presses.

## Mouse and trackpad

- Control-click the Hush icon in the menu bar (or right-click it, or click it with two fingers) to open the [quick menu](/Hush/using/mixer/#quick-menu) for output, mute all, Settings and Quit.
- In channel strips, scroll over a fader to change it in 5% steps. In classic rows and tiles a plain scroll moves the list; hold **Option** and scroll over an app to change its volume instead. Scrolling up always raises the level, whatever your natural-scrolling setting.
- Double-click a fader's knob (or anywhere on a tile), or Option-click it in any layout, to reset the app to 100%.
- In the tiles layout, click an app's icon to mute or unmute it.

## VoiceOver

Every control has a spoken label:

| Element | VoiceOver reads |
|---|---|
| Menu bar icon | "Hush", or "Hush, update available" when there's a new version |
| Output pill | "Output: *device name*, pop-up button". Open it with VoiceOver's press command to pick an [output device](/Hush/using/mixer/#output-device). |
| Fader, slider or tile | "*App* volume", with the value "*62* percent". It's adjustable: use VoiceOver's increment and decrement commands to change it in 5% steps. Every layout reads the same. |
| Mute button | "Mute *App*", or "Unmute *App*" when muted |
| Warning badge | "Warning:" followed by the problem, for example "Hush couldn't control this app's audio, so it's playing normally." |
| Gear button | "Settings" |
| Shortcut recorder (Settings) | "Keyboard shortcut", with the shortcut as its value (or "None"), and "Type Shortcut" while it's waiting for keys. The button next to it reads "Clear keyboard shortcut". |

The level meters (and the tiles' green glow) are decorative and hidden from VoiceOver, as is the small layout preview in Settings. VoiceOver reads the level even when **Show percentages** is off.

When controls are disabled, because Hush doesn't have permission or the app isn't running, they ignore every kind of input, including VoiceOver adjustments.

## Display settings

- **Reduce motion:** strips and the update banner no longer animate when they're added, removed or reordered.
- **Increase contrast:** fader tracks, the 100% tick, meter backgrounds, tile outlines and the mute button get stronger outlines and fills, and the system accent colour (if you chose it) is darkened further in light mode.
- **Colour:** states never rely on colour alone. A muted app also reads **Muted** with a slashed speaker, and a boosted app shows its percentage.
