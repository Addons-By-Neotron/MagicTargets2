-- Luacheck configuration for World of Warcraft addons

-- Ignore unused self warnings (common in OOP-style Lua for WoW addons)
self = false

-- Set max line length
max_line_length = 120

-- Ignore trailing whitespace (or set to true to enforce)
-- std = "max"

-- Define WoW API globals
std = "lua51"

-- Read-only globals (WoW API functions and variables)
read_globals = {
    -- WoW Global Functions
    "CreateFrame",
    "GetInventoryItemLink",
    "GetItemInfo",
    "GetNumGroupMembers",
    "IsInRaid",
    "GetRaidRosterInfo",
    "GetRaidTargetIndex",
    "InCombatLockdown",
    "UIParent",
    "UnitCanAttack",
    "UnitClass",
    "UnitClassification",
    "UnitCreatureType",
    "UnitExists",
    "UnitGUID",
    "UnitHealth",
    "UnitHealthMax",
    "UnitIsDead",
    "UnitIsPlayer",
    "UnitLevel",
    "UnitName",
    "UnitPlayerControlled",
    "UnitGroupRolesAssigned",
    "UnitAffectingCombat",
    "UnitIsTrivial",
    "UnitThreatSituation",
    "UnitHealthPercent",
    "UnitIsUnit",
    "GameTooltip",
    "GetPartyAssignment",
    "UnitInPhase",
    "UnitInRange",
    "UnitIsConnected",
    "UnitIsDeadOrGhost",
    "UnitIsEnemy",
    "UnitIsFriend",
    "UnitIsPartyLeader",
    "UnitIsRaidOfficer",
    "UnitIsTapDenied",
    "UnitIsVisible",
    "UnitPowerType",
    "UnitReaction",

    -- WoW Global Tables/Namespaces
    "RAID_CLASS_COLORS",
    "C_NamePlate",
    "BackdropTemplateMixin",
    "AceGUIWidgetLSMlists",

    -- Standard Lua functions that WoW provides globally
    "strsub",
    "strlen",

    -- Addon libraries
    "LibStub",
}

-- Globals that can be set (addon namespaces)
globals = {
    "MagicTargets",
    "UnitGroupRolesAssigned", -- Compatibility shim
}

-- Exclude library folders from checking
exclude_files = {
    "Libs/**",
}

-- Ignore specific warnings
ignore = {
    "212", -- Unused argument (common with 'self' in methods)
    "213", -- Unused loop variable
    "631", -- Line is too long (we set max_line_length instead)
}