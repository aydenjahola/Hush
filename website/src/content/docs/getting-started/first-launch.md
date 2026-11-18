---
title: First launch
description: Give Hush permission to record system audio and get to know its menu bar icon.
---

The first time Hush runs, macOS asks whether it may record system audio. Hush needs this permission to change other apps' volume.

## Why Hush needs audio recording permission

macOS doesn't let one app change another app's volume directly. Instead, Hush uses a Core Audio *process tap*: it captures an app's sound, silences the original and plays the captured sound back at the level you chose. Capturing another app's audio counts as recording, so macOS asks you first.

Hush only taps apps whose level you've changed, plus, while the mixer is open, the apps that are playing, so it can show their level meters. The audio never leaves your Mac and is never saved.

## Grant permission

1. Open Hush. macOS asks whether Hush may record system audio, and shows Hush's reason: *"Hush listens to each app's audio so it can change its volume."*
2. Click **Allow**.

That's it. Click the speaker icon in the menu bar to open the mixer.

## If you clicked Don't Allow

Hush still runs, but its controls are greyed out and the mixer shows a banner: **"Hush needs Audio Recording access to control app volumes."**

1. Click **Open System Settings** in the banner. System Settings opens at **Privacy & Security → Screen & System Audio Recording**.
2. In the **System Audio Recording Only** list, turn on **Hush**.
3. Click the Hush menu bar icon again. The banner is gone and the controls work.

If Hush isn't in the list, or the switch doesn't seem to work, reset the permission and relaunch Hush so macOS asks again:

```sh
tccutil reset AudioCapture io.github.aydenjahola.Hush
```

## The menu bar icon

Hush lives in the menu bar and has no Dock icon.

- A speaker with **two waves** means every running app is at its normal volume or louder.
- A speaker with **one wave** means at least one running app is muted or turned down.
- A small **dot** on the icon means a new version of Hush is available.

Click the icon to open the [mixer](/Hush/using/mixer/). Click anywhere outside the mixer to close it.

## Quit Hush

Right-click the gear button in the bottom-right corner of the mixer and choose **Quit Hush**.

When Hush quits, or even if it crashes, macOS removes its taps and every app goes back to its normal volume. Your levels are saved and come back the next time you open Hush.

## Next steps

- Learn the controls in [The mixer](/Hush/using/mixer/).
- Turn on **Launch at login** and choose your maximum boost in [Settings](/Hush/using/settings/).
