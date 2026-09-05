"""Usage: python3 tools/repose.py [--sweep] [--write]   (needs numpy)

Retarget the Start Plank frames (38 = marks, 52 = set) onto real starting
blocks: feet planted on the pedals, hands just behind the line, hips at
set/marks heights. Damped least squares over per-bone rotation deltas
(post-multiplied in the bone's local frame, the same composition SceneKit
applies when BlockPose plays back), then emits BlockPose.swift."""
import numpy as np
from dae import Rig, mat_to_quat, quat_to_mat, rotvec_to_quat

import os
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(REPO, "DashRivals/Assets/Mixamo/")
OUT = os.path.join(REPO, "DashRivals/Game/BlockPose.swift")
rig = Rig(P + "Start Plank/Start Plank.dae")
S = 1.85 * 0.54 / rig.bind[rig.by_short("Hips")][1, 3]   # raw units -> metres
ROOT_Z = -0.35                                           # runner root in world

# ---------------------------------------------------------------- geometry
# World-space, forward = +z, lane centre x = 0, start line z = 0.
PEDAL = {                    # x, plate base z, plate angle (rad), ball distance up the plate
    "L": dict(x=+0.06, zb=-0.60, phi=np.radians(45), t=0.16, gamma=np.radians(30)),
    "R": dict(x=-0.06, zb=-0.88, phi=np.radians(62), t=0.15, gamma=np.radians(45)),
}
FOOT_LEN = np.linalg.norm(rig.bind[rig.by_short("LeftToeBase")][:3, 3]) * S

# Angle of the ankle->ball segment above the sole, from the flat-footed bind pose.
_wb = rig.world({n: rig.bind[n] for n in rig.order})
_a = _wb[rig.by_short("LeftFoot")][:3, 3] * S
_b = _wb[rig.by_short("LeftToeBase")][:3, 3] * S
FOOT_ALPHA = np.arctan2(_a[1] - _b[1], _b[2] - _a[2])   # ankle sits above/behind the ball


def pedal_targets(side):
    p = PEDAL[side]
    ramp = np.array([0, np.sin(p["phi"]), np.cos(p["phi"])])
    base = np.array([p["x"], 0.02, p["zb"]])
    ball = base + p["t"] * ramp
    # Ball of the foot on the plate; the heel drops back and down off it at
    # angle gamma above the track, the way a sprinter loads the pedal.
    seg = np.array([0, np.sin(p["gamma"]), np.cos(p["gamma"])])
    ankle = ball - FOOT_LEN * seg
    return ankle, ball


def w2r(v):
    """world metres -> raw rig units relative to the runner root"""
    return (np.asarray(v, float) - np.array([0, 0, ROOT_Z])) / S


def r2w(v):
    return np.asarray(v, float) * S + np.array([0, 0, ROOT_Z])


# ---------------------------------------------------------------- solver
def solve(locals_, chain, targets, reg=0.02, iters=60, fixed_axes=None):
    """chain: bone short names to rotate. targets: [(bone, world target, weight)].
    fixed_axes: {bone: [axis idx...]} rotation axes to lock (knee = hinge)."""
    bones = [rig.by_short(b) for b in chain]
    base = {b: locals_[b].copy() for b in bones}
    n = 3 * len(bones)
    x = np.zeros(n)
    fixed_axes = fixed_axes or {}
    mask = np.ones(n)
    for b, axes in fixed_axes.items():
        i = chain.index(b)
        for a in axes:
            mask[3 * i + a] = 0

    def apply(xv):
        for i, b in enumerate(bones):
            m = base[b].copy()
            m[:3, :3] = base[b][:3, :3] @ quat_to_mat(rotvec_to_quat(xv[3 * i:3 * i + 3] * mask[3 * i:3 * i + 3]))
            locals_[b] = m

    def residual(xv):
        apply(xv)
        w = rig.world(locals_)
        r = []
        for bname, tgt, wt in targets:
            p = w[rig.by_short(bname)][:3, 3]
            r.extend(np.sqrt(wt) * (p - w2r(tgt)))
        r.extend(np.sqrt(reg) * xv * 100)     # keep close to the mocap pose (radians scaled to ~units)
        return np.array(r)

    lam = 1e-2
    r = residual(x)
    for _ in range(iters):
        J = np.zeros((len(r), n))
        h = 1e-4
        for j in range(n):
            if mask[j] == 0:
                continue
            xp = x.copy(); xp[j] += h
            J[:, j] = (residual(xp) - r) / h
        A = J.T @ J + lam * np.eye(n)
        step = np.linalg.solve(A, -J.T @ r)
        xn = x + step
        rn = residual(xn)
        if rn @ rn < r @ r:
            x, r, lam = xn, rn, max(lam / 3, 1e-6)
        else:
            lam *= 4
            apply(x)
    apply(x)
    return locals_


