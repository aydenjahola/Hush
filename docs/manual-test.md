# Hush manual test checklist

Run before every release. Build with `make run`.

- [ ] **Two apps at different levels.** Play audio in two apps (e.g. Music and a browser video). Set one to 30% and the other to 150%. Each changes independently.
- [ ] **Boost to 200%.** Play a quiet source and raise it to 200%. It's louder, with no harsh clipping on peaks.
- [ ] **Disconnect headphones mid-playback.** With one app at 50%, unplug or disconnect headphones. Audio continues on the new output at 50%; the header pill shows the new device.
- [ ] **Force-quit Hush mid-playback.** With an app muted, run `killall -9 Hush`. The app's audio returns immediately at normal volume.
- [ ] **Permission denied, then granted.** Run `tccutil reset AudioCapture io.github.hush-mixer.Hush`, relaunch and deny: the banner shows and the controls are disabled. Click "Open System Settings", grant access, reopen the popover: controls work.
- [ ] **Levels restored after relaunch.** Set one app to 60% and mute another. Quit Hush from the gear menu and relaunch. Both settings apply as soon as the apps play.
