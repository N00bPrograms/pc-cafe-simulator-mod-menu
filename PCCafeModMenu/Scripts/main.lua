-- PC Cafe Mod Menu: an in-game cheat menu for PC Cafe Simulator (UE4SS Lua mod).
-- Press Insert in game. Works in single player and in lobbies you host; the game's
-- money, level and time live on the host, so a joining player's changes would not stick.

local MENU_KEY = Key.INS

local function cls(path)
    local c = StaticFindObject(path)
    if c and c:IsValid() then return c end
    return nil
end
local function valid(o) return o ~= nil and o:IsValid() end
local UNIT = 1000 -- the game stores cash in thousandths of a dollar
local function money(raw) -- raw game units -> "$1,234.56"
    local cents = math.floor((tonumber(raw) or 0) / 10 + 0.5)
    local neg = cents < 0; cents = math.abs(cents)
    local s = string.format("%d", cents // 100):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-$" or "$") .. s .. string.format(".%02d", cents % 100)
end
local function fmt(n)
    local s = string.format("%d", math.floor(tonumber(n) or 0))
    local neg = s:sub(1, 1) == "-"; if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. s
end

-- ---------------------------------------------------------------- game access
local function GS()
    local gs = FindFirstOf("PCCafeGameState")
    if valid(gs) then return gs end
end
local function PC()
    local pc = FindFirstOf("PCCafePlayerController")
    if valid(pc) then return pc end
end
local function Char()
    local pc = PC(); if not pc then return nil end
    local p = pc.Pawn
    if valid(p) and p:IsA(cls("/Script/PCCafeSimulator.PCCafeCharacter")) then return p end
end
local function Cheats()
    local pc = PC(); if not pc then return nil end
    local cm = pc.CheatManager
    if not valid(cm) then
        pcall(function() pc:EnableCheats() end)
        cm = pc.CheatManager
    end
    if valid(cm) then return cm end
end
local function isHost(gs) return gs and gs:HasAuthority() end

-- ---------------------------------------------------------------- state
local W, tree, statusText, msgText, switcher
local buttons, inputs, tabButtons = {}, {}, {}
local open = false
local nameSeq = 0
local cashLock, clockFrozen, speedMult = nil, false, 1.0
local savedDayLength, savedSpeeds = nil, nil
local savedCursor = nil

local function N(base) nameSeq = nameSeq + 1; return FName("PCCMM_" .. base .. "_" .. nameSeq) end
local function new(path, base) return StaticConstructObject(cls(path), tree, N(base)) end

local function say(text, bad)
    if valid(msgText) then
        msgText:SetText(FText(text))
        msgText:SetColorAndOpacity({ SpecifiedColor = bad and { R = 1, G = 0.45, B = 0.4, A = 1 } or { R = 0.55, G = 0.9, B = 0.6, A = 1 }, ColorUseRule = 0 })
    end
end

-- Runs fn(gs) only on the host; reports what happened.
local function act(fn)
    local gs = GS()
    if not gs then say("Load a game first.", true) return end
    if not isHost(gs) then say("Only the host can change the cafe.", true) return end
    local ok, res = pcall(fn, gs)
    if not ok then say("Error: " .. tostring(res), true) elseif res then say(res) end
end

local function readNumber(id)
    local box = inputs[id]; if not valid(box) then return nil end
    local s = box:GetText():ToString():gsub("[,%s]", ""):lower()
    local num, suf = s:match("^(-?%d*%.?%d+)([kmb]?)$")
    if not num then return nil end
    local v = tonumber(num) * (({ k = 1e3, m = 1e6, b = 1e9 })[suf] or 1)
    return math.floor(v)
end

-- ---------------------------------------------------------------- cheats
local function addCash(n)
    act(function(gs)
        gs.Cash = gs.Cash + n * UNIT; gs:AddCash(0) -- AddCash(0) refreshes the HUD without counting as income
        if cashLock then cashLock = gs.Cash end
        return "Added " .. money(n * UNIT) .. "."
    end)
end
local function setCash(n)
    act(function(gs)
        gs.Cash = n * UNIT; gs:AddCash(0)
        if cashLock then cashLock = n * UNIT end
        return "Cash set to " .. money(n * UNIT) .. "."
    end)
end

local function addXP(n)
    act(function(gs)
        local cm = Cheats()
        if cm then cm:AddXP(n) return "Added " .. fmt(n) .. " XP." end
        gs.Experience = gs.Experience + n; gs:OnRep_Level()
        return "Added " .. fmt(n) .. " XP."
    end)
end
local function addLevel(n)
    act(function(gs)
        gs.Level = math.max(1, gs.Level + n); gs.Experience = 0; gs:OnRep_Level()
        return "Cafe level is now " .. gs.Level .. "."
    end)
end
local function addSkillPoints(n)
    act(function(gs)
        gs.UnspentSkillPoints = math.max(0, gs.UnspentSkillPoints + n); gs:OnRep_SkillState()
        return "Unspent skill points: " .. gs.UnspentSkillPoints .. "."
    end)
end
local function addRating(d)
    act(function(gs)
        local cm = Cheats()
        if cm then cm:AddRating(d) else gs.RatingCheatOffset = gs.RatingCheatOffset + d; gs:OnRep_Rating() end
        return string.format("Rating %+.1f.", d)
    end)
end
local function clearBills()
    act(function(gs)
        local owed = gs.PendingUnpaidAmount
        gs.PendingUnpaidAmount = 0
        gs.LastSettlementUnpaidAmount = 0
        return owed > 0 and ("Cleared " .. money(owed) .. " of unpaid bills.") or "No unpaid bills."
    end)
end

local function setHour(h)
    act(function(gs)
        gs:SetGameTimeMinutes(h * 60, false)
        return string.format("Clock set to %02d:00.", h)
    end)
end
local function addHours(h)
    act(function(gs)
        gs:SetGameTimeMinutes(gs.GameTimeMinutes + h * 60, true)
        return "Skipped " .. h .. " hour" .. (h == 1 and "" or "s") .. "."
    end)
end
local function setDayLength(mult)
    act(function(gs)
        if not savedDayLength then savedDayLength = gs.RealMinutesPerGameDay end
        clockFrozen = false
        gs.RealMinutesPerGameDay = savedDayLength * mult
        return mult == 1 and "Day length back to normal." or ("Days now last " .. mult .. "x longer.")
    end)
end
local function toggleFreezeClock()
    act(function(gs)
        if not savedDayLength then savedDayLength = gs.RealMinutesPerGameDay end
        clockFrozen = not clockFrozen
        gs.RealMinutesPerGameDay = clockFrozen and 1e9 or savedDayLength
        return clockFrozen and "Clock frozen." or "Clock running."
    end)
end
local function endDay()
    act(function(gs) gs:EndDay() return "Ending the day." end)
end

local function setSpeed(m)
    local c = Char(); if not c then say("No player character.", true) return end
    if not savedSpeeds then savedSpeeds = { walk = c.WalkSpeed, run = c.RunSpeed, crouch = c.CrouchMoveSpeed } end
    speedMult = m
    c.WalkSpeed = savedSpeeds.walk * m; c.RunSpeed = savedSpeeds.run * m; c.CrouchMoveSpeed = savedSpeeds.crouch * m
    local mv = c.CharacterMovement
    if valid(mv) then mv.MaxWalkSpeed = savedSpeeds.walk * m end
    say(m == 1 and "Normal move speed." or ("Move speed x" .. m .. "."))
end
local savedReach
local function setReach(m)
    local c = Char(); if not c then say("No player character.", true) return end
    if not savedReach then savedReach = { i = c.InteractionRange, p = c.PlacementRange } end
    c.InteractionRange = savedReach.i * m; c.PlacementRange = savedReach.p * m
    say(m == 1 and "Normal reach." or ("Reach x" .. m .. "."))
end

local function weather(kind)
    local cm = Cheats(); if not cm then say("Weather needs the game's cheat manager.", true) return end
    act(function()
        if kind == "clear" then cm:WeatherClear()
        elseif kind == "rain" then cm:WeatherRain(1.0)
        elseif kind == "snow" then cm:WeatherSnow(1.0)
        elseif kind == "storm" then cm:WeatherStorm() end
        return "Weather: " .. kind .. "."
    end)
end

-- ---------------------------------------------------------------- UI building
local function textBlock(text, size, color)
    local t = new("/Script/UMG.TextBlock", "Text")
    t:SetText(FText(text))
    if size then t.Font.Size = size end
    t:SetColorAndOpacity({ SpecifiedColor = color or { R = 0.9, G = 0.92, B = 0.96, A = 1 }, ColorUseRule = 0 })
    return t
end

local function button(label, fn, tint)
    local b = new("/Script/UMG.Button", "Btn")
    b:SetBackgroundColor(tint or { R = 0.22, G = 0.27, B = 0.38, A = 1 })
    local t = textBlock(label, 13)
    b:SetContent(t)
    buttons[#buttons + 1] = { w = b, fn = fn, down = false }
    return b
end

local function hrow(parent, ...)
    local h = new("/Script/UMG.HorizontalBox", "Row")
    for _, child in ipairs({ ... }) do
        local s = h:AddChildToHorizontalBox(child)
        s:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 })
    end
    local s = parent:AddChildToVerticalBox(h)
    s:SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 3 })
    return h