def report(locals_, label):
    w = rig.world(locals_)
    def W(b): return r2w(w[rig.by_short(b)][:3, 3])
    print(f"--- {label}")
    for b in ["Hips", "LeftFoot", "LeftToeBase", "RightLeg", "RightFoot", "RightToeBase",
              "LeftArm", "LeftHand", "LeftHandMiddle4", "RightHand", "RightHandMiddle4", "Head"]:
        p = W(b); print("   %-16s x=%+.3f y=%.3f z=%+.3f" % (b, *p))
    # arm extension + knee angles
    for side in ("Left", "Right"):
        sh, el, wr = W(side + "Arm"), W(side + "ForeArm"), W(side + "Hand")
        ext = np.linalg.norm(wr - sh) / (np.linalg.norm(el - sh) + np.linalg.norm(wr - el))
        hip, kn, an = W(side + "UpLeg"), W(side + "Leg"), W(side + "Foot")
        v1, v2 = hip - kn, an - kn
        knee = np.degrees(np.arccos(v1 @ v2 / np.linalg.norm(v1) / np.linalg.norm(v2)))
        print("   %s arm %.0f%% straight, knee %.0f°" % (side, ext * 100, knee))


def build(frame, hips_xyz, hips_pitch, hand_z, extra_targets=(), arm_reg=0.02):
    loc = rig.frame_locals(frame)
    H = rig.by_short("Hips")
    loc[H][:3, 3] = w2r(hips_xyz)
    if hips_pitch:
        loc[H][:3, :3] = loc[H][:3, :3] @ quat_to_mat(rotvec_to_quat([hips_pitch, 0, 0]))

    # Legs: ankle + ball on the pedal. Knee treated as a hinge (lock twist/abduction).
    for side, key in (("Left", "L"), ("Right", "R")):
        ankle, ball = pedal_targets(key)
        tg = [(side + "Foot", ankle, 4.0), (side + "ToeBase", ball, 4.0)]
        tg += [t for t in extra_targets if t[0].startswith(side)]
        solve(loc, [side + "UpLeg", side + "Leg", side + "Foot"], tg,
              fixed_axes={side + "Leg": [1, 2]}, reg=0.01)

    # Arms: wrist just off the track, knuckles forward-and-out so the fingertips
    # stop short of the line (a bridge, not a flat slap).
    for side, sx in (("Left", +1), ("Right", -1)):
        wrist = [sx * 0.27, 0.09, hand_z]
        knuckle = [sx * 0.34, 0.05, hand_z + 0.09]
        solve(loc, [side + "Shoulder", side + "Arm", side + "ForeArm", side + "Hand"],
              [(side + "Hand", wrist, 4.0), (side + "HandMiddle1", knuckle, 3.0)], reg=arm_reg)
    return loc


BONES = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
         "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
         "RightShoulder", "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]


def emit(marks, sets):
    def block(name, loc):
        lines = [f"    static let {name}: [(String, SCNQuaternion)] = ["]
        for b in BONES:
            q = mat_to_quat(loc[rig.by_short(b)])
            lines.append('        ("%s", SCNQuaternion(%.6f, %.6f, %.6f, %.6f)),' % (b, *q))
        lines.append("    ]")
        t = loc[rig.by_short("Hips")][:3, 3]
        lines.append("    /// Hips local translation for this pose (model units).")
        lines.append("    static let %sHips = SCNVector3(%.4f, %.4f, %.4f)" % (name, *t))
        return "\n".join(lines)

    src = f"""// Generated by repose.py: the Start Plank mocap (frame 38 = on your marks,
// frame 52 = set) retargeted onto real starting blocks. Feet are IK'd onto the
// pedals defined in Stadium.startingBlock, hands onto the track just behind
// the line, hips lifted to set/marks heights. Regenerate by re-running the
// script; do not hand-edit.
import SceneKit

enum BlockPose {{
{block("marks", marks)}
{block("set", sets)}
}}
"""
    open(OUT, "w").write(src)
    print("wrote", OUT)


def sweep():
    for hy, hz in [(0.70, -0.55), (0.66, -0.58), (0.72, -0.60)]:
        sets = build(52, hips_xyz=[-0.05, hy, hz], hips_pitch=0.0, hand_z=-0.19)
        report(sets, f"SET hips y={hy} z={hz}")
    for hy, hz, pit in [(0.50, -0.58, -0.15), (0.46, -0.60, -0.10), (0.52, -0.55, -0.22)]:
        marks = build(38, hips_xyz=[-0.05, hy, hz], hips_pitch=pit, hand_z=-0.19,
                      extra_targets=[("RightLeg", [-0.10, 0.07, -0.50], 3.0)])
        report(marks, f"MARKS hips y={hy} z={hz} pitch={pit}")


if __name__ == "__main__":
    import sys
    if "--sweep" in sys.argv:
        sweep(); sys.exit()
    print("foot len %.3f  alpha %.1f°" % (FOOT_LEN, np.degrees(FOOT_ALPHA)))
    for k in PEDAL:
        a, b = pedal_targets(k)
        print(" pedal %s ankle=(%+.3f %.3f %+.3f) ball=(%+.3f %.3f %+.3f)" % (k, *a, *b))

    # Set: hips high, both knees off the ground, arms near straight.
    sets = build(52, hips_xyz=[-0.05, 0.72, -0.60], hips_pitch=0.0, hand_z=-0.19)
    report(sets, "SET")
    # Marks: hips low, rear knee on the track beside the front foot.
    marks = build(38, hips_xyz=[-0.05, 0.50, -0.62], hips_pitch=-0.22, hand_z=-0.19,
                  extra_targets=[("RightLeg", [-0.10, 0.07, -0.53], 3.0)])
    report(marks, "MARKS")
    if "--write" in sys.argv:
        emit(marks, sets)
