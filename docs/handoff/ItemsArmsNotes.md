# Items and arms integration: notes for the next pass

From the items/arms integration agent (Part 1). A duplicate copy of that agent ran for a while after a
message forked it, so the next items pass must also reconcile any edits the two copies both made
(see "Reconcile" below).

## State reported by the agent

- Items.glb and Arms.glb are uploaded and approved: Model assets 89569069083663 (Items) and
  130319005401961 (Arms).
- Both were inserted into ServerStorage.MeshImports. `insert_asset` returned `isPackage = true` for
  both. The templates built from them are plain copies, but the package caveat still applies: a
  package update or re-insert would bring back the unrepaired originals.
- Templates are built into ReplicatedStorage.Assets by ServerStorage.WorldGen.ItemAssets.
- Shared.ItemModels now clones the mesh templates.
- Work on the viewmodel (Rig / Poses / ViewmodelController) was in progress.

## Hands decision (user, 18:3x)

The user said: "keep the old style of hands you had just make the roblox charachter the same as a normal
one just make it realistic like before". The first-person arms go back to the original v1 part-built
arms: dark fabric sleeves, cuffs, and hands in the character's skin colour, with two-bone IK and the
realistic motion. The Blender mesh arms (Arms.glb, asset 130319005401961) are no longer used, and the
realistic ArmsReal set from Part 1b must NOT be integrated. The mesh items stay.

## Bow aim visibility (user report)

The user reported: "bow animations - doesnt let you see when your shooting somebody". The
viewmodel-old-hands-bow workflow does three things:
- restores the old hands
- reworks the first-person bow pose so the crosshair and target stay visible while drawing, holding
  and releasing
- applies fix 1 below.

It replaced the earlier fix-bow-aim-view workflow, which was stopped because it was built around the
mesh arms. Whoever swaps in the realistic ItemsReal meshes later must keep that pose and re-run its
screen-coverage check.

## Five fixes to apply

1. **Wrist limit in Rig:pose.** Don't rotate the bow hand, or the right hand hooking the string, when
   their wrist bend goes over 30°. The arrow frame and the string hook are computed from the hand
   frames before IK, so rotating either hand puts the arrow or the string off the hand. Exempt those
   hands with per-hand flags.
2. **Bottle and ration holds.** Bottles read better held by the neck in HandGrip than cradled across an
   open palm. Grip-hold offsets: about `CFrame.new(0, 0, 0.40)` for water_bottle and
   `CFrame.new(0, 0, 0.36)` for empty_bottle. Drinking then shows the fist at the mouth with the bottle
   tipped up into view. The ration looks best upright in the palm.
3. **Crate collider material.** Set the crate Base collider's Material to WoodPlanks, so arrow and melee
   hit sounds aren't the Plastic ones.
4. **Package caveat.** Report it to the user (see above). Offer to unlink the copies or republish the
   repaired versions; do neither without the user's go-ahead.
5. **Client replication guard.** ItemModels on the client falls back to a stand-in if
   ReplicatedStorage.Assets hasn't replicated yet. Add a one-time `game.Loaded` wait (or a
   WaitForChild on Assets) as cheap insurance.

## Reconcile

Nothing to reconcile. The duplicate copy reports that it made no Studio changes after the fork:
one undo waypoint that created nothing, and otherwise only read-only checks. Its one file on disk is a
throwaway transcript copy in the session scratchpad. The workflow's copy finished the integration
at 06:06 and its report is the real result. The uploaded Model assets are named `LS_Items_v1` and
`LS_Arms_v1`; no Image assets were created (the v1 GLBs have no textures).

The duplicate's read-only check, as of about 06:06: all 20 item templates, 3 crates and 10 viewmodel
pieces match the manifest, with 0 problems. Every manifest part is present with its manifest colour and
material. Item parts are massless with collision, query and touch off. Every attachment is present, and
every viewmodel piece's pivot is at the origin. The duplicate did not review the ItemModels, Rig,
Poses or ViewmodelController edits.

The shared design files (ItemAssets.lua, Manifest.lua, ItemModels.lua, Rig.lua, Poses.lua,
vm_edits.md and the pose-analysis scripts) are in the session scratchpad under `items/`. They are not
in the repo.
