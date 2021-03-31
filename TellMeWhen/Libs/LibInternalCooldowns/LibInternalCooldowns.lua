local lib = LibStub:NewLibrary("LibInternalCooldowns", 1)
if not lib then
    return
end

local CallbackHandler = LibStub:GetLibrary("CallbackHandler-1.0")

local GetInventoryItemLink = _G.GetInventoryItemLink
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local GetMacroInfo = _G.GetMacroInfo
local GetActionInfo = _G.GetActionInfo
local substr = _G.string.sub
local wipe = _G.wipe
local playerGUID = UnitGUID("player")
local GetTime = _G.GetTime

lib.spellToItem = lib.spellToItem or {}
lib.cooldownStartTimes = lib.cooldownStartTimes or {}
lib.cooldownDurations = lib.cooldownDurations or {}
lib.callbacks = lib.callbacks or CallbackHandler:New(lib)
lib.cooldowns = lib.cooldowns or nil
lib.hooks = lib.hooks or {}

local enchantProcTimes = {}

if not lib.eventFrame then
    lib.eventFrame = CreateFrame("Frame")
    lib.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    lib.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    lib.eventFrame:SetScript(
        "OnEvent",
        function(frame, event, ...)
            frame.lib[event](frame.lib, event, ...)
        end
    )
end
lib.eventFrame.lib = lib

local INVALID_EVENTS = {
    SPELL_DISPEL = true,
    SPELL_DISPEL_FAILED = true,
    SPELL_STOLEN = true,
    SPELL_AURA_REMOVED = true,
    SPELL_AURA_REMOVED_DOSE = true,
    SPELL_AURA_BROKEN = true,
    SPELL_AURA_BROKEN_SPELL = true,
    SPELL_CAST_FAILED = true
}

local slots = {
    AMMOSLOT = 0,
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5,
    INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10,
    INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = 15,
    INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_2HWEAPON = 16,
    INVTYPE_WEAPON = {16, 17},
    INVTYPE_HOLDABLE = 17,
    INVTYPE_SHIELD = 17,
    INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_RANGED = 18
}

function lib:PLAYER_ENTERING_WORLD()
    playerGUID = UnitGUID("player")
    self:Hook("GetInventoryItemCooldown")
    self:Hook("GetActionCooldown")
    self:Hook("GetItemCooldown")
end

function lib:Hook(name)
    -- unhook if a hook existed from an older copy
    if lib.hooks[name] then
        _G[name] = lib.hooks[name]
    end

    -- Re-hook it now
    lib.hooks[name] = _G[name]
    _G[name] = function(...)
        return self[name](self, ...)
    end
end

local function checkSlotForEnchantID(slot, enchantID)
    local link = GetInventoryItemLink("player", slot)
    if not link then
        return false
    end
    local itemID, enchant = link:match("item:(%d+):(%d+)")
    if tonumber(enchant or -1) == enchantID then
        return true, tonumber(itemID)
    else
        return false
    end
end

local function isEquipped(itemID)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
    local slot = slots[equipLoc]

    if type(slot) == "table" then
        for _, v in ipairs(slot) do
            local link = GetInventoryItemLink("player", v)
            if link and link:match(("item:%s"):format(itemID)) then
                return true
            end
        end
    else
        local link = GetInventoryItemLink("player", slot)
        if link and link:match(("item:%s"):format(itemID)) then
            return true
        end
    end
    return false
end

