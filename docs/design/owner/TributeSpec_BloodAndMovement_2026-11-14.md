<!-- The owner's pasted production spec (14 November 2026), kept verbatim as design input. Not yet adopted:
     see docs/design/Direction_2026-11-14.md for what is planned, and the open decisions (gore rating, names). -->

PASTE-READY SPEC: "TRIBUTE" — Roblox Hunger Games, Blood & Movement Systems
Feed this to Claude as a single document. It is written as a production spec, not a mood board. Build order is at the bottom; do not let the model start with the train.

1. Design pillars
Three rules that override everything else when the model has to make a judgement call:

Damage is legible. The player must always be able to see where they're hurt and how close a limb is to coming off, without a HUD number telling them.
Weight over speed. Every animation and physics impulse reads as mass. Nobody in this game moves like a Roblox default avatar.
Blood is a system, not a particle. It stacks, it pools, it dries, it gets on things, and it changes how the character moves.
Tone: the 2012 film's brutal but readable violence. Hard cuts, handheld camera, practical-looking blood. Not anime gore, not Doom. Nobody sprays a fountain. It comes out in pulses.

2. Rig architecture
Do not use stock R15. Build a custom severable rig with 22 MeshParts. Each part is its own object so it can detach cleanly.

Segment list
Segment	Severable	Parent joint	Notes
Head	yes (death)	Neck	keeps hair, face decals
UpperTorso	no	—	spine root
LowerTorso	no	Waist	pelvis
UpperArm L/R	yes	Shoulder	
LowerArm L/R	yes	Elbow	
Hand L/R	yes	Wrist	weapon socket lives here
UpperLeg L/R	yes	Hip	
LowerLeg L/R	yes	Knee	
Foot L/R	yes	Ankle	
Knife / Bow / Arrow	—	Hand socket	
Every joint is a Motor6D with a mirrored Attachment pair (A0/A1) pre-created and pre-named but disabled. Severing is a matter of destroying the Motor6D and switching the Attachment pair on.

Custom collision groups
CharBody — collides with world, not with other body parts
SeveredLimb — collides with world only, never with CharBody or other SeveredLimb
Debris — severed limbs after 8 seconds
3. Region hitboxes
Per-region Attachment sets feeding a hitbox raycast. Hitboxes are slightly larger than the mesh (0.15 stud inflation) so combat feels generous, and overlap order is explicit so a hit never double-registers.

Priority order (first match wins, top to bottom):

Head
UpperTorso
LowerTorso
UpperArm L/R
UpperLeg L/R
LowerArm L/R
LowerLeg L/R
Hand L/R
Foot L/R
Each region holds an independent woundCount integer, 0–3, and an independent bleed state. Torso is a single logical region despite being two parts — torso wounds never sever, they just bleed to death.Penetration values
Weapon	Per-hit region penetration	Notes
Knife slash	1	3 hits = sever
Knife stab	1.5	2 hits = sever
Machete	1.5	
Spear thrust	2	
Arrow, >60 studs/s	3	instant sever on any limb
Arrow, <60 studs/s	1	sticks in, bleed 4/s
Arrow, head	3	instant kill
Arrow severing requires the projectile's impact speed, so the bow's draw time and the target's distance both matter. A snap shot at range won't take an arm; a full draw at 15 studs will.

4. Wound visual states
Four stages per region. Each is a Decal on the MeshPart, swapped with a 0.05s TweenService alpha.

Stage	Condition	Visual	Bleed
0 Clean	0 wounds	none	0
1 Cut	1 wound	thin 0.4-stud red slash, slight edge glow	0.8 HP/s
2 Deep	2 wounds	1.2-stud gash, dark centre, ragged edges	2.5 HP/s
3 Mangled	3 wounds, not severed	exposed dark tissue, bone hint on limbs	5 HP/s
Blood HP totals: 100. Bleed damage stacks additively across all regions. A 3-region Deep state is 7.5 HP/s and will kill an unattended player in 13 seconds. Bandaging drops a region one stage and halves its bleed rate.

