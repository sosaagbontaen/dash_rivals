# Dash Rivals

> **DO NOT BUILD THE ROADMAP YET.**
>
> [ROADMAP.md](ROADMAP.md) is a product vision document, not a current implementation
> specification. The current task is to build the smallest possible 100m prototype that
> allows us to evaluate whether the core race is fun and immersive. See [BRIEF.md](BRIEF.md).

## What this is

A mobile 3D track-and-field racing game **proof of concept** for iOS. One event (100m),
one stadium, 8 fictional sprinters. The only question the POC answers:

> Can a short 100m race on an iPhone feel so immersive and satisfying that the player
> immediately wants to run another race?

## Tech

- Native Swift, SwiftUI shell + SceneKit renderer. No external dependencies, no assets —
  stadium, athletes, textures, and audio are all generated procedurally in code.
- iOS 17+, iPhone only, landscape.
- Xcode project uses filesystem-synchronized groups (Xcode 16+ format): every file under
  `DashRivals/` is automatically part of the target. Add/remove source files freely;
  never edit `project.pbxproj` to register files.

## Build & run

```bash
xcodebuild -project DashRivals.xcodeproj -scheme DashRivals \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Or use the iOS Simulator MCP tools (build + launch + screenshot) from Claude Code.

### Debug autopilot (tuning aid)

Launch args (DEBUG-relevant, parsed in `GameController`):

```bash
xcrun simctl launch booted com.dashrivals.poc -autopilot -apq 0.9
```

- `-autopilot` — the game plays itself: starts races, holds SET, taps with human-like
  timing noise, and re-runs after results.
- `-apq <0..1>` — autopilot tap quality (timing sd = 0.02 + (1-q)·0.25). Rough finish
  times: q=1.0 → ~9.75, 0.9 → ~9.9, 0.8 → ~10.1, 0.7 → ~10.3, 0.5 → ~11.0.
- `-aponce` — stop after one race and hold on the results screen.

`scratchpad tune2.swift` (session scratchpad) mirrors the player model for headless
tuning; keep `RaceEngine` formulas in sync if retuning.

## Layout

- `DashRivals/` — all app sources (synced into the Xcode target automatically)
  - `Game/` — simulation, athletes, procedural runner models, stadium, cameras, audio
  - `UI/` — SwiftUI HUD, menus, results
- `BRIEF.md` — the POC spec. This is the active document.
- `ROADMAP.md` — long-term vision. **Not to be implemented.**

## The mechanic (current design)

Hold both sides to crouch into SET → gun fires after a random delay → first movement
launches (reaction timed; early movement = false start penalty) → alternate L/R taps in
sync with the on-screen metronome pulses. Three sprint phases by distance: DRIVE
(0–28m, cadence ramps 3.1→4.3 Hz, generous window, each quality tap adds an impulse),
MAX VELOCITY (28–82m, 4.4 Hz, tight window), HOLD FORM (82m+, fatigue bites). Rhythm
quality is shown live on the FORM meter and superlinearly drives effective top speed.
Final 6m: plant both thumbs to LEAN — a dip timed to land on the line saves up to
0.03s. Target cadence is distance-based (predictable/learnable), never velocity-based.

## Product principles (POC)

- Optimize the loop: race → result → immediately race again.
- One excellent gameplay camera beats five mediocre ones.
- Feel > realism > feature count. If the race doesn't feel good, nothing else matters.
- All athletes are fictional and original. No real athletes, no real likenesses.
- Do not add: multiplayer, backend, accounts, monetization, career mode, extra events,
  extra stadiums, or any Phase 1–14 roadmap feature.