function lib:COMBAT_LOG_EVENT_UNFILTERED(
    frame,
    timestamp,
    event,
    sourceGUID,
    sourceName,
    sourceFlags,
    destGUID,
    destName,
    destFlags,
    spellID,
    spellName)
    playerGUID = playerGUID or UnitGUID("player")
    if
        ((destGUID == playerGUID and (sourceGUID == nil or sourceGUID == destGUID)) or sourceGUID == playerGUID) and
            not INVALID_EVENTS[event] and
            substr(event, 0, 6) == "SPELL_"
     then
        local itemID = lib.spellToItem[spellID]
        if itemID then
            if type(itemID) == "table" then
                for k, v in ipairs(itemID) do
                    if isEquipped(v) then
                        self:SetCooldownFor(v, spellID, "ITEM")
                    end
                end
                return
            else
                if isEquipped(itemID) then
                    self:SetCooldownFor(itemID, spellID, "ITEM")
                end
                return
            end
        end

        -- Tests for enchant procs
        local enchantID = lib.enchants[spellID]
        if enchantID then
            local enchantID, slot1, slot2 = unpack(enchantID)
            local enchantPresent, itemID, first, second
            enchantPresent, itemID = checkSlotForEnchantID(slot1, enchantID)
            if enchantPresent then
                first = itemID
                if (enchantProcTimes[slot1] or 0) < GetTime() - (lib.cooldowns[spellID] or 45) then
                    enchantProcTimes[slot1] = GetTime()
                    self:SetCooldownFor(itemID, spellID, "ENCHANT")
                    return
                end
            end

            enchantPresent, itemID = checkSlotForEnchantID(slot2, enchantID)
            if enchantPresent then
                second = itemID
                if (enchantProcTimes[slot2] or 0) < GetTime() - (lib.cooldowns[spellID] or 45) then
                    enchantProcTimes[slot2] = GetTime()
                    self:SetCooldownFor(itemID, spellID, "ENCHANT")
                    return
                end
            end

            if first and second then
                if enchantProcTimes[slot1] < enchantProcTimes[slot2] then
                    self:SetCooldownFor(first, spellID, "ENCHANT")
                else
                    self:SetCooldownFor(second, spellID, "ENCHANT")
                end
            end
        end

        local metaID = lib.metas[spellID]
        if metaID then
            local link = GetInventoryItemLink("player", 1)
            if link then
                local id = tonumber(link:match("item:(%d+)") or 0)
                if id and id ~= 0 then
                    self:SetCooldownFor(id, spellID, "META")
                end
            end
            return
        end

        local talentID = lib.talents[spellID]
        if talentID then
            self:SetCooldownFor(("%s: %s"):format(UnitClass("player"), talentID), spellID, "TALENT")
            return
        end
    end
end

function lib:SetCooldownFor(itemID, spellID, procSource)
    local duration = lib.cooldowns[spellID] or 45
    lib.cooldownStartTimes[itemID] = GetTime()
    lib.cooldownDurations[itemID] = duration

    -- Talents have a separate callback, so that InternalCooldowns_Proc always has an item ID.
    if procSource == "TALENT" then
        lib.callbacks:Fire("InternalCooldowns_TalentProc", spellID, GetTime(), duration, procSource)
    else
        lib.callbacks:Fire("InternalCooldowns_Proc", itemID, spellID, GetTime(), duration, procSource)
    end
end

local function cooldownReturn(id)
    if not id then
        return
    end
    local hasItem = id and lib.cooldownStartTimes[id] and lib.cooldownDurations[id]
    if hasItem then
        if lib.cooldownStartTimes[id] + lib.cooldownDurations[id] > GetTime() then
            return lib.cooldownStartTimes[id], lib.cooldownDurations[id], 1
        else
            return 0, 0, 0
        end
    else
        return nil
    end
end

function lib:IsInternalItemCooldown(itemID)
    return cooldownReturn(itemID) ~= nil
end

function lib:GetInventoryItemCooldown(unit, slot)
    local start, duration, enable = self.hooks.GetInventoryItemCooldown(unit, slot)
    if not enable or enable == 0 then
        local link = GetInventoryItemLink("player", slot)
        if link then
            local itemID = link:match("item:(%d+)")
            itemID = tonumber(itemID or 0)

            local start, duration, running = cooldownReturn(itemID)
            if start then
                return start, duration, running
            end
        end
    end
    return start, duration, enable
