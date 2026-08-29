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

- `-autopilot` — the game plays itself: starts races, holds SET, tracks the effort
  band with human-like lag/noise/over-press bias, leans at the line, re-runs after
  results.
- `-apq <0..1>` — autopilot tracking quality (lag 0.06+(1-q)·0.5s, noise sd
  0.008+(1-q)·0.15, over-press bias (1-q)·0.12). q=0.85 finishes ≈ 10.0–10.1.
- `-aponce` — stop after one race and hold on the results screen.

A `tune*.swift` script in the session scratchpad mirrors the player model for headless
tuning; keep `RaceEngine` formulas in sync if retuning.

Build gotcha: if Xcode has the project open, the shared DerivedData can serve a stale
binary even though `xcodebuild` reports success. Build with an explicit
`-derivedDataPath` and install that .app when testing from the CLI.

## Layout

- `DashRivals/` — all app sources (synced into the Xcode target automatically)
  - `Game/` — simulation, athletes, procedural runner models, stadium, cameras, audio
  - `UI/` — SwiftUI HUD, menus, results
- `BRIEF.md` — the POC spec. This is the active document.
- `ROADMAP.md` — long-term vision. **Not to be implemented.**

## The mechanics (A/B toggle on the menu: BAND / MOMENTS)

Shared: hold both sides to crouch into SET → gun after a random delay → first movement
launches (reaction timed; moving before the gun = false start penalty). Both thumbs
then ride twin **joystick gauges** at the bottom corners: push out from the stick =
more effort (radial), keep your white deflection ring inside the gold target ring.
The target follows a real sprint's arc: high through the DRIVE, a sharp *relax* drop
into MAX VELOCITY (relax to run fast), then it sinks and wobbles through HOLD ON
(80m+) — chasing it down smoothly is "decelerating slowest". Fixed "breathe" dips at
40/64/86m reward race knowledge; pushing past the band builds tension → extra
deceleration; tracking quality (qBar → FORM meter) superlinearly drives sustainable
speed; thumbs drifting apart costs form. Final 6m: **swipe both thumbs DOWN** to dip
at the line (up to 0.03s; "DIP!" chevron cue at 88m).

- **BAND**: band-riding the whole race.
- **MOMENTS**: 0–30m is a mash — every tap a power step; intensity fills a BURN meter
  (sweet spot ~55%) that you pay for after 80m — then the sticks take over at 30m.

Skill curves validated headlessly (scratchpad tune6/tune7.swift): band — perfect
≈ 9.86 … chaotic ≈ 12.2; moments — optimal-rev ≈ 9.94, masher ≈ 10.1, lazy ≈ 10.3.
AI field runs 9.96–10.4. Cinematic beats: gun impact-freeze, FULL FLIGHT FOV bloom +
letterbox bars past 30m, super-slow-mo final meters, then a trackside long-lens
broadcast REPLAY (tap to skip) into results (photo-finish stamp, wind reading).

## Product principles (POC)

- Optimize the loop: race → result → immediately race again.
- One excellent gameplay camera beats five mediocre ones.
- Feel > realism > feature count. If the race doesn't feel good, nothing else matters.
- All athletes are fictional and original. No real athletes, no real likenesses.
- Do not add: multiplayer, backend, accounts, monetization, career mode, extra events,
  extra stadiums, or any Phase 1–14 roadmap feature.
