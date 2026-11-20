---
title: Ducking during calls
description: Lower your music and videos automatically while a call app such as Zoom, FaceTime or a Meet tab uses the microphone, and bring them back when the call ends.
---

Ducking lowers every other playing app while you're in a call, then brings them back up when the call ends. For example, if music is playing when a Zoom call starts, the music fades down to 30% of its level, and fades back up a couple of seconds after you hang up.

Ducking is off by default. Turn it on in **Settings → Ducking → Lower other apps during calls**, or choose **Duck During Calls** in the [quick menu](/Hush/using/mixer/#quick-menu).

## How Hush knows you're in a call

A call app is "in a call" while it's using a microphone. Hush sees this through the same audio information it already reads to find playing apps, so ducking needs no extra permission and never asks for microphone access.

- An app has to use the microphone for about half a second before ducking starts, so a quick microphone check doesn't lower anything.
- Ducking ends about 2 seconds after the last call app stops using the microphone. Muting and unmuting yourself in a call app can briefly stop its microphone, and this delay keeps your music from bouncing up and down when you do. Some call apps, such as Discord, may let go of the microphone for as long as you stay muted. If that lasts longer than 2 seconds, other apps come back up until you unmute.
- Apps that use the microphone but aren't on the call apps list, such as a voice recorder, don't start ducking.
- Hush itself never counts.

While ducking is active, the mixer shows a line such as **Ducking for Zoom**, or **Ducking for 2 apps** when more than one call app is in a call. It works with the mixer closed too.

## What gets lowered

Every playing app is lowered except:

- the **call apps**, whether or not they're the one in the call;
- the apps in **Never lower**;
- [hidden apps](/Hush/using/mixer/#hide-an-app). Hush leaves hidden apps alone, so they're never lowered. A hidden call app still counts as being in a call, though.

Call apps are never lowered, even when another call app is in the call. Browsers are on the list because calls in Google Meet (and the web versions of the other apps) run in a browser tab, so Hush can't tell a browser playing music from a browser in a call. For example, music playing in Safari keeps its level during a Zoom call. If you only use a browser for music, remove it from the call apps list so that it's lowered too, or play music in an app that isn't on the list.

For the same reason, any web page that uses the microphone, such as an online voice recorder or dictation, lowers other apps while it listens. If that gets in the way, remove the browser from the call apps list.

## How much to lower

**Lower other apps to** sets how far apps go down, from 0% (silent) to 90%, in steps of 5%. The default is 30%.

The percentage applies to each app's own level, the same way a fader does. An app at 100% plays as if its fader were at 30%. An app you've already set to 50% plays at 30% of that. A muted app stays muted.

## Your levels don't change

Ducking works on top of each app's level and never changes it:

- The faders keep showing your own levels while apps are lowered.
- Moving a fader, muting, applying a [preset](/Hush/using/presets/) or switching the output device during a call works as usual, and the app stays lowered by the same amount.
- Nothing about ducking is saved in your levels, your presets or each device's saved levels. The checkmark on the active preset stays where it was.
- Only the ducking settings themselves are saved.

Apps fade down over less than half a second and back up over about a second. Turning ducking off during a call fades apps back up the same way.

## Call apps

The list starts with Zoom, FaceTime, Microsoft Teams (new and classic), Discord, Slack, Webex, and the Safari, Chrome, Arc, Edge and Firefox browsers. FaceTime's call audio runs in a background part of macOS rather than in the FaceTime app, so that's listed too, as **FaceTime Calls**.

Open **Call apps** in **Settings → Ducking** to change the list:

- **Add App** offers the apps running now that aren't on either list, and **Choose App…** picks any app from your Applications folder.
- **Remove** takes an app off the list.
- **Restore Defaults** puts the list back the way it started.

While you haven't changed the list, Hush follows its own default list, so apps added to it in a later version appear automatically.

## Never lower

Apps in **Never lower** keep their level during calls, for example a podcast app you want to keep hearing. The list is empty to start with. Add and remove apps the same way as call apps.

## Good to know

- Lowering an app that wasn't already adjusted takes it over the same way as moving its fader for the first time, so there can be a very short gap (about 10 to 20 milliseconds) as ducking starts. After the fade back up has finished, Hush stops processing that app again.
- Ducking needs Audio Recording permission, like moving a fader. Without it, **Duck During Calls** in the quick menu is greyed out and nothing is lowered.
- While ducking is off, Hush doesn't watch microphone use at all.
