---
title: Releasing
description: How a Hush release is cut with release-please, built into a DMG and published to the website.
---

Releases are automated with [release-please](https://github.com/googleapis/release-please). You merge pull requests with Conventional Commit messages. release-please turns them into a release pull request, and merging that pull request publishes the release.

## One-time repository setup

- **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"** must be on, so release-please can open its pull request.
- **Settings → Pages → Build and deployment → Source** must be **GitHub Actions**, so the website can deploy.
- The first release is pinned with `"release-as": "0.1.0"` in `release-please-config.json` so that it matches `version.txt`. **Remove that line after 0.1.0 ships**, or every later release pull request will propose 0.1.0 again.

## 1. Write Conventional Commits

release-please reads the commit messages on `main` to choose the next version and write `CHANGELOG.md`:

| Prefix | Meaning | Version bump |
|---|---|---|
| `fix:` | A bug fix | Patch |
| `feat:` | A new feature | Minor |
| `feat!:`, `fix!:` or a `BREAKING CHANGE:` footer | A breaking change | Major (minor while the version is below 1.0) |
| `docs:`, `test:`, `refactor:`, `chore:`, `ci:` | No user-facing change | None on their own |

A scope is optional and is shown in the changelog, for example `fix(ui): …` or `feat(audio): …`.

## 2. Review the release pull request

After changes land on `main`, release-please opens or updates a pull request titled like `chore(main): release 0.2.0`. It contains:

- the new section of `CHANGELOG.md`;
- the new version in `version.txt`.

Don't edit `CHANGELOG.md` or `version.txt` by hand and don't push tags yourself. release-please owns all of them.

`version.txt` is the single source of truth for the version. `make app` writes it into `CFBundleShortVersionString` in the built app, and that's what **Settings → About** and the update checker show.

## 3. Test before merging

Check out the release pull request's branch, run `make test`, then work through the [manual checklist](/Hush/contributing/testing/#manual-checklist) with `make run`.

## 4. Merge

Merging the release pull request makes release-please:

1. tag the merge commit `vX.Y.Z`;
2. publish a GitHub release with the changelog section as its notes.

## 5. The DMG is built and attached

Everything happens in one workflow, `.github/workflows/release.yml`. It's one workflow on purpose: a release created with the default `GITHUB_TOKEN` doesn't start other workflows, so a separate "build on release" workflow would never run. After release-please creates the release, the workflow:

1. checks that the tag matches `version.txt`;
2. runs the tests;
3. builds a universal (arm64 and x86_64) `Hush.app` and packages it as a DMG;
4. attaches `Hush-X.Y.Z.dmg` and `Hush.dmg`, plus a `.sha256` checksum file for each, to the GitHub release.

The fixed name `Hush.dmg` keeps `https://github.com/aydenjahola/Hush/releases/latest/download/Hush.dmg` pointing at the newest release, which is the link the website's download button uses.

### Signing and notarization

Releases are ad-hoc signed by default, and users follow the Gatekeeper steps on the [install page](/Hush/getting-started/install/). If you add the `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` secrets, the workflow signs with your Developer ID using the hardened runtime, then notarizes and staples the DMG. Setting only one group of secrets produces a warning and an ad-hoc or un-notarized build.

## 6. The website updates itself

When the DMG is uploaded, the `pages` job in `release.yml` calls the **Deploy website** workflow (`.github/workflows/pages.yml`), which also runs whenever `CHANGELOG.md` or `website/` changes on `main`. At build time the download button asks GitHub for the latest release and shows its tag, for example "v0.2.0 · macOS 26+". Nothing on the site needs a manual version bump.

If the site hasn't updated a few minutes after a release, run the workflow by hand: **Actions → Deploy website → Run workflow**.

## 7. Check the release

1. Open https://aydenjahola.github.io/Hush/ and check the version on the download button.
2. Download the DMG from the button, install it as a new user would, follow the Gatekeeper steps and open Hush.
3. Check **Settings → About** for the new version, and check the [changelog page](/Hush/changelog/).
4. Verify the checksum: put `Hush.dmg.sha256` next to `Hush.dmg` and run `shasum -a 256 -c Hush.dmg.sha256`.
