# Hush manual test checklist

Run before every release. `make run` builds `Hush.app` and launches it. Test the app bundle, not the bare binary from Xcode's Run button: without the bundle there's no bundle ID or usage description, so permission and Settings misbehave.

- [ ] **Two apps at different levels.** Play audio in two apps (e.g. Music and a browser video). Set one to 30% and the other to 150%. Each changes independently.
- [ ] **Boost to 200%.** Play a quiet source and raise it to 200%. It's louder, with no harsh clipping on peaks.
- [ ] **Disconnect headphones mid-playback.** With one app at 50%, unplug or disconnect headphones. Audio continues on the new output at 50%; the header pill shows the new device.
- [ ] **Force-quit Hush mid-playback.** With an app muted, run `killall -9 Hush`. The app's audio returns immediately at normal volume.
- [ ] **Output device with a microphone.** Switch output to a device that also has a mic (USB headset, AirPods, or a display with a built-in mic). Set an app to 50%. You hear the app at 50%, not your own microphone.
- [ ] **Multichannel output.** If you have a 5.1/7.1 device or a multichannel interface, set an app to 50%. It plays only on the front left/right pair, not on every speaker.
- [ ] **Permission denied, then granted.** Run `tccutil reset AudioCapture io.github.hush-mixer.Hush`, relaunch and deny: the banner shows and the controls are disabled. Click "Open System Settings", grant access, reopen the popover: controls work.
- [ ] **Permission banner opens the right pane.** With access denied, click "Open System Settings" in the banner. System Settings opens at Privacy & Security → Screen & System Audio Recording, with the System Audio Recording Only list visible.
- [ ] **Levels restored after relaunch.** Set one app to 60% and mute another. Quit Hush from the gear menu and relaunch. Both settings apply as soon as the apps play.
- [ ] **Settings from the gear.** Click the gear in the popover. The Settings window opens and comes to the front, even when another app is active. Right-click the gear: "Quit Hush" is offered.
- [ ] **Launch at login.** Turn on "Launch at login" in Settings, log out and back in. Hush is in the menu bar. Turn it off; it no longer appears in System Settings → General → Login Items.
- [ ] **Reset all levels.** Set two apps to non-100% levels, then Settings → "Reset All Levels…" → confirm. Both strips go back to 100% and unmuted, and the apps play at normal volume.
- [ ] **Show apps that aren't playing.** Turn the setting on. Only real apps (with a Dock icon) and apps you've saved a level for appear; no system daemons such as callservicesd. A saved app that isn't running shows its real name and icon, dimmed.
- [ ] **No hitch with many apps.** Play audio in 4–5 apps at once and open the popover several times. It opens without a visible stutter and the meters move smoothly.
