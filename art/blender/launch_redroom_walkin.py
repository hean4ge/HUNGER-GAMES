"""
launch_redroom_walkin.py - the walk-in red room for the Training Centre (docs/design/TrainingAndLoadup.md section 5.2).

LaunchRedRoom.glb (art/blender/launch_rooms.py, pass 2) is a sealed room: its back wall has no way in. The walk-in room
needs "an entry cut into the back walkway" (design page table 4, row 14): the corridor from the launch doors meets the
room's upper walkway (deck top at 10 studs), so the room stands 10 studs lower than the hall floor and a doorway is cut
through the back wall over the walkway. This script makes that copy without touching the pass-2 generator:

  blender -b -P art/blender/launch_redroom_walkin.py            (or through the Blender MCP's run_python)

Reads  BlenderExports/Launch/LaunchRedRoom.glb
Writes BlenderExports/Launch/LaunchRedRoom_WalkIn.glb  (same 13 meshes and names, the Shell with the doorway)

The doorway (room space, Roblox axes; the room's back wall is at z -12 .. -13): x -3 .. 3 (the corridor is 6 wide),
y 10.02 .. 18.6 (from the walkway deck to the net channel), through the two upper oxblood panels there and the backing.
The reveal's four new faces take the UV of the backing's dark oxblood, so the palette atlas paints them like the wall.
"""
import os

import bmesh
import bpy
from mathutils import Vector

EXP = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports", "Launch")
SRC = os.path.join(EXP, "LaunchRedRoom.glb")
OUT = os.path.join(EXP, "LaunchRedRoom_WalkIn.glb")
# Blender axes of the import: x = Roblox x, y = -Roblox z, z = Roblox y. The asset root sits at its origin (16, 0, 0).
DOOR = {"x": (-3.0, 3.0), "z": (10.02, 18.6)}
BACKING = (12.6, 13.0)   # the back wall's backing, Blender y (inner face, outer face)
PANEL_Y = (12.0, 12.3)   # its oxblood panels


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    root = bpy.data.objects["LaunchRedRoom"]
    ox = root.matrix_world.translation.x
    shell = bpy.data.objects["LaunchRedRoom_Shell"]
    before = len(shell.data.polygons)

    # a UV on the backing's oxblood: a face whose centre lies on the back wall's inner backing, mid height
    inv = shell.matrix_world.inverted()
    uv_layer = shell.data.uv_layers.active.data
    pick = None
    for poly in shell.data.polygons:
        c = shell.matrix_world @ poly.center
        if abs(c.y - 12.6) < 0.05 and abs(c.x - ox) < 10 and 10 < c.z < 18 and poly.normal.y < -0.9:
            pick = uv_layer[poly.loop_start].uv.copy()
            break
    if pick is None:
        pick = uv_layer[shell.data.polygons[0].loop_start].uv.copy()

    # the doorway, by hand (an EXACT boolean keeps the cutter's faces on this merged, many-box mesh): split the
    # backing along the doorway's four edges, delete the backing inside it and the two upper oxblood panels in it,
    # then close the reveal with four quads between the backing's faces
    x0, x1 = ox + DOOR["x"][0], ox + DOOR["x"][1]
    z0, z1 = DOOR["z"]
    yi, yo = BACKING
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    bm.transform(shell.matrix_world)
    uv = bm.loops.layers.uv.active

    def backing_faces():
        return [f for f in bm.faces if all(yi - 0.02 <= v.co.y <= yo + 0.02 for v in f.verts)]

    for co, no in (((x0, 0, 0), (1, 0, 0)), ((x1, 0, 0), (1, 0, 0)), ((0, 0, z0), (0, 0, 1)), ((0, 0, z1), (0, 0, 1))):
        geom = list({e for f in backing_faces() for e in f.edges}) + backing_faces() + list({v for f in backing_faces() for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no))
    gone = []
    for f in bm.faces:
        c = f.calc_center_median()
        if x0 < c.x < x1 and z0 < c.z < z1 and PANEL_Y[0] - 0.02 <= c.y <= yo + 0.02:
            gone.append(f)
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    # the reveal: (corner a, corner b) along the doorway's edge, each quad spans the backing's depth
    corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    made = 0
    for k in range(4):
        (ax, az), (bx, bz) = corners[k], corners[(k + 1) % 4]
        vs = [bm.verts.new((ax, yi, az)), bm.verts.new((bx, yi, bz)), bm.verts.new((bx, yo, bz)), bm.verts.new((ax, yo, az))]
        f = bm.faces.new(vs)
        f.normal_update()
        mid = Vector(((ax + bx) / 2, (yi + yo) / 2, (az + bz) / 2))
        centre = Vector(((x0 + x1) / 2, (yi + yo) / 2, (z0 + z1) / 2))
        if f.normal.dot(centre - mid) < 0:
            f.normal_flip()
        for loop in f.loops:
            loop[uv].uv = pick
        made += 1
    bm.transform(shell.matrix_world.inverted())
    bm.to_mesh(shell.data)
    bm.free()
    shell.data.update()
    n = len(gone)

    # the export: the same root and names as LaunchRedRoom.glb
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True,
                              export_yup=True)
    tris = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("WALKIN shell faces %d -> %d; faces removed %d; triangles %d; wrote %s (%d bytes)"
          % (before, len(shell.data.polygons), n, tris, OUT, os.path.getsize(OUT)))


main()
