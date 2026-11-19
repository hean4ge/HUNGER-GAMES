--[[
	ThrowLooks - how a thrown melee weapon flies and where it sticks (19 Nov 2026: every melee weapon can be thrown).
	Shared, so the server's resting pose (ProjectileService.WorldProjectiles) and the client's flying copy
	(ProjectileController) agree. Arrows, throwing knives and the spear keep Shared.WorldItems' dart rules.

	Flight styles (ItemDefs: throwSpin = studs flown per full turn; throwFlight = "point" | "flat")
	  "tumble"  end over end in the vertical plane of the throw, about the weapon's balance point (its Spin attachment,
	            else the middle of its bounding box). At release the head (or the point) is up and the edge faces the
	            target, as it leaves an over-the-shoulder throw; the top then turns forward. The turn rate follows the
	            throw: speed / throwSpin turns a second (a hatchet at 110 studs/s and 15 studs a turn: 7.3 turns/s).
	  "flat"    the Ring Blade: the hoop level, spinning about the vertical through its centre.
	  "point"   the spear: point first along the path, no spin (WorldItems).
	Sticking (World.embed / World.stick): how a weapon bites
	  "edge"    axes and the pick: the cutting edge (its Tip attachment) goes in; the haft hangs out and down from
	            the head about 35 degrees past square, as a real thrown axe sits in a tree or the ground.
	  "point"   blades: the point (Tip) goes in along a blend of the path and the surface, the grip out.
	  "flat"    the Ring Blade: its rim bites a wall, the hoop level; on the ground it lies flat.
	  Stone, metal, glass and ice: every thrown weapon glances off and falls flat (WorldItems.restPivot).

	API
	  ThrowLooks.handles(itemId) -> boolean          a thrown melee weapon these rules cover
	  ThrowLooks.style(itemId) -> "tumble" | "flat" | "point" | nil
	  ThrowLooks.spinRate(itemId, speed) -> number   radians a second
	  ThrowLooks.centre(model) -> Vector3            the balance point in the model's pivot (Handle) space
	  ThrowLooks.flightPose(itemId, centre, body, angle) -> CFrame   the model's pivot in flight: `body` is
	      CFrame.lookAt(position, position + direction, up), `angle` the spin so far (radians)
	  ThrowLooks.glances(itemId, material) -> boolean
	  ThrowLooks.depth(itemId, material, speed, incidence, body?) -> number   how far the edge or point goes in
	  ThrowLooks.stickPivot(itemId, point, normal, direction, depth, tipLocal) -> CFrame?   the stuck pose (nil: it
	      should lie flat instead); tipLocal = the Tip attachment's position in Handle space
]]
local ItemDefs = require(script.Parent:WaitForChild("ItemDefs"))

local ThrowLooks = {}

local BITE = { edge = math.rad(35), point = math.rad(25) } -- past square: how far the haft or grip leans out

local HARD: { [string]: boolean } = {
	Rock = true, Slate = true, Basalt = true, Granite = true, Marble = true, Limestone = true, Sandstone = true,
	Concrete = true, Brick = true, Cobblestone = true, Pavement = true, Asphalt = true, CrackedLava = true, Glacier = true,
	Ice = true, Metal = true, CorrodedMetal = true, DiamondPlate = true, Foil = true, Glass = true, Salt = true, Pebble = true,
}
local CLASS: { [string]: string } = {
	Grass = "soil", LeafyGrass = "soil", Ground = "soil", Mud = "soil", Sand = "soil", Snow = "soil",
	Wood = "wood", WoodPlanks = "wood", Cardboard = "wood", Fabric = "cloth", Leather = "cloth", Carpet = "cloth",
	Rubber = "cloth",
}
-- { base, extra at full speed } studs past the surface
local DEPTH = { soil = { 0.28, 0.14 }, wood = { 0.2, 0.08 }, cloth = { 0.25, 0.08 }, other = { 0.15, 0.05 }, body = { 0.25, 0.1 } }

local BITE_KIND: { [string]: string } = { hatchet = "edge", twin_axe = "edge", climb_pick = "edge", ring_blade = "flat" }

function ThrowLooks.handles(itemId: string?): boolean
	local def = ItemDefs.get(itemId)
	return def ~= nil and def.kind == "Melee" and def.throwable == true and def.throwFlight ~= "point"
end

function ThrowLooks.style(itemId: string?): string?
	local def = ItemDefs.get(itemId)
	if not (def and def.kind == "Melee" and def.throwable) then
		return nil
	end
	if def.throwFlight == "point" then
		return "point"
	elseif def.throwFlight == "flat" then
		return "flat"
	end
	return "tumble"
end

