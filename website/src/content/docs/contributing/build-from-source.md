---
title: Build from source
description: Build, test and install Hush on your own Mac with Xcode 26, and work on this website.
---

Hush is a Swift package with a small Makefile. To just use Hush, [download the DMG](/Hush/getting-started/install/) instead: you only need Xcode to build it yourself.

## Requirements

- macOS 26 or later.
- **Xcode 26 or later.** The Command Line Tools alone aren't enough, because Swift Testing and the SwiftUI and Observation macros ship with Xcode.
- `git`.

Select Xcode once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for a single command. The Makefile stops with a clear message if neither points into an Xcode app whose version is 26 or later.

## Get the code

```sh
git clone https://github.com/aydenjahola/Hush.git
cd Hush
```

## Build, test and run

```sh
make test     # run the unit tests
make app      # build build/Hush.app (release, ad-hoc signed)
make run      # build the app and launch it
make install  # build, quit Hush, replace /Applications/Hush.app and relaunch it
```

When Hush launches, a speaker icon appears in the menu bar and macOS asks for permission to record system audio. Click **Allow**.

### Make targets

| Target | What it does |
|---|---|
| `make build` | `swift build`: a debug build of every module, with no app bundle. |
| `make test` | `swift test`. |
| `make app` | Builds the `Hush` product, assembles `build/Hush.app` with `Resources/Info.plist` and the version from `version.txt`, checks the plist and ad-hoc signs it with `Resources/Hush.entitlements`. |
| `make run` | `make app`, then opens `build/Hush.app`. |
| `make install` | `make app`, then asks a running Hush to quit (falling back to `pkill` after 5 seconds), replaces `/Applications/Hush.app` and relaunches it. A failed build leaves your installed copy alone. |
| `make dmg` | `make app`, then packages `build/Hush-<version>.dmg` and a copy named `build/Hush.dmg`. |
| `make icon` | Regenerates `Resources/Hush.icns` and the website icons from `scripts/make-icon.swift`. |
| `make clean` | Deletes `.build/` and `build/`. |

`make app` builds the release configuration for your own architecture. Add `ARCHS="arm64 x86_64"` to `make app`, `make dmg` or `make install` for a universal binary. For a debug app bundle, run `make app CONFIG=debug`.

### Telling a local build from a release

Apps you build yourself show an orange **DEV** badge next to "Hush" in the popover. Hover over it to see the commit the build came from. **Settings → About** shows the version as, for example, `0.2.0 (local build, 545d335)`. A `-dirty` suffix on the commit means the build had uncommitted changes. Only the release workflow builds with `CHANNEL=release`, so downloaded DMGs show no badge.

### Always run the app bundle

Run `Hush.app` with `make run`, not the bare executable from `swift run` or Xcode's Run button. The app bundle carries Hush's bundle ID (`io.github.aydenjahola.Hush`), the `LSUIElement` flag that keeps it out of the Dock, and the audio recording usage description. Without them the permission prompt and the Settings window misbehave.

### Permission prompts after rebuilding

Every build gets a new ad-hoc code signature, so macOS may treat it as a new app and ask for audio recording permission again. Click **Allow**. If the old entry gets in the way, reset it and relaunch:

```sh
tccutil reset AudioCapture io.github.aydenjahola.Hush
```

### Install your own build

```sh
make install
```

An app you built yourself isn't quarantined, so Gatekeeper doesn't block it.

## Logs

Hush logs through `os.Logger` with the subsystem `io.github.aydenjahola.Hush` and the categories `engine`, `processes`, `output` and `settings`. To follow them live:

```sh
log stream --level debug --predicate 'subsystem == "io.github.aydenjahola.Hush"'
```

## Work on this website

The site lives in `website/` and is built with [Astro](https://astro.build/) and [Starlight](https://starlight.astro.build/). You need Node.js 22.23.4 or later (`website/.nvmrc` pins the major version).

```sh
cd website
npm ci          # install the exact locked dependencies
npm test        # unit tests for the release lookup
npm run dev     # live preview at http://localhost:4321/Hush/
npm run build   # production build into website/dist, with link checking
npm run preview # serve the production build at http://localhost:4321/Hush/
```

- Docs pages are Markdown files in `website/src/content/docs/`. The sidebar is set in `website/astro.config.mjs`.
- Links between docs pages must be absolute and include the `/Hush` base and a trailing slash, for example `/Hush/contributing/build-from-source/`. The build fails on a broken or relative internal link.
- Search only works in a production build (`npm run build && npm run preview`), not in `npm run dev`.
- If `npm run dev` returns straight away and prints a stop command, Astro has started the server in the background. Stop it with `npx astro dev stop`.
- The favicon and logo in `website/public/` are generated by `make icon`. Don't edit them by hand.
