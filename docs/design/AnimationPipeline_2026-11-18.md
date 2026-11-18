# Blender to Roblox animation pipeline (proved 18 November 2026)

Scripts: art/blender/anim (Blender side) and tools/anim (Studio side). Nothing here uploads anything.

# The proof

## summary

The pipeline works end to end without a plugin window, a playtest or an upload. One sword swing made in Blender (0.6 s, 19 frames at 30 fps, hit marker at 0.3 s) was built in Studio as a KeyframeSequence by one execute_luau call, read back, and played on an R15 rig in Edit mode with a temporary id. Part positions in Studio matched Blender to 0.00065 studs, the sword hand's orientation at the hit matched exactly, and the "Hit" marker fired once. Studio is clean again: ServerStorage._AnimProof is deleted and QA_Lock is nil.

Not proven: the swing has not been seen in a running game, on a spawned player, with the game's own procedural layers on top, or by a second client. Publishing was not attempted.

Three things the research had wrong or open, now settled for this place:
- **Joints:** characters here use AnimationConstraints (Avatar Joint Upgrade), not Motor6D. Poses are still matched by part name, and Attachment0 * Transform = Attachment1 holds.
- **Rest pose:** the part positions of a freshly created character are not the rest pose; attachments sit 0.03 to 0.08 studs apart per joint. The rest pose has to be computed from the rig attachments, which the Blender rig now does.
- **Held weapon:** the game welds the sword to the hand (Weld "GripWeld"), so a swing needs no weapon bone. A weapon that must move inside the hand would need that weld changed to a Motor6D in InventoryService; not tested.

What an upload would involve: one Animation asset per clip (one for this swing), under the owner's user account 5458010221. Studio reports the experience as user-owned by that id, not group-owned. Each upload is permanent, goes through moderation, and needs the owner's yes. A click-free publish route is still unconfirmed.

Decision for the fighting work: third-person swings are already procedural and timed by the server (0.36 / 0.42 / 0.5 s to the strike by weapon weight). Three ways forward:
- **Keep procedural:** no uploads, but every new move is code.
- **Animation assets:** one upload per clip; each clip must be speed-fitted to the server's strike time, and the procedural swing layer switched off for it.
- **Mix (my recommendation):** keep first-person hands and server timing as they are, author third-person body motion in Blender, and play the baked joint Transforms as data through the existing CharacterVisuals layer. That needs no upload at all, but it needs a small clip player written in src, which I did not touch.

The preview for the owner is C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\owner_swing_preview.png. The character in it is box stand-ins sized from the real R15 parts with placeholder colours; the sword is the project's ItemsReal sword.

## done

- Read the real R15 rig from Studio without changing the place (15 parts, 15 joints, grip attachments) and saved it as r15_rig.json.
- Built a Blender rig from that data by script: one bone per R15 part with the same names, box body parts at the real sizes, rest pose computed from the rig attachments.
- Put the project's existing sword (ItemsReal.glb, asset "sword") in the right hand the same way InventoryService does, grip on RightGripAttachment.
- Animated one swing: guard, wind-up to frame 6, hit at frame 9 (0.3 s), follow-through to frame 12, back to guard at frame 18. Torso keyed sparsely; arms and legs solved per frame from hand and foot controls so the feet stay planted.
- Rendered the 8-frame contact sheet and looked at it three times. Fixed an overexposed sky, a blade that swung under the arm instead of over the top (added keys at frames 7 and 8), a hit that landed too low, and a hand twisted 174 degrees by a wrong edge convention.
- Numeric checks on every frame: 0 foot slide, 0 blade-inside-body, 0 blade-in-ground.
- Exported three files: a compact Studio payload (5,658 bytes, joint Transforms as integers with a checksum and a rig-match check), a verbose review file (23 KB), and an FBX fallback (384 KB).
- Inspected the FBX by re-importing it: 16 bones with the right names and hierarchy, 18 meshes at scale 1, 19 frames.
- Built the KeyframeSequence in ServerStorage._AnimProof with one execute_luau call: checksum passed, rig check passed (worst attachment difference 0.00007 studs).
- Read it back: 19 keyframes from 0 to 0.6 s, Priority Action, Loop false, KeyframeMarker "Hit" on keyframe 9, 16 poses per keyframe, all names and nesting match the R15 rig.
- Played it in Edit mode with no playtest: RegisterKeyframeSequence gave a temporary id, the rig sat in a WorldModel inside the temp folder, Animator:StepAnimations advanced it. At 0.2 s and 0.3 s part positions matched Blender within 0.00065 studs; the marker signal fired once.
- Deleted ServerStorage._AnimProof and confirmed it is gone and QA_Lock is nil. Every Edit-mode change set and cleared the lock; no other label held it.
- Wrote the effects recipe (sword trail, neutral hit spark, optional hit flash) as fx_sword_recipe.luau. It was never run in the place; its property names were checked by setting them on unparented instances in Studio, and ParticleEmitter:Emit exists.
- Nothing was uploaded, no playtest was started, nothing under src was edited, nothing was committed, nothing was downloaded or installed.

