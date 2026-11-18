---
title: Architecture
description: How Hush changes another app's volume with Core Audio process taps, and how the code is organised.
---

Hush changes the volume of individual apps without an audio driver. It uses Core Audio *process taps* and needs macOS 26 or later. This page explains the moving parts and where they live in the code.

## The big picture

For each app you adjust, Hush:

1. Creates a **private process tap** on the app's audio processes, with the tap set to mute the app at the source.
2. Creates a **private aggregate device** that contains your current output device and the tap.
3. Runs an **IOProc** on that aggregate device that reads the tapped audio, applies your gain and writes it to the output.

You hear the app only through Hush's copy, at the level you chose. A muted app is the same engine at gain 0. Apps at 100% and unmuted are left alone. Taps and aggregate devices are private to the Hush process, so when Hush quits or crashes, macOS destroys them and every app plays normally again.

## Modules

The Swift package has four targets, each depending only on the ones above it in this table:

| Target | Responsibility | Key types |
|---|---|---|
| `HushCore` | Pure logic with no system frameworks beyond Foundation. Fully unit tested. | `VolumeCurve`, `SoftLimiter`, `SampleProcessor`, `MeterBallistics`, `AppVolumeSetting`, `Preferences`, `SettingsDocument`, `StripOrdering`, `SemanticVersion`, `UpdatePolicy`, `UpdateSettings`, `HushIdentity` |
| `HushAudio` | Everything that talks to Core Audio and the system. | `AudioProcessMonitor`, `RunningStatePoller`, `AppIdentityResolver`, `DefaultOutputMonitor`, `AppAudioEngine`, `BufferRouting`, `AudioCapturePermission`, `CoreAudioProperty` |
| `HushUI` | State and SwiftUI views. | `MixerStore`, `SettingsStore`, `UpdateChecker`, `GitHubReleaseFetcher`, `MixerPopover`, `ChannelStrip`, `VerticalFader`, `LevelMeter`, `MuteButton`, `PermissionBanner`, `UpdateBanner`, `SettingsView` |
| `HushApp` | The `@main` entry point: a `MenuBarExtra` with the `.window` style plus a `Settings` scene. | `HushApp` |

`HushIdentity.bundleID` (`io.github.aydenjahola.Hush`) is the single source for the `os.Logger` subsystem and the prefix of every aggregate device UID.

## State: `MixerStore`

`MixerStore` is a `@MainActor @Observable` class and the single source of truth for the mixer UI. It receives events from four sources, each behind a protocol so tests can fake them:

| Protocol | Real implementation | Tells the store about |
|---|---|---|
| `AudioProcessSource` | `AudioProcessMonitor` | Apps with Core Audio process objects, and whether each one is playing |
| `OutputDeviceSource` | `DefaultOutputMonitor` | The system default output device |
| `AudioCapturePermissionSource` | `AudioCapturePermission` | The audio capture (TCC) permission state |
| `SettingsPersisting` | `SettingsStore` | Loading and saving `settings.json` |

Engines come from an `AudioEngineFactory`, so tests can swap in fake engines too.

### The reconcile rule

After every change (an app appears or starts playing, a level moves, the output changes, the popover opens or closes, permission changes), `MixerStore.reconcile()` makes the set of running engines match this table:

| Condition | Engine |
|---|---|
| No permission, or no output device | None. Every engine is torn down. |
| The app is playing and is muted or not at 100% | **Control** engine (gain 0 when muted) |
| The app is playing at 100%, unmuted, and the popover is open | **Meter-only** engine |
| Anything else | None |

An engine is also replaced when the app's set of process object IDs changes, for example when a browser starts a new helper. The replacement is built before the old engine stops, so audio never passes through unprocessed in between. When an app disappears, its engine and any error go with it, but its saved setting stays for its return.

