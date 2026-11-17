# Hush

Per-app volume control for macOS, in your menu bar.

Turn Spotify down, boost a quiet call, mute a noisy tab: Hush gives every app that's playing audio its own fader, mute button and level meter. It uses Core Audio process taps, so there's **no audio driver to install** and no admin password.

## Features

- A fader per app, from silent up to 200% boost, with a soft limiter so boosted audio doesn't clip harshly
- Mute any app with one click
- Live level meters
- Remembers each app's level across restarts
- Apps you haven't touched aren't processed at all (except for level meters while the popover is open)
- Follows your output device when you switch headphones or speakers

## Requirements

- macOS 26 or later
- Audio Recording permission (Hush asks on first launch)

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). Xcode itself is optional.

```sh
make test   # run the unit tests
make app    # build build/Hush.app (ad-hoc signed)
make run    # build and launch
```

Run `Hush.app` (via `make run`), not the bare binary from Xcode's Run button. Without the app bundle there's no bundle ID or Audio Recording usage description, so the permission prompt and the Settings window misbehave.

Rebuilding changes the ad-hoc signature, so macOS may ask for Audio Recording permission again.

With only the Command Line Tools installed, use `make test` rather than plain `swift test`: it passes the flag that loads the Swift Testing macro plugin, which the Command Line Tools don't load on their own.

## How it works

For each app you adjust, Hush creates a private process tap that mutes the app at the source, then plays the tapped audio back through a private aggregate device with your gain applied. Apps left at 100% are untouched. If Hush quits or crashes, macOS removes its taps and every app plays normally again.

## Known limitations

- A muted or lowered app is only tapped once it starts playing, so the first fraction of a second of each sound plays at normal volume.
- Audio from command-line tools is attributed to the terminal app that launched them.
- When you switch output devices, apps briefly play at their normal level while Hush rebuilds its engines.

## License

Hush is free software, licensed under the [GNU General Public License v3.0](LICENSE).
