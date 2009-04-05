--[[
**********************************************************************
LibSimpleBar-1.0 - Very simple bar widget
**********************************************************************
This file is part of MagicTargets, a World of Warcraft Addon

MagicTargets is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicTargets is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicTargets.  If not, see <http://www.gnu.org/licenses/>.

**********************************************************************
]]


-- Code and inspiration from LibBars.
-- This is a much less complete implementation. It doesn't handle groupings, 
-- has no bar decorations etc - all it is, is a bar.
-- Snippets used with permission from Antiarc, the LibBars-1.0 author

local MAJOR = "LibSimpleBar-1.0"
local MINOR = tonumber(("$Revision$"):match("(%d+)")) 

local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

local tremove = table.remove
local tinsert = table.insert
local max = max

local dummyFrame, barFrameMT, barPrototype, barPrototype_mt, recycledBars

lib.LEFT_TO_RIGHT = 1
lib.BOTTOM_TO_TOP = 2
lib.RIGHT_TO_LEFT = 3
lib.TOP_TO_BOTTOM = 4

lib.dummyFrame = lib.dummyFrame or CreateFrame("Frame")
lib.barFrameMT = lib.barFrameMT or {__index = lib.dummyFrame}
lib.barPrototype = lib.barPrototype or setmetatable({}, lib.barFrameMT)
lib.barPrototype_mt = lib.barPrototype_mt or {__index = lib.barPrototype}

dummyFrame = lib.dummyFrame
barFrameMT = lib.barFrameMT
barPrototype = lib.barPrototype
barPrototype_mt = lib.barPrototype_mt

barPrototype.super = dummyFrame

lib.recycledBars = lib.recycledBars or {}
lib.embeds = lib.embeds or {}
recycledBars = lib.recycledBars

function lib:NewSimpleBar(...)
   local newBar = tremove(recycledBars)
   if not newBar then
      newBar = CreateFrame("Frame")
   else
      newBar:Show()
   end
   newBar = setmetatable(newBar, barPrototype_mt)
   newBar:Create(...)
   return newBar
end

do
   local mixins = { "NewSimpleBar" }
   function lib:Embed(target)
      for k, v in pairs( mixins ) do
	 target[v] = self[v]
      end
      lib.embeds[target] = true
      return target
   end
end


function barPrototype:Create(parent, value, maxVal, length, thickness, orientation)
   if not self.spark then
      self.spark = self:CreateTexture(nil, "OVERLAY")
      self.spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
      self.spark:SetWidth(10)
      self.spark:SetHeight(10)
      self.spark:SetBlendMode("ADD")
   end

   self.texture = self.texture or self:CreateTexture(nil, "ARTWORK")
   self.texture:SetAllPoints()
   self.texture:SetVertexColor(1, 1, 0, 1)
   
   self.bgtexture = self.bgtexture or self:CreateTexture(nil, "BACKGROUND")
   self.bgtexture:SetAllPoints()
   self.bgtexture:SetVertexColor(0.3, 0.3, 0.3, 0.6)

   self:SetTexture([[Interface\TARGETINGFRAME\UI-StatusBar]])
   self:SetScale(1)
   self:SetAlpha(1)
   self:SetParent(parent)

   self.orientation = orientation or 1
   self.length = length or 200
   self.thickness = thickness or 15
   self.value = value or 1
   self.maxValue = maxVal or value
   self:SetOrientation(self.orientation)
end

function barPrototype:SetMaxValue(maxValue)
   assert(maxValue ~= nil, "maxValue cannot be nil!")
   self:SetValue(self.value, maxValue)
end
   
function barPrototype:SetValue(value, maxValue)
   assert(value ~= nil, "Value cannot be nil!")

   self.value = value 
   self.maxValue = maxValue or self.maxValue

   if not self.maxValue or val > self.maxValue then
      self.maxValue = value
   end

   local amt = min(1, value / self.maxValue)

   if amt == 1 or amt == 0 then
      self.spark:Hide()
   else
      self.spark:Show()
   end

   self:SetTextureValue(amt, self.length)
end

