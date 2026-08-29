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

## The mechanic (current design: effort-band riding — no tapping)

Hold both sides to crouch into SET → gun fires after a random delay → **lift a thumb**
(reaction timed; any movement before the gun = false start penalty) → the remaining
thumb slides vertically, riding a choreographed **effort band** on the right-edge gauge
(white bar = thumb, gold band = target). The band follows a real sprint's arc: high
through the DRIVE (0–30m), a sharp *relax* drop into MAX VELOCITY (the sprinting
paradox: relax to run fast), then it sinks and wobbles through HOLD ON (80m+) — chasing
it down smoothly is "decelerating slowest". Three fixed "breathe" dips at 40/64/86m
reward race knowledge. Riding **above** the band builds tension → extra deceleration
(tighten up = slow down; "RELAX" flash at tension 0.55). Tracking quality (qBar, shown
as FORM) superlinearly drives sustainable speed. Final 6m: plant the second thumb to
LEAN — a dip timed to land on the line saves up to 0.03s.

Skill curve (validated headlessly, see scratchpad tune6.swift): perfect ≈ 9.86,
great ≈ 9.95, good ≈ 10.1, average ≈ 10.7, chaotic ≈ 12.2 vs the AI field's 9.96–10.4.

## Product principles (POC)

- Optimize the loop: race → result → immediately race again.
- One excellent gameplay camera beats five mediocre ones.
- Feel > realism > feature count. If the race doesn't feel good, nothing else matters.
- All athletes are fictional and original. No real athletes, no real likenesses.
- Do not add: multiplayer, backend, accounts, monetization, career mode, extra events,
  extra stadiums, or any Phase 1–14 roadmap feature.
