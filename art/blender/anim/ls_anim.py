"""
ls_anim.py - Blender side of the LAST STANDING animation pipeline.

    Studio rig data (r15_rig.json)  ->  Blender armature + block body + held item  ->  keyed Action
    ->  baked JSON (per frame, per R15 part: delta from rest)  ->  Studio builds a KeyframeSequence from it.

Conventions
  * 1 Blender unit = 1 stud. Roblox (x, y, z) = Blender (x, z, -y). The character faces Blender +Y (Roblox -Z).
  * The armature object sits at the HumanoidRootPart centre, so armature space = HumanoidRootPart space.
  * One bone per R15 part, named exactly like the part. Bone head = the joint that drives the part. Every bone points
    +Z with roll 0, so all bones share one rest orientation and a rotation given in part axes maps straight onto the
    pose bone.
  * The rest pose is forward kinematics from the rig attachments (child = parent * c0 * c1^-1), which is what Roblox
    assembles when every joint Transform is identity. The part CFrames in the JSON are not used (except the root's).
  * What is exported is, for every frame and part, D = pose * rest^-1 in armature space, converted to Roblox axes.
    Studio turns that into joint Transforms with its own c0/c1, so no bone-roll or rest-pose guess can leak through.

Authoring model
  * LowerTorso (location + rotation), UpperTorso and Head (rotation) are keyed directly: sparse keys, Blender's
    own Bezier interpolation.
  * Hands and feet are driven by control empties (CTL_RightHand, CTL_LeftHand, CTL_RightElbow, CTL_LeftElbow,
    CTL_RightFoot, CTL_LeftFoot). bake_limbs() solves both arms and both legs analytically on every frame and keys the
    limb bones, so planted feet stay planted on every exported frame.
"""
import json
import math
import os

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector

C_B2R = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # p_roblox = C_B2R @ p_blender
C_R2B = C_B2R.transposed()
BONE_LEN = 0.25
ROOT = "HumanoidRootPart"
# Handle frame of a held item inside the item's asset space (Roblox axes): LookVector = +Y (business end),
# UpVector = +Z. Rows of the rotation matrix (right, up, back as columns).
HANDLE_IN_ASSET = [0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 1, 0]

BODY_COLOURS = {
    "Head": (0.80, 0.62, 0.45), "LeftHand": (0.80, 0.62, 0.45), "RightHand": (0.80, 0.62, 0.45),
    "UpperTorso": (0.20, 0.27, 0.33), "LowerTorso": (0.20, 0.27, 0.33),
    "LeftUpperArm": (0.24, 0.32, 0.39), "RightUpperArm": (0.24, 0.32, 0.39),
    "LeftLowerArm": (0.80, 0.62, 0.45), "RightLowerArm": (0.80, 0.62, 0.45),
    "LeftUpperLeg": (0.22, 0.21, 0.19), "RightUpperLeg": (0.22, 0.21, 0.19),
    "LeftLowerLeg": (0.22, 0.21, 0.19), "RightLowerLeg": (0.22, 0.21, 0.19),
    "LeftFoot": (0.12, 0.11, 0.10), "RightFoot": (0.12, 0.11, 0.10),
}


# ------------------------------------------------------------------------------------------------ math
def cf_to_mat(c):
    """Roblox CFrame components (x, y, z, R00..R22) -> Blender 4x4 with the axes converted."""
    R = Matrix((c[3:6], c[6:9], c[9:12]))
    q = (C_R2B @ R @ C_B2R).to_quaternion()
    q.normalize()
    M = q.to_matrix().to_4x4()
    M.translation = C_R2B @ Vector(c[0:3])
    return M


def mat_to_cf7(M, nd=5):
    """Blender 4x4 -> [x, y, z, qx, qy, qz, qw] in Roblox axes."""
    p = C_B2R @ M.translation
    q = (C_B2R @ M.to_3x3().normalized() @ C_R2B).to_quaternion()
    q.normalize()
    if q.w < 0:
        q.negate()
    return [round(v, nd) + 0.0 for v in (p.x, p.y, p.z, q.x, q.y, q.z, q.w)]


def rx(deg):
    return Quaternion((1, 0, 0), math.radians(deg))


def ry(deg):
    return Quaternion((0, 1, 0), math.radians(deg))


def rz(deg):
    return Quaternion((0, 0, 1), math.radians(deg))