Bleeding VFX per stage
Stage 1: ParticleEmitter at wound attachment, 6 particles/s, gravity 40, lifetime 0.7, size 0.08→0.2, dark crimson, LockedToPart = false. Dies at 5 studs. Floor decal on raycast hit, 0.3 scale, 0.85 transparency, fades over 20s.
Stage 2: same emitter at 14/s, plus a thin Beam from wound to a floor raycast point, CurveSize0 = 0.06, CurveSize1 = 0.25, animated texture scrolling downward at 1.5 UV/s. Floor decal 0.7 scale, builds to a pool over 6s via tween to 1.4 scale.
Stage 3: 24/s, two emitters at divergent angles, beam thicker, decal pool 1.2 scale. Trails on the character's movement path: 0.25s Trail, Lifetime = 0.3, shrinks to nothing.
Severed stump: a persistent low emitter (10/s) plus a pulsing beam — NumberSequence on Transparency synced to a fake 1.1 Hz heartbeat so it visibly spurts. Bleed 8 HP/s for 4 seconds, then 3 HP/s.
All blood uses a single shared 4-variant decal atlas for batching. Decal pool capped at 60 per server, oldest fades first.

5. Severing
The cut
Motor6D destroyed, replaced by two Attachments + a BallSocketConstraint for a single frame
Limb reparented to workspace.Debris, CollisionGroup = SeveredLimb
Impulse applied along the hit normal: mass * 26 studs/s plus 8 studs/s of lift, plus 3–6 studs/s of random tangential spin
AngularVelocity on the limb, 4–11 rad/s random per axis, decaying over 1.5s
Limb decal set to stage 3, stump emitter attached to the character side
Two-sided blood burst: 40 particles at the stump, 25 at the detached limb
Screen shake 0.25 magnitude for 0.2s on the attacker, 0.4 for 0.3s on the victim
Detached limbs behave as physical debris. They land, they leave a stain, they can be kicked. They CanCollide with world but not with the body, so a severed arm doesn't wedge the player into a wall. Despawn at 8s with a 2s fade.

Region consequences
Severed	Effect
UpperArm	that hand's item drops, 2H weapons unusable, swing speed −40%
LowerArm	hand drops with it, one-handed only, aim sway +60%
Hand	item drops, bow draw time +0.8s
UpperLeg	forced crawl, walk 4 studs/s, jump removed
LowerLeg	forced hop-crawl, 2.5 studs/s, direction drifts toward the injured side
Foot	−35% speed, limp cycle, footsteps silent
Head	instant death, decapitated ragdoll
Both legs	prone drag, 1.5 studs/s
Both arms	cannot attack, kick only
Losing a limb also triggers a 2-second adrenaline window: no bleed damage, +15% speed. Then the full bleed rate lands at once.

Near-sever (2 wounds)
Region goes slack: hangs 12° off natural rest with a slow pendulum via AlignOrientation, MaxTorque = 40, Responsiveness = 6. Limb-specific penalty at 50% of the full sever effect. Player sees the limb swinging uselessly and knows exactly how close they are.

6. Knockback
Impulse-based, never CFrame-based. Server applies AssemblyLinearVelocity, client predicts, server reconciles.
impulse = hitNormal.Unit * (weapon.force / totalMass) * massModifier
massModifier by region: Head 1.4, Torso 1.0, Limbs 0.7. A 60 kg character takes ~18 studs/s from a knife and ~34 from a machete. Decay 12 studs/s², so a knife shove costs about 1.5 studs of ground.

Arrows add a stagger: 0.4s where input is ignored, camera jolts 6° along the impact vector, and a HitStop freezes both animations for 3 frames (0.05s). Heavy weapons add 0.7s and drop the player to one knee on a woundCount == 2 region.

Directional stagger animations per quadrant — the character steps back with the correct foot and rotates the torso into the hit, never a generic flinch.

7. Movement physics
Roblox defaults are floaty. Replace them.

Parameter	Value
Walk	12 studs/s
Run	20 studs/s
Sprint	26 studs/s, 8s stamina
Crouch	5 studs/s
Ground accel	45 studs/s²
Ground decel	60 studs/s²
Air control	0.35
Turn rate cap	9 rad/s on ground, 4 in air
Momentum carry on direction change	0.85
Extras that sell weight: 0.12s of acceleration lag before the character visibly commits, 4° of lean into strafe and 6° into sprint, footstep IK planting on slopes so feet don't skate, a 0.3s recovery pause after landing from any fall over 8 studs, and a 0.15s startup on every dodge.

Injured movement runs through a multiplier stack (leg injuries, bleed stage, adrenaline) and feeds the limp cycle blend weight. Above 2.0 total multiplier the character's breathing becomes audible and the camera bobs harder.

8. Animation set
All on an Animator with three layers: base locomotion, additive upper body, additive full-body reaction.

Locomotion: idle, idle_breathe, walk, run, sprint, crouch_idle, crouch_walk, strafe L/R/F/B, jump, fall, land_soft, land_hard, turn_180.

