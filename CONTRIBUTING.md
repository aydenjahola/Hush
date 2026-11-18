# Contributing to Hush

Thanks for helping. Hush is small, so the rules are short.

- **Build and unit tests.** You need Xcode 26 or later (see [Build from source](README.md#build-from-source)). `make test` must pass.
- **Audio changes need the integration tests.** Any change to audio behaviour (engines, taps, aggregate devices, the process monitor, or how the mixer starts, swaps or stops engines) must pass `make integration-test` before it merges. The unit tests use fake engines, so they keep passing when real muting breaks; the integration tests play a real tone and measure what reaches the output. Setup (BlackHole 2ch and the Audio Recording permission) is in [docs/manual-test.md](docs/manual-test.md#before-every-release). CI runs them only experimentally, so run them locally and mention it in your pull request.
- **Commits.** Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, …): release-please builds the changelog from them. Keep commits small and focused.
- **Realtime code.** Nothing inside an IOProc may allocate, lock, log, call Objective-C or await.

By contributing you agree that your work is licensed under the [GNU General Public License v3.0](LICENSE).
