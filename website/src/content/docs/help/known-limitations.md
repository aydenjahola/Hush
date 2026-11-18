---
title: Known limitations
description: Things Hush can't do yet, or does differently from what you might expect.
---

## The first instant of a new sound can leak through

Hush processes a muted, lowered or boosted app only while it's playing, and it starts as soon as it notices the app playing. The first instant of a new sound, for example a notification ping from a muted chat app, can therefore play at normal volume before Hush catches up. That can last up to about a second, and is usually much less.

The same applies when an app starts a new audio helper process, which browsers do often. Hush can only tap a process once Core Audio reports it.

## A tiny dropout when Hush takes over a playing app

When Hush starts adjusting an app that's already playing, there can be a tiny (~10 ms) dropout at that moment. It happens once, when you first lower, boost or mute a playing app (or a muted app starts playing), because Core Audio drops one buffer of the app's audio as Hush takes it over. Later changes to that app's level don't cause it.

## Switching output devices causes a short blip

When you change the output device, for example by connecting headphones, Hush rebuilds each adjusted app's tap on the new device. For that moment, apps play at their normal level.

Waking your Mac from sleep doesn't cause this when the output device stays the same: Hush keeps the taps it already has. It still happens after a wake if the output device actually changed while the Mac slept, for example when Bluetooth headphones or a display's speakers reconnect late and macOS switches to the built-in speakers and back.

## Command-line audio is listed under the terminal

Audio from a command-line tool, such as `afplay` or a script, is attributed to the terminal app that launched it. Changing the terminal's strip changes every tool running in it.

## One level per app, not per tab or window

Hush controls whole apps. All tabs in a browser share the browser's strip, and all windows of an app share one level.

## Surround devices play adjusted apps in stereo

Hush captures each adjusted app as a stereo mix. On a 5.1 or 7.1 device or a multichannel interface, an adjusted app plays only on the front left and right speakers. Apps at 100% and unmuted aren't affected.

## Adjusted apps play on the default output

Hush plays adjusted apps through the system default output device. An app that chooses its own output device plays on the default output instead while it's muted, lowered or boosted.

## The app isn't notarized

Hush is ad-hoc signed, not signed with a paid Apple Developer ID, so you need to approve it once before it opens. See [Install Hush](/Hush/getting-started/install/#open-hush-for-the-first-time). Each new version has a new signature, so macOS may ask for audio recording permission again after you update.

## Updates are notify-only

Hush tells you when a new version is available, but you download and install it yourself. See [Update Hush](/Hush/getting-started/install/#update-hush).

## macOS 26 or later only

Hush relies on Core Audio process taps and SwiftUI features that need macOS 26. It doesn't run on earlier versions.

## Permission status uses a private interface

macOS has no public way to check the audio recording permission, so Hush reads it through a private system framework. If a future macOS removes that interface, Hush assumes permission is granted and lets macOS show its own prompt the first time it taps an app. See [Architecture](/Hush/contributing/architecture/#permission-audiocapturepermission).
