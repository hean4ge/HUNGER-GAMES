"""
lr_shots.py - review shots for the LandmarksReal set: every asset at eye level next to a 5.5-stud figure, close up
and at gameplay distance, context shots (the Spire on its plaza with the 24 launch plates, one plate half-way
up its tube), a lineup render of the lobby kit and a contact sheet. Cycles + built-in Sky Texture (lr_review).
Never exported.
"""
import math
import os

import bpy

import lr_core as C
import lr_review as RV

TAU = 2.0 * math.pi
PLAZA_TOP = 0.6


def _objs(a):
    return [a.root] + list(a.root.children_recursive)


def _instance(a, loc=(0, 0, 0), rz=0.0, tag="inst"):
    holder = bpy.data.objects.new("%s_%s" % (a.name, tag), None)
    bpy.context.scene.collection.objects.link(holder)
    out = [holder]
    for c in a.root.children:
        d = c.copy()
        d.name = c.name + "_" + tag
        bpy.context.scene.collection.objects.link(d)
        d.parent = holder
        out.append(d)
    holder.location = loc
    holder.rotation_euler = (0, 0, rz)
    return out


def plate_pos(i):
    a = math.radians(15.0 * i)
    return (52.0 * math.sin(a), 52.0 * math.cos(a))


S = 5.0    # eye height of a standing player
# name: dict(shots=[(label, cam, target, lens)], figs=[(loc, rz)], context=bool, hide=[plate idx], lift={idx: dz})
SHOTS = {
    "Spire": dict(context=True, shots=[
        ("gameplay", (10.0, -78.0, PLAZA_TOP + S), (0.0, 0.0, 24.0), 22.0),
        ("base_eye", (9.0, 27.0, 5.0 + 0.6), (0.0, 8.0, 6.5), 24.0),
        ("alcove", (2.5, 15.0, 8.6), (0.0, 7.0, 5.5), 32.0),
        ("band_slit", (16.0, 26.0, 30.0), (0.0, 0.0, 33.0), 55.0),
        ("slit_close", (1.5, 30.0, 33.0), (0.0, 0.0, 38.0), 45.0),
        ("crown", (13.0, 17.0, 60.5), (0.0, 0.0, 53.5), 42.0),
        ("slit_far", (2.0, 95.0, 7.0), (0.0, 0.0, 30.0), 30.0),
        ("far", (70.0, 230.0, 8.0), (0.0, 0.0, 28.0), 45.0)],
        figs=[((1.2, 10.6, 3.6), 3.4), ((5.5, 24.5, 0.6), 2.6), ((-14.0, -40.0, 0.6), 0.3)]),
    "SpirePlatform": dict(context=True, hide=[12], shots=[
        ("overview", (40.0, -96.0, 36.0), (0.0, -8.0, 2.0), 30.0),
        ("eye_plate", (2.5, -61.0, PLAZA_TOP + S), (0.0, -30.0, 4.0), 28.0),
        ("flags_close", (6.5, -27.5, 3.4), (3.0, -23.0, 0.6), 35.0),
        ("opening", (4.0, -45.0, 5.2), (0.0, -52.0, 0.0), 35.0),
        ("kerb", (-10.5, -67.0, 3.6), (-4.0, -58.5, 0.7), 35.0)],
        figs=[((6.0, -47.0, PLAZA_TOP), 2.8), ((-3.5, -25.0, PLAZA_TOP), 0.4)]),
    "Plinth": dict(context=True, lift={11: -5.5}, shots=[
        ("front", (5.0, -43.0, PLAZA_TOP + S), (0.0, -52.0, 2.4), 32.0),
        ("detail", (1.6, -46.4, 3.7), (0.0, -49.4, 1.9), 38.0),
        ("rising", (22.0, -42.0, 4.5), (13.46, -50.23, -1.0), 38.0),
        ("ring", (0.0, -67.0, 9.0), (0.0, -40.0, 1.0), 30.0)],
        figs=[((0.0, -52.0, PLAZA_TOP + 1.5), 0.0), ((13.46, -50.23, PLAZA_TOP + 1.5 - 5.5), 2.88),
              ((-13.46, -50.23, PLAZA_TOP + 1.5), -2.88)]),
    "Pavilion": dict(shots=[
        ("eye", (16.0, 27.0, S), (0.0, 0.0, 5.5), 28.0),
        ("close", (6.0, 9.6, 4.6), (1.8, 4.0, 3.0), 35.0),
        ("under", (2.0, 4.5, 4.5), (-3.0, -2.0, 9.0), 26.0)],
        figs=[((-2.0, 1.0, 0.95), 0.4), ((5.0, 9.5, 0.0), 2.6)]),
    "LobbyGate": dict(shots=[
        ("eye", (7.0, 24.0, S), (0.0, 0.0, 6.5), 30.0),
        ("close", (5.5, 6.0, 4.3), (5.4, 0.0, 4.2), 35.0),
        ("arch", (1.5, 4.5, 3.0), (0.0, 0.0, 10.0), 26.0)],
        figs=[((0.6, 1.0, 0.0), 0.2)]),
    "Brazier": dict(shots=[
        ("eye", (6.0, 8.5, S), (0.0, 0.0, 3.0), 35.0),
        ("close", (2.2, 3.4, 5.9), (0.0, 0.0, 4.6), 40.0)],
        figs=[((2.6, 1.2, 0.0), 2.2)]),
    "BannerPole": dict(shots=[
        ("eye", (3.5, 14.0, S), (0.0, 0.5, 7.0), 35.0),
        ("close", (1.8, 5.2, 7.8), (0.0, 0.6, 8.3), 35.0)],
        figs=[((1.8, 1.6, 0.0), 2.6)]),
    "Bench": dict(shots=[
        ("eye", (4.0, 7.0, S), (0.0, 0.0, 1.4), 35.0),
        ("close", (2.6, 2.8, 2.7), (1.0, 0.0, 1.5), 40.0)],
        figs=[((-3.8, 1.3, 0.0), 2.4)]),
    "NoticeBoard": dict(shots=[
        ("eye", (4.5, 15.0, S), (0.0, 0.0, 5.2), 32.0),
        ("close", (3.0, 4.6, 6.2), (2.2, 0.0, 6.6), 40.0)],
        figs=[((-5.6, 2.0, 0.0), 1.2)]),
    "Railing": dict(shots=[
        ("eye", (5.0, 9.5, S), (0.0, 0.0, 1.8), 35.0),
        ("close", (2.7, 2.6, 3.5), (2.6, 0.0, 2.6), 40.0)],
        figs=[((-1.5, 1.6, 0.0), 2.8)]),
    "StoneSteps": dict(shots=[
        ("eye", (6.5, 11.5, S), (0.0, 0.0, 1.5), 35.0),
        ("close", (2.6, 5.2, 2.9), (1.0, 1.5, 1.4), 40.0)],
        figs=[((0.5, -1.0, 2.0), 3.0)]),
}

