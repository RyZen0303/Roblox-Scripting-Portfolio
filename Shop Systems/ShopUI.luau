
-- [[ SHOP UI CONTROLLER - BLITZKRIEG SINGLE-PAGE VERSION ]]
-- Location: StarterGui / ShopUI / MainFrame / ShopUIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UIMaster = require(ReplicatedStorage:WaitForChild("UIMaster"))
local Events = ReplicatedStorage:WaitForChild("Events")

local UpdateCashEvent = Events:WaitForChild("UpdateCashEvent")
local PurchaseItemFunction = Events:WaitForChild("PurchaseItemFunction")
local SkillActionFunction = Events:WaitForChild("SkillActionFunction", 10)

local player = Players.LocalPlayer
local mainFrame = script.Parent
local gui = mainFrame.Parent

local selectedItemName = ""

local INSUFFICIENT_DISPLAY_TIME = 1.5

local clickConnections = {}
local isProcessingPurchase = false
local layoutSetupVersion = 0

-- Initialize the centralized UI manager.
UIMaster.InitCenter(gui, mainFrame)
UIMaster.ConnectPads(gui, nil, {"ShopPad_1", "ShopPad_2"})

-- Resolve the core UI elements.
local cashTextLabel = mainFrame
	:WaitForChild("CloseButton")
	:WaitForChild("MoneyLabel")

local shopItemContainer = mainFrame:WaitForChild("ItemList")

-- Check whether the server response indicates insufficient funds.
local function isInsufficientFundsMessage(message)
	if typeof(message) ~= "string" then
		return false
	end

	local normalized = string.lower(message)

	return normalized:find("insufficient", 1, true) ~= nil
		or normalized:find("not enough", 1, true) ~= nil
		or normalized:find("lack of funds", 1, true) ~= nil
		or normalized:find("เงินไม่พอ", 1, true) ~= nil
		or normalized:find("เงินไม่เพียงพอ", 1, true) ~= nil
end

-- Request the latest skill status from the server.
local function getSkillStatus(itemName)
	if not SkillActionFunction then
		warn("[SHOP] SkillActionFunction is missing.")
		return nil
	end

	local callSuccess, success, status = pcall(function()
		return SkillActionFunction:InvokeServer("GetStatus", itemName)
	end)

	if not callSuccess then
		warn("[SHOP STATUS ERROR] " .. tostring(success))
		return nil
	end

	if not success or typeof(status) ~= "table" then
		warn("[SHOP STATUS REJECTED] " .. tostring(status))
		return nil
	end

	return status
end

-- Apply the server-authoritative status to the purchase button.
local function updatePurchaseButton(purchaseBtn, status)
	if not purchaseBtn or not status then
		return
	end

	if status.Owned == true and status.Equipped == true then
		purchaseBtn.Text = "Equipped"
		purchaseBtn.Active = false
		purchaseBtn.AutoButtonColor = false

	elseif status.Owned == true then
		purchaseBtn.Text = "Equip"
		purchaseBtn.Active = true
		purchaseBtn.AutoButtonColor = true

	else
		purchaseBtn.Text = "Purchase"
		purchaseBtn.Active = true
		purchaseBtn.AutoButtonColor = true
	end
end

-- Refresh a button using the latest server status.
local function refreshSkillStatus(itemName, purchaseBtn)
	local status = getSkillStatus(itemName)

	if status and purchaseBtn and purchaseBtn.Parent then
		updatePurchaseButton(purchaseBtn, status)
	end

	return status
end

-- Select the default shop item.
local function autoSelectDefaultItem(containerFrame)
	if not containerFrame then
		return
	end

	selectedItemName = ""

	UIMaster.SelectDefault(containerFrame, function(cardNode)
		local detectedName = string.gsub(cardNode.Name, "_Card", "")
		detectedName = string.gsub(detectedName, "_Button", "")

		if detectedName ~= "" then
			selectedItemName = detectedName
		end
	end)

	if selectedItemName ~= "" then
		print("[SHOP DEFAULT] Auto-selected: " .. selectedItemName)
	end
end