end

local function heading(parent, text)
    local s = parent:AddChildToVerticalBox(textBlock(text, 11, { R = 0.55, G = 0.6, B = 0.7, A = 1 }))
    s:SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 1 })
end

local function inputBox(id, hint)
    local e = new("/Script/UMG.EditableTextBox", "Input")
    e:SetHintText(FText(hint))
    inputs[id] = e
    local sb = new("/Script/UMG.SizeBox", "Size")
    sb:SetWidthOverride(130)
    sb:SetContent(e)
    return sb
end

local GOLD = { R = 0.55, G = 0.42, B = 0.1, A = 1 }
local RED = { R = 0.5, G = 0.17, B = 0.15, A = 1 }

local function toggleLabel(b, text)
    local t = b:GetContent(); if valid(t) then t:SetText(FText(text)) end
end

local pages = {
    { "Money", function(p)
        heading(p, "ADD CASH")
        hrow(p, button("+1k", function() addCash(1000) end), button("+10k", function() addCash(10000) end),
            button("+100k", function() addCash(100000) end, GOLD), button("+1M", function() addCash(1000000) end, GOLD))
        heading(p, "SET CASH")
        hrow(p, inputBox("cash", "e.g. 250k"),
            button("Add", function() local n = readNumber("cash"); if n then addCash(n) else say("Type an amount like 5000, 50k or 2m.", true) end end),
            button("Set", function() local n = readNumber("cash"); if n then setCash(n) else say("Type an amount like 5000, 50k or 2m.", true) end end))
        local lockBtn
        lockBtn = button("Lock cash: off", function()
            local gs = GS()
            if not gs or not isHost(gs) then say("Load a game you host first.", true) return end
            if cashLock then cashLock = nil else cashLock = tonumber(gs.Cash) end
            toggleLabel(lockBtn, cashLock and "Lock cash: ON" or "Lock cash: off")
            say(cashLock and ("Cash locked at " .. money(cashLock) .. ".") or "Cash unlocked.")
        end)
        heading(p, "BILLS")
        hrow(p, lockBtn, button("Clear unpaid bills", clearBills, RED))
    end },
    { "Cafe", function(p)
        heading(p, "EXPERIENCE")
        hrow(p, button("+100 XP", function() addXP(100) end), button("+1,000 XP", function() addXP(1000) end), button("+10,000 XP", function() addXP(10000) end, GOLD))
        hrow(p, button("Level +1", function() addLevel(1) end, GOLD), button("Level -1", function() addLevel(-1) end))
        heading(p, "SKILL POINTS")
        hrow(p, button("+1", function() addSkillPoints(1) end), button("+5", function() addSkillPoints(5) end), button("+20", function() addSkillPoints(20) end, GOLD))
        heading(p, "RATING")
        hrow(p, button("+0.5 stars", function() addRating(0.5) end), button("+1 star", function() addRating(1) end, GOLD), button("-0.5 stars", function() addRating(-0.5) end))
    end },
    { "Time", function(p)
        heading(p, "CLOCK")
        local frz
        frz = button("Freeze clock: off", function() toggleFreezeClock(); toggleLabel(frz, clockFrozen and "Freeze clock: ON" or "Freeze clock: off") end, GOLD)
        hrow(p, frz, button("Skip 1 hour", function() addHours(1) end), button("End day now", endDay, RED))
        heading(p, "SET TIME")
        hrow(p, button("08:00", function() setHour(8) end), button("12:00", function() setHour(12) end), button("18:00", function() setHour(18) end), button("22:00", function() setHour(22) end))
        heading(p, "DAY LENGTH")
        hrow(p, button("Normal", function() setDayLength(1) end), button("2x longer", function() setDayLength(2) end), button("4x longer", function() setDayLength(4) end))
        heading(p, "WEATHER")
        hrow(p, button("Clear", function() weather("clear") end), button("Rain", function() weather("rain") end), button("Snow", function() weather("snow") end), button("Storm", function() weather("storm") end))
    end },
    { "Player", function(p)
        heading(p, "MOVE SPEED")
        hrow(p, button("x1", function() setSpeed(1) end), button("x1.5", function() setSpeed(1.5) end), button("x2", function() setSpeed(2) end, GOLD), button("x3", function() setSpeed(3) end))
        heading(p, "REACH (interact and place)")
        hrow(p, button("x1", function() setReach(1) end), button("x2", function() setReach(2) end, GOLD), button("x4", function() setReach(4) end))
    end },
}

