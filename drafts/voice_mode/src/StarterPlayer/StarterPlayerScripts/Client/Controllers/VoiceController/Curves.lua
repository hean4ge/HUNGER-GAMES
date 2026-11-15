--[[
	Curves - Proximity Voice distance curves (VoiceController). A profile { Full, Silent, Shape } from Config.Voice.Profiles
	becomes the { [studs] = volume } table that AudioListener:SetDistanceAttenuation / AudioEmitter:SetDistanceAttenuation
	take: full volume up to Full, nothing from Silent on, and between them the inverse law raised to Shape (1 = realistic,
	lower = flatter) times a taper that reaches 0 at Silent. The engine draws straight lines between points and holds the
	end values (at most 400 points; we send about 50).
	  Curves.build(profile) -> { [number]: number }
	  Curves.value(profile, distance) -> number    the same curve, evaluated (UI and fallbacks)
	  Curves.FLAT                                   { [0] = 1 }: no falloff (put on emitters, so the listener's curve rules)
	Arena (8 / 90 / 0.8): 16 studs -5 dB, 32 -10 dB, 48 -15 dB, 64 -20 dB, 80 -29 dB, silent at 90 (~30 m).
]]
local Curves = {}

Curves.FLAT = { [0] = 1 }

local STEPS = 48

local function params(profile: { [string]: any }?): (number, number, number)
	local p = profile or {}
	local full = math.max(0, tonumber(p.Full) or 8)
	local silent = math.max(full + 1, tonumber(p.Silent) or 90)
	local shape = math.clamp(tonumber(p.Shape) or 1, 0.1, 2)
	return full, silent, shape
end

function Curves.value(profile: { [string]: any }?, distance: number): number
	local full, silent, shape = params(profile)
	if distance <= full then
		return 1
	end
	if distance >= silent then
		return 0
	end
	local inverse = (math.max(full, 1) / distance) ^ shape
	local t = (distance - full) / (silent - full)
	return math.clamp(inverse * (1 - t * t), 0, 1)
end

function Curves.build(profile: { [string]: any }?): { [number]: number }
	local full, silent = params(profile)
	local points: { [number]: number } = { [0] = 1 }
	points[full] = 1
	for i = 1, STEPS - 1 do
		local d = math.floor((full + (silent - full) * i / STEPS) * 100 + 0.5) / 100
		points[d] = math.floor(Curves.value(profile, d) * 1000 + 0.5) / 1000
	end
	points[silent] = 0
	return points
end

return Curves
