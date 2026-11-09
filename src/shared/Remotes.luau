--!strict
-- Server creates the remotes once; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"VacInput", -- C->S  (action, ...)
	"Jet", -- C->S  (on: boolean)
	"State", -- S->C  player state snapshot
	"Notify", -- S->C  (text, kind)
	"Fx", -- S->C  (kind, ...)
	"OpenShop", -- S->C  (category)
}
local FUNCTIONS = {
	"Purchase", -- C->S  (category, key) -> (ok, message)
}

local Remotes = {}

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("RanchRemotes")
	if existing then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = "RanchRemotes"
		for _, name in EVENTS do
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = f
		end
		for _, name in FUNCTIONS do
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = f
		end
		f.Parent = ReplicatedStorage
		folder = f
	end
else
	folder = ReplicatedStorage:WaitForChild("RanchRemotes")
end

function Remotes.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