def torso_rot(yaw=0.0, pitch=0.0, roll=0.0):
    """Part-axis rotation, Blender axes. yaw + = turn left, pitch + = lean FORWARD, roll + = tip to the right."""
    return rz(yaw) @ rx(-pitch) @ ry(roll)


def blade_frame(blade, edge):
    """Hand orientation (delta from rest) that points a held blade along `blade` with its edge leading along `edge`.
    At rest the blade leaves the bottom of the hand (-Z); the game's Handle UpVector (the blade's spine) is the hand's
    +Y, so the cutting edge is the hand's -Y."""
    z = -Vector(blade).normalized()
    y = -Vector(edge) + z * Vector(edge).dot(z)
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_quaternion()


def _frame(up, hinge):
    y = up.cross(hinge)
    return Matrix((hinge, y, up)).transposed()


def two_bone(S, W, r1, r2, pole, flex_sign):
    """Analytic two-bone IK. S = proximal joint, W = wanted distal joint, r1 / r2 = the rest vectors joint -> joint of
    the two segments (armature axes), pole = direction the middle joint should point. flex_sign +1 for arms (the
    forearm folds toward the part's +Y), -1 for legs (the shin folds toward -Y).
    Returns (R_upper, R_lower, middle, distal, reached): the two rotation deltas from rest."""
    L1, L2 = r1.length, r2.length
    v = W - S
    d = v.length
    reached = True
    dmax = (L1 + L2) * 0.999
    if d > dmax:
        d, reached = dmax, False
    d = max(d, abs(L1 - L2) * 1.001 + 1e-4)
    dirv = v.normalized()
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    pp = Vector(pole) - dirv * Vector(pole).dot(dirv)
    if pp.length < 1e-5:
        pp = Vector((0, 1, 0)) - dirv * dirv.y
    pp.normalize()
    E = S + dirv * a + pp * h
    Wc = S + dirv * d
    n = pp.cross(dirv) * flex_sign
    n.normalize()
    out = []
    for r, up in ((r1, (S - E).normalized()), (r2, (E - Wc).normalized())):
        rest_up = -r.normalized()
        rest_n = Vector((1, 0, 0)) - rest_up * rest_up.x
        rest_n.normalize()
        out.append(_frame(up, n) @ _frame(rest_up, rest_n).inverted())
    return out[0], out[1], E, Wc, reached


