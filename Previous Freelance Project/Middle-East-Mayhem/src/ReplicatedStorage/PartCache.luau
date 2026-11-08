local PartCache = {}
PartCache.__index = PartCache

-- Function to create a new cache pool
function PartCache.new(template: BasePart, initialSize: number, parent: Instance)
	local self = setmetatable({}, PartCache)
	
	self.Template = template:Clone()
	self.Template.Anchored = true
	self.Template.CanCollide = false
	self.Parent = parent or workspace
	
	self.FreeParts = {} -- Store available (unused) parts
	self.InUseParts = {} -- Store parts currently in use
	
	-- Faraway coordinates used to hide unused parts
	self.HiddenCFrame = CFrame.new(0, 100000, 0)
	
	-- Pre-create parts in advance based on the initialSize
	for _ = 1, initialSize do
		local newPart = self.Template:Clone()
		newPart.CFrame = self.HiddenCFrame
		newPart.Parent = self.Parent
		table.insert(self.FreeParts, newPart)
	end
	
	return self
end

-- Retrieve a part from the cache for use
function PartCache:GetPart(): BasePart
	local part
	
	-- If the pool is empty, expand the pool by creating a new part
	if #self.FreeParts == 0 then
		part = self.Template:Clone()
		part.Parent = self.Parent
	else
		-- Pop the last part from the free pool
		part = table.remove(self.FreeParts)
	end
	
	table.insert(self.InUseParts, part)
	return part
end

-- Return a part back to the cache pool
function PartCache:ReturnPart(part: BasePart)
	local index = table.find(self.InUseParts, part)
	if index then
		table.remove(self.InUseParts, index)
		
		-- Warp the part to the hidden location
		part.CFrame = self.HiddenCFrame
		
		-- Push the part back into the free pool for reuse
		table.insert(self.FreeParts, part)
	end
end

return PartCache