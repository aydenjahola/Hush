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

## Install

1. Download `Hush.dmg` from the [latest release](https://github.com/aydenjahola/Hush/releases/latest).
2. Open it and drag **Hush** onto **Applications**.
3. Open Hush from Applications. macOS blocks it the first time, because Hush isn't signed with a paid Apple Developer ID: it's free and open source, so releases are ad-hoc signed. To allow it, either:
   - open **System Settings → Privacy & Security**, scroll down to the message about Hush, click **Open Anyway** and confirm; or
   - run `xattr -dr com.apple.quarantine /Applications/Hush.app` in Terminal.

   Since macOS 15, right-click → Open no longer bypasses this check.
4. Grant Audio Recording permission when Hush asks.

Each DMG has a matching `.sha256` file (`Hush.dmg.sha256`, `Hush-x.y.z.dmg.sha256`). To check your download, put the `.sha256` file in the same folder as the DMG and run `shasum -a 256 -c Hush.dmg.sha256` there (or the versioned name, to match the DMG you downloaded).

## Uninstall

1. If you turned on "Launch at login", turn it off in Hush's Settings, or remove Hush from System Settings → General → Login Items.
2. Quit Hush (right-click the gear in the popover → Quit Hush).
3. Delete `/Applications/Hush.app`.
4. Remove its saved levels: `rm -r ~/Library/Application\ Support/Hush`
5. Reset its Audio Recording permission: `tccutil reset AudioCapture io.github.aydenjahola.Hush`

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). Xcode itself is optional.

```sh
make test   # run the unit tests
make app    # build build/Hush.app (ad-hoc signed)
make run    # build and launch
make install  # quit Hush, build, replace /Applications/Hush.app and relaunch it
make dmg    # build build/Hush-<version>.dmg (add ARCHS="arm64 x86_64" for a universal binary)
make icon   # regenerate Resources/Hush.icns from scripts/make-icon.swift
```

Run `Hush.app` (via `make run`), not the bare binary from Xcode's Run button. Without the app bundle there's no bundle ID or Audio Recording usage description, so the permission prompt and the Settings window misbehave.

Rebuilding changes the ad-hoc signature, so macOS may ask for Audio Recording permission again.

With only the Command Line Tools installed, use `make test` rather than plain `swift test`: it passes the flag that loads the Swift Testing macro plugin, which the Command Line Tools don't load on their own.

## How it works

For each app you adjust, Hush creates a private process tap that mutes the app at the source, then plays the tapped audio back through a private aggregate device with your gain applied. Lowered or boosted apps are processed only while they play. Muted apps are cheaper: Hush holds a lightweight tap that silences the app for as long as it's running, with no audio processing at all, so a muted app's next sound is silent from its first moment. Apps left at 100% are untouched. If Hush quits or crashes, macOS removes its taps and every app plays normally again.

## Known limitations

- For apps that are lowered or boosted (not muted), up to about a second (usually much less) of each new sound can play at normal volume before Hush notices it and starts processing it.
- Even a muted app can leak its very first sound after it launches, or when it starts a new audio helper process (common in browsers), because Hush can only tap a process once Core Audio reports it.
- Audio from command-line tools is attributed to the terminal app that launched them.
- When you switch output devices, lowered or boosted apps briefly play at their normal level while Hush rebuilds their engines. Muted apps stay muted.

## Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please):

1. Write [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, …) on `main`.
2. release-please keeps a release PR open that bumps `version.txt` and updates `CHANGELOG.md`.
3. Merge the release PR. release-please tags `vX.Y.Z` and creates the GitHub release.
4. The same workflow (`.github/workflows/release.yml`) then runs the tests, builds a universal DMG and uploads `Hush-X.Y.Z.dmg`, `Hush.dmg` and a `.sha256` checksum for each to the release.

The first release is pinned with `"release-as": "0.1.0"` in `release-please-config.json` so it matches `version.txt`. **Remove that line after 0.1.0 ships**, or every later release PR will propose 0.1.0 again.

The repository needs Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" turned on so release-please can open its PR. Releases are ad-hoc signed. If the `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` secrets are ever added, the workflow signs with the Developer ID and notarizes too. Before merging a release PR, run through [docs/manual-test.md](docs/manual-test.md).

## License

Hush is free software, licensed under the [GNU General Public License v3.0](LICENSE).
