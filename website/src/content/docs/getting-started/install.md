---
title: Install Hush
description: Download the Hush disk image, move the app to Applications and get past Gatekeeper on first launch.
---

Hush is a menu bar app for macOS 26 or later. It's free and open source, and it has no audio driver, so installing it is just copying an app. You don't need Xcode.

## Requirements

- macOS 26 or later.
- Permission to record system audio. Hush asks for this the first time it runs. See [First launch](/Hush/getting-started/first-launch/).

## Download

1. Download `Hush.dmg` from the [latest release](https://github.com/aydenjahola/Hush/releases/latest). The file named `Hush-x.y.z.dmg` is the same app with the version in its name.
2. Open the disk image.
3. Drag **Hush** into your **Applications** folder.
4. Eject the disk image.

If no release is listed yet, you can [build Hush from source](/Hush/contributing/build-from-source/) instead.

### Check your download (optional)

Each DMG has a matching `.sha256` file. Put it in the same folder as the DMG and run this there:

```sh
shasum -a 256 -c Hush.dmg.sha256
```

Use `Hush-x.y.z.dmg.sha256` if you downloaded the versioned file. It prints `OK` when the file is intact.

## Open Hush for the first time

Hush isn't signed with a paid Apple Developer ID or notarized by Apple. The first time you open it, macOS blocks it and says it couldn't verify the app. This is expected, and you only need to approve Hush once.

### Option 1: Open Anyway in System Settings

1. Double-click **Hush** in Applications. macOS shows **"Hush" Not Opened**. Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security**. You'll see a message that Hush was blocked. Click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open Anyway** in the dialog that follows.

:::note
On older versions of macOS you could right-click the app and choose **Open** to skip this check. Since macOS 15 that no longer works, so use **Open Anyway** or the Terminal command below.
:::

### Option 2: Remove the quarantine flag in Terminal

macOS marks files downloaded from the internet as quarantined. Removing the mark lets Hush open normally:

```sh
xattr -dr com.apple.quarantine /Applications/Hush.app
```

Then open Hush from Applications as usual.

Once Hush is running, a speaker icon appears in your menu bar. Hush has no Dock icon and no main window. Everything happens from that menu bar icon. Continue with [First launch](/Hush/getting-started/first-launch/).

## Update Hush

Hush tells you when a new version is available, but it never installs one itself. About 30 seconds after launch, and then once a day, it asks GitHub for the latest release. When there's a newer one, you see a banner in the mixer, a dot on the menu bar icon and a notification. See [Settings](/Hush/using/settings/#updates) to turn this off and [Privacy](/Hush/help/privacy/) for exactly what's sent.

To update:

1. Click **Download** on the banner or notification. Your browser downloads the new DMG.
2. Quit Hush: right-click the gear in the mixer and choose **Quit Hush**.
3. Open the disk image and drag Hush into Applications, replacing the old copy.
4. Open Hush again. You may need to repeat the Gatekeeper steps above.

Your saved levels and settings are kept. Every build of Hush has a new ad-hoc signature, so macOS may ask you to allow audio recording again after an update.

## Uninstall Hush

1. Quit Hush: right-click the gear in the mixer and choose **Quit Hush**.
2. Drag **Hush** from Applications to the Trash.
3. Delete your saved levels and settings by removing the folder `~/Library/Application Support/Hush`. In Finder, choose **Go → Go to Folder…** and paste the path, or run `rm -r ~/Library/Application\ Support/Hush` in Terminal.
4. If you turned on **Launch at login**, remove Hush from **System Settings → General → Login Items**.
5. Remove Hush from the audio recording permission list:

   ```sh
   tccutil reset AudioCapture io.github.aydenjahola.Hush
   ```

When Hush quits, macOS removes everything Hush set up, so every app plays at its normal volume straight away.
