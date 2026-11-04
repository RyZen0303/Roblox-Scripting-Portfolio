-- [[  LEADERSTATS INITIALIZATION ]] --
game.Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local points = Instance.new("IntValue")
	points.Name = "Points"
	points.Value = 20 -- Starting balance for every player
	points.Parent = leaderstats
end)
