local frame = CreateFrame("Frame")
local trinketOnCD = false
local potionOnCD = false
local trackedItemID = nil
local ignoreNextPotDing = false
local hadPI = false
local PISpellID = 10060

local soundList = {
    { name = "Raid Warning", id = 567397 },
    { name = "Level Up!", id = 569593 },
    { name = "You Are Not Prepared", id = 552503 },
    { name = "Ready Check", id = 567478 },
    { name = "Quest Complete", id = 567421 },
    { name = "Murloc", id = 556000 },
    { name = "Evil Laugh", id = 12811 },
    { name = "Loot Coin", id = 120 },
    { name = "Aggro Warning", id = 5274 },
    { name = "Gong", id = 8959 },
    { name = "Fel Reaver", id = 878 },
    { name = "Bike Horn", id = "Interface\\AddOns\\Sounds4Stuff\\Sounds\\bikehorn.ogg" }
}

local function PlayDingSound(soundID)
    if not soundID then return end

    if type(soundID) == "string" then
        PlaySoundFile(soundID, "Master")
    elseif type(soundID) == "number" and soundID > 100000 then
        PlaySoundFile(soundID, "Master")
    else
        PlaySound(soundID, "Master")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("ENCOUNTER_END") -- Detect boss kills
frame:RegisterUnitEvent("UNIT_AURA", "player") -- Optimized to only track player buffs

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Sounds4Stuff" then
            Sounds4StuffDB = Sounds4StuffDB or {}
            Sounds4StuffDB.slot = Sounds4StuffDB.slot or 13
            if Sounds4StuffDB.chatAlert == nil then Sounds4StuffDB.chatAlert = true end
            if Sounds4StuffDB.potDing == nil then Sounds4StuffDB.potDing = true end
            if Sounds4StuffDB.piDing == nil then Sounds4StuffDB.piDing = true end

            Sounds4StuffDB.trinketSound = Sounds4StuffDB.trinketSound or 567397
            Sounds4StuffDB.potionSound = Sounds4StuffDB.potionSound or 569593
            Sounds4StuffDB.piSound = Sounds4StuffDB.piSound or 567397

            self:BuildMenu()
        end

    elseif event == "ENCOUNTER_END" then
        -- Boss died or fight wiped; set flag to ignore the automatic potion reset ding
        ignoreNextPotDing = true

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and Sounds4StuffDB and Sounds4StuffDB.piDing then
            local hasPI = false

            -- Modern Midnight compatible aura check
            for i = 1, 40 do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then break end -- Stop looking if we run out of buffs

                if aura.spellId == PISpellID then
                    hasPI = true
                    break
                end
            end

            -- Trigger sound only on the frame the buff is applied
            if hasPI and not hadPI then
                PlayDingSound(Sounds4StuffDB.piSound)
                if Sounds4StuffDB.chatAlert then print("|cff00ff00[Sounds4Stuff]|r Power Infusion Active!") end
            end
            hadPI = hasPI
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        if not Sounds4StuffDB then return end

        -- --- TRINKET LOGIC ---
        local tStart, tDuration = GetInventoryItemCooldown("player", Sounds4StuffDB.slot)
        local currentItemID = GetInventoryItemID("player", Sounds4StuffDB.slot)

        if tStart > 0 and tDuration > 1.5 then
            trinketOnCD = true
            trackedItemID = currentItemID
        elseif trinketOnCD and tDuration <= 1.5 then
            trinketOnCD = false
            if currentItemID == trackedItemID then
                if UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player") then
                    PlayDingSound(Sounds4StuffDB.trinketSound)
                    if Sounds4StuffDB.chatAlert then print("|cff00ff00[Sounds4Stuff]|r Trinket Ready!") end
                end
            end
            trackedItemID = nil
        end

        -- --- COMBAT POTION LOGIC ---
        if Sounds4StuffDB.potDing then
            local pStart, pDuration = GetItemCooldown(241289)

            if pStart > 0 and pDuration > 1.5 then
                potionOnCD = true
                ignoreNextPotDing = false -- Reset flag if we actually use a pot mid-fight
            elseif potionOnCD and pDuration <= 1.5 then
                potionOnCD = false

                -- Only ding if we aren't supposed to ignore this specific reset (boss kill)
                if not ignoreNextPotDing then
                    if UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player") then
                        PlayDingSound(Sounds4StuffDB.potionSound)
                        if Sounds4StuffDB.chatAlert then print("|cff00ff00[Sounds4Stuff]|r Combat Potion Ready!") end
                    end
                end
                ignoreNextPotDing = false -- Reset for next use
            end
        end
    end
end)

