"""
anim_sword_swing.py - one sword swing (wind-up, cut, follow-through, recover), 18 frames at 30 fps = 0.6 s.

    blender --background --factory-startup --python anim_sword_swing.py -- <out_dir> [items_glb] [norender] [nofbx]

Writes into <out_dir>:
    SwordSwing.blend            rig + sword + controls + the keyed Action
    SwordSwing.studio.json      compact joint Transforms: what Studio turns into a KeyframeSequence (ls_anim_studio/1)
    SwordSwing.anim.json        verbose per-part deltas from rest + check frames (ls_anim/1), for review and tests
    SwordSwing.fbx              fallback for the Animation Clip Editor (not used by the data route)
    owner_swing_preview.png     8-frame contact sheet
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import ls_anim as la  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else HERE
GLB = next((a for a in argv[1:] if a.lower().endswith(".glb")),
           os.path.expandvars(r"%USERPROFILE%\OneDrive\Documents\LastStanding\BlenderExports\ItemsReal.glb"))
RENDER = "norender" not in argv
FBX = "nofbx" not in argv

NAME = "SwordSwing"
F0, F1, HIT = 0, 18, 9

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start, scene.frame_end = F0, F1
scene.unit_settings.system = "NONE"

rig = la.Rig(os.path.join(HERE, "r15_rig.json")).build("R15")
rig.attach_item(GLB, "sword")
rig.build_controls()

# ------------------------------------------------------------------------------------------------ the swing
# Body keys. yaw + = turn left, pitch + = lean forward, roll + = tip right. move = (right, forward, up) in studs.
#        frame  pelvis yaw/pitch  move                    chest yaw/pitch/roll   head yaw/pitch
BODY = [
    (0,   -10,  0, (0.00,  0.00, -0.05),   -8,   3,  0,     17,  -2),   # guard
    (5,   -20, -2, (0.05, -0.13, -0.10),  -30,  -6, -4,     44,   6),   # wind-up: weight back, chest opens
    (6,   -21, -2, (0.05, -0.14, -0.11),  -32,  -6, -4,     46,   6),   # hang at the top
    (9,     6,  5, (-0.02, 0.14, -0.18),   14,  10,  2,    -18,  -8),   # HIT: weight forward and down
    (12,   12,  6, (-0.03, 0.17, -0.23),   28,  14,  3,    -34, -11),   # follow-through
    (13,   12,  6, (-0.03, 0.17, -0.23),   29,  14,  3,    -35, -11),   # settle
    (18,  -10,  0, (0.00,  0.00, -0.05),   -8,   3,  0,     17,  -2),   # back to guard
]
# Sword hand. Positions are the wrist in chest space (origin = UpperTorso centre, x right, y forward, z up; the right
# shoulder joint is at (0.97, 0, 0.60) and the arm reaches 1.73). blade = where the blade points, edge = where the
# cutting edge leads, elbow = which way the elbow points from the shoulder. Frames 7 and 8 carry the blade over the
# top: without them the shortest turn from "behind the head" to "forward" would swing it under the arm.
#        frame  wrist                  blade                  edge                  elbow
SWORD = [
    (0,   (1.05, 0.95, -0.10), (-0.20, 0.45, 0.87), (0.0, 0.9, -0.45), (0.6, -0.5, -1.0)),
    (5,   (1.30, -0.24, 1.30), (-0.22, -0.52, 0.83), (0.1, 0.6, 0.8), (1.0, -0.2, 0.2)),
    (6,   (1.31, -0.28, 1.32), (-0.24, -0.56, 0.80), (0.1, 0.6, 0.8), (1.0, -0.2, 0.2)),
    (7,   (1.25, 0.35, 1.32), (-0.18, 0.02, 0.98), (0.0, 1.0, 0.2), (1.0, -0.2, 0.0)),
    (8,   (0.95, 1.05, 0.90), (-0.28, 0.62, 0.73), (-0.2, 0.7, -0.7), (0.8, -0.3, -0.6)),
    (9,   (0.55, 1.42, 0.20), (-0.40, 0.91, -0.02), (-0.5, -0.1, -0.86), (0.5, -0.3, -1.0)),
    (12,  (0.45, 1.05, -0.60), (-0.78, 0.48, -0.40), (-0.4, -0.5, -0.77), (0.6, -0.6, -0.6)),
    (13,  (0.46, 1.03, -0.61), (-0.78, 0.46, -0.42), (-0.4, -0.5, -0.77), (0.6, -0.6, -0.6)),
    (18,  (1.05, 0.95, -0.10), (-0.20, 0.45, 0.87), (0.0, 0.9, -0.45), (0.6, -0.5, -1.0)),
]
# Off hand: wrist in chest space, elbow direction.
OFF = [
    (0,   (-1.05, 0.55, -0.55), (-0.6, -1.0, -0.4)),
    (5,   (-0.85, 1.05, 0.02), (-0.7, -0.6, -0.7)),
    (6,   (-0.85, 1.06, 0.03), (-0.7, -0.6, -0.7)),
    (9,   (-1.30, 0.05, -0.75), (-0.6, -1.0, -0.2)),
    (12,  (-1.35, -0.30, -0.70), (-0.6, -1.0, -0.1)),
    (13,  (-1.35, -0.31, -0.70), (-0.6, -1.0, -0.1)),
    (18,  (-1.05, 0.55, -0.55), (-0.6, -1.0, -0.4)),
]

for f, pyaw, ppitch, move, cyaw, cpitch, croll, hyaw, hpitch in BODY:
    rig.key_joint("LowerTorso", la.torso_rot(pyaw, ppitch), f, loc=move)
    rig.key_joint("UpperTorso", la.torso_rot(cyaw, cpitch, croll), f)
    rig.key_joint("Head", la.torso_rot(hyaw, hpitch), f)
S_R = rig.rest["UpperTorso"].inverted() @ rig.jpos["RightUpperArm"]
S_L = rig.rest["UpperTorso"].inverted() @ rig.jpos["LeftUpperArm"]
for f, wrist, blade, edge, elbow in SWORD:
    rig.key_ctl("RightHand", f, pos=wrist, rot=la.blade_frame(blade, edge))
    rig.key_ctl("RightElbow", f, pos=S_R + Vector(elbow).normalized() * 1.5)
for f, wrist, elbow in OFF:
    rig.key_ctl("LeftHand", f, pos=wrist)
    rig.key_ctl("LeftElbow", f, pos=S_L + Vector(elbow).normalized() * 1.5)
for side in ("Right", "Left"):  # feet stay where the idle leaves them: no slide when the clip fades in or out
    rig.key_ctl(side + "Foot", F0, pos=rig.jpos[side + "Foot"])

report = rig.bake_limbs(F0, F1)
scene.timeline_markers.new("Hit", frame=HIT)

for f, part, ok, wrist in report:
    if not ok:
        print("WARNING unreachable f%d %s" % (f, part))
    if wrist > 80:
        print("WARNING wrist bend f%d %s %.0f deg" % (f, part, wrist))
problems = rig.check(F0, F1)
for line in problems:
    print("CHECK", line)
print("CHECKS %d problem line(s)" % len(problems))

# ------------------------------------------------------------------------------------------------ outputs
os.makedirs(OUT, exist_ok=True)
js = rig.export_json(os.path.join(OUT, NAME + ".anim.json"), NAME, F0, F1, markers=[("Hit", HIT)], loop=False,
                     priority="Action", check_frames=(F0, 6, HIT))
print("EXPORTED %s.anim.json: %d frames, %d parts, %.3f s, markers %s, %d bytes" % (
    NAME, js["frameCount"], len(js["parts"]), js["length"], [m["name"] + "@" + str(m["f"]) for m in js["markers"]],
    os.path.getsize(os.path.join(OUT, NAME + ".anim.json"))))
st = rig.export_studio_json(os.path.join(OUT, NAME + ".studio.json"), NAME, F0, F1, markers=[("Hit", HIT)], loop=False,
                            priority="Action")
print("EXPORTED %s.studio.json: %d numbers, checksum %d, %d bytes" % (
    NAME, st["count"], st["checksum"], os.path.getsize(os.path.join(OUT, NAME + ".studio.json"))))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, NAME + ".blend"))
if FBX:
    try:
        la.export_fbx(os.path.join(OUT, NAME + ".fbx"), rig)
        print("EXPORTED %s.fbx %d bytes" % (NAME, os.path.getsize(os.path.join(OUT, NAME + ".fbx"))))
    except Exception as exc:  # the fallback must never block the data route
        print("WARNING fbx export failed: %r" % (exc,))
if RENDER:
    la.daylight(scene)
    shots = [0, 3, 6, 7, 8, 9, 12, 15]
    names = {0: "guard", 3: "wind-up", 6: "top of wind-up", 7: "cut starts", 8: "cut", 9: "HIT", 12: "follow-through",
             15: "recover"}
    labels = ["f%02d  %.2fs  %s" % (f, f / 30.0, names[f]) for f in shots]
    dev, tiles = la.render_contact_sheet(scene, shots, labels, os.path.join(OUT, "owner_swing_preview.png"))
    print("PREVIEW owner_swing_preview.png (%s)" % dev)
