---
title: The mixer
description: The three mixer layouts, and how to change each app's volume, boost quiet apps, mute noisy ones and read the level meters.
---

Click the Hush icon in the menu bar to open the mixer, and click it again (or press **Esc**, or click anywhere else) to close it. Right-click the icon for the [quick menu](#quick-menu). The mixer has three parts:

- **Header:** the name Hush and a pill showing your current output device, such as "MacBook Pro Speakers". Click it to [switch output device](#output-device). If there's no output device, the pill reads "No Output".
- **Apps:** one strip, row or tile per app, depending on the [layout](#layouts).
- **Footer:** how many apps are playing, such as "2 apps playing", and the gear button for [Settings](/Hush/using/settings/).

When nothing is playing, the mixer shows **Nothing is playing**. If an update is available, a banner appears at the top. See [Settings](/Hush/using/settings/#updates).

## Quick menu

Right-click the Hush icon in the menu bar, click it with two fingers on a trackpad, or Control-click it, to open a short menu without opening the mixer:

- **Output:** the same list of output devices as the [output pill](#output-device), with a checkmark on the current one, and **Sound Settings…** at the bottom.
- **Presets:** your saved [presets](/Hush/using/presets/), with a checkmark on the one the current levels match, then **Save Current Levels as Preset…** and **Manage Presets…**. With no presets saved, it shows **No Presets**.
- **Mute All Playing Apps:** mutes every app that's playing right now, except [hidden apps](#hide-an-app). Each app keeps its level, so unmuting brings it back where it was. Once every playing app is muted, the item reads **Unmute All** instead, which unmutes every muted app, including ones that aren't playing or running at the moment. It's greyed out when there's nothing to mute or unmute, or when Hush doesn't have permission.
- **Settings…** opens [Settings](/Hush/using/settings/).
- **Check for Updates…** checks for a new version straight away, like **Check Now** in [Settings](/Hush/using/settings/#updates).
- **Quit Hush.**

## Which apps appear

An app gets a strip while it's playing audio. Hush groups helper processes under the app you know, so a video playing in a browser tab shows up under the browser, not under a helper process.

To also see apps that aren't playing right now, such as a chat app you want to mute before its next notification, turn on **Show apps that aren't playing** in [Settings](/Hush/using/settings/).

If an app is missing, check that you haven't [hidden it](#hide-an-app), then see [Troubleshooting](/Hush/help/troubleshooting/#an-app-isnt-in-the-mixer).

## Hide an app

Right-click an app's strip, row or tile and choose **Hide _App_** to take it out of the mixer, for example a system sound or a helper you never want to adjust. It works the same in every layout.

A hidden app plays at its normal volume and Hush leaves its audio alone: it isn't listed in any layout, isn't counted in "apps playing", gets no level meter, and **Mute All Playing Apps** and **Unmute All** skip it. If you'd lowered, boosted or muted the app, hiding it puts it back to 100% and unmuted.

To bring an app back, click **Show** next to it under **Hidden apps** in [Settings](/Hush/using/settings/#hidden-apps). It returns at 100% and unmuted.

## Layouts

Choose a layout under **Appearance** in [Settings](/Hush/using/settings/#appearance). All three show the same apps with the same controls: percentage, level meter, volume slider, icon (with the warning badge when something's wrong), name and mute button. The keyboard and VoiceOver controls are the same too, and so is scrolling to change the volume, except that classic rows and tiles need Option held (a plain scroll moves their list).

- **Channel strips** (the default): a column per app with a vertical fader, side by side like a mixing desk. With many apps, scroll the row sideways.
- **Classic rows:** a dense row per app, like Control Center: icon, name, a horizontal slider with a thin level meter under it, percentage and mute button.
- **Tiles:** each app's row is the slider. Drag anywhere on it; the shaded fill shows the volume and a soft green glow shows how loud the app is right now. Click the app's icon to mute or unmute it, or use the mute button at the end of the row.

Rows and tiles stack vertically and scroll once there are more than about six apps.

**Size** in Settings switches between **Comfortable** and **Compact**, which fits more apps with tighter spacing and smaller icons. You can also hide the percentages and the level meters there.

## Parts of a strip

In the channel-strip layout, each strip has, from top to bottom:

| Part | What it shows |
|---|---|
| Percent | The app's level, like `62%`. It turns amber above 100% (primary colour on tiles, where the fill behind it is amber) and reads **Muted** in red when the app is muted. |
| Level meter | A thin bar next to the fader showing how loud the app is right now. |
| Fader | The app's volume, from 0% at the bottom to your maximum boost at the top. |
| Icon | The app's icon, greyed out when muted. A warning triangle on it means Hush couldn't control the app. See [Troubleshooting](/Hush/help/troubleshooting/#a-warning-triangle-appears-on-an-apps-icon). |
| Name | The app's name. Hover to see it in full if it's cut off. |
| Mute button | Mutes or unmutes the app. |

Classic rows and tiles show the same parts in one line. Apps that aren't playing are dimmed in every layout.

## Change an app's volume

- **Drag** the fader knob, or click anywhere on the fader to jump there. In the tiles layout, drag or click anywhere on the tile.
- **Scroll** over a channel strip's fader with a mouse wheel or trackpad. Each step is 5%. In classic rows and tiles a plain scroll scrolls the list, so hold **Option** and scroll over the app you want to change.
- **Double-click** the knob (or anywhere on a tile), or **Option-click** the fader, slider or tile in any layout, to put the app back at 100%.
- **Arrow keys:** with the fader focused, press **↑** or **↓** (or **→** / **←**) to move 5%. See [Keyboard and accessibility](/Hush/using/keyboard-accessibility/).

When the maximum boost is above 100%, a small tick marks 100% on the fader, and the knob snaps to 100% when you drag within 3% of it. The fader fills white (black in light mode) up to 100% and amber above it. If you chose the system accent under **Accent colour** in [Settings](/Hush/using/settings/#accent-colour), the part up to 100% takes that colour instead; boost stays amber. Classic-row sliders also tint the stretch above 100% very faintly, so you can see where boosting starts. Tiles draw a thin line at the volume position.

### How the percentages work

- **100%** is the app's own volume, untouched.
- **Below 100%** the fader follows a curve that sounds even to the ear: 50% is about −12 dB, not half as loud on paper.
- **Above 100%** the level is a plain multiplier: 150% is 1.5 times as loud and 200% is twice as loud.

When you boost an app, a soft limiter gently rounds off the loudest peaks so the boosted sound doesn't clip harshly. Below 100% the limiter is off and the audio is only scaled.

The highest level available depends on **Maximum boost** in [Settings](/Hush/using/settings/): 100%, 150% or 200% (the default).

## Mute an app

Click the speaker button at the bottom of the strip (at the end of the row in classic rows and tiles), or in the tiles layout click the app's icon. The button turns red with a slashed speaker, the percent reads **Muted** and the icon greys out. The fader keeps its position, so unmuting brings the app back to the level it had.

You can mute an app that isn't playing right now, as long as it's running. Hush starts silencing it as soon as it notices the app playing. The very first instant of a new sound can still be heard, for up to about a second and usually much less. See [Known limitations](/Hush/help/known-limitations/).

## Level meters

The meters show each playing app's level on a scale from −60 dB at the bottom to 0 dB (full scale) at the top. They're green, turning yellow in the top 30% of the scale. They jump up instantly and fall back at 20 dB per second.

In classic rows the meter is a thin bar under the slider, and in tiles it's the green glow behind the app's name.

Meters only run while the mixer is open. They're hidden for muted apps and for apps that aren't playing. To measure an app it hasn't adjusted, Hush has to tap it while the mixer is open, which also shows macOS's purple recording dot. If you'd rather not, turn off **Show level meters** in [Settings](/Hush/using/settings/#show-level-meters).

## Strip order

By default, playing apps come first, then the apps you adjusted most recently, then the rest in alphabetical order.

While the mixer is open, the order stays put so nothing moves under your cursor. Apps that start playing join at the end. The next time you open the mixer, the order is refreshed.

To list apps by name instead, choose **Alphabetical** under **Sort apps** in [Settings](/Hush/using/settings/#sort-apps).

With many apps, scroll the row of strips sideways (the edges fade to show there's more), or scroll classic rows and tiles up and down.

## Output device

Click the pill at the top right of the mixer to choose where your Mac plays sound. The menu lists every output device, each with an icon for how it's connected: built-in speakers or headphones, Bluetooth, USB, HDMI or DisplayPort, AirPlay, or a virtual device such as BlackHole. The current output has a checkmark.

Choosing a device changes your Mac's output, exactly like picking it in Control Center or **System Settings → Sound**. Every app follows, not just the ones Hush adjusts, and apps you've adjusted keep their levels. The list updates by itself as you connect or disconnect devices.

**Sound Settings…** at the bottom of the menu opens **System Settings → Sound**, for balance, alert sounds and input devices.

If macOS refuses the switch, a short message appears under the header for a few seconds and the checkmark stays on the device that's really playing.

You can also open the menu from the keyboard. See [Keyboard and accessibility](/Hush/using/keyboard-accessibility/).

### When the output changes

Hush plays adjusted apps through the system's default output device, whether you pick it in Hush, in Control Center or in **System Settings → Sound**. When it changes, for example because you connected headphones, Hush follows automatically and the header pill shows the new device.

While Hush switches over, apps briefly play at their normal level. See [Known limitations](/Hush/help/known-limitations/).

If there's no output device at all, the pill reads **No Output** and Hush steps aside. Apps play normally until an output device is available again.

## Levels are remembered

Hush saves each app's level and mute state about half a second after your last change, and again when it quits. The next time the app runs, even after a restart, Hush applies the saved level as soon as it notices the app playing.

Apps at 100% and unmuted aren't saved, and Hush doesn't touch their audio at all, except to measure their level while the mixer is open.

To put every app back to 100%, use **Reset All Levels…** in [Settings](/Hush/using/settings/).