end

function lib:GetActionCooldown(slotID)
    local t, id, subtype, globalID = GetActionInfo(slotID)
    if t == "item" then
        local start, duration, running = cooldownReturn(id)
        if start then
            return start, duration, running
        end
    elseif t == "macro" then
        local _, tex = GetMacroInfo(id)
        if tex == GetInventoryItemTexture("player", 13) then
            id = tonumber(GetInventoryItemLink("player", 13):match("item:(%d+)"))
            local start, duration, running = cooldownReturn(id)
            if start then
                return start, duration, running
            end
        elseif tex == GetInventoryItemTexture("player", 14) then
            id = tonumber(GetInventoryItemLink("player", 14):match("item:(%d+)"))
            local start, duration, running = cooldownReturn(id)
            if start then
                return start, duration, running
            end
        end
    end
    return self.hooks.GetActionCooldown(slotID)
end

function lib:GetItemCooldown(param)
    local id
    local iparam = tonumber(param)
    if iparam and iparam > 0 then
        id = param
    elseif type(param) == "string" then
        local name, link = GetItemInfo(param)
        if link then
            id = link:match("item:(%d+)")
        end
    end

    if id then
        id = tonumber(id)
        local start, duration, running = cooldownReturn(id)
        if start then
            return start, duration, running
        end
    end

    return self.hooks.GetItemCooldown(param)
end

-- DATA --

