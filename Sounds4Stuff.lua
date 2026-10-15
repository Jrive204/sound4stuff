-- Sounds4Stuff - Retail 12.1.5
-- Trinket-ready and combat-potion-ready alerts.
-- Optional SharedMedia / LibSharedMedia-3.0 sound support.
-- No embedded library required: SharedMedia provides LSM when installed.

local frame = CreateFrame("Frame")
local trinketOnCD = false
local trackedItemID = nil
local potionOnCD = false
local checkTimer = 0
local categoryID = nil
local pendingOpenSettings = false

local DEFAULT_POTION_ID = 241289 -- Potion of Recklessness; change with /s4s potion <itemID>

local soundList = {
    { name = "Raid Warning",         id = 567397 },
    { name = "Level Up!",            id = 569593 },
    { name = "You Are Not Prepared", id = 552503 },
    { name = "Ready Check",          id = 567478 },
    { name = "Quest Complete",       id = 567421 },
    { name = "Murloc",               id = 556000 },
    { name = "Evil Laugh",           id = 12811 },
    { name = "Loot Coin",            id = 120 },
    { name = "Aggro Warning",        id = 5274 },
    { name = "Gong",                 id = 8959 },
    { name = "Fel Reaver",           id = 878 },
    { name = "Bike Horn",            id = "Interface\\AddOns\\Sounds4Stuff\\Sounds\\bikehorn.ogg" },
}

-- LibSharedMedia is optional. Resolve it at use time, since another addon
-- may make it available after Sounds4Stuff loads.
local function GetSharedMedia()
    local stub = _G.LibStub
    if not stub then return nil end
    return stub("LibSharedMedia-3.0", true)
end

-- Keep existing numeric IDs and custom file paths fully backwards compatible.
-- SharedMedia choices are stored as "lsm:<registered sound name>", rather
-- than an absolute file path, so they survive future MyMedia path changes.
local SHARED_MEDIA_PREFIX = "lsm:"

