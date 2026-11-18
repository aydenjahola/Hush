# Contributing to Hush

Thanks for helping. Hush is small, so the rules are short. The full contributor docs are [on the website](https://aydenjahola.github.io/Hush/contributing/build-from-source/).

- **Build and unit tests.** You need Xcode 26 or later ([Build from source](https://aydenjahola.github.io/Hush/contributing/build-from-source/)). `make test` must pass.
- **Audio changes need the integration tests.** Any change to audio behaviour (engines, taps, aggregate devices, the process monitor, or how the mixer starts, swaps or stops engines) must pass `make integration-test` before it merges. The unit tests use fake engines, so they keep passing when real muting breaks. Setup (BlackHole 2ch and the Audio Recording permission) is in the [testing guide](https://aydenjahola.github.io/Hush/contributing/testing/#integration-tests). CI runs these tests only experimentally, so run them locally and mention it in your pull request.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, …): release-please builds the changelog from them. Keep commits small and focused.
- **Realtime code.** Nothing inside an IOProc may allocate, lock, log, call Objective-C or await.

By contributing you agree that your work is licensed under the [GNU General Public License v3.0](LICENSE).