## open

- Not seen in a running game: no playtest was allowed, so the swing has not played on a spawned player character, under the game's CharacterVisuals layers, or for a second client. The Studio check was numeric, not a screenshot.
- Whether a temporary id registered on one side of a playtest plays for the server and other clients is still unknown.
- Publishing is untested: no click-free route is confirmed (Open Cloud Animation upload, the Animation Editor's Load menu, right-click Save to Roblox).
- The clip is full-body, so it would override the legs while a player runs. An upper-body-only variant is not built and the exporter has no part filter yet.
- The clip's hit is at 0.3 s; the game's server decides the strike time (0.36 / 0.42 / 0.5 s wind-up by weapon weight). Fitting the clip to that is not done.
- The FBX fallback was not tried in Roblox's importer. Its root bone is HumanoidRootPart, not the Root > HumanoidRootNode chain the research read, and the meshes are named <Part>_Geo.
- Payload size: one call carried a 10.5 KB script for 0.6 s (about 300 bytes per frame). Longer clips were not tried and may need chunking or fewer keyframes.
- Only the sword and only the Motor-free weld case were proven. Bow draw, two-handed grips and first-person viewmodel clips are untested.
- In the effects recipe the dust texture path rbxasset://textures/particles/smoke_main.dds was not checked to exist; the sparkle texture is the engine default and was.
- The preview body is boxes with placeholder colours, not the real R15 meshes or a player's avatar.
- studio_verify_play.luau is a tidied copy of the script that ran, not byte-identical; it has not been re-run in its saved form.

## howTo

All paths are under C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\

1. Read the rig (Studio, Edit, read-only). execute_luau with studio_read_rig.luau. It calls Players:CreateHumanoidModelFromDescription(blank HumanoidDescription, R15), keeps the model unparented, and returns JSON. Save it as r15_rig.json. Only needed again if the avatar settings change.

2. Animate and export (Blender tool). blender_run_script with script_path anim_sword_swing.py and script_args ["<out_dir>"] (add "norender" or "nofbx" to skip those). It takes about 9 seconds including the preview. It:
   - builds the rig from r15_rig.json (ls_anim.Rig.build), rest pose = parent * c0 * c1^-1;
   - imports ItemsReal.glb, keeps the "sword" asset, parents it to the RightHand bone at RightGripAttachment;
   - keys LowerTorso, UpperTorso and Head directly, and the hand, elbow and foot controls; bake_limbs solves arms and legs on every frame;
   - adds the timeline marker "Hit" at frame 9;
   - prints CHECK lines for foot slide, blade in body and blade in ground (0 on the final run);
   - writes SwordSwing.blend, SwordSwing.studio.json, SwordSwing.anim.json, SwordSwing.fbx and owner_swing_preview.png.
   Read the PNG, change the key tables at the top of anim_sword_swing.py, run again.
   Axes: Roblox (x, y, z) = Blender (x, z, -y); the character faces Blender +Y. Blade edge convention: the hand's Blender +Y is the blade's spine, the cutting edge is -Y.

3. Make the Studio call text. python make_studio_luau.py out/SwordSwing.studio.json <lock label> <ServerStorage folder>  writes out/SwordSwing.build.luau (the template studio_build_kfs.luau with the JSON pasted in).

4. Build in Studio (Edit). list_roblox_studios, then execute_luau with the text of SwordSwing.build.luau. The script itself verifies the checksum, reads Workspace QA_Lock and refuses if another label set it under 9 minutes ago, sets and clears the lock, compares the place's rig attachments with the authoring rig, then builds KeyframeSequence > Keyframe > Pose tree (HumanoidRootPart pose with Weight 0 at the top, Pose.CFrame = joint Transform, Linear easing), adds the KeyframeMarker, sets Priority, Loop and AuthoredHipHeight, and parents it to ServerStorage.<folder>. It returned: "OK / rig check: 15 joints (AnimationConstraint), worst 0.00007 studs / built ServerStorage._AnimProof.SwordSwing: 19 keyframes, 0.6000 s".

5. Read back and play without a playtest (Edit). execute_luau with studio_verify_play.luau: KeyframeSequenceProvider:RegisterKeyframeSequence(kfs) for a temporary id (a bare hash string here), a fresh rig inside a WorldModel in the temp folder, Animator:LoadAnimation, wait until track.Length > 0, track:Play(0), Animator:StepAnimations(dt), compare joint Transforms and part positions, count GetMarkerReachedSignal("Hit"). The first attempt stepped before the clip had loaded and stayed at time 0; the wait fixed it.

6. Clean up (Edit). Destroy ServerStorage.<folder> under the same lock.

7. Publish: not done. Needs the owner's yes per clip.

Fallback if the data route ever fails: SwordSwing.fbx, then by hand in Studio: Animation Clip Editor > Import > From File, Rig Type R15, Rest Pose Source "Animation Editor Rig", then Publish. Untested.

Effects recipe (fx_sword_recipe.luau, not built):
- Swing trail: a Trail between the blade's existing "Tip" attachment and a new attachment a fifth of the way up the blade. Lifetime 0.14, FaceCamera false, pale grey ColorSequence (236,232,222 to 190,188,182), Transparency 0.55 to 1, WidthScale 1 to 0.25, LightEmission 0.15, LightInfluence 1. Enabled only from the top of the wind-up to the follow-through.
- Hit spark: one reusable Attachment under workspace.Terrain moved to the contact point, two ParticleEmitters with Rate 0 fired by :Emit(). Sparks: Emit(12), Lifetime 0.12-0.26, Speed 10-22, SpreadAngle 55, Acceleration (0,-45,0), Drag 4, Size 0.16 to 0, colour pale straw (240,232,210) to grey (165,156,140), LightEmission 0.3, VelocityParallel with Squash 1.5. Dust: Emit(4), Lifetime 0.3-0.45, Speed 2-5, Size 0.5 to 1.3, Transparency 0.6 to 1, colour (196,190,178), LightEmission 0. No flipbook, nothing red.
- Optional flash: one reused Highlight per character, white fill, FillTransparency 0.6 to 1 over 0.12 s, no outline.

## files

- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\owner_swing_preview.png
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\notes.md
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\ls_anim.py
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\anim_sword_swing.py
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\r15_rig.json
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\make_studio_luau.py
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\studio_build_kfs.luau
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\studio_read_rig.luau
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\studio_verify_play.luau
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\fx_sword_recipe.luau
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\out\SwordSwing.blend
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\out\SwordSwing.studio.json
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\out\SwordSwing.anim.json
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\out\SwordSwing.build.luau
- C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-proof\out\SwordSwing.fbx

## questionsForLead

- Which way should Blender clips reach the live game: uploaded Animation assets (one permanent upload and one owner yes per clip), or baked data played by the existing CharacterVisuals Transform layer (no upload, but a clip player has to be written in src)?
- Should attack clips be full-body as proven here, or upper-body only so the legs keep running? Upper-body needs a part filter in the exporter.
- Should clips be fitted to the server's strike timing (0.36 / 0.42 / 0.5 s by weapon weight) instead of this proof's 0.3 s hit?
- Should ls_anim.py, anim_sword_swing.py and r15_rig.json go into art\blender, and the three Studio scripts somewhere in the repo? They are worth keeping; I left them in the scratchpad.
- When Studio is free, may someone run a playtest check of the temporary id on a spawned character and a second client? That is the main thing still unproven.
- If assets are chosen: will the owner do the publish clicks, or approve trying the Open Cloud route under user 5458010221?
# The research behind it

## summary

Web research only, done 18 November 2026. Nothing was downloaded, installed, uploaded or changed in Studio or Blender. Notes are at C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\anim-research\notes.md.

Recommendation: keep Blender as the animation tool, but do not move animations into Studio through FBX and the Animation Editor's import dialog. That step needs a human in a plugin window and has been unreliable since August 2026. Instead, have a Blender Python script bake the animation to data, and have Studio's own execute_luau tool build a normal KeyframeSequence from it. That can be tested in a Studio playtest with no upload, and published as an ordinary animation asset only when the owner says yes. Fight effects need no plugin at all.

1. What people use. Combat animation is made mostly in Blender (with a community transfer plugin, or FBX into the Animation Clip Editor) or in Moon Animator; the built-in editor is the fallback and is where hit-moment markers get added. I found no 2026 survey, so "how common" is forum impression, not a number.

2. The August 2026 breakage is real. Roblox staff changed the animation importer on 4 August 2026; from 10-11 August users reported malformed and inverted imports (GLB worst, FBX too, mainly custom and skinned rigs). Staff acknowledged it on 13 September and said some variants were fixed. One reporter fixed theirs on 15 September by setting Rest Pose Source to "Animation Editor Rig". The GLB-inverted thread had a new "same issue" post on 27 October and no accepted answer.

3. "VFX Studio" does exist: a free community plugin by Sytranom (texture and mesh library plus emitter tools). It has no scripting or agent interface that I could find, so it does not fit an agent-driven pipeline.

4. The "do not use this server" listing: the note on the listing, written as the author, reads "do not use this server. i did not upload it here and there's no way to delete it". The GitHub repository it points to returned 404 today. It is not worth the risk.

5. Publishing an animation is the one step with no confirmed click-free path. It is permanent, needs the owner's yes, and the asset must belong to whoever owns the experience (user or group) or be granted to it.

Questions for the lead:
- Is the experience owned by the owner's user account or by a group? That decides the Creator for every animation upload.
- Will the owner do the publish clicks per animation, or enable the asset read/write permissions for the Studio tool so the Open Cloud route can be tried?
- Should the first-person hands stay procedural for now, with uploaded animations used for third-person fighting only?
- May Studio's own generate_animation be used for rough first drafts?

## whatPeopleUse

COMBAT ANIMATION (melee and bow)

No 2026 poll or usage figure was found; the ranking below is forum impression from DevForum threads.

1. Blender plus a transfer step. Experienced animators in the January 2026 staff thread call Blender the best option for quality. Two transfer methods:
   - Community rig-export / animation-import plugin pair. The original is by Den_S (DevForum, 2017; 1,306 likes, about 1,885 posts). The fork most people now use is by Cautioned (GitHub: 119 stars, GPL-3.0; also on the Creator Store). It works on Motor6D rigs such as blocky R15; the original states skinned meshes are not supported. Human clicks: export rig in the Studio plugin, rebuild rig in the Blender add-on, export or sync, import in the Studio plugin, upload.
   - FBX or glTF into Studio's Animation Clip Editor. Human clicks: select the rig, create a clip, the three-dots menu, Import, "From File", pick the file, set the import dialog (Rig Scale, Rest Pose Source, Rig Type, track), then Publish. The scripting call for this (Plugin:ImportFbxAnimation) is documented as prompting the user to open a file, so it cannot run unattended.

2. Moon Animator 2 (paid community Studio plugin). Very commonly named on the forum for combat and cutscene work. Entirely a plugin window: a human does everything. Price not confirmed today.

3. Studio's built-in Animation Editor. Free, used for simple animations and as the place where Blender animations get event markers, priority and looping set, and get published. All of it is plugin-window clicks, though the same data (KeyframeSequence, Keyframe, Pose, KeyframeMarker) can be created by script.

4. Roblox's own Blender plugin (Roblox/roblox-blender-plugin, MIT, 259 stars). It uploads selected meshes or collections from Blender to Roblox as packages through Open Cloud. Neither the docs page nor the README mentions animation. Not an animation route, and every use is a permanent upload.

5. The 3D Importer (File > Import). Since 4 August 2026, animations attached to an imported model are saved automatically under AnimSaves if the Animation Clip Editor is open. Human clicks throughout, and "Upload to Roblox" is on by default, so it uploads the model unless switched off.

6. AI generation. The Animation Editor docs offer capture, not text: face capture from a webcam and body capture from a video under 15 seconds (both beta). Text-to-animation exists only as the generate_animation tool of Roblox's Studio MCP server (R15, from a prompt, or converts R6 to R15). That one an agent can call with no clicks. I found no announcement or usage reports for it.

FIGHT EFFECTS

- The norm is Roblox's built-in instances: ParticleEmitter (including flipbook textures), Trail, Beam and Highlight, triggered from script. Roblox's docs teach all of them with Explorer and Properties only; no plugin is required. An agent can create and tune all of them through execute_luau.
- VFX plugins are conveniences for human artists: curve and colour-sequence editors, texture libraries, preview and emit buttons. Named on the forum: VFX Editor, VFX Forge, Sine VFX, Beziers, VFX Suite, Lumina, VFX Studio. All are plugin windows driven by a human.
- Flipbook textures and any custom particle texture are image uploads (permanent, moderated), so they need the owner's yes.

## recommendedPipeline

Steps marked [read] were read today in the cited Roblox source. Steps marked [proposed] are my design from those facts and have not been run.

A. RIG
1. [read] Bone names and hierarchy must be exactly: Root > HumanoidRootNode > LowerTorso > UpperTorso > Head; UpperTorso > LeftUpperArm > LeftLowerArm > LeftHand (same on the right); LowerTorso > LeftUpperLeg > LeftLowerLeg > LeftFoot (same on the right). Root and LowerTorso sit at 0,0,0. Note: Roblox's Maya animation page names the second joint HumanoidRootPart, the body specification names it HumanoidRootNode.
2. [read] Official rig files on Roblox's docs site (allowed source): Rig_and_Attachments_Templates.zip (.blend, .ma, .fbx, "Standard R15 rig template for Blender") and BlockyCharacter.fbx.
3. [proposed] Better for this game: read the real rig from Studio with execute_luau (each Motor6D's Part0, Part1, C0, C1 and each part's rest CFrame and size) and build the Blender armature from that data, so Blender matches the character the game actually spawns.

B. UNITS AND SCALE
4. [read] Blender: Unit System None, so one Blender unit is one stud. Staff state a stud is 0.28 metres.
5. [read] Only if FBX is ever used: Transform > Apply Scalings = FBX Unit Scale, Add Leaf Bones off, Bake Animation on, Forward = Z Forward, Up = Y Up. glTF needs no scale adjustment.
6. [read] The Animation Editor runs at 30 frames per second: bake at 30.

C. HELD WEAPON
7. [read, community practice] Join the weapon to the hand with a Motor6D (Part0 = RightHand, Part1 = the weapon's root part), not a weld, so the animation can move it.
8. [read] A Pose is matched to a part by name and drives the motor joining that part to its parent pose's part.
9. [proposed] In Blender add one bone under RightHand named exactly like the weapon's root part in Studio and parent the Blender weapon model to it. A bow gets a second bone for the string hand or nock point if the draw needs it.

D. BAKE AND EXPORT (Blender tool)
10. [proposed] A Python script steps the action at 30 fps and writes JSON: for each frame and bone, the bone's change from rest in armature space, converted to Roblox axes, plus the frame number of the hit and whether it loops.
11. [read] Staff note Blender exports one extra frame on loops: trim the end frame.
12. [read] Keep root translation muted so attacks play in place.

E. INTO STUDIO (Studio tool, no plugin window)
13. [read] A KeyframeSequence can be built entirely by script: KeyframeSequence (Loop, Priority) > Keyframe (Time) > Pose tree nested by joint hierarchy starting at HumanoidRootPart, added with AddPose, AddSubPose, AddKeyframe. Pose.CFrame is applied to Motor6D.Transform; C0 and C1 are untouched.
14. [proposed] execute_luau reads the JSON, turns each bone delta into the target part CFrame, solves each joint's Transform from the rig's own C0 and C1, and writes the Poses. Solving in Studio avoids the rest-pose rotation mismatch that breaks FBX imports.
15. [read] Add the hit moment by script: Instance.new("KeyframeMarker"), Name = "Hit", parent it to the contact Keyframe.
16. [read] Store the sequence in ReplicatedStorage; clients cannot see ServerStorage.

F. TEST WITHOUT UPLOADING
17. [read] KeyframeSequenceProvider:RegisterKeyframeSequence(sequence) returns a temporary id "for localized testing"; put it in Animation.AnimationId. It "cannot be used outside of Studio".
18. [proposed] start_stop_play, then execute_luau on the Client: register, Animator:LoadAnimation, Play, screen_capture at several times. First check: an all-identity sequence must reproduce the rest pose exactly.

G. PUBLISH (permanent, owner's yes each time)
19. [read] Human route: Animation Editor three-dots menu > Publish to Roblox, title, and Creator = the group if the game is group-owned.
20. [read] Ownership: the asset must belong to the experience's owner, or be granted to the experience on the Creator Hub asset page under Permissions > Experiences.
21. [read] It must pass moderation, "generally within a few hours". No fee or quota for animations appears on the pages read.
22. [read, untested] Possible click-free route: the Open Cloud Assets API accepts Animation as .rbxm or .rbxmx, and the Studio tool's open_cloud_invoke can upload files once the owner enables asset read and write for the game and approves a folder. Roblox documents this only for models.

H. IN THE GAME
23. [read] Animation instance with the asset id; Animator:LoadAnimation from a LocalScript on the local player's Humanoid Animator; Play. Animations started on a player's own character replicate to the server and other clients. The Animator must have been created on the server and be in the Workspace.
24. [read] NPCs and other models: load and play on the server. A locally created Animator (a first-person viewmodel) does not replicate, which is what a viewmodel wants.
25. [read] Priorities, highest first: Action4, Action3, Action2, Action, Movement, Idle, Core. Attacks at Action or above.
26. [read] Hit moment: track:GetMarkerReachedSignal("Hit"):Connect(function(param) ... end).
27. [proposed] The client reports the marker and the server validates the hit. In Studio builds the game registers the local KeyframeSequence; in live builds it uses the published id.

FALLBACK IF THE DATA ROUTE FAILS
FBX from Blender, then the owner clicks: Animation Clip Editor > Import > From File, Rig Type R15, Rest Pose Source "Animation Editor Rig" (the setting that fixed the August breakage for one reporter), then Publish.

EFFECTS
execute_luau creates ParticleEmitters (bursts), a Trail between two Attachments on the blade, Beams, and one reused Highlight per character for hit flash, all as plain instances in the place. No blood or wounds: sparks, dust, swing trails, flashes.

## thirdPartyTools

VFX FORGE (plugin). Made by zilibobi ("Checkmate" on DevForum). DevForum thread opened 8 August 2025: 129 likes, about 34,000 views, last post 16 April 2026. Paid (a reviewer cites 15 dollars). It adds particles, beams, trails, mesh and decal flipbooks, bezier paths, lightning, camera shake and screen effects, plus a Studio API and an "Emit Module" the game must include to play its effects. Warnings: version 2 added a licence whitelist and obfuscated main code; the author says the Creator Store copy "can no longer be updated"; the itch.io page says the plugin is currently unavailable there and sends buyers to the author's own site and Discord; users report a startup crash and setup that is hard to drive from code. Not worth it here: paid, closed, obfuscated code inside Studio, and a runtime dependency in the game.

VFX FORGE MCP SERVER. Same author, version 0.1.0. It bridges an agent to the VFX Forge plugin over a local WebSocket (port 3847), needs Bun and the paid plugin, and can create, modify and delete instances. Directory listings show 0 to 4 stars and 12 installs. The Glama listing titled "do not use this server" carries this note, written as the author: "do not use this server. i did not upload it here and there's no way to delete it". The GitHub repository returned 404 today. One directory page (LobeHub) also carried text telling automated readers to run a registration command with credentials; I ignored it. Do not use.

ROBLOX VFX LAB. By NevelStudios, MIT. An MCP server that has an agent write a small GPU shader, render it, bake a flipbook sheet, and apply it to ParticleEmitters, Beams or Trails through Roblox's own Studio MCP; it needs Node 22 and a GPU, and installs straight from GitHub. Its own listing warns uploads are public, moderated and permanent. No stars, dates or usage were visible, and its GitHub page returned 404 today. Interesting idea, unproven, and it means running unreviewed code: not now. The project's Blender tool can already render flipbook sheets if they are ever wanted.

VFX STUDIO. By Sytranom; docs show version 3.9.1; Discord server created 18 June 2025 with 2,454 members. Described as a free plugin: texture, mesh and sound library, emitter and camera-shake tools, bezier curve editor. No scripting or agent interface found, and no install source or Creator Store listing confirmed. This is probably what the owner half-remembered. Fine for a human artist; adds nothing an agent can drive.

VFX EDITOR. By VirtualButFake, open source on GitHub, also on the Creator Store. Thread from 5 August 2024: 162 likes, about 27,800 views, last post 19 February 2026. A better property, curve and colour editor for built-in effects. Some crash reports. Harmless, but human-only: not needed.

SINE VFX, BEZIERS, VFX SUITE, LUMINA. Seen in search results only; not examined. Lumina is a custom particle system, which would add a runtime dependency.

CAUTIONED'S BLENDER ANIMATIONS PLUGIN (fork of Den_S's). GitHub: 119 stars, 29 open issues, GPL-3.0; also on the Creator Store. A Studio plugin plus a Blender add-on that sync rigs and animations over a local server (port 31337). This is the real mainstream Blender route for Motor6D rigs, and during the August breakage a reporter said default rigs imported with it looked correct. It needs an install from a community source and human clicks in both programs. Worth offering to the owner as the conventional alternative if they prefer to click; not required.

DEN_S'S ORIGINAL PLUGIN. The 2017 original, add-on distributed through Pastebin and Gist. Superseded by the fork; skip.

MOON ANIMATOR 2. Paid, widely used, human-only window. It does not combine with Blender animation. Skip.

ROBLOX'S OWN BLENDER PLUGIN. First-party and safe, but it only uploads meshes as packages, and every use is a permanent upload. Not an animation tool.

NILO. A third-party service whose articles were useful as a secondary source; it also sells text-to-animation. Not needed.

## knownProblems

- Animation import through the Animation Clip Editor has been unreliable since the 4 August 2026 importer change: malformed or inverted results, mainly on custom and skinned rigs, GLB worst. Staff said on 13 September 2026 that some variants were fixed; a user still reported the GLB inversion on 27 October 2026.
- Workarounds reported for the importer: set Rest Pose Source to "Animation Editor Rig" (fixed one reporter's case on 15 September 2026); re-import the rig, then the animation; remove any extra bone parented under the root (it caused a 'clamp' error on import); keep a root bone at the origin.
- There is no scriptable FBX or glTF animation import: Plugin:ImportFbxAnimation prompts the user for a file, and the Animation Editor import is a dialog. An agent cannot complete it alone.
- Publishing has no confirmed click-free route. AssetService:CreateAssetAsync does not list Animation as a type. The Open Cloud Assets API lists Animation as .rbxm or .rbxmx but warns that files edited outside Studio might not upload or function.
- Uploads are permanent and cannot be archived or deleted through Open Cloud; removal needs the Creator Dashboard. Every publish needs the owner's yes.
- The 3D Importer has "Upload to Roblox" enabled by default, so using it to bring in an animated model uploads the model unless that is switched off first.
- The temporary id from RegisterKeyframeSequence works only inside Studio. The live game needs a published asset id, so the game needs a Studio-only code path for testing.
- A looping animation does not interpolate from the last keyframe back to the first, and Blender exports an extra frame at the end of loops: duplicate the first pose as the last and trim the end frame.
- Roblox's two documents disagree on the second joint's name: HumanoidRootNode (body specification) versus HumanoidRootPart (Maya animation export page).
- The generate_animation tool's limits are stated inconsistently: the docs page says up to 10 seconds, the tool's own description says 1 to 30 seconds.
- Highlight is capped at 255 instances on a client and disabled ones still count; adding or removing one can cause a frame spike. Reuse one per character and change its properties.
- Flipbook particles are switched off automatically on low-memory devices, so an effect must still read without its flipbook.
- Group-owned experiences have a history of animations failing to load for some members even when ownership is correct (forum reports, including 2026).
- The LobeHub directory page for the VFX Forge MCP server contained text instructing automated readers to run a registration command with credentials. I did not act on it.

## unverified

- Whether the proposed data route works end to end. It has not been run. In particular the Motor6D relation used to solve Transform (Part0.CFrame * C0 * Transform * C1 inverse = Part1.CFrame) was not read today and must be confirmed by a rest-pose round trip in Studio.
- Whether execute_luau can accept a full animation's JSON in one call, or needs it in chunks.
- Whether a temporary id registered on one side in a Studio playtest plays for the server and other test clients, or must be registered on each.
- Whether a script-built KeyframeSequence placed under the rig's AnimSaves appears in the Animation Editor's Load menu for publishing, and whether right-click Save to Roblox on a KeyframeSequence publishes it as an Animation today.
- Whether open_cloud_invoke can upload an Animation, and how to obtain a Studio-made .rbxm of the sequence without a human click.
- Whether execute_luau has the plugin-level permission needed for Animator:StepAnimations (preview in Edit mode without a playtest).
- Whether the August 2026 importer bugs affect a plain blocky Motor6D R15 rig imported from Blender FBX; the reports concern custom and skinned rigs.
- Current state of the importer in November 2026: no staff post confirming a full fix was found.
- Where generate_animation stores its result, its quality for melee or bow moves, and whether it costs anything.
- Fees and upload quotas for animation assets: none appear on the pages read, which is not proof there are none.
- The exact official rule on animation ownership: Roblox's "Transfer animations" docs page returned 404 today, so the rule is taken from a search snippet of that page and the August 2025 staff post on sharing.
- The exact download URLs of the official rig files; the docs page gives relative paths only.
- How common each animation tool is; no 2026 survey was found.
- Moon Animator 2's current price and status.
- Why the VFX Forge MCP and Roblox VFX Lab GitHub pages return 404 (deleted, private or renamed).
- VFX Studio's install source, Creator Store listing and whether it is still free.
- The "Animation Editor Rig" option name for Rest Pose Source comes from a user's post, not from the staff announcement, which names only "Imported Rig" and "Imported Rig (Zeroed Rotations)".
- ParticleEmitter:Emit for one-shot bursts was not on the docs page read today.

## sources

- https://devforum.roblox.com/t/animation-import-improvements/4775593 (Roblox staff bballerblox, 4 Aug 2026; staff replies by egg_roe same day; last post 19 Aug 2026)
- https://devforum.roblox.com/t/animation-importer-malforms-animations/4804266 (bug report 11 Aug 2026; staff reply 13 Sep 2026; resolved for reporter 15 Sep 2026; closed 29 Sep 2026)
- https://devforum.roblox.com/t/glb-animations-importing-inverted/4805191 (bug report 11 Aug 2026; staff reply 17 Aug 2026; latest post 27 Oct 2026)
- https://devforum.roblox.com/t/problems-while-importing-glb-and-fbx-animations-inverted-bone-rotations-on-skinned-mesh-rigs/4807176 (12 Aug 2026; latest post 1 Sep 2026)
- https://devforum.roblox.com/t/animation-editor-animation-import-fails-due-to-invalid-clamp-arguments/4816692 (17 Aug 2026, with staff replies)
- https://devforum.roblox.com/t/studio-beta-animation-clip-editor-improved-importing-and-gltf-support/4260501 (Roblox staff, 15 Jan 2026; general availability 31 Mar 2026; closed 31 Jul 2026)
- https://devforum.roblox.com/t/sharing-animation-assets-with-connections-and-groups/3892540 (Roblox staff BobaMuncher, 21 Aug 2025)
- https://create.roblox.com/docs/animation/editor (no date shown; read 18 Nov 2026)
- https://create.roblox.com/docs/animation/using (no date shown; read 18 Nov 2026)
- https://create.roblox.com/docs/animation/events (no date shown; read 18 Nov 2026)
- https://create.roblox.com/docs/animation/capture (last updated 17 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/KeyframeSequenceProvider (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/KeyframeSequence (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/Pose (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/KeyframeMarker (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/Animator (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/Animation (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/Plugin (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/engine/classes/AssetService (read 18 Nov 2026)
- https://create.roblox.com/docs/avatar/character-bodies/specifications (read 18 Nov 2026)
- https://create.roblox.com/docs/art/characters/export-avatar-animations-from-maya (read 18 Nov 2026)
- https://create.roblox.com/docs/art/modeling/project-files (read 18 Nov 2026)
- https://create.roblox.com/docs/art/modeling/export-requirements (read 18 Nov 2026)
- https://create.roblox.com/docs/art/blender (read 18 Nov 2026)
- https://create.roblox.com/docs/art/modeling/rigging (read 18 Nov 2026)
- https://create.roblox.com/docs/art/modeling/gltf-export (read 18 Nov 2026)
- https://create.roblox.com/docs/art/modeling/roblox-blender-plugin (read 18 Nov 2026)
- https://create.roblox.com/docs/studio/importer (read 18 Nov 2026)
- https://create.roblox.com/docs/studio/mcp (last updated 17 Nov 2026)
- https://create.roblox.com/docs/studio/mcp-open-cloud (last updated 17 Nov 2026)
- https://create.roblox.com/docs/assistant/guide (last updated 17 Nov 2026)
- https://create.roblox.com/docs/cloud/guides/usage-assets (read 18 Nov 2026)
- https://create.roblox.com/docs/reference/cloud/assets/v1 (read 18 Nov 2026)
- https://create.roblox.com/docs/projects/assets (read 18 Nov 2026)
- https://create.roblox.com/docs/projects/assets/privacy (last updated 17 Nov 2026)
- https://create.roblox.com/docs/effects/particle-emitters (read 18 Nov 2026)
- https://create.roblox.com/docs/effects/highlighting (read 18 Nov 2026)
- https://create.roblox.com/docs/llms.txt (docs index, read 18 Nov 2026)
- https://github.com/Roblox/roblox-blender-plugin (README read 18 Nov 2026; no release date shown)
- https://devforum.roblox.com/t/blender-rig-exporteranimation-importer/34729 (Den_S, 30 Mar 2017)
- https://github.com/Cautioned/Blender-Animations-Plugin (README read 18 Nov 2026; no release date shown)
- https://devforum.roblox.com/t/how-to-animate-tool-parts-guns-knifes-etc/359484 (Headstackk, 30 Sep 2019)
- https://devforum.roblox.com/t/plugin-vfx-forge-an-advanced-custom-vfx-system/3867553 (zilibobi, 8 Aug 2025; last post 16 Apr 2026)
- https://zilibobi.itch.io/vfx-forge ("updated 5 days ago" when read 18 Nov 2026)
- https://glama.ai/mcp/servers/u4g5sok44r (listing titled "do not use this server"; no date shown)
- https://glama.ai/mcp/servers/dvbb9xtsxv (roblox-vfx-lab listing, which shows the VFX Forge MCP author's note; no date shown)
- https://market.lobehub.com/s/plugins/zilibobi-vfx-forge-mcp (no date shown; contained injected instructions, ignored)
- https://sytranom.github.io/vfx-studio-docs (VFX Studio docs, version 3.9.1; no date shown)
- https://discord.com/servers/vfx-studio-1385020672480252118 (server created 18 Jun 2025)
- https://devforum.roblox.com/t/vfx-editor-all-your-vfx-needs-in-one/3103467 (5 Aug 2024; last post 19 Feb 2026)
- https://nilo.io/articles/export-blender-animation-roblox-studio (third party; published 31 Aug 2026, updated 18 Nov 2026)