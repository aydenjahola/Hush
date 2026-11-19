# Hush roadmap

Where Hush is heading. Plans change, so treat this as direction, not a promise. Each item links to its issue, and each version has a [milestone](https://github.com/aydenjahola/Hush/milestones). Releases bundle several changes; they don't ship one feature at a time.

Ideas and feedback are welcome: [open an issue](https://github.com/aydenjahola/Hush/issues/new/choose).

## Released

- **0.1** to **0.3**: per-app volume, boost and mute; three layouts; level meters; output device switching; the right-click quick menu; a global keyboard shortcut; Launch at Login; no volume blip after sleep.

## 0.4: presets and smarter levels (next release)

- Hide apps from the mixer
- Volume presets ("Call", "Focus") from the quick menu or Settings
- Remember levels for each output device
- Muted apps cost almost no CPU
- Engine and test fixes: no dip on fast toggles, takeover-gap and CI allowances

## 0.5: smart ducking

- [Auto-duck other apps during calls](https://github.com/aydenjahola/Hush/issues/55): music and videos drop while a call app is in a call, then come back.

## 0.6: sound shaping

- [Per-app EQ](https://github.com/aydenjahola/Hush/issues/56): bass, mid and treble, with presets such as Voice and Bass boost
- [Per-app balance and mono](https://github.com/aydenjahola/Hush/issues/57)
- [Loudness levelling](https://github.com/aydenjahola/Hush/issues/58): even out quiet dialogue and loud moments

## 1.0: stable

- [Signed and notarized releases and a Homebrew cask](https://github.com/aydenjahola/Hush/issues/20)
- [Integration tests required in CI](https://github.com/aydenjahola/Hush/issues/21)
- [Translations](https://github.com/aydenjahola/Hush/issues/22)
- [A full VoiceOver and keyboard pass](https://github.com/aydenjahola/Hush/issues/59)
- [Liquid Glass popover background](https://github.com/aydenjahola/Hush/issues/18) and [menu bar icon polish](https://github.com/aydenjahola/Hush/issues/17)
- [Strict memory safety](https://github.com/aydenjahola/Hush/issues/9)

## Later

Smaller improvements and ideas without a version yet are in the [Later milestone](https://github.com/aydenjahola/Hush/milestone/3).
