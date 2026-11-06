-- // KillFeedUIController //
-- Location: StarterGui -> LocalScript
-- Description: Personal Client-side Kill Confirmation Engine (Battlefield Style: Skull Top, Centered Text).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local PointEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PointStatusUpdate")

-- Create Safe Screen Container for Personal Kill Rewards
local killNotificationGui = Instance.new("ScreenGui")
killNotificationGui.Name = "PersonalKillNotificationGui"
killNotificationGui.ResetOnSpawn = false
killNotificationGui.Parent = PlayerGui

-- Main Centered Notification Frame (Battlefield Center Position)
local notifyFrame = Instance.new("Frame")
notifyFrame.Name = "NotifyFrame"
--  [CHANGED]: Condensed the frame size for a more compact look (from 0.4, 0.25 -> 0.35, 0.2)
notifyFrame.Size = UDim2.new(0.35, 0, 0.2, 0)
--  [CHANGED]: Shifted the position further down (from Y: 0.50 -> Y: 0.62) to avoid obstructing the crosshair
notifyFrame.Position = UDim2.new(0.325, 0, 0.67, 0)
notifyFrame.BackgroundTransparency = 1
notifyFrame.Parent = killNotificationGui

--  UI List Layout to force objects to stack "Top to Bottom" and remain "Centered"
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2) -- Reduced spacing between the skull and text for a tighter feel
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = notifyFrame

--  Battlefield Skull Label (Top)
local skullLabel = Instance.new("TextLabel")
skullLabel.Name = "1_SkullLabel"
--  [CHANGED]: Adjusted the initial skull area scale to look more refined/sleek
skullLabel.Size = UDim2.new(0.12, 0, 0.3, 0)
skullLabel.BackgroundTransparency = 1
skullLabel.Text = ""
skullLabel.TextScaled = true
skullLabel.TextTransparency = 1
skullLabel.Parent = notifyFrame

--  Battlefield Style Text Label (Below the skull)
local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "2_InfoLabel"
--  [CHANGED]: Adjusted the text label area scale to balance with the new skull size
infoLabel.Size = UDim2.new(1, 0, 0.6, 0)
infoLabel.BackgroundTransparency = 1
infoLabel.TextScaled = true
infoLabel.Font = Enum.Font.GothamBold
infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
infoLabel.TextStrokeTransparency = 0.3
infoLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
infoLabel.TextTransparency = 1
infoLabel.TextXAlignment = Enum.TextXAlignment.Center
infoLabel.RichText = true
infoLabel.Parent = notifyFrame

-- Listen for Personal Kill RPC Signals
PointEvent.OnClientEvent:Connect(function(actionType, data)
	if actionType == "TANK_KILLED" then
		local victim = data.Victim or "TARGET"
		local weapon = data.Weapon or "CANNON"
		local points = data.RewardPoints or 0

		-- Format in Battlefield style: Bold, clear, and intimidating
		infoLabel.Text = string.format("<font color='rgb(255, 255, 255)'>VEHICLE DESTROYED</font><br/><font color='rgb(230, 70, 70)'>%s</font> [%s]<br/><font color='rgb(245, 190, 40)'>+%d POINTS</font>", string.upper(victim), string.upper(weapon), points)

		-- Reset status before starting the animation
		skullLabel.TextTransparency = 1
		infoLabel.TextTransparency = 1

		--  [CHANGED]: Adjusted the impact animation (Pop Effect) to scale down for the new size
		skullLabel.Size = UDim2.new(0.25, 0, 0.5, 0) -- Initial flash size (preventing it from overflowing the UI)

		TweenService:Create(skullLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Size = UDim2.new(0.12, 0, 0.3, 0) -- Shrink back to the default size logic
		}):Play()

		task.wait(0.05)

		--  Detail text slides in following the skull
		TweenService:Create(infoLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0
		}):Play()

		-- Keep displayed for 2.5 seconds to soak in the satisfaction
		task.wait(2.5)

		--  Fade out smoothly together
		TweenService:Create(skullLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
		TweenService:Create(infoLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
	end
end)
