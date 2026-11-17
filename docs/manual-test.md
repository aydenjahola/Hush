# Hush manual test checklist

Run before every release. `make run` builds `Hush.app` and launches it. Test the app bundle, not the bare binary from Xcode's Run button: without the bundle there's no bundle ID or usage description, so permission and Settings misbehave.

- [ ] **Two apps at different levels.** Play audio in two apps (e.g. Music and a browser video). Set one to 30% and the other to 150%. Each changes independently.
- [ ] **Boost to 200%.** Play a quiet source and raise it to 200%. It's louder, with no harsh clipping on peaks.
- [ ] **Disconnect headphones mid-playback.** With one app at 50%, unplug or disconnect headphones. Audio continues on the new output at 50%; the header pill shows the new device.
- [ ] **Force-quit Hush mid-playback.** With an app muted, run `killall -9 Hush`. The app's audio returns immediately at normal volume.
- [ ] **Output device with a microphone.** Switch output to a device that also has a mic (USB headset, AirPods, or a display with a built-in mic). Set an app to 50%. You hear the app at 50%, not your own microphone.
- [ ] **Multichannel output.** If you have a 5.1/7.1 device or a multichannel interface, set an app to 50%. It plays only on the front left/right pair, not on every speaker.
- [ ] **Permission denied, then granted.** Run `tccutil reset AudioCapture io.github.aydenjahola.Hush`, relaunch and deny: the banner shows and the controls are disabled. Click "Open System Settings", grant access, reopen the popover: controls work.
- [ ] **Permission banner opens the right pane.** With access denied, click "Open System Settings" in the banner. System Settings opens at Privacy & Security → Screen & System Audio Recording, with the System Audio Recording Only list visible.
- [ ] **Levels restored after relaunch.** Set one app to 60% and mute another. Quit Hush from the gear menu and relaunch. Both settings apply as soon as the apps are running.
- [ ] **Muted app's sounds start silent.** Mute a chat or mail app while it's idle, then trigger a notification sound in it (e.g. send yourself a message). The sound is silent from its very first moment, with no blip at full volume. (Lowered rather than muted apps may let the first instant through at normal volume; that's a known limitation.)
- [ ] **Muted idle apps don't keep audio running.** Mute an app, make sure nothing is playing, and run `pmset -g assertions | grep -i audio`. No audio assertion is held on Hush's behalf, and Bluetooth headphones idle as they do without Hush.
- [ ] **Browser pause/resume is noticed.** With the popover closed, pause and resume a YouTube video in Zen and in Chrome. (a) With the browser at 50%: processing kicks in within about 1 s of resuming (the level drops). (b) With no adjusted apps: open the popover after resuming; the browser's strip is there and shows as playing within about 3 s.
- [ ] **No blip when muting or unmuting.** Set a playing app to 50%, then mute and unmute it a few times. Listen for a blip at full volume at each switch; there should be none.
- [ ] **Muted browser, new audio tab.** Mute a browser while one tab plays, then open a new tab that plays audio. Neither tab is ever audible, including the moment the new tab starts.
- [ ] **Settings from the gear.** Click the gear in the popover. The Settings window opens and comes to the front, even when another app is active. Right-click the gear: "Quit Hush" is offered.
- [ ] **Launch at login.** Turn on "Launch at login" in Settings, log out and back in. Hush is in the menu bar. Turn it off; it no longer appears in System Settings → General → Login Items.
- [ ] **Reset all levels.** Set two apps to non-100% levels, then Settings → "Reset All Levels…" → confirm. Both strips go back to 100% and unmuted, and the apps play at normal volume.
- [ ] **Show apps that aren't playing.** Turn the setting on. Only real apps (with a Dock icon) and apps you've saved a level for appear; no system daemons such as callservicesd. A saved app that isn't running shows its real name and icon, dimmed.
- [ ] **No hitch with many apps.** Play audio in 4–5 apps at once and open the popover several times. It opens without a visible stutter and the meters move smoothly.