# ------------------------------------------------------------------------------------------------ rig
class Rig:
    def __init__(self, rig_json):
        self.path = rig_json
        with open(rig_json, "r", encoding="utf-8") as f:
            self.data = json.load(f)
        self.parts = self.data["parts"]
        self.joints = {j["child"]: j for j in self.data["joints"]}
        self.c0 = {n: cf_to_mat(j["c0"]) for n, j in self.joints.items()}
        self.c1 = {n: cf_to_mat(j["c1"]) for n, j in self.joints.items()}
        self.parent = {n: j["parent"] for n, j in self.joints.items()}
        self.order = [ROOT]
        i = 0
        while i < len(self.order):
            cur = self.order[i]
            self.order += sorted(n for n, p in self.parent.items() if p == cur)
            i += 1
        assert len(self.order) == len(self.parts), "rig is not one tree under HumanoidRootPart"
        # rest pose by forward kinematics (armature space = HumanoidRootPart space)
        self.rest = {ROOT: Matrix.Identity(4)}
        self.jpos = {ROOT: Vector((0, 0, 0))}
        for n in self.order[1:]:
            self.rest[n] = self.rest[self.parent[n]] @ self.c0[n] @ self.c1[n].inverted()
            self.jpos[n] = (self.rest[n] @ self.c1[n]).translation.copy()
        self.ground = min(self.rest[n].translation.z - self.parts[n]["size"][1] / 2 for n in self.order)
        self.arm = None
        self.body = {}
        self.items = []
        self._last_q = {}

    # -- build -----------------------------------------------------------------------------------
    def build(self, name="R15"):
        ad = bpy.data.armatures.new(name)
        arm = bpy.data.objects.new(name, ad)
        bpy.context.scene.collection.objects.link(arm)
        arm.location = (0, 0, -self.ground)  # feet on z = 0
        arm["ls_rig_json"] = os.path.basename(self.path)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        for n in self.order:
            eb = ad.edit_bones.new(n)
            eb.head = self.jpos[n]
            eb.tail = self.jpos[n] + Vector((0, 0, BONE_LEN))
            eb.roll = 0.0
            if n != ROOT:
                eb.parent = ad.edit_bones[self.parent[n]]
                eb.use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        ad.display_type = "STICK"
        self.arm = arm
        self.bone_rest = {n: ad.bones[n].matrix_local.copy() for n in self.order}
        bpy.context.view_layer.update()
        self._build_body()
        return self

    def _material(self, name, rgb, rough=0.85):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*rgb, 1.0)
        b.inputs["Roughness"].default_value = rough
        for key in ("Specular IOR Level", "Specular"):
            if key in b.inputs:
                b.inputs[key].default_value = 0.25
                break
        return m

    def bone_parent(self, ob, part, part_local=None):
        """Parent `ob` to the bone of `part` so that ob sits at part-space matrix `part_local` (identity = the part's
        own centre and axes) and follows the part exactly."""
        bone = self.arm.data.bones[part]
        ob.parent = self.arm
        ob.parent_type = "BONE"
        ob.parent_bone = part
        tail = bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
        ob.matrix_parent_inverse = tail.inverted() @ self.rest[part]
        ob.matrix_basis = part_local if part_local is not None else Matrix.Identity(4)

    def _build_body(self):
        mats = {}
        eye = self._material("LS_Eye", (0.03, 0.03, 0.03))
        for n in self.order:
            if n == ROOT:
                continue
            sx, sy, sz = self.parts[n]["size"]
            dims = Vector((sx, sz, sy))
            me = bpy.data.meshes.new("Body_" + n)
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co = Vector((v.co.x * dims.x, v.co.y * dims.y, v.co.z * dims.z))
            bev = 0.16 if n == "Head" else 0.045
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=3 if n == "Head" else 2, affect="EDGES")
            if n == "Head":  # two eyes on the front (+Y) so the facing direction reads in previews
                for ex in (-0.22, 0.22):
                    r = bmesh.ops.create_cube(bm, size=1.0)
                    for v in r["verts"]:
                        v.co = Vector((v.co.x * 0.13 + ex, v.co.y * 0.04 + dims.y / 2, v.co.z * 0.2 + 0.1))
                    for f in {f for v in r["verts"] for f in v.link_faces}:
                        f.material_index = 1
            bm.to_mesh(me)
            bm.free()
            rgb = BODY_COLOURS.get(n, (0.5, 0.5, 0.5))
            if rgb not in mats:
                mats[rgb] = self._material("LS_Body_%d" % len(mats), rgb)
            me.materials.append(mats[rgb])
            if n == "Head":
                me.materials.append(eye)
            ob = bpy.data.objects.new(n + "_Geo", me)
            bpy.context.scene.collection.objects.link(ob)
            self.bone_parent(ob, n)
            self.body[n] = ob

    # -- held item -------------------------------------------------------------------------------
    def attach_item(self, glb, asset, hand="RightHand", grip="RightGripAttachment"):
        """Imports one asset out of a project GLB and puts it in the hand the way InventoryService.attachModel does:
        Handle.CFrame = hand.CFrame * <grip attachment>.CFrame, Handle look = the item's +Y."""
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
        new = [o for o in bpy.data.objects if o not in before]
        root = next((o for o in new if o.name == asset), None)
        if root is None:
            root = next((o for o in new if o.name.split(".")[0] == asset), None)
        assert root is not None, "asset %s not in %s" % (asset, glb)
        keep, stack = [], [root]
        while stack:
            o = stack.pop()
            keep.append(o)
            stack += list(o.children)
        bpy.context.view_layer.update()
        origin = Matrix.Translation(root.matrix_world.translation)
        local = {o.name: origin.inverted() @ o.matrix_world for o in keep if o.type == "MESH"}
        meshes = [o for o in keep if o.type == "MESH"]
        for o in new:
            if o not in meshes:
                bpy.data.objects.remove(o, do_unlink=True)
        grip_cf = cf_to_mat(self.data["attachments"][grip]["cframe"])
        item_in_hand = grip_cf @ cf_to_mat(HANDLE_IN_ASSET).inverted()
        for o in meshes:
            o.parent = None
            self.bone_parent(o, hand, item_in_hand @ local[o.name])
        self.items.append({"asset": asset, "hand": hand, "in_hand": item_in_hand, "meshes": meshes})
        return meshes

    # -- controls --------------------------------------------------------------------------------
    def _empty(self, name, size=0.25, kind="PLAIN_AXES"):
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = kind
        e.empty_display_size = size
        e.rotation_mode = "QUATERNION"
        bpy.context.scene.collection.objects.link(e)
        return e

    def build_controls(self):
        """Hand and elbow controls live in UpperTorso part space (they ride the chest); foot controls are in armature
        space. A hand / foot control's origin is the wrist / ankle joint and its rotation is the hand's / foot's
        rotation away from rest."""
        chest = self.rest["UpperTorso"].inverted()
        self.ctl = {}
        for side in ("Right", "Left"):
            h = self._empty("CTL_%sHand" % side, 0.35, "ARROWS")
            self.bone_parent(h, "UpperTorso", Matrix.Translation(chest @ self.jpos[side + "Hand"]))
            e = self._empty("CTL_%sElbow" % side, 0.2, "SPHERE")
            self.bone_parent(e, "UpperTorso", Matrix.Translation(chest @ self.jpos[side + "LowerArm"] + Vector((0, -1.5, 0))))
            f = self._empty("CTL_%sFoot" % side, 0.35, "ARROWS")
            f.parent = self.arm
            f.location = self.jpos[side + "Foot"]
            self.ctl[side + "Hand"], self.ctl[side + "Elbow"], self.ctl[side + "Foot"] = h, e, f
        return self.ctl

    def chest_space(self, v):
        return Vector(v)

    # -- keying ----------------------------------------------------------------------------------
    def _cont(self, key, q):
        last = self._last_q.get(key)
        if last is not None and last.dot(q) < 0:
            q = -q
        self._last_q[key] = q.copy()
        return q

    def key_joint(self, part, q_local, frame, loc=None):
        """q_local: rotation of the part relative to its parent part, in part axes (Blender). loc: joint offset in the
        parent part's axes (only useful on LowerTorso)."""
        pb = self.arm.pose.bones[part]
        rc = self.bone_rest[part].to_quaternion()
        q = self._cont(part, rc.inverted() @ q_local @ rc)
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if loc is not None:
            pb.location = rc.inverted() @ Vector(loc)
            pb.keyframe_insert("location", frame=frame)

    def key_ctl(self, name, frame, pos=None, rot=None):
        """pos is in the control's space: UpperTorso part space for hands and elbows, armature space for feet."""
        ob = self.ctl[name]
        if pos is not None:
            ob.location = Vector(pos)
            ob.keyframe_insert("location", frame=frame)
        if rot is not None:
            ob.rotation_quaternion = self._cont("ctl" + name, rot)
            ob.keyframe_insert("rotation_quaternion", frame=frame)

    # -- evaluation ------------------------------------------------------------------------------
    def deltas(self, frame=None):
        """{part: D} with D = pose * rest^-1 in armature space, evaluated at `frame`."""
        if frame is not None:
            bpy.context.scene.frame_set(frame)
        dg = bpy.context.evaluated_depsgraph_get()
        ae = self.arm.evaluated_get(dg)
        return {n: ae.pose.bones[n].matrix @ self.bone_rest[n].inverted() for n in self.order}

    def bake_limbs(self, f0, f1, knee_out=0.22, follow_forearm=("Left",)):
        """Solves both arms and both legs on every frame from the controls and keys the 12 limb bones."""
        scene = bpy.context.scene
        report = []
        ainv = self.arm.matrix_world.inverted()
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            ae = self.arm.evaluated_get(dg)
            D = {n: ae.pose.bones[n].matrix @ self.bone_rest[n].inverted() for n in ("LowerTorso", "UpperTorso")}

            def ctl(name):
                return ainv @ self.ctl[name].evaluated_get(dg).matrix_world

            for side in ("Right", "Left"):
                ua, la, hd = side + "UpperArm", side + "LowerArm", side + "Hand"
                S = D["UpperTorso"] @ self.jpos[ua]
                T = ctl(hd)
                pole = ctl(side + "Elbow").translation - S
                Ru, Rl, E, Wc, ok = two_bone(S, T.translation, self.jpos[la] - self.jpos[ua],
                                             self.jpos[hd] - self.jpos[la], pole, +1)
                Rh = Rl if side in follow_forearm else T.to_3x3().normalized()
                Rc = D["UpperTorso"].to_3x3()
                self.key_joint(ua, (Rc.inverted() @ Ru).to_quaternion(), f)
                self.key_joint(la, (Ru.inverted() @ Rl).to_quaternion(), f)
                self.key_joint(hd, (Rl.inverted() @ Rh).to_quaternion(), f)
                # wrist bend = angle between the forearm's axis and the hand's axis (twist about the axis is free)
                wrist = math.degrees((Rl @ Vector((0, 0, -1))).angle(Rh @ Vector((0, 0, -1))))
                report.append((f, hd, ok, round(wrist, 1)))
            yaw = D["LowerTorso"].to_3x3().to_euler("ZXY").z
            for side, sgn in (("Right", 1), ("Left", -1)):
                ul, ll, ft = side + "UpperLeg", side + "LowerLeg", side + "Foot"
                S = D["LowerTorso"] @ self.jpos[ul]
                T = ctl(ft)
                fyaw = T.to_3x3().to_euler("ZXY").z
                pole = Matrix.Rotation(0.5 * (yaw + fyaw), 3, "Z") @ Vector((sgn * knee_out, 1.0, 0.0))
                Ru, Rl, E, Wc, ok = two_bone(S, T.translation, self.jpos[ll] - self.jpos[ul],
                                             self.jpos[ft] - self.jpos[ll], pole, -1)
                Rf = T.to_3x3().normalized()
                Rp = D["LowerTorso"].to_3x3()
                self.key_joint(ul, (Rp.inverted() @ Ru).to_quaternion(), f)
                self.key_joint(ll, (Ru.inverted() @ Rl).to_quaternion(), f)
                self.key_joint(ft, (Rl.inverted() @ Rf).to_quaternion(), f)
                report.append((f, ft, ok, 0.0))
        return report

    # -- checks ----------------------------------------------------------------------------------
    def check(self, f0, f1, blade=((0, 0, 0.30), (0, 0, 3.05)), margin=0.02):
        """Numbers behind 'does it look wrong': foot drift, lowest point of the held blade, blade inside the body.
        `blade` is the tested segment in item asset space (Blender axes: the item's long axis is +Z)."""
        lines = []
        foot0 = {}
        skip = {"RightHand", "RightLowerArm", ROOT}
        up = Matrix.Translation((0, 0, -self.ground))
        for f in range(f0, f1 + 1):
            D = self.deltas(f)
            for ft in ("LeftFoot", "RightFoot"):
                p = (D[ft] @ self.rest[ft]).translation
                foot0.setdefault(ft, p.copy())
                drift = (p - foot0[ft]).length
                if drift > 1e-3:
                    lines.append("FOOT_SLIDE f%d %s %.4f" % (f, ft, drift))
            for it in self.items:
                Wm = D[it["hand"]] @ self.rest[it["hand"]] @ it["in_hand"]
                a, b = Vector(blade[0]), Vector(blade[1])
                low = min((up @ Wm @ a).z, (up @ Wm @ b).z)
                if low < 0.05:
                    lines.append("BLADE_GROUND f%d %s lowest z = %.3f" % (f, it["asset"], low))
                hits = {}
                for i in range(25):
                    p = Wm @ a.lerp(b, i / 24.0)
                    for n in self.order:
                        if n in skip:
                            continue
                        q = (D[n] @ self.rest[n]).inverted() @ p
                        sx, sy, sz = self.parts[n]["size"]
                        if abs(q.x) < sx / 2 - margin and abs(q.y) < sz / 2 - margin and abs(q.z) < sy / 2 - margin:
                            hits[n] = hits.get(n, 0) + 1
                for n, c in hits.items():
                    lines.append("BLADE_IN_BODY f%d %s through %s (%d/25 samples)" % (f, it["asset"], n, c))
        return lines

    # -- export ----------------------------------------------------------------------------------
    def export_json(self, path, name, f0, f1, markers=None, loop=False, priority="Action", check_frames=()):
        scene = bpy.context.scene
        fps = scene.render.fps
        parts = [n for n in self.order if n != ROOT]
        frames, checks = [], []
        for f in range(f0, f1 + 1):
            D = self.deltas(f)
            frames.append({"f": f - f0, "t": round((f - f0) / fps, 5), "d": [mat_to_cf7(D[n]) for n in parts]})
            if f in check_frames:
                tr = {}
                for n in parts:
                    p = self.parent[n]
                    tr[n] = mat_to_cf7((D[p] @ self.rest[p] @ self.c0[n]).inverted() @ (D[n] @ self.rest[n] @ self.c1[n]))
                checks.append({"f": f - f0, "transform": tr,
                               "partCFrame": {n: mat_to_cf7(D[n] @ self.rest[n]) for n in parts}})
        out = {
            "format": "ls_anim/1",
            "name": name,
            "fps": fps,
            "frameCount": f1 - f0 + 1,
            "length": round((f1 - f0) / fps, 5),
            "loop": bool(loop),
            "priority": priority,
            "space": "per part: delta from rest in HumanoidRootPart space, Roblox axes, [x,y,z,qx,qy,qz,qw]; "
                     "posed part CFrame = HRP * delta * restPart; Transform = (dParent*restParent*c0)^-1 * (dChild*restChild*c1)",
            "parts": parts,
            "parents": {n: self.parent[n] for n in parts},
            "markers": [{"name": m, "f": fr - f0, "t": round((fr - f0) / fps, 5)} for m, fr in (markers or [])],
            "frames": frames,
            "check": checks,
        }
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(out, fh, separators=(",", ":"))
        return out


    def export_studio_json(self, path, name, f0, f1, markers=None, loop=False, priority="Action", scale=10000):
        """The compact file that travels into Studio (an agent has to type it into execute_luau, so every byte counts).
        Per frame, per part: the joint Transform as integers = value * scale, [qx, qy, qz] (qw >= 0 is implied) plus
        [x, y, z] only when the joint is translated. `rig` carries the c0 / c1 positions the clip was authored on so
        Studio can refuse a rig that does not match, and `checksum` catches typing errors."""
        fps = bpy.context.scene.render.fps
        parts = [n for n in self.order if n != ROOT]
        frames = []
        for f in range(f0, f1 + 1):
            D = self.deltas(f)
            row = []
            for n in parts:
                p = self.parent[n]
                c = mat_to_cf7((D[p] @ self.rest[p] @ self.c0[n]).inverted() @ (D[n] @ self.rest[n] @ self.c1[n]), 7)
                q = [int(round(v * scale)) for v in c[3:6]]
                pos = [int(round(v * scale)) for v in c[0:3]]
                row.append(q + pos if any(abs(v) > 1 for v in pos) else q)
            frames.append(row)
        total, count = 0, 0
        for row in frames:
            for tr in row:
                for v in tr:
                    total = (total + v * (count % 7 + 1)) % 1000000007
                    count += 1
        rig = {}
        for n in parts:
            a, b = C_B2R @ self.c0[n].translation, C_B2R @ self.c1[n].translation
            rig[n] = [int(round(v * scale)) for v in (a.x, a.y, a.z, b.x, b.y, b.z)]
        out = {"format": "ls_anim_studio/1", "name": name, "fps": fps, "loop": bool(loop), "priority": priority,
               "hipHeight": self.data.get("hipHeight", 2.0), "scale": scale, "parts": parts,
               "parents": [self.parent[n] for n in parts],
               "markers": [[m, fr - f0] for m, fr in (markers or [])], "rig": [rig[n] for n in parts],
               "count": count, "checksum": total, "frames": frames}
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(out, fh, separators=(",", ":"))
        return out


