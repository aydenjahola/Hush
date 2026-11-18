---
title: Privacy
description: What Hush listens to, what it stores, and the one network request it makes.
---

Hush doesn't collect or send any data about you or your audio.

## Audio

Hush listens to an app's audio only to change its volume and to draw its level meter. The audio is processed in memory on your Mac, never saved and never sent anywhere. See [First launch](/Hush/getting-started/first-launch/#why-hush-needs-audio-recording-permission) for why macOS asks you for permission.

## What Hush stores

Your levels, mute states and preferences are saved in `~/Library/Application Support/Hush/settings.json`. See [Settings](/Hush/using/settings/#where-settings-are-stored). Nothing else is kept, and nothing leaves your Mac.

## The update check

The only network request Hush makes is the update check. It contacts GitHub once a day, and can be turned off.

About 30 seconds after launch and then once a day, Hush asks GitHub's public API for the latest Hush release. The request carries only:

- a generic `Hush/<version>` user agent;
- standard HTTP headers: `Accept`, `Accept-Language: en` and the GitHub API version;
- an `If-None-Match` tag, so an unchanged answer costs almost nothing.

There are no cookies, accounts or other identifiers. As with any web request, GitHub sees your IP address.

If a check fails, Hush retries after 1 hour, then 4 hours, then daily. When a newer version exists, Hush shows a banner in the mixer, a dot on the menu bar icon and a notification. **Download** opens the release in your browser. Hush never downloads or installs anything itself.

To turn the check off, clear **Check for updates automatically** in [Settings](/Hush/using/settings/#updates). With it off, Hush makes no request at all, unless you press **Check Now**.
