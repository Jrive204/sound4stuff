local frame = CreateFrame("Frame")
local trinketOnCD = false
local potionOnCD = false
local trackedItemID = nil

local soundList = {
    { name = "Raid Warning", id = 567397 },
    { name = "Level Up!", id = 569593 },
    { name = "You Are Not Prepared", id = 552503 },
    { name = "Ready Check", id = 567478 },
    { name = "Quest Complete", id = 567421 },
    { name = "Murloc", id = 556000 },
    { name = "Evil Laugh", id = 12811 }
}

local function PlayDingSound(soundID)
    if not soundID then return end
    if type(soundID) == "number" and soundID > 100000 then
        PlaySoundFile(soundID, "Master")
    else
        PlaySound(soundID, "Master")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Sounds4Stuff" then
            Sounds4StuffDB = Sounds4StuffDB or {}
            Sounds4StuffDB.slot = Sounds4StuffDB.slot or 13
            if Sounds4StuffDB.chatAlert == nil then Sounds4StuffDB.chatAlert = true end
            if Sounds4StuffDB.potDing == nil then Sounds4StuffDB.potDing = true end

            Sounds4StuffDB.trinketSound = Sounds4StuffDB.trinketSound or 567397
            Sounds4StuffDB.potionSound = Sounds4StuffDB.potionSound or 569593

            self:BuildMenu()
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
                -- Check if player is alive AND in combat before making noise
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
            elseif potionOnCD and pDuration <= 1.5 then
                potionOnCD = false
                -- Check if player is alive AND in combat before making noise
                if UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player") then
                    PlayDingSound(Sounds4StuffDB.potionSound)
                    if Sounds4StuffDB.chatAlert then print("|cff00ff00[Sounds4Stuff]|r Combat Potion Ready!") end
                end
            end
        end
    end
end)

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

    local tSoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tSoundLabel:SetPoint("TOPLEFT", 16, -150)
    tSoundLabel:SetText("Trinket Sound:")

    local tSoundDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    tSoundDropdown:SetPoint("TOPLEFT", 120, -145)
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
    pSoundLabel:SetPoint("TOPLEFT", 16, -190)
    pSoundLabel:SetText("Potion Sound:")

    local pSoundDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    pSoundDropdown:SetPoint("TOPLEFT", 120, -185)
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

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Sounds4Stuff")
    Settings.RegisterAddOnCategory(category)
end