-- Menu
function frame:BuildMenu()
    local panel = CreateFrame("Frame", "Sounds4StuffOptionsPanel")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Sounds4Stuff Configuration")

    local slotBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    slotBtn:SetPoint("TOPLEFT", 16, -60)
    slotBtn:SetSize(180, 30)
    local function UpdateSlotText()
        slotBtn:SetText("Trinket Slot: " .. (Sounds4StuffDB.slot == 13 and "Top (13)" or "Bottom (14)"))
    end
    UpdateSlotText()
    slotBtn:SetScript("OnClick", function()
        Sounds4StuffDB.slot = (Sounds4StuffDB.slot == 13) and 14 or 13
        UpdateSlotText()
    end)

    local potCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    potCheck:SetPoint("TOPLEFT", 16, -100)
    potCheck:SetChecked(Sounds4StuffDB.potDing)
    potCheck.text = potCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    potCheck.text:SetPoint("LEFT", potCheck, "RIGHT", 5, 0)
    potCheck.text:SetText("Track Combat Potions (Ignores Health Pots)")
    potCheck:SetScript("OnClick", function(self) Sounds4StuffDB.potDing = self:GetChecked() end)

    local chatCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    chatCheck:SetPoint("LEFT", potCheck.text, "RIGHT", 20, 0)
    chatCheck:SetChecked(Sounds4StuffDB.chatAlert)
    chatCheck.text = chatCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatCheck.text:SetPoint("LEFT", chatCheck, "RIGHT", 5, 0)
    chatCheck.text:SetText("Show Chat Alert")
    chatCheck:SetScript("OnClick", function(self) Sounds4StuffDB.chatAlert = self:GetChecked() end)

    local piCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    piCheck:SetPoint("TOPLEFT", 16, -130)
    piCheck:SetChecked(Sounds4StuffDB.piDing)
    piCheck.text = piCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    piCheck.text:SetPoint("LEFT", piCheck, "RIGHT", 5, 0)
    piCheck.text:SetText("Track Power Infusion")
    piCheck:SetScript("OnClick", function(self) Sounds4StuffDB.piDing = self:GetChecked() end)

    local tSoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tSoundLabel:SetPoint("TOPLEFT", 16, -180)
    tSoundLabel:SetText("Trinket Sound:")

    local tSoundDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    tSoundDropdown:SetPoint("TOPLEFT", 120, -175)
    tSoundDropdown:SetWidth(150)
    tSoundDropdown:SetupMenu(function(dropdown, rootDescription)
        for _, soundInfo in ipairs(soundList) do
            rootDescription:CreateRadio(soundInfo.name, function() return Sounds4StuffDB.trinketSound == soundInfo.id end, function() Sounds4StuffDB.trinketSound = soundInfo.id end)
        end
    end)

    local tTestBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    tTestBtn:SetPoint("LEFT", tSoundDropdown, "RIGHT", 15, 0)
    tTestBtn:SetSize(100, 30)
    tTestBtn:SetText("Test Trinket")
    tTestBtn:SetScript("OnClick", function() PlayDingSound(Sounds4StuffDB.trinketSound) end)

    local pSoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pSoundLabel:SetPoint("TOPLEFT", 16, -220)
    pSoundLabel:SetText("Potion Sound:")

    local pSoundDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    pSoundDropdown:SetPoint("TOPLEFT", 120, -215)
    pSoundDropdown:SetWidth(150)
    pSoundDropdown:SetupMenu(function(dropdown, rootDescription)
        for _, soundInfo in ipairs(soundList) do
            rootDescription:CreateRadio(soundInfo.name, function() return Sounds4StuffDB.potionSound == soundInfo.id end, function() Sounds4StuffDB.potionSound = soundInfo.id end)
        end
    end)

    local pTestBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pTestBtn:SetPoint("LEFT", pSoundDropdown, "RIGHT", 15, 0)
    pTestBtn:SetSize(100, 30)
    pTestBtn:SetText("Test Potion")
    pTestBtn:SetScript("OnClick", function() PlayDingSound(Sounds4StuffDB.potionSound) end)

    local piSoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    piSoundLabel:SetPoint("TOPLEFT", 16, -260)
    piSoundLabel:SetText("PI Sound:")

    local piSoundDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    piSoundDropdown:SetPoint("TOPLEFT", 120, -255)
    piSoundDropdown:SetWidth(150)
    piSoundDropdown:SetupMenu(function(dropdown, rootDescription)
        for _, soundInfo in ipairs(soundList) do
            rootDescription:CreateRadio(soundInfo.name, function() return Sounds4StuffDB.piSound == soundInfo.id end, function() Sounds4StuffDB.piSound = soundInfo.id end)
        end
    end)

    local piTestBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    piTestBtn:SetPoint("LEFT", piSoundDropdown, "RIGHT", 15, 0)
    piTestBtn:SetSize(100, 30)
    piTestBtn:SetText("Test PI")
    piTestBtn:SetScript("OnClick", function() PlayDingSound(Sounds4StuffDB.piSound) end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Sounds4Stuff")
    Settings.RegisterAddOnCategory(category)

    Sounds4StuffCategoryID = category:GetID()
end

SLASH_SOUNDSFORSTUFF1 = "/s4s"
SLASH_SOUNDSFORSTUFF2 = "/sounds4stuff"
SlashCmdList["SOUNDSFORSTUFF"] = function()
    Settings.OpenToCategory(Sounds4StuffCategoryID)
end