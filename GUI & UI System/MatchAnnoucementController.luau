-- // MatchAnnouncementController //
-- Location: StarterGui -> LocalScript
-- Description: Client-side cinematic victory HUD announcement triggered by Server life-cycle loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- [[ NETWORKING CONFIGURATION ]] --
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local PointEvent = EventsFolder:WaitForChild("PointStatusUpdate")

-- Match Server-Authoritative Colors Exactly
local TEAM_COLORS = {
	["Germany"] = Color3.fromRGB(245, 190, 40),
	["Britain"] = Color3.fromRGB(45, 120, 230)
}

-- =========================================================================
-- [[  DYNAMIC CINEMATIC UI GENERATION ENGINE ]]
-- =========================================================================
-- Automatically constructs the screen infrastructure to avoid manual Studio overhead.
local matchOverGui = Instance.new("ScreenGui")
matchOverGui.Name = "MatchOverAnnouncementGui"
matchOverGui.ResetOnSpawn = false
matchOverGui.Parent = PlayerGui

-- Cinematic horizontal dark bar running across the screen center
local centerFrame = Instance.new("Frame")
centerFrame.Name = "CenterFrame"
centerFrame.Size = UDim2.new(1, 0, 0.22, 0)
centerFrame.Position = UDim2.new(0, 0, 0.38, 0) -- Dead center framing
centerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
centerFrame.BackgroundTransparency = 1 -- Hidden by default
centerFrame.BorderSizePixel = 0
centerFrame.Parent = matchOverGui

-- Smooth horizontal alpha gradient edge blur
local gradient = Instance.new("UIGradient")
gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 0.3),
	NumberSequenceKeypoint.new(0.5, 0.15),
	NumberSequenceKeypoint.new(0.85, 0.3),
	NumberSequenceKeypoint.new(1, 1)
})
gradient.Parent = centerFrame

-- Huge bold victory text header
local victoryLabel = Instance.new("TextLabel")
victoryLabel.Name = "VictoryLabel"
victoryLabel.Size = UDim2.new(1, 0, 0.6, 0)
victoryLabel.Position = UDim2.new(0, 0, 0.1, 0)
victoryLabel.BackgroundTransparency = 1
victoryLabel.Text = ""
victoryLabel.TextScaled = true
victoryLabel.Font = Enum.Font.GothamBold
victoryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
victoryLabel.TextStrokeTransparency = 0.4
victoryLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
victoryLabel.TextTransparency = 1
victoryLabel.Parent = centerFrame

-- Subtitle track handling countdown metadata
local subLabel = Instance.new("TextLabel")
subLabel.Name = "SubLabel"
subLabel.Size = UDim2.new(1, 0, 0.25, 0)
subLabel.Position = UDim2.new(0, 0, 0.68, 0)
subLabel.BackgroundTransparency = 1
subLabel.Text = "RETURNING TO STAGING LOBBY..."
subLabel.TextScaled = true
subLabel.Font = Enum.Font.Gotham
subLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
subLabel.TextStrokeTransparency = 0.5
subLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
subLabel.TextTransparency = 1
subLabel.Parent = centerFrame

-- =========================================================================
-- [[  NETWORK EVENT LISTENER ]]
-- =========================================================================
PointEvent.OnClientEvent:Connect(function(actionType, winningTeam)
	if actionType == "MATCH_OVER" then
		local teamColor = TEAM_COLORS[winningTeam] or Color3.fromRGB(255, 255, 255)

		-- Setup layout properties safely before launching tweens
		victoryLabel.Text = string.upper(winningTeam) .. " VICTORY"
		victoryLabel.TextColor3 = teamColor

		victoryLabel.TextTransparency = 1
		subLabel.TextTransparency = 1
		centerFrame.BackgroundTransparency = 1

		-- Setup Pop-In Impact effect coordinates
		victoryLabel.Size = UDim2.new(1, 0, 0.3, 0) -- Start squished/smaller
		victoryLabel.Position = UDim2.new(0, 0, 0.25, 0)

		--  Phase 1: Cinematic Cinematic Background Blur and Header Impact Pop
		TweenService:Create(centerFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.3}):Play()

		TweenService:Create(victoryLabel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Size = UDim2.new(1, 0, 0.6, 0),
			Position = UDim2.new(0, 0, 0.1, 0)
		}):Play()

		task.wait(0.6)

		--  Phase 2: Fade-in the map lifecycle status text
		TweenService:Create(subLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()

		-- Wait out the Server-side reset window (Server waits 5 seconds, client fades out slightly early)
		task.wait(3.8)

		--  Phase 3: Outro cleanup fade to clear screen space for respawn execution
		TweenService:Create(centerFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
		TweenService:Create(victoryLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
		TweenService:Create(subLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
	end
end)