-- Process a purchase or equip request.
local function processShopAction(itemName, purchaseBtn)
	if isProcessingPurchase then
		return
	end

	if not purchaseBtn or not purchaseBtn.Active then
		return
	end

	local currentText = purchaseBtn.Text

	if currentText ~= "Purchase" and currentText ~= "Equip" then
		return
	end

	selectedItemName = itemName
	isProcessingPurchase = true

	purchaseBtn.Active = false
	purchaseBtn.AutoButtonColor = false

	local showInsufficient = false

	local actionSuccess, actionError = pcall(function()
		if currentText == "Purchase" then
			local success, message =
				PurchaseItemFunction:InvokeServer(itemName)

			if success then
				print("[SHOP SUCCESS] Purchased: " .. itemName)
			else
				warn("[SHOP PURCHASE REJECTED] " .. tostring(message))

				if isInsufficientFundsMessage(message) then
					showInsufficient = true
					purchaseBtn.Text = "Insufficient!"
				end
			end

		elseif currentText == "Equip" then
			if not SkillActionFunction then
				warn("[SHOP] SkillActionFunction is missing.")
				return
			end

			local success, message =
				SkillActionFunction:InvokeServer("Equip", itemName)

			if success then
				print("[SHOP EQUIP SUCCESS] Equipped: " .. itemName)
			else
				warn("[SHOP EQUIP REJECTED] " .. tostring(message))
			end
		end
	end)

	if not actionSuccess then
		warn("[SHOP ACTION ERROR] " .. tostring(actionError))
	end

	isProcessingPurchase = false

	if not purchaseBtn or not purchaseBtn.Parent then
		return
	end

	if showInsufficient then
		purchaseBtn.Text = "Insufficient!"
		purchaseBtn.Active = true
		purchaseBtn.AutoButtonColor = true

		task.delay(INSUFFICIENT_DISPLAY_TIME, function()
			if purchaseBtn and purchaseBtn.Parent then
				refreshSkillStatus(itemName, purchaseBtn)
			end
		end)
	else
		refreshSkillStatus(itemName, purchaseBtn)
	end
end

-- Locate shop cards inside ItemListPage > ItemListFrame.
local function setupShopUILayout()
	layoutSetupVersion += 1
	local currentVersion = layoutSetupVersion

	for _, connection in ipairs(clickConnections) do
		connection:Disconnect()
	end

	table.clear(clickConnections)

	local realPage = shopItemContainer:FindFirstChild("ItemListPage")
		or shopItemContainer

	local itemListFrame = realPage:FindFirstChild("ItemListFrame", true)

	if not itemListFrame then
		warn("[SHOP] ItemListFrame was not found under ItemList.")
		return
	end

	local cardCount = 0
	local buttonCount = 0

	for _, card in ipairs(itemListFrame:GetChildren()) do
		if card:IsA("GuiObject") and card.Name:match("_Card$") then
			cardCount += 1

			local purchaseBtn = card:FindFirstChild("Purchase_Button")

			if purchaseBtn and purchaseBtn:IsA("TextButton") then
				buttonCount += 1

				local itemName = string.gsub(card.Name, "_Card$", "")

				purchaseBtn.Text = "Loading..."
				purchaseBtn.Active = false
				purchaseBtn.AutoButtonColor = false

				task.spawn(function()
					if currentVersion ~= layoutSetupVersion then
						return
					end

					refreshSkillStatus(itemName, purchaseBtn)
				end)

				local connection = purchaseBtn.Activated:Connect(function()
					print("[SHOP CLICK] Button clicked: " .. itemName)
					processShopAction(itemName, purchaseBtn)
				end)

				table.insert(clickConnections, connection)
			else
				warn(
					"[SHOP] Purchase_Button missing or not a TextButton in "
						.. card:GetFullName()
				)
			end
		end
	end

	print(
		"[SHOP SETUP] Cards found: "
			.. cardCount
			.. " | Purchase buttons connected: "
			.. buttonCount
	)

	if buttonCount == 0 then
		warn("[SHOP] No purchase buttons were connected. Check the UI hierarchy.")
	end

	autoSelectDefaultItem(itemListFrame)
end

-- Update the displayed cash balance.
local function updateCashDisplay(newCashAmount)
	if typeof(newCashAmount) == "number" then
		cashTextLabel.Text = "$ " .. string.format("%d", newCashAmount)
	end
end

player:GetAttributeChangedSignal("Cash"):Connect(function()
	updateCashDisplay(player:GetAttribute("Cash"))
end)

UpdateCashEvent.OnClientEvent:Connect(function(newCashAmount)
	updateCashDisplay(newCashAmount)
end)

updateCashDisplay(player:GetAttribute("Cash") or 0)

-- Initialize the shop and monitor team changes.
task.spawn(function()
	local timeout = 0

	while not player.Team and timeout < 5 do
		task.wait(0.1)
		timeout += 0.1
	end

	player:GetPropertyChangedSignal("Team"):Connect(function()
		local currentTeam = player.Team and player.Team.Name

		if currentTeam == "Blitzkrieg" then
			setupShopUILayout()
		end
	end)

	setupShopUILayout()
end)

-- Refresh the shop when the GUI becomes visible.
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		setupShopUILayout()
	end
end)

-- Close the shop.
local closeButton = mainFrame:FindFirstChild("CloseButton")

if closeButton then
	closeButton.Activated:Connect(function()
		UIMaster.Close(gui)
	end)
end

gui.Enabled = false
