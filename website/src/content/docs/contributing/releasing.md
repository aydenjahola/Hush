---
title: Releasing
description: How a Hush release is cut with release-please, built into a DMG and published to the website.
---

Releases are automated with [release-please](https://github.com/googleapis/release-please). You merge pull requests with Conventional Commit titles. release-please turns them into a release pull request. Merging that pull request creates a **draft** release, the release workflow builds and attaches the DMG, and then it publishes the release.

The flow is **draft → DMG uploaded → published**. It works this way because the repository has release immutability turned on: once a release is published, its assets and tag can't change.

## One-time repository setup

- **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"** must be on, so release-please can open its pull request.
- **Settings → Pages → Build and deployment → Source** must be **GitHub Actions**, so the website can deploy.
- **Settings → General → Pull Requests**: allow **squash merging** only, with the default commit message set to the pull request title.
- **Settings → General → Releases → Enable release immutability** is on. The release workflow is built around it (see below).
- **A `RELEASE_PLEASE_TOKEN` secret** (Settings → Secrets and variables → Actions). This is a fine-grained personal access token scoped to this repository only, with **Contents** and **Pull requests** set to read and write, and an expiry date. release-please uses it to open its pull request, so the pull request counts as yours and CI runs on it straight away. Without the secret, release-please falls back to `GITHUB_TOKEN`. Its pull requests then come from `github-actions[bot]`, so GitHub holds their CI runs until you click **Approve and run workflows**. When the token expires, create a new one and update the secret.

## 1. Write Conventional Commit titles

Pull requests are **squash-merged**, and the squash commit uses the pull request title as its message. release-please reads those messages on `main` to choose the next version and write `CHANGELOG.md`, so the **pull request title** must be a Conventional Commit. The commits inside the branch can be anything. The **PR title** check (`.github/workflows/pr-title.yml`) fails a pull request whose title doesn't match:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+
```

For example `fix(audio): keep the tap alive after sleep`. GitHub's default revert titles (`Revert "feat: add X"`) are accepted too. release-please's own pull requests (`chore(main): release 0.2.0`) already match.

The check skips pull requests opened by bots (author type `Bot` or a login ending in `[bot]`, such as Imgbot and Dependabot). Their titles still become the squash commit, so when you merge one, change the title to a Conventional Commit (for example `chore: optimize images`), or accept that it won't appear in the changelog.

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

1. tag the merge commit `vX.Y.Z` (`"force-tag-creation": true` in `release-please-config.json`, because GitHub doesn't create the tag of a draft until it's published);
2. create a **draft** GitHub release with the changelog section as its notes (`"draft": true`).

Nobody outside the repository can see the draft yet, and the website still shows the previous version. Finish (publish) a draft before you merge the next release pull request, so releases go out in order.

## 5. The DMG is built, attached and published

Everything happens in one workflow, `.github/workflows/release.yml`. It's one workflow on purpose: a release created with the default `GITHUB_TOKEN` doesn't start other workflows, so a separate "build on release" workflow would never run. After release-please creates the draft, the workflow:

1. checks that the release for the tag exists and is still a draft;
2. checks that the tag matches `version.txt`;
3. runs the tests;
4. builds a universal (arm64 and x86_64) `Hush.app` and packages it as a DMG;
5. uploads `Hush-X.Y.Z.dmg` and `Hush.dmg`, plus a `.sha256` checksum file for each, to the draft;
6. downloads the uploaded files again and verifies them against the checksums;
7. publishes the release and marks it as the latest.

Publishing is the last step, so a release is never public without its DMG.

The fixed name `Hush.dmg` keeps `https://github.com/aydenjahola/Hush/releases/latest/download/Hush.dmg` pointing at the newest release, which is the link the website's download button uses.

### Signing and notarization

Releases are ad-hoc signed by default, and users follow the Gatekeeper steps on the [install page](/Hush/getting-started/install/). If you add the `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` secrets, the workflow signs with your Developer ID using the hardened runtime, then notarizes and staples the DMG. Setting only one group of secrets produces a warning and an ad-hoc or un-notarized build.

### If the build fails

A failed build leaves the release as a draft with the tag in place. Nothing is public, so you can fix it:

- **A flaky failure** (a runner hiccup, a notarization timeout): open the failed run and choose **Re-run failed jobs**. Uploads replace any files an earlier attempt left on the draft. Don't choose **Re-run all jobs**: release-please has already created the release, so it won't report a new one and the build is skipped.
- **The run is too old to re-run, or you want a fresh run**: go to **Actions → Release → Run workflow**, keep the branch as `main` and enter the tag, for example `v0.2.0`. The build only runs when dispatched from `main`; from any other branch it's skipped. This skips release-please, then checks out that tag, builds, uploads and publishes the draft.
- **The code at the tag is broken** (the tests fail, say): that version can't ship. Delete the draft but **keep the tag**, because release-please finds the previous version from it. Then merge the fix to `main` as a `fix:` pull request. release-please opens the next patch release pull request as usual.

The manual run refuses a release that's already published.

### Published releases are immutable

Once published, a release's DMG, checksums and tag can't be changed or replaced. If a published release has a bug, even just in packaging, don't try to edit it. Merge a `fix:` pull request and ship a new patch release.

## 6. The website updates itself

When the release is published, the `pages` job in `release.yml` calls the **Deploy website** workflow (`.github/workflows/pages.yml`), which also runs whenever `CHANGELOG.md` or `website/` changes on `main`. At build time the download button asks GitHub for the latest published release (drafts don't count) and shows its tag, for example "v0.2.0 · macOS 26+". Nothing on the site needs a manual version bump.

If the site hasn't updated a few minutes after a release, run the workflow by hand: **Actions → Deploy website → Run workflow**.

## 7. Check the release

1. Open https://aydenjahola.github.io/Hush/ and check the version on the download button.
2. Download the DMG from the button, install it as a new user would, follow the Gatekeeper steps and open Hush.
3. Check **Settings → About** for the new version, and check the [changelog page](/Hush/changelog/).
4. Verify the checksum: put `Hush.dmg.sha256` next to `Hush.dmg` and run `shasum -a 256 -c Hush.dmg.sha256`.
