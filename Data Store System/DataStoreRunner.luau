-- ServerScriptService / DataStoreRunner.server.lua

local Players = game:GetService("Players")
local PlayerDataManager = require(script.Parent.PlayerDataManager)

-- Player Joining
Players.PlayerAdded:Connect(function(player)
	PlayerDataManager.LoadData(player)
end)

-- Player Leaving
Players.PlayerRemoving:Connect(function(player)
	PlayerDataManager.SaveData(player)
	PlayerDataManager.RemoveSession(player)
end)

-- Game Shutdown Failsafe (Save all active players)
game:BindToClose(function()
	print("[DataStoreRunner] Game shutting down, saving all player data...")
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			PlayerDataManager.SaveData(player)
		end)
	end
	-- Wait brief moment to allow spawned threads to complete SetAsync
	task.wait(3)
end)