local function selectTab(i)
    switcher:SetActiveWidgetIndex(i - 1)
    for j, b in ipairs(tabButtons) do
        b:SetBackgroundColor(j == i and { R = 0.45, G = 0.36, B = 0.12, A = 1 } or { R = 0.16, G = 0.19, B = 0.26, A = 1 })
    end
end

local function build()
    buttons, inputs, tabButtons = {}, {}, {}
    local gi = FindFirstOf("GameInstance")
    W = StaticConstructObject(cls("/Script/UMG.UserWidget"), gi, FName("PCCMM_Root_" .. os.time()))
    tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), W, FName("PCCMM_Tree"))
    W.WidgetTree = tree
    local canvas = new("/Script/UMG.CanvasPanel", "Canvas")
    tree.RootWidget = canvas

    local border = new("/Script/UMG.Border", "Panel")
    border:SetBrushColor({ R = 0.035, G = 0.04, B = 0.055, A = 0.94 })
    border:SetPadding({ Left = 16, Top = 12, Right = 16, Bottom = 14 })
    local cs = canvas:AddChildToCanvas(border)
    cs:SetAutoSize(true)
    cs:SetPosition({ X = 40, Y = 140 })

    local v = new("/Script/UMG.VerticalBox", "Main")
    border:SetContent(v)
    v:AddChildToVerticalBox(textBlock("PC Cafe Mod Menu", 20, { R = 1, G = 0.78, B = 0.32, A = 1 }))
    statusText = textBlock("", 12, { R = 0.75, G = 0.79, B = 0.86, A = 1 })
    local ss = v:AddChildToVerticalBox(statusText)
    ss:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 6 })

    local tabs = new("/Script/UMG.HorizontalBox", "Tabs")
    for i, page in ipairs(pages) do
        local b = button(page[1], function() selectTab(i) end)
        tabButtons[i] = b
        local s = tabs:AddChildToHorizontalBox(b)
        s:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
    end
    v:AddChildToVerticalBox(tabs)

    switcher = new("/Script/UMG.WidgetSwitcher", "Pages")
    for _, page in ipairs(pages) do
        local pv = new("/Script/UMG.VerticalBox", "Page")
        page[2](pv)
        switcher:AddChild(pv)
    end
    local sw = v:AddChildToVerticalBox(switcher)
    sw:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 4 })

    msgText = textBlock("", 12)
    local ms = v:AddChildToVerticalBox(msgText)
    ms:SetPadding({ Left = 0, Top = 6, Right = 0, Bottom = 0 })
    v:AddChildToVerticalBox(textBlock("Insert closes - host or single player only", 10, { R = 0.45, G = 0.5, B = 0.58, A = 1 }))

    selectTab(1)
    W:AddToViewport(10000)
    W:SetVisibility(1) -- collapsed until opened