# ------------------------------------------------------------------------------------------------ preview
def enable_gpu(scene):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                devs = [d for d in prefs.devices if d.type == kind]
                if devs:
                    for d in prefs.devices:
                        d.use = d.type == kind
                    scene.cycles.device = "GPU"
                    return kind
            except Exception:
                continue
    except Exception:
        pass
    scene.cycles.device = "CPU"
    return "CPU"


def daylight(scene, sun_elev=46.0, sun_azim=-35.0, strength=0.045, sun_strength=3.2):
    w = bpy.data.worlds.new("LS_AnimSky")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sk = nt.nodes.new("ShaderNodeTexSky")
    for kind in ("MULTIPLE_SCATTERING", "NISHITA"):
        try:
            sk.sky_type = kind
            break
        except Exception:
            continue
    try:
        sk.sun_disc = False
    except Exception:
        pass
    sk.sun_elevation = math.radians(sun_elev)
    sk.sun_rotation = math.radians(sun_azim)
    bg.inputs["Strength"].default_value = strength
    nt.links.new(sk.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    scene.world = w
    ld = bpy.data.lights.new("LS_AnimSun", "SUN")
    sun = bpy.data.objects.new("LS_AnimSun", ld)
    scene.collection.objects.link(sun)
    ld.energy = sun_strength
    ld.angle = math.radians(1.5)
    ld.color = (1.0, 0.96, 0.9)
    e, a = math.radians(sun_elev), math.radians(sun_azim)
    d = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    # matte ground with a faint 1-stud checker: makes sliding feet and scale easy to see
    me = bpy.data.meshes.new("LS_AnimGround")
    h = 600.0
    me.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new("LS_AnimGround", me)
    scene.collection.objects.link(g)
    m = bpy.data.materials.new("LS_AnimGround")
    m.use_nodes = True
    N, L = m.node_tree.nodes, m.node_tree.links
    b = N.get("Principled BSDF")
    b.inputs["Roughness"].default_value = 1.0
    tc = N.new("ShaderNodeTexCoord")
    ch = N.new("ShaderNodeTexChecker")
    ch.inputs["Scale"].default_value = 1.0
    ch.inputs["Color1"].default_value = (0.36, 0.38, 0.33, 1)
    ch.inputs["Color2"].default_value = (0.31, 0.33, 0.29, 1)
    L.new(tc.outputs["Object"], ch.inputs["Vector"])
    L.new(ch.outputs["Color"], b.inputs["Base Color"])
    me.materials.append(m)
    return sun, g


def render_contact_sheet(scene, frames, labels, out_png, tile=(480, 560), cols=4, samples=40, target=(0.0, 0.5, 3.3),
                         azim=38.0, elev=11.0, dist=18.0, lens=70.0, tmp_dir=None):
    """Renders `frames` from one fixed three-quarter camera and tiles them into one PNG."""
    dev = enable_gpu(scene)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.resolution_x, scene.render.resolution_y = tile
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "AgX"
    except Exception:
        pass
    cd = bpy.data.cameras.new("LS_AnimCam")
    cd.lens = lens
    cd.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("LS_AnimCam", cd)
    scene.collection.objects.link(cam)
    a, e = math.radians(azim), math.radians(elev)
    tgt = Vector(target)
    cam.location = tgt + dist * Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    # label: a text object fixed to the camera
    fd = bpy.data.curves.new("LS_AnimLabel", "FONT")
    fd.size = 0.0175
    txt = bpy.data.objects.new("LS_AnimLabel", fd)
    scene.collection.objects.link(txt)
    txt.parent = cam
    half_w = 0.5 * 36.0 / lens
    half_h = half_w * tile[1] / tile[0]
    txt.location = (-half_w * 0.93, -half_h * 0.93, -1.0)
    tm = bpy.data.materials.new("LS_AnimLabel")
    tm.use_nodes = True
    tm.node_tree.nodes.clear()
    o = tm.node_tree.nodes.new("ShaderNodeOutputMaterial")
    em = tm.node_tree.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    em.inputs["Strength"].default_value = 3.0
    tm.node_tree.links.new(em.outputs[0], o.inputs["Surface"])
    fd.materials.append(tm)
    txt.visible_shadow = False
    tmp_dir = tmp_dir or os.path.join(os.path.dirname(out_png), "_tiles")
    os.makedirs(tmp_dir, exist_ok=True)
    paths = []
    for f, lab in zip(frames, labels):
        scene.frame_set(f)
        fd.body = lab
        p = os.path.join(tmp_dir, "f%02d.png" % f)
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    rows = int(math.ceil(len(paths) / cols))
    W, H = tile
    sheet = np.zeros((rows * H, cols * W, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        px = np.empty(W * H * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(H, W, 4)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * H
        sheet[y0:y0 + H, c * W:(c + 1) * W, :] = px
        sheet[y0:y0 + H, c * W, :3] = 0.08
        sheet[y0, c * W:(c + 1) * W, :3] = 0.08
        bpy.data.images.remove(img)
    out = bpy.data.images.new("LS_AnimSheet", cols * W, rows * H, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = out_png
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    for ob in (txt, cam):
        bpy.data.objects.remove(ob, do_unlink=True)
    return dev, paths


def export_fbx(path, rig):
    """Fallback only (Animation Clip Editor import by hand). Settings from Roblox's Blender export notes."""
    bpy.ops.object.select_all(action="DESELECT")
    rig.arm.select_set(True)
    for ob in list(rig.body.values()) + [m for it in rig.items for m in it["meshes"]]:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = rig.arm
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"ARMATURE", "MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", add_leaf_bones=False, bake_anim=True,
                             bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
                             bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
                             bake_anim_simplify_factor=0.0, axis_forward="Z", axis_up="Y")