Combat: slash_L, slash_R, stab, overhead, block, parry, dodge_roll, bow_nock, bow_draw, bow_hold, bow_release.

Reactions: flinch per region × 6, stagger per quadrant × 4, near_sever_arm, near_sever_leg, downed_crawl, downed_getup.

Sever reactions: sever_larm (clutch stump, scream), sever_rarm, sever_lleg (collapse to knee, look down), sever_rleg, sever_hand (stare at wrist), sever_foot, decapitate (head tracks, body takes one more step, folds).

Death: ragdoll trigger plus three collapse variants — forward fold, backward sprawl, side crumple. On ragdoll, every remaining Motor6D becomes a BallSocketConstraint, and limbs with 2 wounds get a 20% chance of detaching on impact with the ground.

Blending: reactions are additive at 0.08s in, 0.25s out. Reactions override the upper body layer only; legs keep walking through a knife hit. Sever reactions take over the full body and hold 1.2s before blending back into the injured locomotion set. Blend from flinch to sever at 0.1s so it snaps.

9. The train
Scene purpose: the last calm before the arena. It has to feel like a moving hotel that's kidnapping you. Everything is soft, warm and expensive, and the windows show a country getting poorer.

Exterior
Seven cars, brushed silver, bullet-nosed, seamless panel gaps, a faint warm glow leaking from every window at night. Magnetic levitation — no wheels, no bogies, no track noise beyond a low hum and a hiss at speed. Reflections slide across the flank. Station lamps smear into long streaks.

Layout
Car 1 — Vestibule. Brass handrails, pleated leather bench, a single wilting flower in a bud vase. The door seals with a pneumatic thump and the outside sound dies.

Car 2 — Dining. Mahogany panelling with inlaid silver filigree, white linen, crystal that rings when the train sways, low warm sconces, a chandelier on a gimbal that never quite stops moving. Silverware laid for a meal nobody wants. Plates carry the Capitol seal. The table has a runner embroidered with all twelve district crests, District 12's corner worn thin.

Car 3 — Lounge. Velvet club chairs, a globe drinks cabinet, a piano bolted to the floor. A wall screen loops Capitol propaganda — fashion segments, arena recaps, a smiling host. The screen's light is the only cool colour in the car.

Car 4 — Corridor. Narrow, brass fittings, a strip of patterned carpet, doors on both sides. Two of them lead to the tribute compartments; the rest are locked.

Car 5 — Compartment (District 12). Two bunks, one made up in silk, one in plain cotton. A fold-down basin, a mirror with a chipped corner, a window seat. Every surface is bolted. A pressed uniform hangs waiting. Under the window, a small brass plaque with the district number.

Car 6 — Observation. Glass on three sides, floor-to-ceiling, a curved bench. This is where the districts go past — slag heaps, fence lines, floodlights, a mine head at District 12 fading behind. The glass is spotless and the view is not.

Car 7 — Guard. Grey steel, no decoration, four white-armoured Peacekeepers standing the whole trip. They don't sit.

Motion and feel
Constant 1.5° roll and 0.4-stud vertical float on a slow sine, out of phase front to back. Loose objects slide with the sway. Chandelier and hanging lamps swing on their own inertia. Speed lines and dust motes streak past the windows. The hum is 52 Hz, and it gets into the score.

Camera: 28mm, handheld, close to faces, shallow depth. The train is shot from inside; the player never sees the exterior until the door opens.

Interactive beats: sit at the table (awkward silence timer), pour from the cabinet, watch the propaganda screen, stand at the observation window as District 12 passes. Each beat is a prompt-free proximity trigger, no button.

Sound: rail hum, glass chime, cutlery shift, distant door thump, the piano's pedal squeak, the guard's boot on steel when the train slows.

10. Performance
Blood particles: max 120 live per character, 400 per server
Decals: 60 cap, 30s life, 2s fade
Severed limbs: 8s life, 2s fade, Debris group
Hitbox raycasts: 3 per swing, 1 per arrow, RaycastParams filtered to a character whitelist
All VFX server-spawned but client-rendered; the server sends region, stage, and a seed only
StreamingEnabled on, train cars as separate models with ModelStreamingMode = Persistent
11. Build order
Custom severable rig + collision groups
Region hitboxes and wound counter
Wound decals and stage VFX
Severing, stump emitters, debris physics
Knockback, stagger, hitstop
Movement physics rewrite
Full animation set and blend rules
The train, car by car
Audio pass
Balance and tuning
Build the arena combat loop before the train. The train is the reward for a system that already works.
