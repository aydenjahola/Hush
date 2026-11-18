---
title: The mixer
description: Change each app's volume, boost quiet apps, mute noisy ones and read the level meters.
---

Click the Hush icon in the menu bar to open the mixer. It has three parts:

- **Header:** the name Hush and a pill showing your current output device, such as "MacBook Pro Speakers". If there's no output device, the pill reads "No Output".
- **Strips:** one column per app.
- **Footer:** how many apps are playing, such as "2 apps playing", and the gear button for [Settings](/Hush/using/settings/).

When nothing is playing, the mixer shows **Nothing is playing**. If an update is available, a banner appears at the top. See [Settings](/Hush/using/settings/#updates).

## Which apps appear

An app gets a strip while it's playing audio. Hush groups helper processes under the app you know, so a video playing in a browser tab shows up under the browser, not under a helper process.

To also see apps that aren't playing right now, such as a chat app you want to mute before its next notification, turn on **Show apps that aren't playing** in [Settings](/Hush/using/settings/).

If an app is missing, see [Troubleshooting](/Hush/help/troubleshooting/#an-app-isnt-in-the-mixer).

## Parts of a strip

From top to bottom, each strip has:

| Part | What it shows |
|---|---|
| Percent | The app's level, like `62%`. It turns amber above 100% and reads **Muted** in red when the app is muted. |
| Level meter | A thin bar next to the fader showing how loud the app is right now. |
| Fader | The app's volume, from 0% at the bottom to your maximum boost at the top. |
| Icon | The app's icon, greyed out when muted. A warning triangle on it means Hush couldn't control the app. See [Troubleshooting](/Hush/help/troubleshooting/#a-warning-triangle-appears-on-an-apps-icon). |
| Name | The app's name. Hover to see it in full if it's cut off. |
| Mute button | Mutes or unmutes the app. |

Strips for apps that aren't playing are dimmed.

## Change an app's volume

- **Drag** the fader knob, or click anywhere on the fader to jump there.
- **Scroll** over the fader with a mouse wheel or trackpad. Each step is 5%.
- **Double-click** the knob to put the app back at 100%.
- **Arrow keys:** with the fader focused, press **↑** or **↓** to move 5%. See [Keyboard and accessibility](/Hush/using/keyboard-accessibility/).

When the maximum boost is above 100%, a small tick marks 100% on the fader, and the knob snaps to 100% when you drag within 3% of it. The fader fills white up to 100% and amber above it.

### How the percentages work

- **100%** is the app's own volume, untouched.
- **Below 100%** the fader follows a curve that sounds even to the ear: 50% is about −12 dB, not half as loud on paper.
- **Above 100%** the level is a plain multiplier: 150% is 1.5 times as loud and 200% is twice as loud.

When you boost an app, a soft limiter gently rounds off the loudest peaks so the boosted sound doesn't clip harshly. Below 100% the limiter is off and the audio is only scaled.

The highest level available depends on **Maximum boost** in [Settings](/Hush/using/settings/): 100%, 150% or 200% (the default).

## Mute an app

Click the speaker button at the bottom of the strip. It turns red with a slashed speaker, the percent reads **Muted** and the icon greys out. The fader keeps its position, so unmuting brings the app back to the level it had.

You can mute an app that isn't playing right now, as long as it's running. Hush starts silencing it as soon as it notices the app playing. The very first instant of a new sound can still be heard, for up to about a second and usually much less. See [Known limitations](/Hush/help/known-limitations/).

## Level meters

The meters show each playing app's level on a scale from −60 dB at the bottom to 0 dB (full scale) at the top. They're green, turning yellow in the top 30% of the scale. They jump up instantly and fall back at 20 dB per second.

Meters only run while the mixer is open. They're hidden for muted apps and for apps that aren't playing.

## Strip order

Playing apps come first, then the apps you adjusted most recently, then the rest in alphabetical order.

While the mixer is open, the order stays put so nothing moves under your cursor. Apps that start playing join at the end. The next time you open the mixer, the order is refreshed.

With many apps, scroll the row of strips sideways. The edges fade to show there's more.

## Your output device

Hush plays adjusted apps through the system's default output device, the one you pick in Control Center or **System Settings → Sound**. When you switch, for example by connecting headphones, Hush follows automatically and the header pill shows the new device.

While Hush switches over, apps briefly play at their normal level. See [Known limitations](/Hush/help/known-limitations/).

If there's no output device at all, the pill reads **No Output** and Hush steps aside. Apps play normally until an output device is available again.

## Levels are remembered

Hush saves each app's level and mute state about half a second after your last change, and again when it quits. The next time the app runs, even after a restart, Hush applies the saved level as soon as it notices the app playing.

Apps at 100% and unmuted aren't saved, and Hush doesn't touch their audio at all, except to measure their level while the mixer is open.

To put every app back to 100%, use **Reset All Levels…** in [Settings](/Hush/using/settings/).
