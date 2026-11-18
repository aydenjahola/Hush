---
title: Troubleshooting
description: Fixes for the most common problems with Hush, and how to collect logs for a bug report.
---

## Hush won't open: "Hush" Not Opened

Hush isn't notarized by Apple, so macOS blocks it the first time. Approve it once with **Open Anyway** in **System Settings → Privacy & Security**, or remove the quarantine flag with `xattr -dr com.apple.quarantine /Applications/Hush.app`. Right-click → Open doesn't work any more on macOS 15 and later. Both options are explained in [Install Hush](/Hush/getting-started/install/#open-hush-for-the-first-time).

## The controls are greyed out and there's a banner

The banner **"Hush needs Audio Recording access to control app volumes"** means Hush doesn't have permission to tap other apps' audio.

1. Click **Open System Settings** in the banner.
2. Under **System Audio Recording Only**, turn on **Hush**.
3. Click the Hush menu bar icon again.

If Hush isn't in the list or the switch doesn't help, reset the permission and relaunch Hush:

```sh
tccutil reset AudioCapture io.github.aydenjahola.Hush
```

More detail is in [First launch](/Hush/getting-started/first-launch/#if-you-clicked-dont-allow).

## Hush asks for permission again after an update

Each build of Hush has a new ad-hoc signature, and macOS may treat a new signature as a new app. Click **Allow** again. If an old **Hush** entry stays in the list, turn it off, or use the `tccutil reset` command above and relaunch.

## An app isn't in the mixer

- **It isn't playing.** By default only apps that are playing audio appear. Turn on **Show apps that aren't playing** in [Settings](/Hush/using/settings/) to see idle apps with a Dock icon.
- **It's listed under another name.** Audio from helper processes appears under the app that owns them, such as a browser. Audio from command-line tools appears under the terminal app that launched them.
- **It's Hush.** Hush doesn't list itself.

## A strip is dimmed or won't move

- A **dimmed** strip belongs to an app that isn't playing. Its controls still work if the app is running.
- If the controls **don't respond at all**, the app isn't running (it's shown because you saved a level for it), or Hush is missing permission (look for the banner).

## A warning triangle appears on an app's icon

Hold the pointer over the triangle to see the message:

- **"Hush couldn't control this app's audio, so it's playing normally."** Hush couldn't set up the tap that changes this app's volume, so you hear it at its own level.
- **"Hush couldn't read this app's level."** Only the level meter failed. The app plays normally.

The technical error follows in brackets. Hush tries again when you change that app's level or mute it, when you switch output devices, when the app quits and opens again, or when you use **Reset All Levels…**. If the warning keeps coming back, [collect logs](#collect-logs-for-a-bug-report) and open an issue.

## The header says "No Output"

macOS has no default output device, for example after you unplug your only audio interface. Hush steps aside and every app plays normally. Pick an output in Control Center or **System Settings → Sound**, and Hush picks it up.

## A muted or lowered app is audible for a moment

Hush starts processing an app when it notices the app playing, so the very first instant of a new sound can play at normal volume, for up to about a second and usually much less. This is a [known limitation](/Hush/help/known-limitations/#the-first-instant-of-a-new-sound-can-leak-through).

## Apps blip at full volume when I switch speakers or headphones

When the output device changes, Hush rebuilds its taps on the new device, and apps play at their normal level for that moment. This is a [known limitation](/Hush/help/known-limitations/#switching-output-devices-causes-a-short-blip).

## A boosted or lowered app plays on the wrong device

Hush plays adjusted apps through the system default output. An app that picks its own output device, such as a music app set to an audio interface, plays on the default output while it's adjusted. Set the app back to 100% to return it to its own device. See [Known limitations](/Hush/help/known-limitations/#adjusted-apps-play-on-the-default-output).

## Launch at login doesn't stick

If macOS refuses, Hush shows the reason under the **Launch at login** switch. Move Hush into your Applications folder, then turn the switch on again. Also check that Hush is allowed in **System Settings → General → Login Items**.

## I'm not told about updates

Check that **Check for updates automatically** is on in [Settings](/Hush/using/settings/#updates), and try **Check Now**. If you chose **Skip This Version**, Hush stays quiet until a newer release comes out. If you declined notifications, the banner and menu bar dot still appear.

## My levels were reset

If Hush can't read its settings file, it moves the file aside as `settings.corrupt-<number>.json` in `~/Library/Application Support/Hush/` and starts with defaults. See [Settings](/Hush/using/settings/#where-settings-are-stored).

## Something sounds stuck or too quiet

Quit Hush (right-click the gear and choose **Quit Hush**). macOS removes every tap Hush made, and all apps go back to their normal volume straight away. If Hush isn't responding, force-quit it with `killall -9 Hush`. That's safe too.

## Collect logs for a bug report

Hush logs with the subsystem `io.github.aydenjahola.Hush`. To capture the last ten minutes:

```sh
log show --last 10m --info --debug --predicate 'subsystem == "io.github.aydenjahola.Hush"' > hush-log.txt
```

Or watch live while you reproduce the problem:

```sh
log stream --level debug --predicate 'subsystem == "io.github.aydenjahola.Hush"'
```

Then [open an issue](https://github.com/aydenjahola/Hush/issues/new) with:

- your macOS version;
- your Hush version (**Settings → About**);
- your output device;
- the steps that cause the problem;
- the log.
