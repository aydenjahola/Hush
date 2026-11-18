---
title: Settings
description: Launch at login, maximum boost, showing idle apps, resetting levels, update checks, and where Hush keeps its settings.
---

To open Settings, click the gear button in the bottom-right corner of the mixer. The Settings window comes to the front even if another app is active.

## General

### Launch at login

Turn this on to start Hush automatically when you log in. Hush registers itself as a login item, and it appears in **System Settings → General → Login Items**.

If macOS refuses, the reason appears in small text under the switch and the switch turns back off. Moving Hush into your Applications folder first usually helps. You can also check whether Hush is turned off in **Login Items**.

### Maximum boost

Choose how far the faders can go above an app's own volume: **100%**, **150%** or **200%**. The default is 200%.

- **100%** turns boosting off. Faders only turn apps down.
- Lowering the maximum also lowers any app saved above it. For example, an app at 180% drops to 150% when you choose 150%. Raising the maximum again doesn't bring back the old level.

### Show apps that aren't playing

Off by default. When it's on, the mixer also shows:

- running apps that have a Dock icon but aren't playing anything, so you can set their level before they make a sound;
- apps you've saved a level for, even if they're not running.

Background processes and system services aren't listed unless they're playing, or you've saved a level for them.

Strips for apps that aren't playing are dimmed. An app that isn't running is shown with its name and icon, but its controls are disabled until it runs.

## Levels

### Reset All Levels…

Puts every app back to 100% and unmuted, and forgets all saved levels. Hush asks you to confirm first: **"Reset all app levels?"**

## Updates

Hush tells you when a new version is available. It never downloads or installs anything by itself.

### Check for updates automatically

On by default. About 30 seconds after launch, and then once a day, Hush asks GitHub's public API for the latest release of Hush. If a newer version exists, you get:

- a banner at the top of the mixer;
- a dot on the menu bar icon;
- a macOS notification, once per version. macOS asks for permission to show notifications the first time. If you decline, the banner and dot still appear.

Each of these offers three choices:

| Choice | What it does |
|---|---|
| **Download** | Opens the release in your browser. Clicking the notification itself does the same. |
| **Later** | Hides the banner and dot for 24 hours. |
| **Skip This Version** | Hides them for good, until an even newer version comes out. |

If a check fails, for example because you're offline, Hush tries again after an hour, then after four hours, then daily.

Turn the switch off and Hush makes no network requests at all. To see exactly what the check sends, read the [privacy notes](/Hush/help/privacy/).

### Check Now

Runs a check straight away and shows the result next to the button: **Checking…**, then **Hush is up to date**, **Hush X.Y.Z is available** (with a **Download** link) or **Couldn't check for updates**. It works even when automatic checks are off.

## About

Shows the version of Hush you're running and a link to the source code on GitHub. Hush is free software under the GNU General Public License v3.0, and comes with no warranty.

## Where settings are stored

Hush keeps everything in one file:

```text
~/Library/Application Support/Hush/settings.json
```

It looks like this:

```json
{
  "apps" : {
    "com.spotify.client" : {
      "isMuted" : false,
      "lastAdjusted" : "2026-11-17T21:04:11Z",
      "percent" : 62
    }
  },
  "preferences" : {
    "maxBoostPercent" : 200,
    "showInactiveApps" : false
  },
  "updates" : {
    "automaticUpdateChecks" : true,
    "lastUpdateCheck" : "2026-11-17T21:00:02Z"
  },
  "version" : 1
}
```

- Each app is listed by its bundle ID, or by its executable name if it doesn't have one.
- `percent` is clamped to between 0 and your maximum boost when the file is read.
- The `updates` section remembers the update checker's state: whether automatic checks are on, the version you skipped, when "Later" ends and when Hush last checked. It may be missing or partly filled in.
- Hush rewrites the file after every change, so quit Hush before editing it by hand.
- If the file can't be read, for example because it isn't valid JSON or comes from a newer version of Hush, Hush moves it aside as `settings.corrupt-<number>.json` in the same folder and starts with default settings. Your old file isn't deleted.