function barPrototype:SetTextureValue(amt, dist)
   local t, o = self.texture, self.orientation
   -- prevent non-zero values
   amt =  max(amt,  0.000001) 
   t:SetValue(amt * max(dist, 0.000001))
   if o == 1 then
      t:SetTexCoord(0, amt, 0, 1)
   elseif o == 2 then
      t:SetTexCoord(1 - amt, 1, 1, 1, 1 - amt, 0, 1, 0)	
   elseif o == 3 then
      t:SetTexCoord(1 - amt, 1, 0, 1)
   elseif o == 4 then
      t:SetTexCoord(0, 1, amt, 1, 0, 0, amt, 0)	
   end
end

do
   local function updateSize(self)
      local vertical, thickness, length = self.orientation % 2 == 0, self.thickness, self.length
      local width = vertical and thickness or length
      local height = vertical and length or thickness
      barPrototype.super.SetWidth(self, width)
      barPrototype.super.SetHeight(self, height)
      self:SetValue(self.value)
   end
   
   function barPrototype:SetLength(length)
      self.length = length
      updateSize(self)
   end
   
   function barPrototype:SetThickness(thickness)
      self.thickness = thickness
      updateSize(self)
   end
end


function barPrototype:SetOrientation(orientation)
   self.orientation = orientation
   self:UpdateOrientationLayout()
   self:SetThickness(self.thickness)
end

function barPrototype:UpdateOrientationLayout()
   local o = self.orientation
   local t
   if o == lib.LEFT_TO_RIGHT then
      t = self.spark
      t:ClearAllPoints()
      t:SetPoint("TOP", self.texture, "TOPRIGHT", 0, 7)
      t:SetPoint("BOTTOM", self.texture, "BOTTOMRIGHT", 0, -7)
      t:SetTexCoord(0, 1, 0, 1)
      
      t = self.texture
      t.SetValue = t.SetWidth
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT")
      t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")

      self.bgtexture:SetTexCoord(0, 1, 0, 1)
   elseif o == lib.BOTTOM_TO_TOP then
      t = self.spark
      t:ClearAllPoints()
      t:SetPoint("LEFT", self.texture, "TOPLEFT", -7, 0)
      t:SetPoint("RIGHT", self.texture, "TOPRIGHT", 7, 0)
      t:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
      
      t = self.texture
      t.SetValue = t.SetHeight
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
      t:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
      
      self.bgtexture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
   elseif o == lib.RIGHT_TO_LEFT then
      t = self.spark
      t:ClearAllPoints()
      t:SetPoint("TOP", self.texture, "TOPLEFT", 0, 7)
      t:SetPoint("BOTTOM", self.texture, "BOTTOMLEFT", 0, -7)
      t:SetTexCoord(0, 1, 0, 1)
      
      t = self.texture
      t.SetValue = t.SetWidth
      t:ClearAllPoints()
      t:SetPoint("TOPRIGHT", self, "TOPRIGHT")
      t:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
      
      self.bgtexture:SetTexCoord(0, 1, 0, 1)
   elseif o == lib.TOP_TO_BOTTOM then
      t = self.spark
      t:ClearAllPoints()
      t:SetPoint("LEFT", self.texture, "BOTTOMLEFT", -7, 0)
      t:SetPoint("RIGHT", self.texture, "BOTTOMRIGHT", 7, 0)
      t:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
      
      t = self.texture
      t.SetValue = t.SetHeight
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT")
      t:SetPoint("TOPRIGHT", self, "TOPRIGHT")
      
      self.bgtexture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
   end
   self:SetValue(self.value or 0)
end

function barPrototype:Release()
   self:SetScript("OnUpdate", nil)
   self:SetParent(UIParent)
   self:ClearAllPoints()
   self:Hide()   
   tinsert(recycledBars, self)
end

function barPrototype:SetTexture(texture, bgtexture)
   if texture then
      self.texture:SetTexture(texture)
   end
   bgtexture = bgtexture or texture
   if bgtexture then
      self.bgtexture:SetTexture(bgtexture)
   end
end

function barPrototype:SetBackgroundColor(r, g, b, a)
   a = a or .6
   if r and g and b and a then
      self.bgtexture:SetVertexColor(r, g, b, a)
   end
end

function barPrototype:SetColor(r, g, b, a)
   a = a or .6
   if r and g and b and a then
      self.texture:SetVertexColor(r, g, b, a)
   end
end

--- Finally: upgrade our old embeds
for target, v in pairs(lib.embeds) do
	lib:Embed(target)
end
