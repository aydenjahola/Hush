---
title: Presets
description: Save every app's level and mute state under a name, such as "Call" or "Focus", and switch back to it from the quick menu or Settings.
---

A preset is a named snapshot of every app's level and mute state. For example, a **Call** preset might lower your music to 20% and mute a game, while a **Focus** preset mutes your chat app. You can switch between presets from the [quick menu](/Hush/using/mixer/#quick-menu) or from Settings.

## Save a preset

1. Set up the levels you want in the mixer.
2. Right-click the Hush icon in the menu bar and choose **Presets → Save Current Levels as Preset…**, or click **Save Current Levels as Preset…** in **Settings → Presets**.
3. Type a name and click **Save**.

From the quick menu, Hush opens Settings at the Presets section with the name sheet open, so naming works the same way from both places.

A preset holds every app that isn't at 100% and unmuted, whether or not the app is running. It also stores each app's name, so the preset still makes sense when the app isn't open. Apps at 100% and unmuted aren't stored; applying the preset puts them back at 100%.

Names follow a few rules:

- A name can't be blank. Spaces at the start and end are removed.
- Names are unique, ignoring capitals: "call" and "Call" are the same name.
- Saving with the name of an existing preset asks **"Replace the preset …?"** first. Replacing keeps the preset's place in the list and saves the current levels in it.
- You can keep up to 20 presets. Delete one to save another. Replacing an existing preset still works when you have 20.

## Apply a preset

Choose the preset in the quick menu's **Presets** submenu, or click **Apply** next to it in **Settings → Presets**.

Applying a preset reproduces the snapshot exactly:

- every app in the preset gets its saved level and mute state;
- every other app you've adjusted goes back to 100% and unmuted.

So if you've lowered an app since saving the preset, and that app isn't in the preset, applying the preset resets it. If a preset holds a level above your current [maximum boost](/Hush/using/settings/#maximum-boost), the app gets the maximum instead. The preset itself keeps the saved level.

Applying a preset needs Audio Recording permission, like moving a fader. Without it, the presets and **Save Current Levels as Preset…** are greyed out.

## The active preset

When the current levels exactly match a preset, that preset has a checkmark in the quick menu and in Settings. As soon as you move a fader or mute an app, the levels no longer match and the checkmark goes away. Apply the preset again to go back to it.

## Rename or delete a preset

In **Settings → Presets**, click the **…** button next to a preset (or right-click the preset) and choose **Rename…** or **Delete…**. Hush asks before deleting. Deleting or renaming a preset doesn't change your current levels.

The quick menu's **Presets → Manage Presets…** opens Settings at this section.

## Where presets are stored

Presets are saved in `settings.json` with your other settings, under `presets`. See [Where settings are stored](/Hush/using/settings/#where-settings-are-stored).
