---
title: Testing
description: Run Hush's unit tests, the Core Audio integration tests and the manual checklist to work through before every release.
---

Hush has three kinds of tests. Automated unit tests cover all the logic that doesn't need real audio hardware. Integration tests run Hush's real engines against real Core Audio. A manual checklist covers what only a person can check.

## Before every release

1. `make test` passes.
2. `make integration-test` passes, with no tests skipped. See [Integration tests](#integration-tests).
3. Every item in the [manual checklist](#manual-checklist) passes.

Any change to audio behaviour (engines, taps, aggregate devices, the process monitor, or how the mixer starts, swaps or stops engines) must also pass `make integration-test` before it merges.

## Unit tests

```sh
make test
```

The tests use Swift Testing (`@Test` and `#expect`) and need Xcode 26. See [Build from source](/Hush/contributing/build-from-source/) for the setup.

| Target | What it covers |
|---|---|
| `HushCoreTests` | Volume curve, soft limiter (the output never reaches 1.0), sample processing and gain ramps, meter ballistics, setting clamping, settings document versioning and normalisation, strip ordering, semantic versions, the update policy and schedule, and the bundle identifier. |
| `HushAudioTests` | `BufferRouting` (interleaved and non-interleaved layouts, mono fan-out, stereo on six-channel outputs, skipping the output device's own input streams, zero-filling and silence) and the running-state poller. |
| `HushUITests` | `MixerStore` against fake process, output, permission and engine sources: the reconcile rule, control engines for playing adjusted apps, meter-only engines while the popover is open, output changes and failed rebuilds, engine error messages and retries, permission flows, "show apps that aren't playing", frozen strip order, saving and Reset All Levels. `UpdateChecker` against a fake fetcher and notifier. `SettingsStore`: missing, corrupt and unknown-version files. |

Fakes for the `MixerStore` dependencies live in `Tests/HushUITests/`. New behaviour in `MixerStore` should come with a test that drives it through those fakes.

## Integration tests

The unit tests use fake engines, so they keep passing even when real muting breaks. The `HushIntegrationTests` target plays a real tone from a helper process (`HushToneGenerator`), lets Hush tap it, and checks what Core Audio does: that taps receive audio, that gain and boost scale the output, that `stop()` leaves no aggregate device behind, that the process monitor notices playback starting and stopping, and, through the BlackHole loopback, that mute really silences the app, that 50% is 12 dB down, and that changing a running engine in place (a helper process joining or leaving, or a metered app being adjusted) never lets a burst or a gap through.

A plain `swift test` (and CI's build job) reports these tests as skipped. To run them:

1. **Install BlackHole 2ch**, a virtual loopback device. The end-to-end tests play into it and record what comes back:

   ```sh
   brew install --cask blackhole-2ch
   ```

   If it doesn't show up in Audio MIDI Setup, run `sudo killall coreaudiod` or log out and back in. Don't select it as your output: the tests never change the system default output.
2. **Grant Audio Recording.** macOS attributes this permission to the app the tests run from (Terminal, iTerm, VS Code…), not to the test binary, so that's the app that needs it. The first local run asks for it: if the permission was never decided, the system prompt appears once, naming your terminal app, and the run waits up to 60 seconds for you to answer. Under CI (`CI` or `GITHUB_ACTIONS` set) it's never requested.

   To grant it by hand, or if you denied the prompt: System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Turn your terminal app on, or click **+** and add it if it isn't listed. **Quit and reopen the terminal app after granting**: a newly granted app often doesn't get the permission until it relaunches. Without the permission, every test is skipped with these instructions.
3. **Run the tests:**

   ```sh
   make integration-test
   ```

   This builds `HushToneGenerator`, then runs `HUSH_INTEGRATION=1 swift test --no-parallel --filter HushIntegrationTests`. Every test must pass, none skipped. Without BlackHole, the engine-level tests still run, on your default output with a -60 dBFS tone, and the end-to-end tests skip.

   Afterwards it prints how many tests actually ran and whether the BlackHole group ran. Swift Testing counts skipped tests as passed, so `make integration-test` fails if no test ran ("No integration tests ran") or if the BlackHole end-to-end group didn't run, and says why. Set `ALLOW_SKIP=1` to allow either (CI does).

   The check that `stop()` leaves no process tap behind only runs when the HAL lists the test's own taps (`kAudioHardwarePropertyTapList`). If it doesn't, only the aggregate-device check runs.

Leave the Mac alone while the tests run (about a minute). Other audio from the terminal app can disturb the level checks.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

- **build-and-test** runs `swift build` and `swift test` on a macOS 26 runner. The integration tests show as skipped.
- **integration** is experimental and can't fail the build. It installs BlackHole, tries to grant Audio Recording with `scripts/ci-grant-audio-capture.sh` (only possible when SIP is off), runs `ALLOW_SKIP=1 make integration-test`, and reports how many tests passed and were skipped. It becomes required once it proves reliable.
- **website** runs on pull requests that change `website/`. It runs `npm ci`, `npm test` and `npm run build`, and the build fails on any broken internal docs link.

## Manual checklist

Run this before every release, on the build you're about to ship. `make run` builds `Hush.app` and launches it. Test the app bundle, not the bare binary from Xcode's Run button: without the bundle there's no bundle ID or usage description, so permission and Settings misbehave.

- [ ] **Two apps at different levels.** Play audio in two apps (e.g. Music and a browser video). Set one to 30% and the other to 150%. Each changes independently.
- [ ] **Boost to 200%.** Play a quiet source and raise it to 200%. It's louder, with no harsh clipping on peaks.
- [ ] **Disconnect headphones mid-playback.** With one app at 50%, unplug or disconnect headphones. Audio continues on the new output at 50%; the header pill shows the new device.
- [ ] **Force-quit Hush mid-playback.** With an app muted, run `killall -9 Hush`. The app's audio returns immediately at normal volume.
- [ ] **Output device with a microphone.** Switch output to a device that also has a mic (USB headset, AirPods, or a display with a built-in mic). Set an app to 50%. You hear the app at 50%, not your own microphone.
- [ ] **Multichannel output.** If you have a 5.1/7.1 device or a multichannel interface, set an app to 50%. It plays only on the front left/right pair, not on every speaker.
- [ ] **Permission denied, then granted.** Run `tccutil reset AudioCapture io.github.aydenjahola.Hush`, relaunch and deny: the banner shows and the controls are disabled. Click "Open System Settings", grant access, reopen the popover: controls work.
- [ ] **Permission banner opens the right pane.** With access denied, click "Open System Settings" in the banner. System Settings opens at Privacy & Security → Screen & System Audio Recording, with the System Audio Recording Only list visible.
- [ ] **Levels restored after relaunch.** Set one app to 60% and mute another. Quit Hush from the gear menu and relaunch. Both settings apply as soon as the apps are running.
- [ ] **Muted app's notification sound is silenced.** Mute a chat or mail app while it's idle, then trigger a notification sound in it (e.g. send yourself a message). The sound is silenced after at most a brief blip (up to about a second, usually much less; a known limitation).
- [ ] **Adjusted idle apps don't keep audio running.** Mute one app and lower another, make sure nothing is playing, and run `pmset -g assertions | grep -i audio`. No audio assertion is held on Hush's behalf, and Bluetooth headphones idle as they do without Hush.
- [ ] **Browser pause/resume is noticed.** With the popover closed, pause and resume a YouTube video in Zen and in Chrome. (a) With the browser at 50%: processing kicks in within about 1 s of resuming (the level drops). (b) With no adjusted apps: open the popover after resuming; the browser's strip is there and shows as playing within about 3 s.
- [ ] **No blip when muting or unmuting.** Set a playing app to 50%, then mute and unmute it a few times. Listen for a blip at full volume at each switch; there should be none.
- [ ] **Muted browser, new audio tab.** Mute a browser while one tab plays, then open a new tab that plays audio. The tab that was already playing never becomes audible; the new tab is silenced after at most a brief blip.
- [ ] **Settings from the gear.** Click the gear in the popover. The Settings window opens and comes to the front, even when another app is active. Right-click the gear: "Quit Hush" is offered.
- [ ] **Launch at login.** Turn on "Launch at login" in Settings, log out and back in. Hush is in the menu bar. Turn it off; it no longer appears in System Settings → General → Login Items.
- [ ] **Reset all levels.** Set two apps to non-100% levels, then Settings → "Reset All Levels…" → confirm. Both strips go back to 100% and unmuted, and the apps play at normal volume.
- [ ] **Show apps that aren't playing.** Turn the setting on. Only real apps (with a Dock icon) and apps you've saved a level for appear; no system daemons such as callservicesd. A saved app that isn't running shows its real name and icon, dimmed.
- [ ] **No hitch with many apps.** Play audio in 4–5 apps at once and open the popover several times. It opens without a visible stutter and the meters move smoothly.
- [ ] **Release DMG from /Applications, with quarantine.** Run `make dmg ARCHS="arm64 x86_64"` (or download the release's `Hush.dmg`). To simulate a browser download, mark it quarantined: `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" build/Hush.dmg`. Open the DMG: it shows Hush and an Applications shortcut, and Finder shows the fader icon. Drag Hush to Applications and open it from there: Gatekeeper blocks it. Allow it with System Settings → Privacy & Security → "Open Anyway"; Hush launches, asks for Audio Recording permission, and Finder's Get Info on /Applications/Hush.app shows the release version. Repeat with a fresh copy, using `xattr -dr com.apple.quarantine /Applications/Hush.app` instead.
- [ ] **Update notifier.** Run a build whose version is older than the latest GitHub release (e.g. `echo 0.0.1 > version.txt && make run`, then `git checkout version.txt`). About 30 s after launch: macOS asks once for notification permission, a "Hush X.Y.Z is available" notification appears with Download / Later / Skip This Version, the menu bar icon shows a dot (check it in a light and a dark menu bar), and the popover shows the same banner. **Download** opens the release's DMG in the browser and nothing is installed. **Later** hides the banner and dot; they return after 24 h (or after setting `snoozedUntil` in the past in `~/Library/Application Support/Hush/settings.json` and relaunching). **Skip This Version** hides them for good, also after a relaunch, until a newer release exists. Repeat the three actions from the notification itself; clicking the notification body acts as Download, and Download or Skip removes the notification from Notification Center. Deny notifications: the banner and dot still appear. Settings → "Check Now" shows "Checking…" then "Hush X.Y.Z is available"; offline it shows "Couldn't check for updates"; on the current release it shows "Hush is up to date". With "Check for updates automatically" off, relaunching makes no request (watch with Little Snitch or `nettop -p Hush`).

## Website checks

For changes to `website/`:

```sh
cd website
npm ci
npm test        # unit tests for the release lookup
npm run build   # must end with "All internal links are valid."
npm run preview # then check the pages at http://localhost:4321/Hush/
```

In the preview, check the landing page and at least one docs page in light and dark mode, at widths of 1280 px and 400 px, and check that search returns docs results.
