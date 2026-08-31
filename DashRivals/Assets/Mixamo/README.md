# Mixamo assets drop zone

Put the Mixamo downloads here (this folder is auto-bundled by the synced Xcode
project). The app detects them at launch; with no files present it falls back to
the procedural v3 athletes.

## What to download (mixamo.com, free Adobe account)

Characters (Download → Collada `.dae` preferred, else FBX Binary; T-pose, with skin):
- `Y Bot` — athletic mannequin, tints per-lane
- one realistic human (e.g. `Remy` or `Malcolm`)

Animations for that character (30 fps, no keyframe reduction, with skin):
- Sprint
- Running
- Standing Idle
- Crouched Idle
- Victory

## Naming

Keep "sprint" / "running" / "idle" / "crouch" / "victory" somewhere in each
animation filename (Mixamo's default names are fine). The character file is
whichever mesh file doesn't match those words.

## Re-download notes (asset-side quality)

The stock **Sprint** clip only covers ~1.6 m per step — a jogging stride. The game
caps leg cadence at a realistic ~4.9 steps/s, so at 11 m/s the feet slide slightly.
To fix it at the source, re-download **Sprint** with:

- **Overdrive ≈ 100** (longer, more aggressive stride — the single biggest win)
- **Character Arm-Space** ~35 (tighter, sprint-like arm carriage)
- "In Place" either way — root motion is compensated in code

There is no true four-point block start in Mixamo's library; the set position is
posed procedurally in `SkinnedRunner.poseBlockStart`.
