---
title: Performance budgets
description: The CPU and memory budgets Hush has to stay inside, the numbers it measures today, and how to measure them.
---

Hush lives in the menu bar all day, so it has to cost almost nothing while it sits there. These budgets are the bar a change must clear. A change that touches polling, listeners, engines, meters or the popover's views should be measured against them before it merges.

## Budgets

| Scenario | Budget |
|---|---|
| Idle: popover closed, nothing adjusted, a quiet system | Average CPU under 0.1%, and under 1 wake-up per second |
| Idle with ordinary app churn (sounds starting and stopping) | Average CPU under 0.2% |
| An adjusted app is running, popover closed | Average CPU under 0.15%, and no more than 2 wake-ups per second |
| One adjusted app playing (real engine) | Average CPU under 1% |
| Popover open with 3 playing apps | Average CPU under 2% |
| Memory (resident size) | Under 40 MB, with the popover opened and closed |
| Growth over 30 minutes of churn | None: memory settles and `leaks` reports 0 leaks |
| Main-thread work per process-list refresh | Under 2 ms |

Meters poll at about 30 Hz, but only while the popover is visible. Process polling follows the same rule: it covers every process while the popover is open, only the adjusted apps' processes while it's closed, and nothing when there's nothing to watch.

## Where Hush stands

Measured with the headless harness described below, on an Apple M4 running macOS 27 (average CPU of one core):

| Scenario | Measured | Budget |
|---|---|---|
| Idle | 0.06% | 0.1% |
| An adjusted app, popover closed | 0.09% | 0.15% |
| Idle with app churn | 0.11% | 0.2% |
| Popover open, 3 strips with live meters | 1.47% | 2% |
| One adjusted app playing (real engine) | 0.47% before the muted fast path; to be remeasured | 1% |

The harness rows use fake engines, so they exclude real audio processing. The "one adjusted app playing (real engine)" row covers that: it was measured at 0.47% on the owner's Mac with Spotify muted and the popover closed. That figure predates the muted fast path (see below), which skips the per-sample work for a muted app. The owner will measure the new figure and update this row.

Memory sits well under 40 MB with the SwiftUI scene loaded, and a 10 minute churn run showed no leaks and under 1 MB of growth.

## How to measure

Measure a release build, never a debug build, and leave the Mac otherwise quiet. Other audio apps change the numbers.

1. **Build and launch.** `make app`, then open `build/Hush.app`. Use the bundle, not the bare binary.
2. **CPU.** Watch Hush in Activity Monitor (CPU tab, sort by % CPU), or sample it from a terminal for a minute:

   ```sh
   top -l 13 -s 5 -pid "$(pgrep -x Hush)" -stats pid,cpu,mem,rsize,idlew,power
   ```

   Ignore the first sample, which is the average since launch. Average the other twelve. For the popover figure, open it with three apps playing and leave it open for 60 seconds.
3. **Wake-ups.** The `idlew` column is idle wake-ups. For exact figures, run `sudo powermetrics --samplers tasks -i 5000 -n 6 | grep -A1 Hush`.
4. **Memory and growth.** Take `footprint "$(pgrep -x Hush)"` at the start and again after 30 minutes of normal use, with sounds starting and stopping every few seconds. The second number should have plateaued. Then run `leaks "$(pgrep -x Hush)"`: it must report 0 leaks.
5. **Where the time goes.** If a number is over budget, profile it without a UI: `xcrun xctrace record --template 'Time Profiler' --attach "$(pgrep -x Hush)" --time-limit 10s`. Open the trace in Instruments, or export it with `xctrace export`.

### The headless harness

The numbers above come from a throwaway benchmark target that isn't in the repository. It drives the real process monitor, output monitor, `MixerStore` and `UpdateChecker`, with fakes for the engines (random meter peaks), the permission source, persistence and the network, and it can host the real `MixerPopover` in an off-screen window so SwiftUI does real layout and rendering. Building one is a copy of the package plus an executable target that wires those pieces together. Run each scenario for 100 seconds and divide total CPU time (`/usr/bin/time -l`) by wall time, which is more stable than any single `top` sample.

## What keeps it cheap

Don't undo these without measuring:

- The meter task runs only while the popover is visible, and each strip's meter is its own observable, so a tick re-renders one small view rather than the popover.
- The process list is read once per change, behind a coalesced refresh, with per-process identities cached.
- The poller reads only the adjusted apps' processes while the popover is closed.
- Timers carry tolerance, so the system can coalesce wake-ups.
- A muted app's engine takes a fast path in the IOProc. Once its gain has ramped down to exactly 0, each buffer is cleared with `memset` instead of running the gain ramp, the soft limiter and peak metering on every sample. The meter still reads 0 for a muted app, as before, and unmuting ramps up from 0 through the full path.

See [Testing](/Hush/contributing/testing/) for the unit, integration and manual checks that go with these.