function ThrowLooks.spinRate(itemId: string?, speed: number): number
	local def = ItemDefs.get(itemId)
	local pitch = def and tonumber(def.throwSpin)
	if not pitch or pitch <= 0 then
		return 0
	end
	return 2 * math.pi * math.max(speed, 0) / pitch
end

function ThrowLooks.centre(model: Model): Vector3
	local handle = model.PrimaryPart
	local spin = handle and handle:FindFirstChild("Spin")
	if spin and spin:IsA("Attachment") then
		return spin.Position
	end
	local box = model:GetBoundingBox()
	return model:GetPivot():PointToObjectSpace(box.Position)
end

-- Item axes in the throw's body frame (look = the path, up = up, right = the spin axis' opposite):
-- tumble: the item's LookVector (to the head / point) up, its UpVector (spine) back, so the edge faces the target.
local TUMBLE = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis)
-- flat: the hoop's flat (the item's X) up; the hoop lies on the -UpVector side of the grip (its Tip, the rim's far
-- point), so -UpVector points along the path and the hoop flies ahead of the grip bar.
local FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis)

function ThrowLooks.flightPose(itemId: string?, centre: Vector3, body: CFrame, angle: number): CFrame
	local style = ThrowLooks.style(itemId)
	if style == "flat" then
		return body * CFrame.Angles(0, angle, 0) * FLAT * CFrame.new(-centre)
	end
	-- the top turns forward: about the body's -X (CFrame.Angles(-a, 0, 0) moves +Y toward -Z, the path)
	return body * CFrame.Angles(-angle, 0, 0) * TUMBLE * CFrame.new(-centre)
end

function ThrowLooks.glances(itemId: string?, material: Enum.Material?): boolean
	return material ~= nil and HARD[material.Name] == true
end

function ThrowLooks.depth(itemId: string?, material: Enum.Material?, speed: number, incidence: number, body: boolean?): number
	local s = math.clamp(((tonumber(speed) or 0) - 60) / 120, 0, 1)
	local c = if body then DEPTH.body else DEPTH[(material and CLASS[material.Name]) or "other"] or DEPTH.other
	local head = math.clamp(tonumber(incidence) or 1, 0, 1)
	return (c[1] + c[2] * s) * (0.7 + 0.3 * head)
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else fallback
end

-- The axis the weapon turned about: horizontal, across the path (forward tumble: up x heading).
local function spinAxis(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = unit(flat, Vector3.zAxis)
	return Vector3.yAxis:Cross(flat).Unit
end

function ThrowLooks.stickPivot(itemId: string, point: Vector3, normal: Vector3, direction: Vector3, depth: number, tipLocal: Vector3): CFrame?
	local d = unit(direction, Vector3.new(0, -1, 0))
	local n = unit(normal, Vector3.yAxis)
	local kind = BITE_KIND[itemId] or "point"
	local R: Vector3, U: Vector3, into: Vector3
	if kind == "flat" then
		if n.Y > 0.6 then
			return nil -- a hoop that comes down on the ground lies flat
		end
		R = Vector3.yAxis -- the hoop level
		into = unit(Vector3.new(-n.X, 0, -n.Z), Vector3.new(d.X, 0, d.Z))
		U = -into -- the rim (on the -UpVector side, the Tip) bites the wall, the grip bar out
		local rot = CFrame.fromMatrix(Vector3.zero, R, U)
		local target = point + into * depth
		return rot + (target - rot:VectorToWorldSpace(tipLocal))
	end
	local w = spinAxis(d) -- the tumble's axis (the blade's flat faces along it)
	-- "into": the surface's inward normal in the plane of the spin, leaned a little toward the path
	local inward = -n - w * (-n):Dot(w)
	local path = d - w * d:Dot(w)
	into = unit(unit(inward, path) * 0.75 + unit(path, inward) * 0.25, unit(path, -n))
	if kind == "edge" then
		-- the edge (-UpVector) goes in; on past square by BITE (the way it was turning) so the haft leans out and down
		local E = CFrame.fromAxisAngle(w, BITE.edge):VectorToWorldSpace(into)
		local L = E:Cross(w).Unit -- grip -> head
		U = -E
		R = L:Cross(U).Unit
	else
		-- the point (LookVector) goes in, leaned back by BITE so the grip sits up out of the surface
		local L = CFrame.fromAxisAngle(w, BITE.point * 0.5):VectorToWorldSpace(into)
		R = -w
		U = R:Cross(L).Unit
	end
	local rot = CFrame.fromMatrix(Vector3.zero, R, U)
	local target = point + into * depth
	return rot + (target - rot:VectorToWorldSpace(tipLocal))
end

return ThrowLooks
