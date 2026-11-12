"""
ls_patch.py - art-direction fixes layered on top of ls_common (ls_common.py itself stays frozen).

Every top-level generator imports this right after ls_common, so all categories share the same behaviour:

    import ls_common as ls
    import ls_patch  # noqa: F401,E402  (patches ls_common in place)

What it changes
1. Hard edges (smooth_angle). ls_common.smooth() calls Mesh.set_sharpness_by_angle(), which does not exist in
   Blender 5.x; the error was swallowed, so every part added with smooth_angle came out fully smooth-shaded
   (log end caps, pommels, rims and boxes shaded like blobs). The patch calls Mesh.set_sharp_from_angle()
   (Blender 4.1+), so smooth_angle now means what the generators intended: smooth below the angle, hard above.
2. Manifest bounds. Library.finish() converted the two Blender corners to Roblox space, which swaps the Roblox Z
   component (boundsMin.z > boundsMax.z). boundsMin/boundsMax are now true per-axis minima/maxima.
3. Non-colliding parts. Every part gets explicit "canQuery" and "canTouch" flags (= "collide"), and parts with
   collide=False are exported with CollisionFidelity "Box": they need no physics data, and with CanQuery off
   arrows, raycasts and hit-scans pass through canopies, moss, trim, ropes and viewmodel pieces.
4. Repo copy. Library.export() also copies <Category>.manifest.json into art/manifests/ (every category, so the
   repo always holds the manifests that match the last export).

Suggested upstream fix: fold 1 and 2 into ls_common.smooth() / Library.finish() and delete this module.
"""
import inspect
import math
import os
import shutil

import ls_common as ls

REPO_MANIFESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "manifests"))

if not getattr(ls, "_ls_patch_applied", False):
    ls._ls_patch_applied = True

    # ---------------------------------------------------------------- 1. smooth shading with hard edges
    def smooth(obj, angle_deg=40):
        me = obj.data
        for p in me.polygons:
            p.use_smooth = True
        if hasattr(me, "set_sharp_from_angle"):          # Blender 4.1+
            me.set_sharp_from_angle(angle=math.radians(angle_deg))
        elif hasattr(me, "set_sharpness_by_angle"):      # older API name
            me.set_sharpness_by_angle(angle=math.radians(angle_deg))
        return obj

    ls.smooth = smooth   # Library.add() looks the name up in ls_common's globals at call time

    # ---------------------------------------------------------------- 2. ordered bounds
    _orig_finish = ls.Library.finish

    def finish(self, root):
        entry = _orig_finish(self, root)
        a, b = entry["boundsMin"], entry["boundsMax"]
        entry["boundsMin"] = [min(x, y) for x, y in zip(a, b)]
        entry["boundsMax"] = [max(x, y) for x, y in zip(a, b)]
        return entry

    ls.Library.finish = finish

    # ---------------------------------------------------------------- 3. query/touch flags, Box for non-colliders
    _orig_add = ls.Library.add
    _add_sig = inspect.signature(_orig_add)

    def add(self, root, obj, role, *args, **kwargs):
        bound = _add_sig.bind(self, root, obj, role, *args, **kwargs)
        bound.apply_defaults()
        collide = bool(bound.arguments["collide"])
        if not collide:
            bound.arguments["collision"] = "Box"
        result = _orig_add(*bound.args, **bound.kwargs)
        part = self._entry(root)["parts"][-1]
        part["canQuery"] = collide
        part["canTouch"] = collide
        return result

    ls.Library.add = add

    # ---------------------------------------------------------------- 4. manifest copy into the repo
    _orig_export = ls.Library.export

    def export(self, out_dir, preview_dir=None, gap=6.0):
        manifest = _orig_export(self, out_dir, preview_dir, gap)
        os.makedirs(REPO_MANIFESTS, exist_ok=True)
        src = os.path.join(out_dir, self.category + ".manifest.json")
        dst = os.path.join(REPO_MANIFESTS, self.category + ".manifest.json")
        if os.path.normcase(os.path.abspath(src)) != os.path.normcase(os.path.abspath(dst)):
            shutil.copyfile(src, dst)
            print("MANIFEST COPIED to " + dst)
        return manifest

    ls.Library.export = export
