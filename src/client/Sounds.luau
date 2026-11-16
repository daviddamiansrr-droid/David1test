--!strict
-- One place for every sound. Names map to Config.Sounds; a list there means
-- "pick a random variant". Volume comes from Config.SoundVolume and the
-- second argument is a multiplier on top of it. Pitch gets a small random
-- spread by default so repeated sounds don't feel robotic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Sounds = {}

local function resolve(name: string): string?
	local entry = (Config.Sounds :: any)[name]
	local id: string? = nil
	if typeof(entry) == "table" then
		local ready = {}
		for _, v in entry do
			if v ~= "" then
				table.insert(ready, v)
			end
		end
		if #ready > 0 then
			id = ready[math.random(1, #ready)]
		end
	elseif typeof(entry) == "string" and entry ~= "" then
		id = entry
	end
	if not id then
		id = (Config.SoundFallback :: any)[name]
	end
	return id
end

local function baseVolume(name: string): number
	return (Config.SoundVolume :: any)[name] or 0.5
end

local function make(name: string, mult: number?, pitch: number?): Sound?
	local id = resolve(name)
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = baseVolume(name) * (mult or 1)
	s.PlaybackSpeed = (pitch or 1) * (0.96 + math.random() * 0.08)
	return s
end

-- 2D (UI, your own vac)
function Sounds.play(name: string, mult: number?, pitch: number?)
	local s = make(name, mult, pitch)
	if not s then
		return
	end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

-- 3D at a world position
function Sounds.at(name: string, pos: Vector3, mult: number?, pitch: number?, maxDistance: number?)
	local s = make(name, mult, pitch)
	if not s then
		return
	end
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldPosition = pos
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = maxDistance or 110
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 5)
end

-- looping sound parented to something (caller owns it)
function Sounds.loop(name: string, parent: Instance, mult: number?): Sound?
	local id = resolve(name)
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = baseVolume(name) * (mult or 1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 90
	s.Parent = parent
	return s
end

function Sounds.volumeOf(name: string): number
	return baseVolume(name)
end

return Sounds
