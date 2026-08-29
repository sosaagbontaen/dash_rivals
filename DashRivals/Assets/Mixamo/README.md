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
