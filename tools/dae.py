"""Minimal Mixamo Collada reader: joint hierarchy (bind matrices) + per-joint
animation matrices per frame. Everything in raw file units (cm) with the
file's Y-up axis, exactly as SceneKit exposes the node transforms."""
import xml.etree.ElementTree as ET
import numpy as np

NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}


def _mat(text):
    v = np.array([float(x) for x in text.split()], dtype=np.float64)
    return v.reshape(4, 4)  # Collada matrices are row-major


class Rig:
    def __init__(self, path):
        root = ET.parse(path).getroot()
        self.parent = {}
        self.bind = {}      # local bind matrix
        self.order = []     # parents before children
        vs = root.find("c:library_visual_scenes/c:visual_scene", NS)

        def walk(node, parent):
            name = node.get("name") or node.get("id")
            if node.get("type") == "JOINT":
                m = node.find("c:matrix", NS)
                self.bind[name] = _mat(m.text) if m is not None else np.eye(4)
                self.parent[name] = parent
                self.order.append(name)
                parent = name
            for ch in node.findall("c:node", NS):
                walk(ch, parent)

        for n in vs.findall("c:node", NS):
            walk(n, None)

        # animations: id "<joint>-anim" -> output float_array of 16*N
        self.anim = {}
        self.times = None
        for a in root.findall("c:library_animations/c:animation", NS):
            aid = a.get("id", "")
            if not aid.endswith("-anim"):
                continue
            joint = aid[:-5].replace("mixamorig_", "mixamorig:")
            for src in a.findall("c:source", NS):
                sid = src.get("id", "")
                fa = src.find("c:float_array", NS)
                if fa is None:
                    continue
                vals = np.array([float(x) for x in fa.text.split()])
                if sid.endswith("-input"):
                    self.times = vals
                elif sid.endswith("-output-transform"):
                    self.anim[joint] = vals.reshape(-1, 4, 4)

        # joint names in the scene may be "mixamorig_X" or "mixamorig:X"; normalise
        def norm(n):
            return n.replace("mixamorig_", "mixamorig:")

        self.bind = {norm(k): v for k, v in self.bind.items()}
        self.parent = {norm(k): (norm(v) if v else None) for k, v in self.parent.items()}
        self.order = [norm(k) for k in self.order]

    def short(self, name):
        return name.split(":")[-1]

    def by_short(self, short):
        for n in self.order:
            if self.short(n) == short:
                return n
        raise KeyError(short)

    # ---- pose helpers ----
    def frame_locals(self, frame):
        """Local matrices at an animation frame (bind where unanimated)."""
        out = {}
        for n in self.order:
            out[n] = self.anim[n][frame] if n in self.anim else self.bind[n]
        return out

    def world(self, locals_):
        """World matrix for every joint given local matrices."""
        w = {}
        for n in self.order:
            p = self.parent[n]
            w[n] = (w[p] @ locals_[n]) if p else locals_[n]
        return w


# ---- quaternion utilities (x, y, z, w) ----
def mat_to_quat(m):
    r = m[:3, :3]
    # strip scale
    sx, sy, sz = [np.linalg.norm(r[:, i]) for i in range(3)]
    r = r / np.array([sx, sy, sz])
    t = np.trace(r)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (r[2, 1] - r[1, 2]) / s
        y = (r[0, 2] - r[2, 0]) / s
        z = (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        w = (r[2, 1] - r[1, 2]) / s
        x = 0.25 * s
        y = (r[0, 1] + r[1, 0]) / s
        z = (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        w = (r[0, 2] - r[2, 0]) / s
        x = (r[0, 1] + r[1, 0]) / s
        y = 0.25 * s
        z = (r[1, 2] + r[2, 1]) / s
    else:
        s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        w = (r[1, 0] - r[0, 1]) / s
        x = (r[0, 2] + r[2, 0]) / s
        y = (r[1, 2] + r[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return q / np.linalg.norm(q)


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def rotvec_to_quat(v):
    a = np.linalg.norm(v)
    if a < 1e-12:
        return np.array([0, 0, 0, 1.0])
    ax = v / a
    return np.array([*(ax * np.sin(a / 2)), np.cos(a / 2)])


def compose(t, q):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(q)
    m[:3, 3] = t
    return m
