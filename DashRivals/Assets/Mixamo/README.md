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

There is no true four-point block start in Mixamo's library. **Start Plank**
stands in: frames 38 (marks) and 52 (set) are retargeted onto real block
geometry by `tools/repose.py` — legs IK'd onto the pedals, hands onto the
track behind the line, hips lifted — and baked into `BlockPose.swift`, which
plays back as held pose animations. The pedal geometry lives in both the
script and `Stadium.startingBlock`; change one, change the other, re-run
`python3 tools/repose.py --write` and check with `-blockprobe`.

## Measured stride (why the gait still glides)

Measured at runtime from the foot bone, for a 1.85 m athlete:

| clip | cycle | stride / step |
|---|---|---|
| Fast Run, Overdrive 50 | 0.433 s | 0.88 m raw |
| Fast Run, Overdrive 100 | 0.267 s | ~0.84 m raw |
| Overdrive 100 + 1.85x swing boost | 0.267 s | **1.36 m** |
| needed at 10.5 m/s | - | ~2.2 m |

**Overdrive raises intensity and speeds the cycle up; it does not lengthen the
stride.** Both downloads carry roughly the same stride. The engine amplifies
thigh swing, paces from the measured stride, and clamps cadence to 2.4-5.4
steps/s; the remaining mismatch shows as glide (~30%).

Do not cap playback as a ratio - clip lengths differ, and a ratio tuned for a
0.43 s cycle becomes 9 steps/s on a 0.27 s one. Clamp cadence instead.