LOBBY = ["Pavilion", "LobbyGate", "Brazier", "BannerPole", "Bench", "NoticeBoard", "Railing", "StoneSteps"]


def review(lib, names, folder, glb=None, only_shots=None):
    os.makedirs(folder, exist_ok=True)
    C.preview_materials()
    names_built = [a.name for a in lib.assets]
    holes = [plate_pos(i) + (3.45,) for i in range(24)] if "SpirePlatform" in names_built else None
    RV.setup(sun_elev=36.0, sun_az=145.0, samples=80, holes=holes)
    assets = {a.name: a for a in lib.assets}
    rendered = []
    plates = {}
    ctx = []
    if "SpirePlatform" in assets:
        ctx += _objs(assets["SpirePlatform"])
    if "Spire" in assets:
        ctx += _objs(assets["Spire"])
    if "Plinth" in assets:
        for i in range(24):
            x, y = plate_pos(i)
            plates[i] = _instance(assets["Plinth"], (x, y, PLAZA_TOP), rz=math.atan2(-y, -x) - math.pi / 2,
                                  tag="p%d" % i)
    temp = [o for v in plates.values() for o in v]
    for name in names:
        if name not in SHOTS or name not in assets:
            continue
        spec = SHOTS[name]
        fobjs = [RV.figure("LR_Fig_%s_%d" % (name, i), loc, rz) for i, (loc, rz) in enumerate(spec.get("figs", []))]
        temp += fobjs
        if spec.get("context"):
            show = list(ctx) + fobjs
            for i, objs in plates.items():
                if i in spec.get("hide", []):
                    continue
                objs[0].location.z = PLAZA_TOP + spec.get("lift", {}).get(i, 0.0)
                show += objs
            if name == "Plinth" and not plates:
                show += _objs(assets["Plinth"])
        else:
            show = _objs(assets[name]) + fobjs
        for label, cam, tgt, lens in spec["shots"]:
            if only_shots and label not in only_shots:
                continue
            path = os.path.join(folder, "%s_%s.png" % (name, label))
            RV.render(path, cam, tgt, lens, res=(1600, 900), show=show)
            rendered.append(path)
        for objs in plates.values():
            objs[0].location.z = PLAZA_TOP
    # lobby lineup: the kit in a row with figures for scale
    lob = [n for n in LOBBY if n in assets and n in names]
    if len(lob) >= 2 and not only_shots:
        x = 0.0
        show = []
        for n in lob:
            a = assets[n]
            w = a.vis_hi.x - a.vis_lo.x
            inst = _instance(a, (x - a.vis_lo.x, 0.0, 0.0), 0.0, tag="lineup")
            temp += inst
            show += inst
            f = RV.figure("LR_Fig_lineup_%s" % n, (x + w + 1.2, 1.5, 0.0), 0.0)
            temp.append(f)
            show.append(f)
            x += w + 4.0
        mid = x / 2
        path = os.path.join(folder, "_lineup_lobby.png")
        RV.render(path, (mid, 1.15 * x, 9.0), (mid, 0.0, 4.5), 50.0, res=(2400, 800), show=show)
        rendered.append(path)
    for o in temp:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    if rendered and not only_shots:
        every = sorted(os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".png") and not f.startswith("_"))
        RV.sheet(every + [p for p in rendered if os.path.basename(p).startswith("_lineup")], os.path.join(folder, "_review_sheet.png"), cols=3, cell_w=800)
    return rendered
