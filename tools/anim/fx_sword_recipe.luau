-- fx_sword_recipe.luau - RECIPE ONLY, never run in the place. Every property below was set on unparented instances
-- in Studio on 2026-11-18 (all accepted; ParticleEmitter:Emit and Trail:Clear exist). Roblox's own Trail and
-- ParticleEmitter, no plugin, no uploaded texture. Matte look: low LightEmission, full LightInfluence, neutral
-- colours. Mild rating: pale sparks and dust only; nothing red, nothing that stays on a body.

-- 1. SWING TRAIL ------------------------------------------------------------------------------------------------
-- Held items are built by ItemModels.build: PrimaryPart "Handle", LookVector = toward the blade tip, and a "Tip"
-- attachment already sits on every blade (sword: 3.05 studs from the grip). Add one more attachment near the guard.
local function addSwingTrail(handle: BasePart): Trail?
	local tip = handle:FindFirstChild("Tip")
	if not (tip and tip:IsA("Attachment")) then
		return nil
	end
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = tip.Position * 0.2 -- a fifth of the way up the blade: the trail covers the cutting length
	base.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = 0.14 -- about 4 frames: reads as a smear, gone before the follow-through settles
	trail.MinLength = 0.05
	trail.FaceCamera = false -- a ribbon in the plane of the cut, not a billboard
	trail.Color = ColorSequence.new(Color3.fromRGB(236, 232, 222), Color3.fromRGB(190, 188, 182))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
	trail.LightEmission = 0.15 -- nearly matte: it takes the scene's light instead of glowing
	trail.LightInfluence = 1
	trail.Enabled = false
	trail.Parent = handle
	return trail
end
-- Switch it on only for the cut. With an animation asset, add two more markers in Blender next to "Hit":
--     track:GetMarkerReachedSignal("TrailOn"):Connect(function() trail.Enabled = true end)    -- top of the wind-up
--     track:GetMarkerReachedSignal("TrailOff"):Connect(function() trail.Enabled = false end)  -- follow-through
-- With the procedural swings, switch it from the swing's own phase (cut start to settle). trail:Clear() on unequip.

-- 2. HIT SPARK --------------------------------------------------------------------------------------------------
-- One reusable Attachment under workspace.Terrain per client, moved to the contact point; two emitters, Rate 0,
-- fired with :Emit(). No flipbook, so it looks the same on low-memory devices.
local function buildHitSpark(): Attachment
	local at = Instance.new("Attachment")
	at.Name = "HitSpark"
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "Sparks"
	spark.Rate = 0
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- the engine's default particle
	spark.Lifetime = NumberRange.new(0.12, 0.26)
	spark.Speed = NumberRange.new(10, 22)
	spark.SpreadAngle = Vector2.new(55, 55)
	spark.Acceleration = Vector3.new(0, -45, 0)
	spark.Drag = 4
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	spark.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	spark.Color = ColorSequence.new(Color3.fromRGB(240, 232, 210), Color3.fromRGB(165, 156, 140)) -- pale straw to grey
	spark.LightEmission = 0.3
	spark.LightInfluence = 0.6
	spark.Orientation = Enum.ParticleOrientation.VelocityParallel
	spark.Squash = NumberSequence.new(1.5) -- short streaks along the direction of travel
	spark.Parent = at
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Rate = 0
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Lifetime = NumberRange.new(0.3, 0.45)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Drag = 3
	dust.Rotation = NumberRange.new(0, 360)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.3) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(Color3.fromRGB(196, 190, 178))
	dust.LightEmission = 0
	dust.LightInfluence = 1
	dust.Parent = at
	at.Parent = workspace.Terrain
	return at
end
local function playHitSpark(at: Attachment, position: Vector3, surfaceNormal: Vector3)
	at.WorldCFrame = CFrame.lookAt(position, position + surfaceNormal) -- particles leave along the attachment's front
	(at:FindFirstChild("Sparks") :: ParticleEmitter):Emit(12)
	(at:FindFirstChild("Dust") :: ParticleEmitter):Emit(4)
end
-- Optional hit flash: ONE Highlight per character, kept parented and reused (the client cap is 255 and disabled
-- ones count). FillColor white, OutlineTransparency 1, DepthMode Occluded, tween FillTransparency 0.6 -> 1 in 0.12 s.

return { addSwingTrail = addSwingTrail, buildHitSpark = buildHitSpark, playHitSpark = playHitSpark }
