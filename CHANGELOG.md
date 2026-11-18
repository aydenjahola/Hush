# Changelog

## [0.3.0](https://github.com/aydenjahola/Hush/compare/v0.2.0...v0.3.0) (2026-11-18)


### Features

* open the mixer with a global keyboard shortcut ([#40](https://github.com/aydenjahola/Hush/issues/40)) ([353e4dc](https://github.com/aydenjahola/Hush/commit/353e4dcb17385641983f8e10cf7c8f8170681e85))
* **ui:** mark local builds with a DEV badge and commit in About ([#26](https://github.com/aydenjahola/Hush/issues/26)) ([05b1561](https://github.com/aydenjahola/Hush/commit/05b15614749a128d5f96f2242828cb292317fde5))
* **ui:** open a quick menu on right-click of the menu bar icon ([#28](https://github.com/aydenjahola/Hush/issues/28)) ([1b025fa](https://github.com/aydenjahola/Hush/commit/1b025fa94337ee43fa074b850f00a241c6ca504d))


### Bug Fixes

* **audio:** keep adjusted apps' engines across sleep when the output is unchanged ([#33](https://github.com/aydenjahola/Hush/issues/33)) ([1e47b9c](https://github.com/aydenjahola/Hush/commit/1e47b9c8e90761afae65101a4b07f419c40dd562))
* **settings:** show Launch at Login's real state and when it needs approval ([#32](https://github.com/aydenjahola/Hush/issues/32)) ([00acc91](https://github.com/aydenjahola/Hush/commit/00acc91462adddcd10fd5bc33b3d600ae5965f85))
* **ui:** close the mixer when clicking in another app or on the desktop ([#43](https://github.com/aydenjahola/Hush/issues/43)) ([d555d5a](https://github.com/aydenjahola/Hush/commit/d555d5ac2acd3433ae3e930ee62083338462a888))
* **ui:** keep the output pill's chevron next to the device name, and refresh screenshots ([#42](https://github.com/aydenjahola/Hush/issues/42)) ([6a5404e](https://github.com/aydenjahola/Hush/commit/6a5404e0ffa23f3ce8513242f986f79c3ab4d19c))

## [0.2.0](https://github.com/aydenjahola/Hush/compare/v0.1.0...v0.2.0) (2026-11-18)


### Features

* **ui:** switch the system output device from the popover ([#24](https://github.com/aydenjahola/Hush/issues/24)) ([545d335](https://github.com/aydenjahola/Hush/commit/545d335a5de15e521c06643e263d1d458634c967))

## 0.1.0 (2026-11-18)


### Features

* add AppAudioEngine using process taps and private aggregates ([12bdbdd](https://github.com/aydenjahola/Hush/commit/12bdbdd0a60a704e365721521f2037cce3cc00ef))
* add AppVolumeSetting and Preferences models ([6835281](https://github.com/aydenjahola/Hush/commit/6835281ef6f742f07e4a6215faeb3b3c16517a9b))
* add AudioProcessMonitor with helper-process grouping ([5f38787](https://github.com/aydenjahola/Hush/commit/5f387878d7cbb1ac61c8f6a05fed1fdbd1e5b2dc))
* add channel strip controls (fader, meter, mute) ([46a336a](https://github.com/aydenjahola/Hush/commit/46a336a3e97c8abaf7e37ecd9138c08812ac4cc0))
* add Core Audio property helpers, output monitor and permission check ([267d270](https://github.com/aydenjahola/Hush/commit/267d270ae3a7671a3d6dd83705f2c265f124fde7))
* add Hush app entry point, bundle resources and Makefile ([9601141](https://github.com/aydenjahola/Hush/commit/9601141b67e31c800c792ed2dfa28300fdff7a27))
* add HushAudio contracts and realtime buffer routing ([69703ba](https://github.com/aydenjahola/Hush/commit/69703bab585e25fe83581205f9c0aa9229e9a256))
* add JSON SettingsStore with corrupt-file recovery ([cc97c3a](https://github.com/aydenjahola/Hush/commit/cc97c3a3bedc3fef3fb9f135cdfcfc593390a97f))
* add mixer popover, permission banner and settings window ([7d40cdf](https://github.com/aydenjahola/Hush/commit/7d40cdf9d3a39e242cd420426eadaa2fac8f868b))
* add MixerStore with reconcile, persistence and meters ([ffe777b](https://github.com/aydenjahola/Hush/commit/ffe777b9b305486e9165df497221455c7f61b2a8))
* add soft limiter and realtime sample processor ([9f44c8d](https://github.com/aydenjahola/Hush/commit/9f44c8d6c2a469283fd72a57c558031dedada0a9))
* add strip ordering and meter ballistics ([85aaf4c](https://github.com/aydenjahola/Hush/commit/85aaf4c8ea71fa5e7b42653dc14e6ecb60d1ba45))
* add the fader trio app icon ([4c2891b](https://github.com/aydenjahola/Hush/commit/4c2891b8bc5aa15e4a921c832e8188adf7444b82))
* add versioned SettingsDocument with normalization ([2f78331](https://github.com/aydenjahola/Hush/commit/2f78331d9059443d31d68f0556f489399e09be2c))
* **audio:** update a running engine's tap in place (process list and mode) ([68c91bc](https://github.com/aydenjahola/Hush/commit/68c91bca460c3e0a08f47840593bdb66b75e0fe6))
* **build:** add make dmg ([b85f2e8](https://github.com/aydenjahola/Hush/commit/b85f2e84ea02bd5353214c09b8be9470d6f83d82))
* **build:** add make install ([5575e29](https://github.com/aydenjahola/Hush/commit/5575e29b0a6dcc213f8f48f9633222e95982d2a8))
* **build:** stamp the version and support universal builds ([33890cc](https://github.com/aydenjahola/Hush/commit/33890cc9a37a663fa874130ecf9875f469dc3e88))
* **core:** add appearance preferences and an alphabetical sort mode ([9205131](https://github.com/aydenjahola/Hush/commit/92051311773f33c1525edb1f126f25b40478964e))
* **core:** add SemanticVersion ([94dfc3a](https://github.com/aydenjahola/Hush/commit/94dfc3ac05e9e2435721dd2800ba0df452d425ad))
* **core:** add the update decision policy and check schedule ([4ca4a2d](https://github.com/aydenjahola/Hush/commit/4ca4a2d6a2d75e7ff0fb6c121a9d5a8fad00b3ba))
* **core:** persist update notifier settings as optional fields ([b195052](https://github.com/aydenjahola/Hush/commit/b1950525d62a38402227ed85affbdb0134d32bce))
* hold a no-IO mute tap for muted apps instead of a control engine ([e84b379](https://github.com/aydenjahola/Hush/commit/e84b3791854feb5db98d08b4b9ca29156de217fc))
* keep control taps open for adjusted apps while they run ([f34efea](https://github.com/aydenjahola/Hush/commit/f34efea6382f4b7496b07d3f2b5acf537dd6df13))
* re-check audio capture permission when Hush becomes active ([8c8dc09](https://github.com/aydenjahola/Hush/commit/8c8dc0904e50eee3317db884de95575968ea48c7))
* scaffold Swift package with VolumeCurve ([306f712](https://github.com/aydenjahola/Hush/commit/306f7123aad67d9c2115ec97039a10b6bf688ea6))
* show available updates in the popover, menu bar icon and Settings ([4803b51](https://github.com/aydenjahola/Hush/commit/4803b5178063f26355677d8f937d97541d378cf0))
* **ui:** add a notify-only UpdateChecker ([ecc10c7](https://github.com/aydenjahola/Hush/commit/ecc10c75c615470f27835508258d38e80343993a))
* **ui:** add a template menu bar icon with an update badge ([fc0d8fe](https://github.com/aydenjahola/Hush/commit/fc0d8fe8b3cc2be7facb39c3de51ee17ee9f9966))
* **ui:** add Settings → Appearance with three layouts and per-strip meters ([b65aaf2](https://github.com/aydenjahola/Hush/commit/b65aaf2fe684b2c92ba51b5065e4dee820273235))
* **ui:** fetch the latest release from the GitHub API ([dec73dc](https://github.com/aydenjahola/Hush/commit/dec73dc517a857d996d81b3705e0fed8b66b3fd3))
* **ui:** localisation groundwork with a String Catalog ([bc72283](https://github.com/aydenjahola/Hush/commit/bc72283d2c5d763265a6bd72790753cecf43e78b))
* **ui:** offer a fader-glyph menu bar icon ([3db7a67](https://github.com/aydenjahola/Hush/commit/3db7a6790821141cdc508510dbe78744c88f664b))
* **ui:** post update notifications with Download, Later and Skip actions ([d5908e5](https://github.com/aydenjahola/Hush/commit/d5908e5970aa3f0bee3518090cc12508bcc764fa))
* **ui:** send If-None-Match, honor rate-limit retry hints and set Accept-Language ([d8022bc](https://github.com/aydenjahola/Hush/commit/d8022bc1ea5c405a4811991032cf86a51f0d491a))
* **website:** add landing page with build-time latest-release download button ([46b7551](https://github.com/aydenjahola/Hush/commit/46b7551752f1267955780a80cf24eadbef94165d))
* **website:** render CHANGELOG.md on a changelog page ([5c775d3](https://github.com/aydenjahola/Hush/commit/5c775d33cc1a7f1ca21a2b9c909e9308c60654bf))
* **website:** scaffold Astro Starlight site with build-from-source docs ([549e830](https://github.com/aydenjahola/Hush/commit/549e8302b62ec89f1444b77d3340482bfbedb86a))


### Bug Fixes

* **audio:** crossfade the replay on in-place mode switches ([c2a6b29](https://github.com/aydenjahola/Hush/commit/c2a6b29fc0ad2b30813d799f8defc5014e389476))
* **audio:** don't treat a nil bundle ID as a failed read ([212b9ec](https://github.com/aydenjahola/Hush/commit/212b9ec08625a1daf36865dc85b75ee7a0e52cd4))
* **audio:** free warm-up buffer list with free() ([0f70160](https://github.com/aydenjahola/Hush/commit/0f701607436620de8e11887aa6d80aae46d77538))
* **audio:** mute only after the IOProc has rendered a replay buffer ([d8edddd](https://github.com/aydenjahola/Hush/commit/d8eddddd867f04bd4f640051c6950e455e795c9d))
* **audio:** poll process running state because HAL notifications are unreliable ([dca1899](https://github.com/aydenjahola/Hush/commit/dca1899bfc9bf12dd633af0e33fbe222e56d586a))
* **audio:** poll quickly while any app needs a playing-time engine ([b3f222c](https://github.com/aydenjahola/Hush/commit/b3f222cce0718427c875dd304793cf66c213fd88))
* **audio:** rebuild control engines on a new output meter-only and switch in place ([29f808a](https://github.com/aydenjahola/Hush/commit/29f808a12821618ea27146246e0e85575cdce611))
* **audio:** retry unreadable objects and refused listeners; reset on stop ([ed81693](https://github.com/aydenjahola/Hush/commit/ed816934745cfa2f3d6536544a7d3d68a392856a))
* **audio:** route stereo tap one-to-one on multichannel outputs ([4d1ccaa](https://github.com/aydenjahola/Hush/commit/4d1ccaa96e5ca2e1cbf5d92a8db50aa52da79a76))
* **audio:** start fresh control engines meter-only and switch in place once the IOProc runs ([7aa89ca](https://github.com/aydenjahola/Hush/commit/7aa89cac8ac8dc5e9028fb6efab6a2fff3b86471))
* clamp negative meter elapsed time and ignore non-finite rate-limit headers ([d6d6d71](https://github.com/aydenjahola/Hush/commit/d6d6d7107638f4392753c0721c8c5d421278eb44))
* **core:** only trust Hush release URLs on github.com ([0752df6](https://github.com/aydenjahola/Hush/commit/0752df6d1f3984836e08367b27ce53444dce1c1a))
* harden process monitor stop and identity cache ([b0a084a](https://github.com/aydenjahola/Hush/commit/b0a084a918617f47665b7aed1cb8c8421846df69))
* **l10n:** ship en.lproj strings and stringsdict instead of a String Catalog ([e7a71a8](https://github.com/aydenjahola/Hush/commit/e7a71a8a614c21a8e0e4043bacb72c770f2cdf20))
* **l10n:** ship strings + stringsdict so Xcode 26 builds localize correctly ([7aaf28f](https://github.com/aydenjahola/Hush/commit/7aaf28f7fd6b39b7abb80618c688929c0c44d2dc))
* mark TCC request completion block as escaping ([e8b0de1](https://github.com/aydenjahola/Hush/commit/e8b0de1d319aa9a22b4d53ea4ac49680dfdfcb52))
* mute playing apps with a control engine again (no-reader mute taps don't silence) ([b45510a](https://github.com/aydenjahola/Hush/commit/b45510a0bfdc6b95acaaa2d5f3b03abd14f91e0d))
* replace engines make-before-break to avoid mute gaps ([9ebe5e4](https://github.com/aydenjahola/Hush/commit/9ebe5e4699cc6e4f17315846bddd03d533607f9d))
* route only tap streams in the engine IOProc ([9b202d7](https://github.com/aydenjahola/Hush/commit/9b202d7bfb11640b699fcd825e899443aead6bc1))
* stop meter polling cleanly after the popover closes ([a53a2e1](https://github.com/aydenjahola/Hush/commit/a53a2e11b08d52b6c6246111deef8011c74dda55))
* **ui:** change engines in place instead of make-before-break rebuilds ([824805b](https://github.com/aydenjahola/Hush/commit/824805b74a6c1acf3b151792c64b8126d30b487c))
* **ui:** clear meters on failed rebuild and word meter failures accurately ([2c763bc](https://github.com/aydenjahola/Hush/commit/2c763bc8cc6591d1c634410defdbedc90a36d3bc))
* **ui:** clear the fader glyph badge from the third cap and pad the compact tile percent ([f4da145](https://github.com/aydenjahola/Hush/commit/f4da145bfef655a1e2578e173a02eb75d6044cc6))
* **ui:** darken the boost amber in light mode ([62cb615](https://github.com/aydenjahola/Hush/commit/62cb6151015662fb098e2a019c701da140c269ee))
* **ui:** deliver popover-closed report even if the observer view is freed ([c026ff7](https://github.com/aydenjahola/Hush/commit/c026ff7eb5d1af96ebd4d04a65da6965b7cb039a))
* **ui:** give the fader enough contrast in light mode ([6f191b1](https://github.com/aydenjahola/Hush/commit/6f191b1d361560910b3ce6e8c208873150d9c1ea))
* **ui:** ignore fader drag, double-click and VoiceOver adjust when disabled ([d0d5a8d](https://github.com/aydenjahola/Hush/commit/d0d5a8debcb2ec9ad02da9abcf45784983061499))
* **ui:** keep the newest skipped version, clear delivered notifications and treat a notification click as Download ([f12a5b7](https://github.com/aydenjahola/Hush/commit/f12a5b7fc5497b5f9e85a9553846a9e8167ebefa))
* **ui:** keep tile percent legible and render boost as amber ([8fec260](https://github.com/aydenjahola/Hush/commit/8fec260851aaea37c58aabc96791846597c7ed0b))
* **ui:** list only real apps when showing apps that aren't playing ([c1d053b](https://github.com/aydenjahola/Hush/commit/c1d053b9ca100c8881abbd2fb70db83a2946fee4))
* **ui:** never spin the update schedule, and retry failures after 1 h, 4 h, then daily ([6a3409c](https://github.com/aydenjahola/Hush/commit/6a3409c7dafc5076497396502ee0de47a665fb04))
* **ui:** open Settings from the gear with SettingsLink ([a090cd9](https://github.com/aydenjahola/Hush/commit/a090cd9e5f226fc90836d8d3c800175b44a2fa31))
* **ui:** Option+scroll for volume in lists, stable Muted slot, tile contrast, amber boost, preview and menu icon polish ([50fcb52](https://github.com/aydenjahola/Hush/commit/50fcb52b15ef2d001e448dbfb80dda2d0f5adc7e))
* **ui:** poll every present adjusted app, playing or not ([7acc96c](https://github.com/aydenjahola/Hush/commit/7acc96c4f0d074b16492ada3e44367b81b5cc5f7))
* **website:** drop no-IO mute note and release trigger, simplify Gatekeeper and uninstall docs, add robots.txt and og:image ([422ca26](https://github.com/aydenjahola/Hush/commit/422ca2634762c1ee2b8f9ecff39f7071abe04c78))


### Performance Improvements

* **audio:** cache every identity, invalidate on app launch and quit (R-C2) ([3be3af0](https://github.com/aydenjahola/Hush/commit/3be3af0eeb3b0606134b356e0ab4963aaea00c37))
* **audio:** incremental, coalesced process monitor with targeted polling ([54f1b7d](https://github.com/aydenjahola/Hush/commit/54f1b7d7296ed51464d9d8a1870d17737c36fab2))
* **ui:** create the scroll monitor and launch-at-login state lazily ([4b8351b](https://github.com/aydenjahola/Hush/commit/4b8351b4f1e46b83c27ca84ce097c2df5af7beaa))
* **ui:** give the meter loop's sleep a 10% tolerance (R-I5) ([670f739](https://github.com/aydenjahola/Hush/commit/670f7391dea44e5c1719ad70a6ab0501e915ee84))


### Reverts

* **audio:** drop the replay-buffer ack wait before muting ([dabb192](https://github.com/aydenjahola/Hush/commit/dabb19257a321e912f9eb86218afd01e84a0e962))

## Changelog
