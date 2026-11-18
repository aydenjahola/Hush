# Security policy

## Supported versions

Only the [latest release](https://github.com/aydenjahola/Hush/releases/latest) gets security fixes. Hush tells you when a new version is out.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through GitHub instead: go to the [Security tab](https://github.com/aydenjahola/Hush/security), then **Report a vulnerability**, or use [this link](https://github.com/aydenjahola/Hush/security/advisories/new).

Include what you found, how to reproduce it, the Hush and macOS versions, and what an attacker could do with it. You'll get a reply within a week. Once a fix ships, the advisory is published with credit to you unless you'd rather stay anonymous.

## Scope

Hush is a local menu bar app. Its only network request is the daily update check to GitHub's public API, and it never downloads or installs anything itself. Areas of interest:

- the update check (`GitHubReleaseFetcher`) and the URLs it will open;
- how Hush handles the Audio Recording permission and the audio it taps;
- the release pipeline and the DMGs it publishes.

Releases are ad-hoc signed, not notarized. That's a known trade-off, explained in the [install guide](https://aydenjahola.github.io/Hush/getting-started/install/), not a vulnerability.
