--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)

local Sounds = {}

-- 2D sound (UI / your own vac)
function Sounds.play(name: string, volume: number?, pitch: number?)
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

-- 3D sound at a world position
function Sounds.at(name: string, pos: Vector3, volume: number?, pitch: number?)
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local a = Instance.new("Attachment")
	a.Parent = workspace.Terrain
	a.WorldPosition = pos
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = 120
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 4)
end

-- looping sound parented to something (caller owns it)
function Sounds.loop(name: string, parent: Instance, volume: number?): Sound?
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = volume or 0.4
	s.RollOffMaxDistance = 80
	s.Parent = parent
	return s
end

return Sounds
