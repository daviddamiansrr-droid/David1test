--!strict
-- Latest snapshot pushed by the server. Read-only mirror; never trusted server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = {}
ClientState.Data = nil :: { [string]: any }?

local changed = Instance.new("BindableEvent")
ClientState.Changed = changed.Event

Remotes.event("State").OnClientEvent:Connect(function(snap)
	local prev = ClientState.Data
	ClientState.Data = snap
	changed:Fire(snap, prev)
end)

return ClientState