A control engine exists only while the app is playing. Hush learns that an app has started playing from Core Audio and from a polling backstop (see [Finding apps](#finding-apps-audioprocessmonitor)), and only then creates the tap. That's why the first instant of a new sound can play at normal volume: it can last up to about a second, and usually much less. See [Known limitations](/Hush/help/known-limitations/).

:::note
A mute tap that nothing reads doesn't actually silence the app, so Hush mutes with a normal control engine at gain 0 rather than a special no-IO tap.
:::

If creating an engine fails, the store records a short message for that app, which shows as a warning badge on its strip, and doesn't retry until something relevant changes: the app's level or mute, the output device, the app quitting, or **Reset All Levels**.

## The engine: `AppAudioEngine`

Each engine owns one tap, one aggregate device and one IOProc.

- **Tap:** `CATapDescription(stereoMixdownOfProcesses:)` over all of the app's process objects, marked private. A control engine uses `muteBehavior = .mutedWhenTapped`, so the original audio is silenced. A meter-only engine uses `.unmuted`, so the app plays normally while Hush just measures it.
- **Aggregate device:** private, not stacked, with the current output device as the main sub-device and the tap in its tap list. Tap drift compensation and tap auto-start are both on.
- **IOProc:** the aggregate's input buffer list starts with the output device's own input streams, such as a headset microphone, followed by the tap's streams. The engine counts the device's input streams and skips them, so a microphone on the output device is never played back.

### Realtime rules

The IOProc runs on Core Audio's realtime thread. The code it calls (`BufferRouting`, `SampleProcessor`, `SoftLimiter`) doesn't allocate, take locks, log, call Objective-C or use async. Before the IOProc starts, the engine runs the routing code once on the main thread so the Swift runtime's lazy initialisation happens there and not on the audio thread.

The main thread and the IOProc share three atomics: the target gain, the gain applied on the previous buffer and the peak level.

### Gain, curve and limiter

- `VolumeCurve` maps the percent on the fader to a linear gain. Up to 100% the curve is quadratic, so the fader feels even (50% is about −12 dB). Above 100% it's linear, so 150% means 1.5×.
- Every buffer ramps linearly from the previously applied gain to the current target, so moving a fader never clicks.
- When the gain is above 1, every sample passes through `SoftLimiter`. Samples below 0.9 of full scale pass unchanged. Above that, a `tanh` curve bends them into the remaining headroom, so output stays below 1.0 and never hard-clips.

### Channel routing

`BufferRouting` copies the stereo mixdown to the output:

- Mono input fans out to every output channel.
- Two or more input channels map one-to-one onto output channels. On a 5.1 or 7.1 device, the stereo tap therefore plays on the front left and right only, and the other channels stay silent.
- Output frames beyond the input are zeroed.

### Output device changes

`DefaultOutputMonitor` listens for changes to the default output device. When it changes, `MixerStore` asks every engine to `rebuild(outputDeviceID:)`, which tears down the tap and aggregate and builds them again on the new device. While that happens, the tap is briefly gone and apps play at their normal level. If a rebuild fails, that engine is torn down and its strip shows a warning.

## Finding apps: `AudioProcessMonitor`

The monitor listens to `kAudioHardwarePropertyProcessObjectList` and to each process's `kAudioProcessPropertyIsRunningOutput`, and publishes one `AudioApp` per app the user would recognise. It skips Hush's own process.

Core Audio doesn't reliably notify when an existing process object starts or stops playing (a browser pausing and resuming a video is the usual example), so a `RunningStatePoller` re-reads each process's running flag on a timer. It polls every 3 seconds normally and every second while the popover is open or any app is muted, lowered or boosted. That second is the upper bound on how late a control engine can start.

`AppIdentityResolver` attributes helper processes to their app. Browsers and chat apps often play audio from helpers. It asks the system for the process *responsible* for each audio process (the private `responsibility_get_pid_responsible_for_pid`, resolved with `dlsym`). If that isn't available, it looks for a running app that owns the process's bundle ID, and otherwise falls back to the executable name. This is why audio from a command-line tool appears under the terminal app that launched it.

## Permission: `AudioCapturePermission`

There's no public API to read the audio capture permission. Hush resolves `TCCAccessPreflight` and `TCCAccessRequest` from the private TCC framework at runtime. On first launch, when the status is undetermined, it requests access, which shows the system prompt. If the symbols are ever missing, Hush reports "authorized" and lets the first tap creation trigger the system prompt instead.

## Meters

While the popover is open, the store polls every engine's peak about 30 times a second (every 33 ms), but only for apps that are playing. `MeterBallistics` gives the meters an instant attack and a release of 20 dB per second, and maps levels onto a −60 to 0 dB scale. When the popover closes, polling stops and meter-only engines are torn down.

## Persistence: `SettingsStore` and `SettingsDocument`

Settings live at `~/Library/Application Support/Hush/settings.json`, a versioned JSON document (`version: 1`). Each app is keyed by bundle ID, or by executable name when there isn't one. The same file holds the preferences and the update checker's state.

- Saves are debounced: the store writes 500 ms after the last change, and flushes any pending save when Hush quits.
- `normalized()` clamps every level to the current maximum boost and drops entries at the default (100%, unmuted) before encoding.
- A file that can't be decoded, or that has an unknown version, is moved aside to `settings.corrupt-<unix-time>.json`, and Hush starts with defaults.
- Every field added after the first release is optional on disk, so older files still decode.

## Update notifier: `UpdateChecker`

Hush is notify-only: it never downloads or installs anything. `UpdateChecker` asks the GitHub Releases API (through `GitHubReleaseFetcher`) for the latest release about 30 seconds after launch and then once a day.

- `UpdatePolicy` decides whether a release is newer than the running version (`SemanticVersion`), whether it was skipped or snoozed, and when to check next. Failed checks retry after 1 hour, then 4 hours, then daily. Rate-limit hints from GitHub are honoured, capped at 24 hours.
- Requests send `If-None-Match` with the last ETag, so an unchanged answer costs almost nothing, and carry only a generic `Hush/<version>` user agent. Only release URLs on `github.com` are trusted.
- When a newer version exists, the popover shows `UpdateBanner`, the menu bar icon gets a dot and a notification is posted once per version, with **Download**, **Later** and **Skip This Version** actions. **Later** snoozes for 24 hours. **Skip** is remembered across launches until a newer release appears.
- Settings has a **Check for updates automatically** toggle and a **Check Now** button. With the toggle off, Hush makes no request at all.
- The fetcher, the notifier and the clock are injected, so the tests never touch the network or the notification centre.

## UI notes

- Strip order comes from `StripOrdering`: playing apps first, then the most recently adjusted, then by name. While the popover is open the order is frozen and new apps join at the end, so nothing jumps under your cursor.
- The gear uses `SettingsLink`, the reliable way to open Settings from a `MenuBarExtra` in an `LSUIElement` app. It also activates Hush so the window comes to the front.
- Views respect Reduce Motion (no reorder animation) and Increase Contrast (stronger tracks, ticks and meter backgrounds).

See [Testing](/Hush/contributing/testing/) for how each layer is tested.