local spellToItem = {
    [64411] = 46017, -- Val'anyr, Hammer of Ancient Kings
    [60065] = {44914, 40684, 49074}, -- Anvil of the Titans, Mirror of Truth, Coren's Chromium Coaster
    [60488] = 40373, -- Extract of Necromatic Power
    [64713] = 45518, -- Flare of the Heavens
    [60064] = {44912, 40682, 49706}, -- Flow of Knowledge, Sundial of the Exiled, Mithril Pocketwatch
    [67703] = {47303, 47115}, -- Death's Choice, Death's Verdict (AGI)
    [67708] = {47303, 47115}, -- Death's Choice, Death's Verdict (STR)
    [67772] = {47464, 47131}, -- Death's Choice, Death's Verdict (heroic) (AGI)
    [67773] = {47464, 47131}, -- Death's Choice, Death's Verdict (heroic) (STR)
    -- ICC epix
    -- Rep rings
    [72416] = {50398, 50397}, -- Ashen Band of Endless Destruction
    [72412] = {50402, 50401}, -- Ashen Band of Endless Vengeance
    [72418] = {50399, 50400}, -- Ashen Band of Unmatched Wisdom
    [72414] = {50404, 50403}, -- Ashen Band of Endless Courage
    -- Deathbringer's Will (normal)
    [71485] = 50362,
    [71492] = 50362,
    [71486] = 50362,
    [71484] = 50362,
    [71491] = 50362,
    [71487] = 50362,
    -- Deathbringer's Will (heroic)
    [71556] = 50363,
    [71560] = 50363,
    [71558] = 50363,
    [71561] = 50363,
    [71559] = 50363,
    [71557] = 50363,
    -- ICC Trinkets
    [71401] = 50342, -- Whispering Fanged Skull (251)
    [71541] = 50343, -- Whispering Fanged Skull (264)
    [71610] = 50359, -- Althor's Abacus (264)
    [71641] = 50366, -- Althor's Abacus (277)
    [71633] = 50352, -- Corpse Tongue Coin (264)
    [71639] = 50349, -- Corpse Tongue Coin (277)
    [71601] = 50353, -- Dislodged Foreign Object (264)
    [71644] = 50348, -- Dislodged Foreign Object (277)
    [71605] = 50360, -- Phylactery of the Nameless Lich (264)
    [71636] = 50365, -- Phylactery of the Nameless Lich (277)
    [71584] = 50358, -- Purified Lunar Dust
    -- RS trinkets
    [75466] = 54572, -- Charred Twilight Scale (271)
    [75473] = 54588, -- Charred Twilight Scale (284)
    [75458] = 54569, -- Sharpened Twilight Scale (271)
    [75456] = 54590, -- Sharpened Twilight Scale (284)
    -- DK T9 2pc. WTF.
    [67117] = {
        48501,
        48502,
        48503,
        48504,
        48505,
        48472,
        48474,
        48476,
        48478,
        48480,
        48491,
        48492,
        48493,
        48494,
        48495,
        48496,
        48497,
        48498,
        48499,
        48500,
        48486,
        48487,
        48488,
        48489,
        48490,
        48481,
        48482,
        48483,
        48484,
        48485
    },
    -- WotLK Epix
    [67671] = 47214, -- Banner of Victory
    [67669] = 47213, -- Abyssal Rune
    [64772] = 45609, -- Comet's Trail
    [65024] = 46038, -- Dark Matter
    [60443] = 40371, -- Bandit's Insignia
    [64790] = 45522, -- Blood of the Old God
    [60203] = 42990, -- Darkmoon Card: Death
    [60494] = 40255, -- Dying Curse
    [65004] = 65005, -- Elemental Focus Stone
    [60492] = 39229, -- Embrace of the Spider
    [60530] = 40258, -- Forethought Talisman
    [60437] = 40256, -- Grim Toll
    [49623] = 37835, -- Je'Tze's Bell
    [65019] = 45931, -- Mjolnir Runestone
    [64741] = 45490, -- Pandora's Plea
    [65014] = 45286, -- Pyrite Infuser
    [65003] = 45929, -- Sif's Remembrance
    [60538] = 40382, -- Soul of the Dead
    [58904] = 43573, -- Tears of Bitter Anguish
    [64765] = 45507, -- The General's Heart
    [71403] = 50198, -- Needle-Encrusted Scorpion
    [60062] = {40685, 49078}, -- The Egg of Mortal Essence, Ancient Pickled Egg
    -- WotLK Blues
    [51353] = 38358, -- Arcane Revitalizer
    [60218] = 37220, -- Essence of Gossamer
    [60479] = 37660, -- Forge Ember
    [51348] = 38359, -- Goblin Repetition Reducer
    [63250] = 45131, -- Jouster's Fury
    [63250] = 45219, -- Jouster's Fury
    [60302] = 37390, -- Meteorite Whetstone
    [54808] = 40865, -- Noise Machine
    [60483] = 37264, -- Pendulum of Telluric Currents
    [52424] = 38675, -- Signet of the Dark Brotherhood
    [55018] = 40767, -- Sonic Booster
    [52419] = 38674, -- Soul Harvester's Charm
    [60520] = 37657, -- Spark of Life
    [60307] = 37064, -- Vestige of Haldor
    -- Greatness cards
    [60233] = {44253, 44254, 44255, 42987}, -- Greatness, AGI
    [60235] = {44253, 44254, 44255, 42987}, -- Greatness, SPI
    [60229] = {44253, 44254, 44255, 42987}, -- Greatness, INT
    [60234] = {44253, 44254, 44255, 42987}, -- Greatness, STR
    -- Burning Crusade trinkets
    -- None yet.

    -- Vanilla Epix
    [23684] = 19288 -- Darkmoon Card: Blue Dragon
}

-- spell ID = {enchant ID, slot1[, slot2]}
local enchants = {
    -- [59620] = {3789, 16, 17},    -- Berserking, no ICD via testing.
    -- [28093] = {2673, 16, 17},    -- Mongoose
    -- [13907] = {912, 16, 17},     -- Demonslaying
    [55637] = {3722, 15}, -- Lightweave
    [55775] = {3730, 15}, -- Swordguard
    [55767] = {3728, 15}, -- Darkglow
    [59626] = {3790, 16}, -- Black Magic ?
    [59625] = {3790, 16} -- Black Magic ?
}