end

-- ---------------------------------------------------------------- open / close
local function wbl() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end

local function setOpen(want)
    if want and not valid(W) then
        local ok, err = pcall(build)
        if not ok then
            if valid(W) then W:RemoveFromParent() end
            W = nil
            error(err)
        end
    end
    if not valid(W) then return end
    open = want
    W:SetVisibility(want and 0 or 1)
    local pc = PC(); if not pc then pc = FindFirstOf("PlayerController") end
    if not valid(pc) then return end
    if want then
        savedCursor = pc.bShowMouseCursor
        pc.bShowMouseCursor = true
        pcall(function() wbl():SetInputMode_GameAndUIEx(pc, W, 0, false) end)
        pcall(function() pc:SetIgnoreLookInput(true) end)
    else
        pcall(function() pc:ResetIgnoreLookInput() end)
        if savedCursor == false then
            pc.bShowMouseCursor = false
            pcall(function() wbl():SetInputMode_GameOnly(pc, false) end)
        end
    end
end

local function refreshStatus()
    if not valid(statusText) then return end
    local gs = GS()
    if not gs then statusText:SetText(FText("Load a game to use the menu.")) return end
    local mins = tonumber(gs.GameTimeMinutes) or 0
    local s = string.format("Cash %s   Level %d (%s XP)   Skill points %d\nDay %d   %02d:%02d   Rating %.1f%s%s",
        money(gs.Cash), gs.Level, fmt(gs.Experience), gs.UnspentSkillPoints,
        gs.CurrentDay, (mins // 60) % 24, mins % 60, gs.Rating,
        isHost(gs) and "" or "   (not host: read only)",
        cashLock and "   [cash locked]" or "")
    statusText:SetText(FText(s))
end

-- ---------------------------------------------------------------- loops
local lastToggle = 0
local function onKey()
    local now = os.clock()
    if now - lastToggle < 0.3 then return end -- both key paths can see the same press
    lastToggle = now
    local ok, err = pcall(setOpen, not open)
    if not ok then print("[PCCafeModMenu] " .. tostring(err) .. "\n") end
end

local INSERT = { KeyName = FName("Insert") }
local insertWasDown = false
local tick = 0
local function onTick()
        tick = tick + 1
        -- Fallback key detection through the game's own input, for when UE4SS key binds don't fire.
        local pc = PC()
        if pc then
            local okDown, down = pcall(function() return pc:IsInputKeyDown(INSERT) end)
            down = okDown and down or false
            if down and not insertWasDown then onKey() end
            insertWasDown = down
        end
        if open and valid(W) then
            for _, b in ipairs(buttons) do
                if valid(b.w) then
                    local pressed = b.w:IsPressed()
                    if b.down and not pressed and b.w:IsHovered() then
                        local ok, err = pcall(b.fn)
                        if not ok then say("Error: " .. tostring(err), true) end
                    end
                    b.down = pressed
                end
            end
            if tick % 10 == 0 then pcall(refreshStatus) end
        elseif open and not valid(W) then
            open = false -- widget lost with a map change; Insert rebuilds it
        end
        if tick % 10 == 0 and cashLock then
            local gs = GS()
            if gs and isHost(gs) and tonumber(gs.Cash) < cashLock then
                gs.Cash = cashLock; gs:AddCash(0)
            end
        end
        if tick % 20 == 0 and speedMult ~= 1 then
            -- the game resets movement speed on some state changes; keep the multiplier applied
            local c = Char()
            if c and savedSpeeds and math.abs(c.WalkSpeed - savedSpeeds.walk * speedMult) > 1 then setSpeed(speedMult) end
        end
end

-- The key bind and loop are registered once and call whichever copy of this script loaded last,
-- so reloading the script in a running game doesn't stack duplicate handlers.
if _G.PCCMM_impl and _G.PCCMM_impl.cleanup then pcall(_G.PCCMM_impl.cleanup) end
_G.PCCMM_impl = { onKey = onKey, onTick = onTick, cleanup = function() if valid(W) then W:RemoveFromParent() end end }
if not _G.PCCMM_registered then
    _G.PCCMM_registered = true
    RegisterKeyBind(MENU_KEY, function()
        ExecuteInGameThread(function() _G.PCCMM_impl.onKey() end)
    end)
    LoopAsync(50, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(_G.PCCMM_impl.onTick)
            if not ok then print("[PCCafeModMenu] " .. tostring(err) .. "\n") end
        end)
        return false
    end)
end

-- handle for the developer test hook (harmless in normal play)
_G.PCCMM = { setOpen = function(v) setOpen(v) end, buttons = function() return buttons end, inputs = function() return inputs end, selectTab = function(i) selectTab(i) end, msg = function() return valid(msgText) and msgText:GetText():ToString() or '' end, status = function() refreshStatus(); return valid(statusText) and statusText:GetText():ToString() or '' end }

print("[PCCafeModMenu] loaded - press Insert in game\n")