local function PlayDingSound(soundID)
    if not soundID then return end

    if type(soundID) == "string" then
        local path = soundID
        if soundID:sub(1, #SHARED_MEDIA_PREFIX) == SHARED_MEDIA_PREFIX then
            local media = GetSharedMedia()
            if not media then return end

            local soundName = soundID:sub(#SHARED_MEDIA_PREFIX + 1)
            path = media:Fetch("sound", soundName, true)
            if type(path) ~= "string" or path == "" then return end
        end
        PlaySoundFile(path, "Master")
    elseif type(soundID) == "number" and soundID > 100000 then
        PlaySoundFile(soundID, "Master")
    elseif type(soundID) == "number" then
        PlaySound(soundID, "Master")
    end
end

-- Sound browser: searchable and scrollable instead of nested dropdowns.
-- Built-in sound IDs and "lsm:<name>" saved values are unchanged.
local soundButtons = {}
local soundBrowser = nil
local RefreshSoundBrowser

local function GetSoundDisplayName(value)
    for _, info in ipairs(soundList) do
        if info.id == value then return info.name end
    end
    if type(value) == "string" then
        if value:sub(1, #SHARED_MEDIA_PREFIX) == SHARED_MEDIA_PREFIX then
            return value:sub(#SHARED_MEDIA_PREFIX + 1)
        end
        return "Custom Sound"
    end
    return "Choose a sound"
end

local function UpdateSoundButtonLabels()
    for field, button in pairs(soundButtons) do
        local name = GetSoundDisplayName(Sounds4StuffDB[field])
        if #name > 30 then name = name:sub(1, 27) .. "..." end
        button:SetText(name .. "  \226\150\190") -- down arrow (UTF-8)
    end
end

local function GetAllSounds()
    local choices = {}
    for _, info in ipairs(soundList) do
        choices[#choices + 1] = { name = info.name, value = info.id, source = "Built-in" }
    end

    local media = GetSharedMedia()
    if not media then return choices end

    local extra = {}
    for _, name in ipairs(media:List("sound") or {}) do
        local path = media:Fetch("sound", name, true)
        if type(path) == "string" and path ~= "" then
            local normalized = path:lower():gsub("/", "\\")
            local source = normalized:find("sharedmedia_mymedia\\sound\\", 1, true)
                and "MyMedia" or "SharedMedia"
            extra[#extra + 1] = {
                name = name,
                value = SHARED_MEDIA_PREFIX .. name,
                source = source,
            }
        end
    end
    table.sort(extra, function(a, b)
        if a.source ~= b.source then return a.source < b.source end
        return a.name:lower() < b.name:lower()
    end)
    for _, info in ipairs(extra) do choices[#choices + 1] = info end
    return choices
end

local function CreateSoundBrowser()
    local browser = CreateFrame("Frame", "Sounds4StuffSoundBrowser", UIParent, "BackdropTemplate")
    browser:SetSize(500, 458)
    browser:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    browser:SetFrameStrata("DIALOG")
    browser:SetClampedToScreen(true)
    browser:SetMovable(true)
    browser:EnableMouse(true)
    browser:RegisterForDrag("LeftButton")
    browser:SetScript("OnDragStart", function(self) self:StartMoving() end)
    browser:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    browser:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })

    browser.title = browser:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    browser.title:SetPoint("TOPLEFT", 24, -19)
    browser.title:SetText("Sound Library")

    local closeButton = CreateFrame("Button", nil, browser, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() browser:Hide() end)

    local hint = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 24, -49)
    hint:SetText("Search, scroll, then choose a sound. Preview any sound with Play.")

    local searchLabel = browser:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 24, -78)
    searchLabel:SetText("Search")

    browser.search = CreateFrame("EditBox", nil, browser, "InputBoxTemplate")
    browser.search:SetSize(392, 26)
    browser.search:SetPoint("TOPLEFT", 80, -73)
    browser.search:SetAutoFocus(false)
    browser.search:SetMaxLetters(80)
    browser.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        browser:Hide()
    end)
    browser.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    browser.search:SetScript("OnTextChanged", function()
        if RefreshSoundBrowser then RefreshSoundBrowser(true) end
    end)

    browser.filter = "All"
    browser.tabs = {}
    local categories = {
        { name = "All", width = 81 },
        { name = "Built-in", width = 105 },
        { name = "MyMedia", width = 105 },
        { name = "SharedMedia", width = 130 },
    }
    local x = 24
    for _, info in ipairs(categories) do
        local tab = CreateFrame("Button", nil, browser, "UIPanelButtonTemplate")
        tab:SetSize(info.width, 25)
        tab:SetPoint("TOPLEFT", x, -114)
        tab:SetText(info.name)
        tab:SetScript("OnClick", function()
            browser.filter = info.name
            RefreshSoundBrowser(true)
        end)
        browser.tabs[info.name] = tab
        x = x + info.width + 7
    end

    browser.resultCount = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    browser.resultCount:SetPoint("TOPLEFT", 24, -152)
    browser.resultCount:SetText("Loading sounds...")

    -- ScrollFrameTemplate is the current Blizzard scrollframe template.
    -- The scroll child is taller than the viewport when there are many sounds.
    browser.scroll = CreateFrame("ScrollFrame", nil, browser, "ScrollFrameTemplate")
    browser.scroll:SetSize(425, 224)
    browser.scroll:SetPoint("TOPLEFT", 24, -172)

    browser.scrollChild = CreateFrame("Frame", nil, browser.scroll)
    browser.scrollChild:SetSize(425, 225)
    browser.scroll:SetScrollChild(browser.scrollChild)

    browser.rows = {}
    browser.sounds = {}
    browser:SetScript("OnHide", function(self) self.search:ClearFocus() end)

    local helpText = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("BOTTOMLEFT", 24, 25)
    helpText:SetText("Only registered SharedMedia sounds appear. Press Esc to close.")

    if UISpecialFrames then
        table.insert(UISpecialFrames, "Sounds4StuffSoundBrowser")
    end

    browser:Hide()
    return browser
end

RefreshSoundBrowser = function(resetScroll)
    local browser = soundBrowser
    if not browser then return end

    local filter = browser.filter
    local query = (browser.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local filtered = {}
    for _, entry in ipairs(browser.sounds) do
        if (filter == "All" or entry.source == filter)
            and (query == "" or entry.name:lower():find(query, 1, true)) then
            filtered[#filtered + 1] = entry
        end
    end

    for name, tab in pairs(browser.tabs) do
        if name == filter then tab:Disable() else tab:Enable() end
    end
    browser.resultCount:SetText(#filtered .. " sound" .. (#filtered == 1 and "" or "s") .. " found")

    local ROW_HEIGHT = 28
    for i, entry in ipairs(filtered) do
        local row = browser.rows[i]
        if not row then
            row = CreateFrame("Button", nil, browser.scrollChild)
            row:SetSize(410, ROW_HEIGHT - 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", 9, 0)
            row.text:SetWidth(324)
            row.text:SetJustifyH("LEFT")

            row.preview = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.preview:SetSize(58, 21)
            row.preview:SetPoint("RIGHT", -7, 0)
            row.preview:SetText("Play")
            row.preview:SetScript("OnClick", function(self)
                PlayDingSound(self:GetParent().sound.value)
            end)

            row:SetScript("OnClick", function(self)
                Sounds4StuffDB[browser.field] = self.sound.value
                UpdateSoundButtonLabels()
                browser:Hide()
            end)
            browser.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", browser.scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row.sound = entry
        local selected = Sounds4StuffDB[browser.field] == entry.value
        local label = (selected and "|cff69ff9b> |r" or "   ") .. entry.name
        if filter == "All" then
            label = label .. "  |cff888888[" .. entry.source .. "]|r"
        end
        row.text:SetText(label)
        row:Show()
    end

    for i = #filtered + 1, #browser.rows do browser.rows[i]:Hide() end
    browser.scrollChild:SetHeight(math.max(225, #filtered * ROW_HEIGHT))
    if resetScroll then browser.scroll:SetVerticalScroll(0) end
end

local function OpenSoundBrowser(field)
    if not soundBrowser then soundBrowser = CreateSoundBrowser() end
    soundBrowser.field = field
    soundBrowser.title:SetText(field == "trinketSound" and "Choose Trinket Sound" or "Choose Potion Sound")
    soundBrowser.sounds = GetAllSounds()
    soundBrowser.filter = "All"
    soundBrowser.search:SetText("")
    RefreshSoundBrowser(true)
    soundBrowser:Show()
end

-- Trinket alerts stay combat-only; potion ready alerts can fire outside combat.
local function Alert(message, soundID, allowOutOfCombat)
    if UnitIsDeadOrGhost("player") then return end
    if not allowOutOfCombat and not UnitAffectingCombat("player") then return end

    PlayDingSound(soundID)
    if Sounds4StuffDB.chatAlert then
        print("|cff00ff00[Sounds4Stuff]|r " .. message)
    end
end

-- start/duration are absolute cooldown data, not remaining time.
-- Use GetTime() so an expired cooldown can be detected without a new event.
-- Return nil if the client withholds a readable cooldown value.
local function IsCooldownActive(start, duration, now)
    if type(start) ~= "number" or type(duration) ~= "number" then
        return nil
    end
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        return nil
    end
    return start > 0 and duration > 1.5 and (start + duration) > now
end

local function CheckTrinket(now)
    local slot = Sounds4StuffDB.slot
    local currentItemID = GetInventoryItemID("player", slot)

    if not currentItemID then
        trinketOnCD = false
        trackedItemID = nil
        return
    end

    -- Swapping trinkets should not cause a false "ready" notification.
    if trackedItemID and currentItemID ~= trackedItemID then
        trinketOnCD = false
        trackedItemID = nil
    end

    local start, duration = GetInventoryItemCooldown("player", slot)
    local active = IsCooldownActive(start, duration, now)
    if active == nil then return end

    if active then
        trinketOnCD = true
        trackedItemID = currentItemID
    elseif trinketOnCD then
        trinketOnCD = false
        if currentItemID == trackedItemID then
            Alert("Trinket Ready!", Sounds4StuffDB.trinketSound)
        end
        trackedItemID = nil
    end
end

local function CheckPotion(now)
    if not Sounds4StuffDB.potDing then
        potionOnCD = false
        return
    end

    -- GetItemCooldown() was removed in 12.1.5.
    local start, duration = C_Item.GetItemCooldown(Sounds4StuffDB.potionItemID)
    local active = IsCooldownActive(start, duration, now)
    if active == nil then return end

    if active then
        potionOnCD = true
    elseif potionOnCD then
        potionOnCD = false
        Alert("Combat Potion Ready!", Sounds4StuffDB.potionSound, true)
    end
end

local function CheckCooldowns()
    if not Sounds4StuffDB then return end
    local now = GetTime()
    CheckTrinket(now)
    CheckPotion(now)
end

function frame:BuildMenu()
    local panel = CreateFrame("Frame", "Sounds4StuffOptionsPanel")
    panel:SetSize(620, 350)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Sounds4Stuff Configuration")

    local slotBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    slotBtn:SetPoint("TOPLEFT", 16, -56)
    slotBtn:SetSize(180, 30)

    local function UpdateSlotText()
        slotBtn:SetText("Trinket Slot: " .. (Sounds4StuffDB.slot == 13 and "Top (13)" or "Bottom (14)"))
    end
    UpdateSlotText()
    slotBtn:SetScript("OnClick", function()
        Sounds4StuffDB.slot = (Sounds4StuffDB.slot == 13) and 14 or 13
        trinketOnCD = false
        trackedItemID = nil
        UpdateSlotText()
        CheckCooldowns()
    end)

    local potCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    potCheck:SetPoint("TOPLEFT", 16, -104)
    potCheck:SetChecked(Sounds4StuffDB.potDing)
    potCheck.text = potCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    potCheck.text:SetPoint("LEFT", potCheck, "RIGHT", 5, 0)
    potCheck.text:SetText("Track Combat Potion")
    potCheck:SetScript("OnClick", function(self)
        Sounds4StuffDB.potDing = self:GetChecked()
        potionOnCD = false
        CheckCooldowns()
    end)

    local chatCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    chatCheck:SetPoint("TOPLEFT", 300, -104)
    chatCheck:SetChecked(Sounds4StuffDB.chatAlert)
    chatCheck.text = chatCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatCheck.text:SetPoint("LEFT", chatCheck, "RIGHT", 5, 0)
    chatCheck.text:SetText("Show Chat Alert")
    chatCheck:SetScript("OnClick", function(self)
        Sounds4StuffDB.chatAlert = self:GetChecked()
    end)

    local trinketLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trinketLabel:SetPoint("TOPLEFT", 16, -162)
    trinketLabel:SetText("Trinket Sound:")

    local trinketDropdown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    trinketDropdown:SetPoint("TOPLEFT", 120, -157)
    trinketDropdown:SetSize(232, 30)
    soundButtons.trinketSound = trinketDropdown
    trinketDropdown:SetScript("OnClick", function() OpenSoundBrowser("trinketSound") end)

    local trinketTest = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    trinketTest:SetPoint("LEFT", trinketDropdown, "RIGHT", 15, 0)
    trinketTest:SetSize(110, 30)
    trinketTest:SetText("Test Trinket")
    trinketTest:SetScript("OnClick", function()
        PlayDingSound(Sounds4StuffDB.trinketSound)
    end)

    local potionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    potionLabel:SetPoint("TOPLEFT", 16, -214)
    potionLabel:SetText("Potion Sound:")

    local potionDropdown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    potionDropdown:SetPoint("TOPLEFT", 120, -209)
    potionDropdown:SetSize(232, 30)
    soundButtons.potionSound = potionDropdown
    potionDropdown:SetScript("OnClick", function() OpenSoundBrowser("potionSound") end)

    local potionTest = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    potionTest:SetPoint("LEFT", potionDropdown, "RIGHT", 15, 0)
    potionTest:SetSize(110, 30)
    potionTest:SetText("Test Potion")
    potionTest:SetScript("OnClick", function()
        PlayDingSound(Sounds4StuffDB.potionSound)
    end)

    local potionNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    potionNote:SetPoint("TOPLEFT", 16, -272)
    potionNote:SetText("Potion item ID: " .. Sounds4StuffDB.potionItemID .. "  |  Change with /s4s potion <itemID>")
    self.potionNote = potionNote
    UpdateSoundButtonLabels()

    local sharedMediaNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sharedMediaNote:SetPoint("TOPLEFT", 16, -301)
    sharedMediaNote:SetText("Select a sound to open the searchable, scrollable sound library.")

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Sounds4Stuff")
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
end

-- Retail 12.x protects Blizzard's Settings panel during combat.
-- Defer slash-command requests rather than calling the protected API.
local function OpenSettingsWhenSafe()
    if not categoryID then
        print("|cff00ff00[Sounds4Stuff]|r Settings are not ready yet. Try /reload.")
        return
    end

    if InCombatLockdown() then
        if not pendingOpenSettings then
            print("|cff00ff00[Sounds4Stuff]|r Settings will open when combat ends.")
        end
        pendingOpenSettings = true
        return
    end

    pendingOpenSettings = false
    Settings.OpenToCategory(categoryID)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= "Sounds4Stuff" then return end

        Sounds4StuffDB = Sounds4StuffDB or {}
        if Sounds4StuffDB.slot ~= 13 and Sounds4StuffDB.slot ~= 14 then
            Sounds4StuffDB.slot = 13
        end
        if Sounds4StuffDB.chatAlert == nil then Sounds4StuffDB.chatAlert = true end
        if Sounds4StuffDB.potDing == nil then Sounds4StuffDB.potDing = true end
        Sounds4StuffDB.trinketSound = Sounds4StuffDB.trinketSound or 567397
        Sounds4StuffDB.potionSound = Sounds4StuffDB.potionSound or 569593
        if type(Sounds4StuffDB.potionItemID) ~= "number" or Sounds4StuffDB.potionItemID <= 0 then
            Sounds4StuffDB.potionItemID = DEFAULT_POTION_ID
        end

        -- Remove unused PI settings from existing saved variables.
        Sounds4StuffDB.piDing = nil
        Sounds4StuffDB.piSound = nil

        self:BuildMenu()
        CheckCooldowns()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingOpenSettings then
            OpenSettingsWhenSafe()
        end
        CheckCooldowns()
    else
        CheckCooldowns()
    end
end)

-- Timer checks the actual expiration time, even if no cooldown event fires.
-- 0.25 sec is responsive without querying cooldowns every frame.
frame:SetScript("OnUpdate", function(_, elapsed)
    checkTimer = checkTimer + elapsed
    if checkTimer < 0.25 then return end
    checkTimer = 0
    CheckCooldowns()
end)

SLASH_SOUNDSFORSTUFF1 = "/s4s"
SLASH_SOUNDSFORSTUFF2 = "/sounds4stuff"
SlashCmdList["SOUNDSFORSTUFF"] = function(msg)
    if not Sounds4StuffDB then return end

    local itemID = (msg or ""):match("^%s*potion%s+(%d+)%s*$")
    if itemID then
        local numericID = tonumber(itemID)
        if numericID and numericID > 0 then
            Sounds4StuffDB.potionItemID = numericID
            potionOnCD = false
            if frame.potionNote then
                frame.potionNote:SetText("Potion item ID: " .. numericID .. "  |  Change with /s4s potion <itemID>")
            end
            print("|cff00ff00[Sounds4Stuff]|r Tracking potion item ID " .. numericID)
            CheckCooldowns()
            return
        end
    end

    if (msg or ""):match("^%s*potion") then
        print("|cff00ff00[Sounds4Stuff]|r Usage: /s4s potion 241289")
        return
    end

    OpenSettingsWhenSafe()
end