-- ICDs on metas assumed to be 45 sec. Needs testing.
local metas = {
    [55382] = 41401, -- Insightful Earthsiege Diamond
    [32848] = 25901, -- Insightful Earthstorm Diamond
    [23454] = 25899, -- Brutal Earthstorm Diamond
    [55341] = 41385, -- Invigorating Earthsiege Diamond
    [18803] = 25893, -- Mystical Skyfire Diamond
    [32845] = 25898, -- Tenacious Earthstorm Diamond
    [39959] = 32410, -- Thundering Skyfire Diamond
    [55379] = 41400 -- Thundering Skyflare Diamond
}

-- Spell ID => cooldown, in seconds
-- If an item isn't in here, 45 sec is assumed.
local cooldowns = {
    -- ICC rep rings
    [72416] = 60,
    [72412] = 60,
    [72418] = 60,
    [72414] = 60,
    [60488] = 15,
    [51348] = 10,
    [51353] = 10,
    [54808] = 60,
    [55018] = 60,
    [52419] = 30,
    [59620] = 90,
    [55382] = 15,
    [32848] = 15,
    [55341] = 90, -- Invigorating Earthsiege, based on WowHead comments (lol?)
    [48517] = 30,
    [48518] = 30,
    [47755] = 12,
    -- Deathbringer's Will, XI from #elitistjerks says it's 105 sec so if it's wrong yell at him.
    [71485] = 105,
    [71492] = 105,
    [71486] = 105,
    [71484] = 105,
    [71491] = 105,
    [71487] = 105,
    -- Deathbringer's Will (heroic)
    [71556] = 105,
    [71560] = 105,
    [71558] = 105,
    [71561] = 105,
    [71559] = 105,
    [71557] = 105,
    -- Phylactery of the Nameless Lich
    [71605] = 90,
    [71636] = 90,
    -- Black Magic
    [59626] = 35,
    [59625] = 35
}

-- Procced spell effect ID = unique name
-- The name doesn't matter, as long as it's non-numeric and unique to the ICD.
local talents = {
    -- Druid
    [48517] = "Eclipse",
    [48518] = "Eclipse",
    -- Hunter
    [56453] = "Lock and Load",
    -- Death Knight
    [52286] = "Will of the Necropolis",
    -- Priest
    [47755] = "Rapture"
}
-----------------------------------------------------------------------
-- Don't edit past this line                  --
-----------------------------------------------------------------------

------------------------------------
-- Upgrade this data into the lib
------------------------------------

lib.spellToItem = lib.spellToItem or {}
lib.cooldowns = lib.cooldowns or {}
lib.enchants = lib.enchants or {}
lib.metas = lib.metas or {}
lib.talents = lib.talents or {}
lib.talentsRev = lib.talentsRev or {}

local tt, tts = {}, {}
local function merge(t1, t2)
    wipe(tts)
    for _, v in ipairs(t1) do
        tts[v] = true
    end
    for _, v in ipairs(t2) do
        if not tts[v] then
            tinsert(t1, v)
        end
    end
end

for k, v in pairs(spellToItem) do
    local e = lib.spellToItem[k]
    if e and e ~= v then
        if type(e) == "table" then
            if type(v) ~= "table" then
                wipe(tt)
                tinsert(tt, v)
            end
            merge(e, tt)
        else
            lib.spellToItem[k] = {e, v}
        end
    else
        lib.spellToItem[k] = v
    end
end

for k, v in pairs(cooldowns) do
    lib.cooldowns[k] = v
end
for k, v in pairs(enchants) do
    lib.enchants[k] = v
end
for k, v in pairs(metas) do
    lib.metas[k] = v
end
for k, v in pairs(talents) do
    lib.talents[k] = v
    -- we ignore "Eclipse"
    if v ~= "Eclipse" then
      lib.talentsRev[v] = k
    end
end
