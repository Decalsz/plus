--[[
    FE_BUNDLE v9 - Massive Saweria Rewrite
    Stable one-file LocalScript for Delta/mobile

    Features:
    - GUI opens by default + draggable + icon toggle + close/kill.
    - Clean Saweria-inspired light UI with normal readable font.
    - Bundle search/apply full bundle.
    - Emote search/play.
    - INFO popup with avatar Viewport preview for emotes.
    - Custom mix slots: Idle/Walk/Run/Jump/Fall/Climb/Swim.
    - Favorites for bundles and emotes.
    - Save packs + autoload.
    - Settings: custom emote speed, loop, move while emote, apply method, popup background transparency.
    - Loading popup with moving bar.

    Notes:
    - Some executors may block game:HttpGet or game:GetObjects.
    - R6 converter can make R15 animation packs look stiff.
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local SAVE_FILE = "FE_BUNDLE_V9_Save.json"
local CAN_SAVE = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local Alive = true
local CurrentPage = "Bundles"
local ChoosingState = nil
local ApplyMethod = "Animate" -- Animate / Description / Both
local AutoLoad = true
local AutoLoadName = ""
local LastAppliedName = ""
local ModalDimTransparency = 0.45

local EmoteSpeed = 1
local EmoteLoop = true
local MoveWhileEmote = true
local CurrentEmoteTrack = nil

local BundleResults = {}
local EmoteResults = {}
local NextBundleCursor = nil
local NextEmoteCursor = nil
local LastBundleKeyword = "animation"
local LastEmoteKeyword = "dance"
local LoadingMore = false

local FavoritesBundles = {}
local FavoritesEmotes = {}
local SavedPacks = {}
local EditingSaveIndex = nil
local AnimationObjectCache = {}
local OriginalIds = {}

local States = {"Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim"}
local CurrentForm = {Idle="", Walk="", Run="", Jump="", Fall="", Climb="", Swim=""}
local SlotMeta = {Idle=nil, Walk=nil, Run=nil, Jump=nil, Fall=nil, Climb=nil, Swim=nil}

local Connections = {}
local PageConnections = {}

local ScreenGui, IconButton, Main, Body, HeaderTitle, StatusLabel
local ModalDim, ModalCard, LoadingDim, LoadingCard, LoadingBar

local Theme = {
    Page = Color3.fromRGB(255, 255, 255),
    Paper = Color3.fromRGB(247, 250, 248),
    Card = Color3.fromRGB(239, 245, 243),
    Field = Color3.fromRGB(248, 250, 249),
    Header = Color3.fromRGB(255, 181, 48),
    Cyan = Color3.fromRGB(137, 211, 222),
    Orange = Color3.fromRGB(255, 181, 48),
    Green = Color3.fromRGB(137, 222, 205),
    Yellow = Color3.fromRGB(255, 216, 126),
    Red = Color3.fromRGB(255, 100, 120),
    Text = Color3.fromRGB(24, 24, 24),
    Muted = Color3.fromRGB(82, 92, 100),
    LightMuted = Color3.fromRGB(150, 160, 168),
    Black = Color3.fromRGB(18, 18, 18)
}

local AnimateNames = {
    Idle = {"idle"},
    Walk = {"walk"},
    Run = {"run"},
    Jump = {"jump"},
    Fall = {"fall"},
    Climb = {"climb"},
    Swim = {"swim", "swimidle"}
}

---------------------------------------------------------------------
-- BASIC HELPERS
---------------------------------------------------------------------

local function add(list, conn)
    table.insert(list or Connections, conn)
    return conn
end

local function disconnectList(list)
    for _, c in ipairs(list) do
        pcall(function() c:Disconnect() end)
    end
    for i = #list, 1, -1 do
        table.remove(list, i)
    end
end

local function new(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thick, trans)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Black
    s.Thickness = thick or 1
    s.Transparency = trans or 0
    s.Parent = obj
    return s
end

local function tween(obj, props, time)
    pcall(function()
        TweenService:Create(obj, TweenInfo.new(time or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end)
end

local function clear(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        child:Destroy()
    end
end

local function getParentGui()
    local pg = nil
    pcall(function() if gethui then pg = gethui() end end)
    if not pg then pcall(function() pg = game:GetService("CoreGui") end) end
    if not pg then pg = LocalPlayer:WaitForChild("PlayerGui") end
    return pg
end

local function normalizeId(raw)
    raw = tostring(raw or "")
    return string.match(raw, "%d+") or ""
end

local function toAnimUrl(id)
    id = normalizeId(id)
    if id == "" then return "" end
    return "rbxassetid://" .. id
end

local function getCharHum()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animate = char and char:FindFirstChild("Animate")
    return char, hum, animate
end

local function status(text, good)
    if not StatusLabel then return end
    StatusLabel.Text = tostring(text or "")
    if good == true then
        StatusLabel.TextColor3 = Color3.fromRGB(40, 130, 90)
    elseif good == false then
        StatusLabel.TextColor3 = Theme.Red
    else
        StatusLabel.TextColor3 = Theme.Muted
    end
end

local function tableCopy(t)
    local out = {}
    for k, v in pairs(t or {}) do
        if type(v) == "table" then
            local inner = {}
            for a, b in pairs(v) do inner[a] = b end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local function bundleThumbnail(id)
    return "rbxthumb://type=BundleThumbnail&id=" .. tostring(id) .. "&w=150&h=150"
end

local function assetThumbnail(id)
    return "rbxthumb://type=Asset&id=" .. tostring(id) .. "&w=150&h=150"
end

local function httpGet(url)
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(result) == "string" then return result end
    return nil
end

local function decodeJson(raw)
    if not raw then return nil end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if ok then return data end
    return nil
end

---------------------------------------------------------------------
-- SAVE / LOAD
---------------------------------------------------------------------

local function saveData()
    if not CAN_SAVE then return false end
    local data = {
        AutoLoad = AutoLoad,
        AutoLoadName = AutoLoadName,
        LastAppliedName = LastAppliedName,
        ApplyMethod = ApplyMethod,
        ModalDimTransparency = ModalDimTransparency,
        EmoteSpeed = EmoteSpeed,
        EmoteLoop = EmoteLoop,
        MoveWhileEmote = MoveWhileEmote,
        CurrentForm = CurrentForm,
        SlotMeta = SlotMeta,
        FavoritesBundles = FavoritesBundles,
        FavoritesEmotes = FavoritesEmotes,
        SavedPacks = SavedPacks
    }
    local ok = pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(data))
    end)
    return ok
end

local function loadData()
    if not CAN_SAVE then return false end
    local exists = false
    pcall(function() exists = isfile(SAVE_FILE) end)
    if not exists then return false end
    local raw
    local okRead = pcall(function() raw = readfile(SAVE_FILE) end)
    if not okRead or not raw then return false end
    local data
    local okDecode = pcall(function() data = HttpService:JSONDecode(raw) end)
    if not okDecode or type(data) ~= "table" then return false end

    if type(data.AutoLoad) == "boolean" then AutoLoad = data.AutoLoad end
    if type(data.AutoLoadName) == "string" then AutoLoadName = data.AutoLoadName end
    if type(data.LastAppliedName) == "string" then LastAppliedName = data.LastAppliedName end
    if type(data.ApplyMethod) == "string" then ApplyMethod = data.ApplyMethod end
    if type(data.ModalDimTransparency) == "number" then ModalDimTransparency = math.clamp(data.ModalDimTransparency, 0.05, 0.9) end
    if type(data.EmoteSpeed) == "number" then EmoteSpeed = data.EmoteSpeed end
    if type(data.EmoteLoop) == "boolean" then EmoteLoop = data.EmoteLoop end
    if type(data.MoveWhileEmote) == "boolean" then MoveWhileEmote = data.MoveWhileEmote end
    if type(data.CurrentForm) == "table" then CurrentForm = data.CurrentForm end
    if type(data.SlotMeta) == "table" then SlotMeta = data.SlotMeta end
    if type(data.FavoritesBundles) == "table" then FavoritesBundles = data.FavoritesBundles end
    if type(data.FavoritesEmotes) == "table" then FavoritesEmotes = data.FavoritesEmotes end
    if type(data.SavedPacks) == "table" then SavedPacks = data.SavedPacks end
    return true
end

---------------------------------------------------------------------
-- GUI HELPERS
---------------------------------------------------------------------

local function getZ(parent, plus)
    local z = 1
    pcall(function() z = parent.ZIndex or 1 end)
    return z + (plus or 1)
end

local function makeLabel(parent, text, pos, size, textSize, color)
    return new("TextLabel", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = color or Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = textSize or 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true,
        ZIndex = getZ(parent, 2)
    })
end

local function makeButton(parent, text, pos, size, callback, color, persistent)
    local bucket = persistent and Connections or PageConnections
    local shadow = new("Frame", {
        Parent = parent,
        Position = UDim2.new(pos.X.Scale, pos.X.Offset + 3, pos.Y.Scale, pos.Y.Offset + 4),
        Size = size,
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        ZIndex = getZ(parent, 1)
    })
    corner(shadow, 8)

    local b = new("TextButton", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = color or Theme.Card,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        AutoButtonColor = false,
        Active = true,
        ClipsDescendants = true,
        ZIndex = getZ(parent, 2)
    })
    corner(b, 8)
    stroke(b, Theme.Black, 1, 0)

    local fired = false
    local function pressAnim()
        tween(b, {Position = UDim2.new(pos.X.Scale, pos.X.Offset + 2, pos.Y.Scale, pos.Y.Offset + 2)}, 0.05)
        local dot = new("Frame", {
            Parent = b,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 6, 0, 6),
            BackgroundColor3 = Theme.Page,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = getZ(b, 3)
        })
        corner(dot, 99)
        tween(dot, {Size = UDim2.new(1.8, 0, 1.8, 0), BackgroundTransparency = 1}, 0.24)
        task.delay(0.26, function() if dot then dot:Destroy() end end)
    end
    local function releaseAnim()
        tween(b, {Position = pos}, 0.06)
    end
    local function fire()
        if fired then return end
        fired = true
        task.delay(0.18, function() fired = false end)
        if callback then callback() end
    end

    add(bucket, b.MouseButton1Down:Connect(pressAnim))
    add(bucket, b.MouseButton1Up:Connect(releaseAnim))
    add(bucket, b.MouseButton1Click:Connect(fire))
    add(bucket, b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then pressAnim() end
    end))
    add(bucket, b.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then releaseAnim(); fire() end
    end))
    pcall(function() add(bucket, b.Activated:Connect(fire)) end)
    return b
end

local function makeBox(parent, placeholder, pos, size)
    local box = new("TextBox", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.LightMuted,
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = getZ(parent, 2)
    })
    corner(box, 8)
    stroke(box, Theme.Black, 1, 0.2)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = box
    return box
end

local function makePanel(parent, pos, size, color)
    local panel = new("Frame", {
        Parent = parent,
        Position = UDim2.new(pos.X.Scale, pos.X.Offset + 4, pos.Y.Scale, pos.Y.Offset + 6),
        Size = UDim2.new(size.X.Scale, math.max(8, math.floor(size.X.Offset * 0.92)), size.Y.Scale, math.max(8, math.floor(size.Y.Offset * 0.86))),
        BackgroundColor3 = color or Theme.Card,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        ZIndex = getZ(parent, 1)
    })
    corner(panel, 10)
    stroke(panel, Theme.Black, 1, 0)
    task.defer(function()
        if panel and panel.Parent then
            tween(panel, {Position = pos, Size = size, BackgroundTransparency = 0}, 0.18)
        end
    end)
    return panel
end

---------------------------------------------------------------------
-- LOADING OVERLAY
---------------------------------------------------------------------

local LoadingActive, LoadingDim, LoadingCard, LoadingBar

local function hideLoading()
    LoadingActive = false
    local card = LoadingCard
    local dim = LoadingDim
    LoadingCard = nil
    LoadingDim = nil
    LoadingBar = nil
    if card then
        tween(card, {Size = UDim2.new(0, 40, 0, 40), BackgroundTransparency = 1}, 0.12)
        task.delay(0.14, function() if card then card:Destroy() end end)
    end
    if dim then
        tween(dim, {BackgroundTransparency = 1}, 0.12)
        task.delay(0.14, function() if dim then dim:Destroy() end end)
    end
end

local function showLoading(text)
    hideLoading()
    LoadingActive = true
    LoadingDim = new("Frame", {Parent = ScreenGui, Position = UDim2.new(0,0,0,0), Size = UDim2.new(1,0,1,0), BackgroundColor3 = Theme.Black, BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = 250})
    LoadingCard = new("Frame", {Parent = ScreenGui, AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(0.5,0,0.5,0), Size = UDim2.new(0,330,0,112), BackgroundColor3 = Theme.Page, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 251})
    corner(LoadingCard, 14)
    stroke(LoadingCard, Theme.Black, 2, 0)
    tween(LoadingCard, {Size = UDim2.new(0,330,0,112)}, 0.16)
    makeLabel(LoadingCard, text or "Loading...", UDim2.new(0,18,0,14), UDim2.new(1,-36,0,28), 16, Theme.Text)
    local bg = new("Frame", {Parent = LoadingCard, Position = UDim2.new(0,18,0,64), Size = UDim2.new(1,-36,0,16), BackgroundColor3 = Theme.Card, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 252})
    corner(bg, 8)
    stroke(bg, Theme.Black, 1, 0.4)
    LoadingBar = new("Frame", {Parent = bg, Position = UDim2.new(-0.55,0,0,0), Size = UDim2.new(0.35,0,1,0), BackgroundColor3 = Theme.Orange, BorderSizePixel = 0, ZIndex = 253})
    corner(LoadingBar, 8)
    task.spawn(function()
        while LoadingActive and LoadingBar and LoadingBar.Parent do
            LoadingBar.Position = UDim2.new(-0.55,0,0,0)
            tween(LoadingBar, {Position = UDim2.new(1.15,0,0,0)}, 0.9)
            task.wait(0.95)
        end
    end)
end

---------------------------------------------------------------------
-- CATALOG SEARCH / RESOLVE
---------------------------------------------------------------------

local function searchCatalog(kind, keyword, append)
    keyword = tostring(keyword or "")
    if keyword == "" then keyword = kind == "Emote" and "dance" or "animation" end

    local encoded = HttpService:UrlEncode(keyword)
    local cursor = kind == "Emote" and NextEmoteCursor or NextBundleCursor
    if not append then
        if kind == "Emote" then
            EmoteResults = {}
            NextEmoteCursor = nil
        else
            BundleResults = {}
            NextBundleCursor = nil
        end
        cursor = nil
    end

    local cursorParam = cursor and ("&Cursor=" .. HttpService:UrlEncode(cursor)) or ""
    local subcategory = kind == "Emote" and "39" or "38"
    local url = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=" .. subcategory .. "&Keyword=" .. encoded .. "&Limit=30&SortType=0" .. cursorParam
    local data = decodeJson(httpGet(url))

    if not data and kind == "Bundle" then
        local url2 = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=27&Keyword=" .. encoded .. "&Limit=30&SortType=0" .. cursorParam
        data = decodeJson(httpGet(url2))
    end

    if not data or type(data.data) ~= "table" then return false, 0 end

    if kind == "Emote" then
        LastEmoteKeyword = keyword
        for _, item in ipairs(data.data) do table.insert(EmoteResults, item) end
        NextEmoteCursor = data.nextPageCursor
        return true, #EmoteResults
    else
        LastBundleKeyword = keyword
        for _, item in ipairs(data.data) do table.insert(BundleResults, item) end
        NextBundleCursor = data.nextPageCursor
        return true, #BundleResults
    end
end

local function fetchBundleDetails(bundleId)
    bundleId = normalizeId(bundleId)
    if bundleId == "" then return nil end
    return decodeJson(httpGet("https://catalog.roblox.com/v1/bundles/" .. bundleId .. "/details"))
end

local function categorizeAnimation(pathText)
    pathText = string.lower(tostring(pathText or ""))
    if string.find(pathText, "idle", 1, true) then return "Idle" end
    if string.find(pathText, "walk", 1, true) then return "Walk" end
    if string.find(pathText, "run", 1, true) then return "Run" end
    if string.find(pathText, "jump", 1, true) then return "Jump" end
    if string.find(pathText, "fall", 1, true) then return "Fall" end
    if string.find(pathText, "climb", 1, true) then return "Climb" end
    if string.find(pathText, "swim", 1, true) then return "Swim" end
    return nil
end

local function scanAnimationTree(root, path, output)
    for _, child in ipairs(root:GetChildren()) do
        local newPath = path .. "." .. child.Name
        if child:IsA("Animation") then
            local id = normalizeId(child.AnimationId)
            local state = categorizeAnimation(newPath)
            if id ~= "" and state and not output[state] then output[state] = id end
        end
        if #child:GetChildren() > 0 then
            scanAnimationTree(child, newPath, output)
        end
    end
end

local function resolveAnimationsFromAsset(assetId)
    assetId = normalizeId(assetId)
    if assetId == "" then return {} end
    if AnimationObjectCache[assetId] then return AnimationObjectCache[assetId] end
    local found = {}
    local ok, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. assetId)
    end)
    if ok and objects then
        for _, obj in ipairs(objects) do
            scanAnimationTree(obj, obj.Name, found)
            pcall(function() obj:Destroy() end)
        end
    end
    AnimationObjectCache[assetId] = found
    return found
end

local function extractAnimationsFromBundle(details)
    local form = {}
    if not details then return form end
    local items = details.items or details.Items or {}
    for _, item in ipairs(items) do
        local itemId = tostring(item.id or item.Id or "")
        local resolved = resolveAnimationsFromAsset(itemId)
        for state, id in pairs(resolved) do
            if not form[state] then form[state] = id end
        end
    end
    local assetTypeToState = {[48]="Climb", [50]="Fall", [51]="Idle", [52]="Jump", [53]="Run", [54]="Swim", [55]="Walk"}
    for _, item in ipairs(items) do
        local id = tostring(item.id or item.Id or "")
        local assetType = tonumber(item.assetType or item.AssetType or item.assetTypeId or item.AssetTypeId)
        local state = assetTypeToState[assetType] or categorizeAnimation(item.name or item.Name)
        if state and not form[state] then form[state] = id end
    end
    return form
end

---------------------------------------------------------------------
-- APPLY BUNDLE / EMOTE
---------------------------------------------------------------------

local function getAnimationsForState(state)
    local _, _, animate = getCharHum()
    if not animate then return {} end
    local result = {}
    for _, child in ipairs(animate:GetChildren()) do
        local lowerName = string.lower(child.Name)
        for _, expected in ipairs(AnimateNames[state] or {}) do
            if lowerName == expected then
                if child:IsA("Animation") then table.insert(result, child) end
                for _, d in ipairs(child:GetDescendants()) do if d:IsA("Animation") then table.insert(result, d) end end
            end
        end
    end
    return result
end

local function captureOriginals()
    OriginalIds = {}
    for _, state in ipairs(States) do
        OriginalIds[state] = {}
        for _, anim in ipairs(getAnimationsForState(state)) do
            table.insert(OriginalIds[state], anim.AnimationId)
        end
    end
end

local function restartAnimate()
    local _, _, animate = getCharHum()
    if animate then
        pcall(function()
            animate.Disabled = true
            task.wait(0.10)
            animate.Disabled = false
        end)
    end
end

local function setStateAnimation(state, id)
    id = normalizeId(id)
    if id == "" then return false end
    local anims = getAnimationsForState(state)
    if #anims <= 0 then return false end
    for _, anim in ipairs(anims) do anim.AnimationId = toAnimUrl(id) end
    return true
end

local function applyDescriptionAnimations()
    local _, hum = getCharHum()
    if not hum then return 0 end
    local props = {Idle="IdleAnimation", Walk="WalkAnimation", Run="RunAnimation", Jump="JumpAnimation", Fall="FallAnimation", Climb="ClimbAnimation", Swim="SwimAnimation"}
    local changed = 0
    pcall(function()
        local desc = hum:GetAppliedDescription()
        for state, prop in pairs(props) do
            local id = normalizeId(CurrentForm[state])
            if id ~= "" then
                desc[prop] = tonumber(id) or 0
                changed = changed + 1
            end
        end
        hum:ApplyDescription(desc)
    end)
    return changed
end

local function applyCurrentForm(name)
    local changed = 0
    local descChanged = 0
    if ApplyMethod == "Animate" or ApplyMethod == "Both" then
        for _, state in ipairs(States) do
            if normalizeId(CurrentForm[state]) ~= "" and setStateAnimation(state, CurrentForm[state]) then changed = changed + 1 end
        end
    end
    if ApplyMethod == "Description" or ApplyMethod == "Both" then descChanged = applyDescriptionAnimations() end
    restartAnimate()
    if name then LastAppliedName = name end
    saveData()
    status("Applied " .. tostring(name or LastAppliedName or "pack") .. " | " .. tostring(changed) .. " states", changed > 0 or descChanged > 0)
end

local function applyBundleFull(bundleId, bundleName)
    showLoading("Resolving bundle...")
    task.spawn(function()
        local details = fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Bundle details failed", false); return end
        local form = extractAnimationsFromBundle(details)
        local count = 0
        for _, state in ipairs(States) do
            CurrentForm[state] = form[state] or ""
            SlotMeta[state] = CurrentForm[state] ~= "" and {Bundle=bundleName or details.name or "Bundle", BundleId=normalizeId(bundleId), Id=CurrentForm[state]} or nil
            if CurrentForm[state] ~= "" then count = count + 1 end
        end
        hideLoading()
        if count <= 0 then status("No animations found in bundle", false); return end
        LastAppliedName = bundleName or details.name or "Bundle"
        applyCurrentForm(LastAppliedName)
    end)
end

local function setCustomSlotFromBundle(state, bundleId, bundleName)
    showLoading("Setting " .. state .. "...")
    task.spawn(function()
        local details = fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Bundle details failed", false); return end
        local form = extractAnimationsFromBundle(details)
        hideLoading()
        local id = form[state]
        if normalizeId(id) == "" then status("This bundle has no " .. state .. " animation", false); return end
        CurrentForm[state] = id
        SlotMeta[state] = {Bundle=bundleName or details.name or "Bundle", BundleId=normalizeId(bundleId), Id=id}
        ChoosingState = nil
        saveData()
        status("Set " .. state .. " from " .. tostring(bundleName or details.name), true)
        renderCustom()
    end)
end

local function restoreOriginal()
    for _, state in ipairs(States) do
        local originals = OriginalIds[state]
        local anims = getAnimationsForState(state)
        if originals and #originals > 0 then
            for i, anim in ipairs(anims) do anim.AnimationId = originals[i] or originals[1] end
        end
    end
    restartAnimate()
    status("Original animations restored", true)
end

local function stopEmote()
    if CurrentEmoteTrack then
        pcall(function()
            CurrentEmoteTrack:Stop(0.15)
            CurrentEmoteTrack:Destroy()
        end)
        CurrentEmoteTrack = nil
    end
end

local function playEmote(assetId, name)
    local _, hum = getCharHum()
    if not hum then status("Humanoid not found", false); return end
    stopEmote()
    local anim = Instance.new("Animation")
    anim.AnimationId = toAnimUrl(assetId)
    local ok, track = pcall(function() return hum:LoadAnimation(anim) end)
    if not ok or not track then status("Emote failed. It may be private or incompatible.", false); return end
    CurrentEmoteTrack = track
    pcall(function()
        track.Priority = MoveWhileEmote and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action4
        track.Looped = EmoteLoop
        track:Play(0.15, 1, EmoteSpeed)
    end)
    status("Playing emote: " .. tostring(name or assetId), true)
end

---------------------------------------------------------------------
-- VIEWPORT PREVIEW + INFO MODAL
---------------------------------------------------------------------

local function createAvatarPreview(parent, animId)
    local viewport = new("ViewportFrame", {Parent=parent, Position=UDim2.new(0,18,0,18), Size=UDim2.new(0,132,0,112), BackgroundColor3=Theme.Field, BorderSizePixel=0, Ambient=Color3.fromRGB(180,180,180), LightColor=Color3.fromRGB(255,255,255), ZIndex=202})
    corner(viewport, 10); stroke(viewport, Theme.Black, 1, 0.25)
    local world = Instance.new("WorldModel"); world.Parent = viewport
    local char = LocalPlayer.Character
    if not char then return viewport end
    local oldArch = char.Archivable
    pcall(function() char.Archivable = true end)
    local clone
    pcall(function() clone = char:Clone() end)
    pcall(function() char.Archivable = oldArch end)
    if not clone then return viewport end
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
    end
    clone.Parent = world
    local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if root then
        clone.PrimaryPart = root
        pcall(function()
            root.Anchored = true
            clone:SetPrimaryPartCFrame(CFrame.new(0,0,0) * CFrame.Angles(0, math.rad(180), 0))
        end)
    end
    local cam = Instance.new("Camera")
    cam.Parent = viewport
    viewport.CurrentCamera = cam
    cam.CFrame = CFrame.new(Vector3.new(0,2.2,6), Vector3.new(0,1.5,0))
    local hum = clone:FindFirstChildOfClass("Humanoid")
    if hum and normalizeId(animId) ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = toAnimUrl(animId)
        local ok, track = pcall(function() return hum:LoadAnimation(anim) end)
        if ok and track then
            pcall(function()
                track.Looped = true
                track:Play(0.1, 1, EmoteSpeed)
            end)
        end
    end
    return viewport
end

local function closeInfoModal()
    if not ModalCard then return end
    local card = ModalCard
    local dim = ModalDim
    ModalCard = nil
    ModalDim = nil
    tween(card, {Size=UDim2.new(0,20,0,20), BackgroundTransparency=1}, 0.13)
    if dim then tween(dim, {BackgroundTransparency=1}, 0.13) end
    task.delay(0.15, function()
        if card then card:Destroy() end
        if dim then dim:Destroy() end
    end)
end

local function showInfoModal(titleText, bodyText, imageId, actions, previewAnimId)
    closeInfoModal()
    ModalDim = new("Frame", {Parent=ScreenGui, Position=UDim2.new(0,0,0,0), Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Black, BackgroundTransparency=1, BorderSizePixel=0, ZIndex=200})
    tween(ModalDim, {BackgroundTransparency=ModalDimTransparency}, 0.16)
    ModalCard = new("Frame", {Parent=ScreenGui, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,20,0,20), BackgroundColor3=Theme.Page, BorderSizePixel=0, ZIndex=201})
    corner(ModalCard, 16)
    stroke(ModalCard, Theme.Black, 2, 0)
    tween(ModalCard, {Size=UDim2.new(0,440,0,318)}, 0.18)
    task.delay(0.03, function()
        if not ModalCard then return end
        if previewAnimId then
            createAvatarPreview(ModalCard, previewAnimId)
        else
            local img = new("ImageLabel", {Parent=ModalCard, Position=UDim2.new(0,18,0,18), Size=UDim2.new(0,132,0,112), BackgroundColor3=Theme.Field, BorderSizePixel=0, Image=imageId or "", ScaleType=Enum.ScaleType.Fit, ZIndex=202})
            corner(img, 10)
            stroke(img, Theme.Black, 1, 0.25)
        end
        makeLabel(ModalCard, titleText or "Info", UDim2.new(0,166,0,20), UDim2.new(1,-190,0,42), 18, Theme.Text)
        makeLabel(ModalCard, bodyText or "No information.", UDim2.new(0,166,0,66), UDim2.new(1,-184,0,172), 13, Theme.Muted)
        makeButton(ModalCard, "X", UDim2.new(1,-42,0,12), UDim2.new(0,28,0,28), closeInfoModal, Theme.Red, true)
        makeButton(ModalCard, "CLOSE", UDim2.new(0,18,1,-48), UDim2.new(0,88,0,30), closeInfoModal, Theme.Red, true)
        local x = 116
        for _, act in ipairs(actions or {}) do
            makeButton(ModalCard, act.Text or "OK", UDim2.new(0,x,1,-48), UDim2.new(0,96,0,30), function()
                if act.Callback then act.Callback() end
                if act.Close ~= false then closeInfoModal() end
            end, act.Color or Theme.Cyan, true)
            x = x + 104
        end
    end)
end

---------------------------------------------------------------------
-- PAGES
---------------------------------------------------------------------

local renderHome, renderCustom, renderFavorites, renderSave, renderSettings

local function setPage(page)
    CurrentPage = page
    disconnectList(PageConnections)
    clear(Body)
    if HeaderTitle then HeaderTitle.Text = page == "Bundles" and "Irenk Bundle Hub" or page end
    if Body then
        Body.Position = UDim2.new(0, 18, 0, 82)
        task.delay(0.02, function()
            if Body then tween(Body, {Position = UDim2.new(0, 12, 0, 66)}, 0.16) end
        end)
    end
end

local function tabs()
    makeButton(Body, "BUNDLES", UDim2.new(0,12,0,8), UDim2.new(0,82,0,32), function() renderHome("Bundle") end, CurrentPage=="Bundles" and Theme.Cyan or Theme.Card)
    makeButton(Body, "EMOTES", UDim2.new(0,102,0,8), UDim2.new(0,78,0,32), function() renderHome("Emote") end, CurrentPage=="Emotes" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CUSTOM", UDim2.new(0,188,0,8), UDim2.new(0,84,0,32), function() renderCustom() end, CurrentPage=="Custom" and Theme.Cyan or Theme.Card)
    makeButton(Body, "FAVS", UDim2.new(0,280,0,8), UDim2.new(0,64,0,32), function() renderFavorites() end, CurrentPage=="Favorites" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SAVE", UDim2.new(0,352,0,8), UDim2.new(0,64,0,32), function() renderSave() end, CurrentPage=="Save" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SET", UDim2.new(0,424,0,8), UDim2.new(0,56,0,32), function() renderSettings() end, CurrentPage=="Settings" and Theme.Cyan or Theme.Card)
end

local function isFavorite(list, id)
    id = tostring(id)
    for _, item in ipairs(list) do
        if tostring(item.id) == id then return true end
    end
    return false
end

local function toggleFavorite(kind, item)
    local list = kind == "Emote" and FavoritesEmotes or FavoritesBundles
    local id = tostring(item.id or item.Id or "")
    for i, fav in ipairs(list) do
        if tostring(fav.id) == id then
            table.remove(list, i)
            saveData()
            status("Removed favorite", true)
            return
        end
    end
    table.insert(list, {id=id, name=tostring(item.name or item.Name or (kind .. " " .. id)), kind=kind})
    saveData()
    status("Added favorite", true)
end

local function renderItemCard(parent, item, index, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = 12 + col * 250
    local y = 12 + row * 142
    local card = makePanel(parent, UDim2.new(0,x,0,y), UDim2.new(0,238,0,130), Theme.Card)
    local imgId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img = new("ImageLabel", {Parent=card, Position=UDim2.new(0,10,0,10), Size=UDim2.new(0,80,0,72), BackgroundColor3=Theme.Field, BorderSizePixel=0, Image=imgId, ScaleType=Enum.ScaleType.Fit, ZIndex=20})
    corner(img, 8)
    makeLabel(card, name, UDim2.new(0,100,0,12), UDim2.new(1,-110,0,44), 13, Theme.Text)
    makeLabel(card, kind .. " ID: " .. id, UDim2.new(0,100,0,58), UDim2.new(1,-110,0,20), 11, Theme.Muted)
    makeButton(card, kind == "Emote" and "PLAY" or (ChoosingState and ("SET "..string.upper(ChoosingState)) or "APPLY"), UDim2.new(0,10,1,-36), UDim2.new(0,92,0,26), function()
        if kind == "Emote" then
            playEmote(id, name)
        else
            if ChoosingState then setCustomSlotFromBundle(ChoosingState, id, name) else applyBundleFull(id, name) end
        end
    end, kind == "Emote" and Theme.Green or Theme.Orange)
    makeButton(card, "INFO", UDim2.new(0,110,1,-36), UDim2.new(0,58,0,26), function()
        local body = kind .. ": " .. name .. "\nID: " .. id .. "\nLink: https://www.roblox.com/catalog/" .. id .. "\n\n" .. (kind == "Emote" and "This popup previews your own avatar with the emote before playing." or (ChoosingState and ("Will be set to: " .. ChoosingState) or "Apply full bundle or use Custom page for mix."))
        local actions = {}
        if kind == "Emote" then
            table.insert(actions, {Text="PLAY", Color=Theme.Green, Callback=function() playEmote(id, name) end, Close=false})
        else
            table.insert(actions, {Text=ChoosingState and "SET" or "APPLY", Color=Theme.Green, Callback=function() if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end})
        end
        table.insert(actions, {Text="FAV", Color=Theme.Yellow, Callback=function() toggleFavorite(kind, item) end, Close=false})
        showInfoModal(name, body, imgId, actions, kind == "Emote" and id or nil)
    end, Theme.Cyan)
    makeButton(card, isFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "★" or "☆", UDim2.new(0,176,1,-36), UDim2.new(0,42,0,26), function()
        toggleFavorite(kind, item)
        if CurrentPage == "Bundles" then renderHome("Bundle") elseif CurrentPage == "Emotes" then renderHome("Emote") end
    end, Theme.Yellow)
end

renderHome = function(kind)
    kind = kind or (CurrentPage == "Emotes" and "Emote" or "Bundle")
    setPage(kind == "Emote" and "Emotes" or "Bundles")
    tabs()
    local placeholder = kind == "Emote" and "Search emotes: dance, pose, laugh..." or "Search bundles: ninja, robot, zombie..."
    local searchBox = makeBox(Body, placeholder, UDim2.new(0,12,0,52), UDim2.new(1,-146,0,38))
    searchBox.Text = kind == "Emote" and (LastEmoteKeyword ~= "dance" and LastEmoteKeyword or "") or (LastBundleKeyword ~= "animation" and LastBundleKeyword or "")
    makeButton(Body, "SEARCH", UDim2.new(1,-124,0,52), UDim2.new(0,112,0,38), function()
        showLoading("Loading " .. string.lower(kind) .. "s...")
        task.spawn(function()
            local ok, count = searchCatalog(kind, searchBox.Text, false)
            hideLoading()
            if ok then renderHome(kind); status("Loaded " .. tostring(count) .. " " .. string.lower(kind) .. "s", true) else status("Search failed", false) end
        end)
    end, Theme.Cyan)
    makeLabel(Body, kind == "Emote" and "Tap INFO to preview your avatar before playing." or (ChoosingState and ("Choosing: " .. ChoosingState .. " | tap a card to set it.") or "Apply full bundle or use Custom to mix slots."), UDim2.new(0,12,0,96), UDim2.new(1,-24,0,24), 12, kind == "Bundle" and ChoosingState and Theme.Red or Theme.Muted)
    local scroll = new("ScrollingFrame", {Parent=Body, Position=UDim2.new(0,12,0,124), Size=UDim2.new(1,-24,1,-162), BackgroundColor3=Theme.Page, BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=Theme.Orange, CanvasSize=UDim2.new(0,0,0,380), ZIndex=19})
    corner(scroll, 10); stroke(scroll, Theme.Black, 1, 0.35)
    local list = kind == "Emote" and EmoteResults or BundleResults
    if #list == 0 then
        makeLabel(scroll, "Loading popular " .. string.lower(kind) .. "s...", UDim2.new(0,16,0,16), UDim2.new(0,300,0,30), 16, Theme.Muted)
        task.spawn(function()
            task.wait(0.15)
            local ok = searchCatalog(kind, kind == "Emote" and LastEmoteKeyword or LastBundleKeyword, false)
            if ok and Body and CurrentPage == (kind == "Emote" and "Emotes" or "Bundles") then
                renderHome(kind)
            end
        end)
    else
        for i, item in ipairs(list) do renderItemCard(scroll, item, i, kind) end
        local rows = math.ceil(#list / 2)
        scroll.CanvasSize = UDim2.new(0,0,0,math.max(360, rows*142 + 62))
        local hasNext = kind == "Emote" and NextEmoteCursor or NextBundleCursor
        if hasNext then
            makeLabel(scroll, "Scroll to bottom to load more...", UDim2.new(0,16,0,rows*142+18), UDim2.new(0,260,0,30), 13, Theme.Muted)
            add(PageConnections, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if LoadingMore then return end
                local bottom = scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y
                local limit = scroll.CanvasSize.Y.Offset - 45
                if bottom >= limit then
                    LoadingMore = true
                    showLoading("Loading more " .. string.lower(kind) .. "s...")
                    task.spawn(function()
                        local ok = searchCatalog(kind, kind == "Emote" and LastEmoteKeyword or LastBundleKeyword, true)
                        hideLoading()
                        LoadingMore = false
                        if ok then renderHome(kind) end
                    end)
                end
            end))
        end
    end
end

renderCustom = function()
    setPage("Custom"); tabs()
    makeLabel(Body, "Customize or mix your animation pack", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    local scroll = new("ScrollingFrame", {Parent=Body, Position=UDim2.new(0,12,0,86), Size=UDim2.new(1,-24,1,-124), BackgroundColor3=Theme.Page, BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=Theme.Orange, CanvasSize=UDim2.new(0,0,0,430), ZIndex=19})
    corner(scroll, 10); stroke(scroll, Theme.Black, 1, 0.35)
    local y = 12
    for _, state in ipairs(States) do
        local panel = makePanel(scroll, UDim2.new(0,12,0,y), UDim2.new(1,-34,0,50), Theme.Card)
        makeLabel(panel, state, UDim2.new(0,10,0,4), UDim2.new(0,62,0,42), 14, Theme.Text)
        local meta = SlotMeta[state]
        makeLabel(panel, meta and ((meta.Bundle or "Bundle") .. " | ID " .. tostring(meta.Id or "")) or "not set", UDim2.new(0,80,0,4), UDim2.new(1,-248,0,42), 12, meta and Theme.Muted or Theme.LightMuted)
        makeButton(panel, "SET", UDim2.new(1,-158,0,10), UDim2.new(0,46,0,30), function() ChoosingState = state; renderHome("Bundle") end, Theme.Green)
        makeButton(panel, "INFO", UDim2.new(1,-106,0,10), UDim2.new(0,58,0,30), function()
            local body = meta and ("State: "..state.."\nBundle: "..tostring(meta.Bundle).."\nBundle ID: "..tostring(meta.BundleId).."\nAnimation ID: "..tostring(meta.Id)) or ("State: "..state.."\nNo animation selected yet.")
            showInfoModal("Custom Slot: "..state, body, meta and bundleThumbnail(meta.BundleId) or "", {})
        end, Theme.Cyan)
        makeButton(panel, "X", UDim2.new(1,-40,0,10), UDim2.new(0,28,0,30), function() CurrentForm[state]=""; SlotMeta[state]=nil; saveData(); renderCustom() end, Theme.Red)
        y = y + 58
    end
    local saveNameBox = makeBox(scroll, "Save as name...", UDim2.new(0,12,0,y+8), UDim2.new(0,160,0,34))
    makeButton(scroll, "APPLY CUSTOM", UDim2.new(0,184,0,y+8), UDim2.new(0,130,0,34), function() LastAppliedName="Custom Mix"; applyCurrentForm("Custom Mix") end, Theme.Orange)
    makeButton(scroll, "SAVE MIX", UDim2.new(0,326,0,y+8), UDim2.new(0,96,0,34), function()
        local nm = tostring(saveNameBox.Text or "")
        if nm == "" then nm = "Custom Mix " .. tostring(#SavedPacks + 1) end
        if EditingSaveIndex and SavedPacks[EditingSaveIndex] then
            SavedPacks[EditingSaveIndex] = {Name=nm, Form=tableCopy(CurrentForm), Meta=tableCopy(SlotMeta)}
            EditingSaveIndex = nil
            status("Saved edit: " .. nm, true)
        else
            table.insert(SavedPacks, {Name=nm, Form=tableCopy(CurrentForm), Meta=tableCopy(SlotMeta)})
            status("Saved mix: " .. nm, true)
        end
        saveData(); renderCustom()
    end, Theme.Green)
    makeButton(scroll, "CLEAR", UDim2.new(0,434,0,y+8), UDim2.new(0,70,0,34), function() for _,st in ipairs(States) do CurrentForm[st]=""; SlotMeta[st]=nil end; EditingSaveIndex=nil; saveData(); renderCustom() end, Theme.Red)
    scroll.CanvasSize = UDim2.new(0,0,0,y+70)
end

renderFavorites = function()
    setPage("Favorites"); tabs()
    makeLabel(Body, "Favorite bundles and emotes", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    local scroll = new("ScrollingFrame", {Parent=Body, Position=UDim2.new(0,12,0,86), Size=UDim2.new(1,-24,1,-124), BackgroundColor3=Theme.Page, BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=Theme.Orange, CanvasSize=UDim2.new(0,0,0,380), ZIndex=19})
    corner(scroll,10); stroke(scroll,Theme.Black,1,0.35)
    local idx = 1
    for _, fav in ipairs(FavoritesBundles) do renderItemCard(scroll, fav, idx, "Bundle"); idx = idx + 1 end
    for _, fav in ipairs(FavoritesEmotes) do renderItemCard(scroll, fav, idx, "Emote"); idx = idx + 1 end
    scroll.CanvasSize = UDim2.new(0,0,0,math.max(360, math.ceil((idx-1)/2)*142+62))
end

renderSave = function()
    setPage("Save"); tabs()
    makeLabel(Body, "Save / Auto-load your current pack", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    local nameBox = makeBox(Body, "Name save as...", UDim2.new(0,12,0,84), UDim2.new(0,220,0,36))
    makeButton(Body, "SAVE CURRENT", UDim2.new(0,244,0,84), UDim2.new(0,140,0,36), function()
        local name = tostring(nameBox.Text or ""); if name == "" then name = "Saved Pack " .. tostring(#SavedPacks+1) end
        table.insert(SavedPacks, {Name=name, Form=tableCopy(CurrentForm), Meta=tableCopy(SlotMeta)})
        saveData(); renderSave(); status("Saved: "..name, true)
    end, Theme.Green)
    local scroll = new("ScrollingFrame", {Parent=Body, Position=UDim2.new(0,12,0,132), Size=UDim2.new(1,-24,1,-170), BackgroundColor3=Theme.Page, BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=Theme.Orange, CanvasSize=UDim2.new(0,0,0,360), ZIndex=19})
    corner(scroll,10); stroke(scroll,Theme.Black,1,0.35)
    local y = 12
    for i, pack in ipairs(SavedPacks) do
        local panel = makePanel(scroll, UDim2.new(0,12,0,y), UDim2.new(1,-34,0,58), Theme.Card)
        local name = tostring(pack.Name or ("Pack "..i)); local auto = AutoLoadName == name and " [AUTO]" or ""
        makeLabel(panel, name..auto, UDim2.new(0,10,0,5), UDim2.new(1,-250,0,22), 14, Theme.Text)
        makeLabel(panel, "Use, edit, delete, or set autoload.", UDim2.new(0,10,0,30), UDim2.new(1,-250,0,20), 11, Theme.Muted)
        makeButton(panel, "AUTO", UDim2.new(1,-228,0,14), UDim2.new(0,52,0,30), function() AutoLoadName=name; AutoLoad=true; saveData(); renderSave() end, AutoLoadName==name and Theme.Green or Theme.Cyan)
        makeButton(panel, "USE", UDim2.new(1,-168,0,14), UDim2.new(0,48,0,30), function() CurrentForm=tableCopy(pack.Form); SlotMeta=tableCopy(pack.Meta); LastAppliedName=name; applyCurrentForm(name) end, Theme.Orange)
        makeButton(panel, "EDIT", UDim2.new(1,-112,0,14), UDim2.new(0,52,0,30), function() CurrentForm=tableCopy(pack.Form); SlotMeta=tableCopy(pack.Meta); EditingSaveIndex=i; renderCustom() end, Theme.Cyan)
        makeButton(panel, "DEL", UDim2.new(1,-52,0,14), UDim2.new(0,40,0,30), function() table.remove(SavedPacks,i); saveData(); renderSave() end, Theme.Red)
        y = y + 66
    end
    scroll.CanvasSize = UDim2.new(0,0,0,math.max(360,y+20))
end

renderSettings = function()
    setPage("Settings"); tabs()
    makeLabel(Body, "Settings", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    makeLabel(Body, "Emote Speed", UDim2.new(0,12,0,90), UDim2.new(0,160,0,24), 13, Theme.Muted)
    local speedBox = makeBox(Body, "Type any speed: 1, 1.5, 2, 100...", UDim2.new(0,12,0,120), UDim2.new(0,230,0,34))
    speedBox.Text = tostring(EmoteSpeed)
    makeButton(Body, "APPLY SPEED", UDim2.new(0,254,0,120), UDim2.new(0,122,0,34), function()
        local n = tonumber(speedBox.Text)
        if not n then status("Invalid speed number", false); return end
        EmoteSpeed = n
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end
        saveData(); status("Emote speed set to "..tostring(EmoteSpeed).."x", true); renderSettings()
    end, Theme.Green)
    makeButton(Body, "1x", UDim2.new(0,386,0,120), UDim2.new(0,48,0,34), function() EmoteSpeed=1; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end; saveData(); renderSettings() end, EmoteSpeed==1 and Theme.Green or Theme.Card)
    makeButton(Body, "+0.5", UDim2.new(0,442,0,120), UDim2.new(0,56,0,34), function() EmoteSpeed=EmoteSpeed+0.5; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end; saveData(); renderSettings() end, Theme.Card)
    makeLabel(Body, "Current speed: " .. tostring(EmoteSpeed) .. "x", UDim2.new(0,12,0,158), UDim2.new(1,-24,0,22), 12, Theme.Muted)
    makeButton(Body, EmoteLoop and "LOOP: ON" or "LOOP: OFF", UDim2.new(0,12,0,190), UDim2.new(0,130,0,34), function() EmoteLoop=not EmoteLoop; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack.Looped=EmoteLoop end) end; saveData(); renderSettings() end, EmoteLoop and Theme.Green or Theme.Card)
    makeButton(Body, MoveWhileEmote and "MOVE: ON" or "MOVE: OFF", UDim2.new(0,154,0,190), UDim2.new(0,130,0,34), function() MoveWhileEmote=not MoveWhileEmote; saveData(); renderSettings() end, MoveWhileEmote and Theme.Green or Theme.Card)
    makeLabel(Body, "Modal background transparency", UDim2.new(0,12,0,240), UDim2.new(1,-24,0,24), 13, Theme.Muted)
    local dims = {{"25%",0.25},{"45%",0.45},{"65%",0.65},{"80%",0.80}}
    local x = 12
    for _, d in ipairs(dims) do
        makeButton(Body, d[1], UDim2.new(0,x,0,270), UDim2.new(0,70,0,34), function() ModalDimTransparency=d[2]; saveData(); renderSettings() end, math.abs(ModalDimTransparency-d[2])<0.01 and Theme.Green or Theme.Card)
        x = x + 80
    end
    makeLabel(Body, "Apply Method", UDim2.new(0,12,0,320), UDim2.new(0,160,0,24), 13, Theme.Muted)
    makeButton(Body, "ANIMATE", UDim2.new(0,12,0,350), UDim2.new(0,100,0,34), function() ApplyMethod="Animate"; saveData(); renderSettings() end, ApplyMethod=="Animate" and Theme.Green or Theme.Card)
    makeButton(Body, "DESCRIPTION", UDim2.new(0,124,0,350), UDim2.new(0,130,0,34), function() ApplyMethod="Description"; saveData(); renderSettings() end, ApplyMethod=="Description" and Theme.Green or Theme.Card)
    makeButton(Body, "BOTH", UDim2.new(0,266,0,350), UDim2.new(0,90,0,34), function() ApplyMethod="Both"; saveData(); renderSettings() end, ApplyMethod=="Both" and Theme.Green or Theme.Card)
    makeButton(Body, AutoLoad and "AUTOLOAD: ON" or "AUTOLOAD: OFF", UDim2.new(0,12,0,410), UDim2.new(0,150,0,34), function() AutoLoad=not AutoLoad; saveData(); renderSettings() end, AutoLoad and Theme.Green or Theme.Card)
    makeButton(Body, "STOP EMOTE", UDim2.new(0,174,0,410), UDim2.new(0,120,0,34), stopEmote, Theme.Red)
    makeButton(Body, "RESET ORIGINAL", UDim2.new(0,306,0,410), UDim2.new(0,140,0,34), restoreOriginal, Theme.Yellow)
end

---------------------------------------------------------------------
-- ICON ART + GUI CREATE
---------------------------------------------------------------------

local function drawPixelIcon(parent)
    local grid = {"000011110000","000111111000","001111111100","011112211110","011122221110","111233332111","112333333211","112393393211","112333333211","011233332110","001122221100","000111111000"}
    local colors = {['1']=Color3.fromRGB(10,22,58), ['2']=Color3.fromRGB(34,50,96), ['3']=Color3.fromRGB(232,132,166), ['9']=Color3.fromRGB(255,42,70)}
    local holder = new("Frame", {Parent=parent, Position=UDim2.new(0,7,0,7), Size=UDim2.new(1,-14,1,-14), BackgroundTransparency=1, Active=false, ZIndex=82})
    local n = 12
    for yy,row in ipairs(grid) do
        for xx=1,n do
            local col = colors[string.sub(row,xx,xx)]
            if col then new("Frame", {Parent=holder, Position=UDim2.new((xx-1)/n,0,(yy-1)/n,0), Size=UDim2.new(1/n,1,1/n,1), BackgroundColor3=col, BorderSizePixel=0, Active=false, ZIndex=83}) end
        end
    end
end

local function createGui()
    local pg = getParentGui()
    pcall(function()
        for _, name in ipairs({"IrenkAnimHubRewriteFinal", "FE_BUNDLE_V9", "IrenkBundleEmoteHubV8InfoSaweria", "IrenkBundleEmoteHubV83InfoSaweria", "IrenkBundleEmoteHubV84OpenFix", "IrenkBundleEmoteHubV85OpenFix"}) do
            local old = pg:FindFirstChild(name)
            if old then old:Destroy() end
        end
    end)
    ScreenGui = new("ScreenGui", {Name="FE_BUNDLE_V9", ResetOnSpawn=false, IgnoreGuiInset=true, DisplayOrder=999999, ZIndexBehavior=Enum.ZIndexBehavior.Global})
    ScreenGui.Parent = pg

    IconButton = new("TextButton", {Parent=ScreenGui, Position=UDim2.new(0,18,0.5,-30), Size=UDim2.new(0,58,0,58), BackgroundColor3=Theme.Orange, BorderSizePixel=0, Text="", AutoButtonColor=true, Active=true, ZIndex=80})
    corner(IconButton, 14); stroke(IconButton, Theme.Black, 2, 0); drawPixelIcon(IconButton)

    Main = new("Frame", {Parent=ScreenGui, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,570,0,535), BackgroundColor3=Theme.Page, BorderSizePixel=0, Visible=true, Active=true, ZIndex=10})
    corner(Main, 14); stroke(Main, Theme.Black, 2, 0)
    local header = new("Frame", {Parent=Main, Position=UDim2.new(0,0,0,0), Size=UDim2.new(1,0,0,58), BackgroundColor3=Theme.Orange, BorderSizePixel=0, ZIndex=11})
    corner(header, 14); new("Frame", {Parent=header, Position=UDim2.new(0,0,1,-14), Size=UDim2.new(1,0,0,14), BackgroundColor3=Theme.Orange, BorderSizePixel=0, ZIndex=11})
    HeaderTitle = makeLabel(Main, "Irenk Bundle Hub", UDim2.new(0,18,0,8), UDim2.new(1,-88,0,28), 21, Theme.Text)
    makeLabel(Main, "bundles, emotes, custom mix, favorites", UDim2.new(0,18,0,34), UDim2.new(1,-100,0,18), 12, Theme.Muted)
    local close = new("TextButton", {Parent=Main, Position=UDim2.new(1,-48,0,12), Size=UDim2.new(0,34,0,32), BackgroundColor3=Theme.Red, BorderSizePixel=0, Text="X", TextColor3=Theme.Text, Font=Enum.Font.GothamBold, TextSize=14, ZIndex=120})
    corner(close,8); stroke(close, Theme.Black, 1, 0)
    add(Connections, close.MouseButton1Click:Connect(function() Alive=false; stopEmote(); disconnectList(Connections); disconnectList(PageConnections); if ScreenGui then ScreenGui:Destroy() end end))
    Body = new("Frame", {Parent=Main, Position=UDim2.new(0,12,0,66), Size=UDim2.new(1,-24,1,-104), BackgroundTransparency=1, ZIndex=18})
    StatusLabel = makeLabel(Main, "Ready", UDim2.new(0,16,1,-34), UDim2.new(1,-32,0,24), 12, Theme.Muted)

    local headerDrag = new("TextButton", {Parent=Main, Position=UDim2.new(0,0,0,0), Size=UDim2.new(1,-58,0,58), BackgroundTransparency=1, Text="", BorderSizePixel=0, AutoButtonColor=false, Active=true, ZIndex=115})
    local dragging=false; local dragInput, dragStart, startPos
    add(Connections, headerDrag.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; dragInput=input; dragStart=input.Position; startPos=Main.Position
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end))
    add(Connections, headerDrag.InputChanged:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end end))
    add(Connections, UserInputService.InputChanged:Connect(function(input) if dragging and input==dragInput then local d=input.Position-dragStart; Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end))

    local lastIcon = 0
    local function toggleMain()
        local now = os.clock()
        if now - lastIcon < 0.2 then return end
        lastIcon = now
        Main.Visible = not Main.Visible
        if Main.Visible and not Body:FindFirstChildWhichIsA("GuiObject") then renderHome("Bundle") end
    end

    -- Draggable icon fix:
    -- The pixel-art children can eat touch input on some mobile executors, so we put a
    -- transparent TextButton hitbox above the whole icon. Tap toggles, drag moves.
    local IconHitbox = new("TextButton", {
        Parent = IconButton,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
        ZIndex = 2000
    })

    local iconDragging = false
    local iconMoved = false
    local iconInput = nil
    local iconStart = nil
    local iconStartPos = nil

    add(Connections, IconHitbox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            iconDragging = true
            iconMoved = false
            iconInput = input
            iconStart = input.Position
            iconStartPos = IconButton.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    if iconDragging and not iconMoved then
                        toggleMain()
                    end
                    iconDragging = false
                end
            end)
        end
    end))

    add(Connections, IconHitbox.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            iconInput = input
        end
    end))

    add(Connections, UserInputService.InputChanged:Connect(function(input)
        if iconDragging and input == iconInput and iconStart and iconStartPos then
            local delta = input.Position - iconStart
            if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
                iconMoved = true
            end
            local newX = iconStartPos.X.Offset + delta.X
            local newY = iconStartPos.Y.Offset + delta.Y
            -- Keep at least part of icon on screen.
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            newX = math.clamp(newX, -20, vp.X - 38)
            newY = math.clamp(newY, -20, vp.Y - 38)
            IconButton.Position = UDim2.new(iconStartPos.X.Scale, newX, iconStartPos.Y.Scale, newY)
        end
    end))

    -- Desktop fallback if the hitbox is bypassed.
    add(Connections, IconHitbox.MouseButton1Click:Connect(function()
        if not iconMoved then toggleMain() end
    end))
    pcall(function()
        add(Connections, IconHitbox.Activated:Connect(function()
            if not iconMoved then toggleMain() end
        end))
    end)

    renderHome("Bundle")
    Main.Size = UDim2.new(0,40,0,40)
    tween(Main, {Size = UDim2.new(0,570,0,535)}, 0.18)
end

---------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------

loadData()
createGui()
LocalPlayer.CharacterAdded:Connect(function() task.wait(1); captureOriginals() end)
if LocalPlayer.Character then task.wait(0.5); captureOriginals() end

-- Auto-load saved pack or popular bundles.
task.spawn(function()
    task.wait(1)
    local hasAny = false
    for _, st in ipairs(States) do if normalizeId(CurrentForm[st]) ~= "" then hasAny=true break end end
    if AutoLoad and hasAny then
        applyCurrentForm(LastAppliedName ~= "" and LastAppliedName or "Saved Pack")
        status("Auto-loaded: " .. tostring(LastAppliedName ~= "" and LastAppliedName or "Saved Pack"), true)
    else
        status("Loading popular bundles...", nil)
        local ok = searchCatalog("Bundle", "animation", false)
        if ok then status("Popular bundles loaded", true); if Main and Main.Visible then renderHome("Bundle") end else status("Search bundles or emotes.", true) end
    end
end)

---------------------------------------------------------------------
-- V12 SYSTEM PATCH: REAL EMOTE RESOLUTION / FLOATING / CONTROLLER / FILTERS
-- This patch intentionally overrides earlier page functions while preserving
-- existing data, save files, bundle resolver, custom mix, favorites, and UI.
---------------------------------------------------------------------

local V12 = {
    SourceFilter = "Roblox", -- Favorites / Roblox / UGC
    PickerProvider = "Floating", -- Floating / Quick
    FloatingMode = "Autogrid", -- Autogrid / Freeform
    FloatingPlacement = "Top right",
    WidthMode = "Wide", -- Wide / Compact
    AvoidScaling = false,
    ScreenBlur = false,
    StartClosed = false,
    Crowdsource = false,
    CacheUGCIds = true,
    CacheUGCTracks = false,
    Suggestions = true,
    EmoteAnimCache = {},
    TrackCache = {},
    Floating = {},
    SelectedTrackIndex = 1,
    ControllerLoop = false,
    ControllerReverse = false,
    ControllerSpeedName = "Normal",
    ControllerSpeed = 1,
    ControllerIntensity = 1,
    ReverseConn = nil,
    QuickOpen = false,
}

local SpeedPresets = {
    {"Paused", 0},
    {"Slower", 0.35},
    {"Slow", 0.65},
    {"Normal", 1},
    {"Fast", 1.5},
    {"Faster", 2.25},
}

local SuggestionBase = {"dance", "pose", "wave", "laugh", "sit", "sleep", "spin", "hype", "ninja", "robot", "zombie", "cute", "sad", "happy"}

local oldSaveData_V12 = saveData
saveData = function()
    if not CAN_SAVE then return false end
    local okOld = false
    pcall(function() okOld = oldSaveData_V12() end)
    local extra = {
        V12 = {
            SourceFilter = V12.SourceFilter,
            PickerProvider = V12.PickerProvider,
            FloatingMode = V12.FloatingMode,
            FloatingPlacement = V12.FloatingPlacement,
            WidthMode = V12.WidthMode,
            AvoidScaling = V12.AvoidScaling,
            ScreenBlur = V12.ScreenBlur,
            StartClosed = V12.StartClosed,
            Crowdsource = V12.Crowdsource,
            CacheUGCIds = V12.CacheUGCIds,
            CacheUGCTracks = V12.CacheUGCTracks,
            Suggestions = V12.Suggestions,
            EmoteAnimCache = V12.EmoteAnimCache,
            Floating = V12.Floating,
        }
    }
    pcall(function()
        writefile("FE_BUNDLE_V12_EXTRA.json", HttpService:JSONEncode(extra))
    end)
    return okOld
end

local function loadV12Data()
    if not CAN_SAVE then return end
    local exists = false
    pcall(function() exists = isfile("FE_BUNDLE_V12_EXTRA.json") end)
    if not exists then return end
    local raw
    local ok = pcall(function() raw = readfile("FE_BUNDLE_V12_EXTRA.json") end)
    if not ok or not raw then return end
    local data
    pcall(function() data = HttpService:JSONDecode(raw) end)
    if type(data) == "table" and type(data.V12) == "table" then
        for k, v in pairs(data.V12) do
            if V12[k] ~= nil then V12[k] = v end
        end
    end
end
loadV12Data()

local function v12Notify(text, good)
    notify(text, good ~= false)
end

local function v12CatalogDetails(assetId)
    assetId = normalizeId(assetId)
    if assetId == "" then return nil end
    local raw = httpGet("https://catalog.roblox.com/v1/catalog/items/" .. assetId .. "/details?itemType=Asset")
    return decodeJson(raw)
end

local function v12ResolveEmoteAnimationId(assetId)
    assetId = normalizeId(assetId)
    if assetId == "" then return nil end
    if V12.EmoteAnimCache[assetId] then return V12.EmoteAnimCache[assetId] end

    -- Method 1: GetObjects. Many UGC emote assets directly contain an Animation.
    local found
    pcall(function()
        local objs = game:GetObjects("rbxassetid://" .. assetId)
        for _, obj in ipairs(objs or {}) do
            if obj:IsA("Animation") then
                found = normalizeId(obj.AnimationId)
            else
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("Animation") then
                        found = normalizeId(d.AnimationId)
                        break
                    end
                end
            end
            pcall(function() obj:Destroy() end)
            if found and found ~= "" then break end
        end
    end)

    -- Method 2: assetdelivery parsing, AFEM-style fallback.
    if not found or found == "" then
        pcall(function()
            local delivery = decodeJson(httpGet("https://assetdelivery.roblox.com/v1/assetId/" .. assetId))
            if delivery and delivery.location then
                local content = httpGet(delivery.location)
                if content then
                    found = normalizeId(string.match(content, "rbxassetid://%d+") or string.match(content, "rbxasset://%d+") or "")
                end
            end
        end)
    end

    if not found or found == "" then
        -- Some Roblox emote catalog IDs are already playable animation IDs.
        found = assetId
    end

    if V12.CacheUGCIds then
        V12.EmoteAnimCache[assetId] = found
        saveData()
    end
    return found
end

-- Override emote playback to use real animation ID, not only catalog item ID.
playEmote = function(assetId, name)
    local realId = v12ResolveEmoteAnimationId(assetId)
    if not realId or realId == "" then
        setStatus("Animation failed: no animation ID found", false)
        v12Notify("Animation failed.", false)
        return
    end
    local _, hum = getCharHum()
    if not hum then setStatus("Humanoid not found", false); return end
    stopEmote()
    local anim = Instance.new("Animation")
    anim.AnimationId = toAnimUrl(realId)
    local ok, track = pcall(function() return hum:LoadAnimation(anim) end)
    if not ok or not track then
        setStatus("Animation failed to load: " .. tostring(realId), false)
        v12Notify("Animation failed.", false)
        return
    end
    CurrentEmoteTrack = track
    if V12.CacheUGCTracks then
        V12.TrackCache[tostring(assetId)] = track
    end
    pcall(function()
        track.Priority = MoveWhileEmote and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action4
        track.Looped = EmoteLoop
        track:Play(0.15, 1, EmoteSpeed)
    end)
    setStatus("Animation loaded: " .. tostring(name or realId), true)
    v12Notify("Animation loaded.", true)
end

local function v12MakeAvatarPreview(parent, animId)
    return createAvatarPreview(parent, animId)
end

-- Override info modal with guaranteed close and avatar preview space.
showInfoModal = function(titleText, bodyText, imageId, actions, previewAnimId)
    closeInfoModal()
    disconnectList(ModalConnections)
    ModalDim = new("Frame", {Parent=ScreenGui, Position=UDim2.new(0,0,0,0), Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Black, BackgroundTransparency=1, BorderSizePixel=0, ZIndex=200})
    tween(ModalDim, {BackgroundTransparency=ModalDimTransparency}, 0.16)
    ModalCard = new("Frame", {Parent=ScreenGui, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,30,0,30), BackgroundColor3=Theme.Page, BorderSizePixel=0, ZIndex=201})
    corner(ModalCard, 16); stroke(ModalCard, Theme.Black, 2, 0)
    tween(ModalCard, {Size=UDim2.new(0,460,0,330)}, 0.18)
    task.delay(0.03, function()
        if not ModalCard then return end
        local previewId = normalizeId(previewAnimId or "")
        if previewId ~= "" then
            v12MakeAvatarPreview(ModalCard, previewId)
        else
            local img = new("ImageLabel", {Parent=ModalCard, Position=UDim2.new(0,18,0,18), Size=UDim2.new(0,140,0,118), BackgroundColor3=Theme.Field, BorderSizePixel=0, Image=imageId or "", ScaleType=Enum.ScaleType.Fit, ZIndex=202})
            corner(img, 10); stroke(img, Theme.Black, 1, 0.25)
        end
        makeLabel(ModalCard, titleText or "Info", UDim2.new(0,176,0,18), UDim2.new(1,-220,0,42), 18, Theme.Text)
        makeLabel(ModalCard, bodyText or "No information.", UDim2.new(0,176,0,66), UDim2.new(1,-198,0,178), 13, Theme.Muted)
        makeButton(ModalCard, "X", UDim2.new(1,-44,0,12), UDim2.new(0,30,0,30), closeInfoModal, Theme.Red, true)
        makeButton(ModalCard, "CLOSE", UDim2.new(0,18,1,-48), UDim2.new(0,88,0,30), closeInfoModal, Theme.Red, true)
        local x = 116
        for _, act in ipairs(actions or {}) do
            makeButton(ModalCard, act.Text or "OK", UDim2.new(0,x,1,-48), UDim2.new(0,100,0,30), function()
                if act.Callback then act.Callback() end
                if act.Close ~= false then closeInfoModal() end
            end, act.Color or Theme.Cyan, true)
            x = x + 108
        end
    end)
end

local function v12IsFavorite(list, id)
    id = tostring(id)
    for _, item in ipairs(list) do if tostring(item.id) == id then return true end end
    return false
end

local function v12FloatingLayer()
    if not ScreenGui then return nil end
    local layer = ScreenGui:FindFirstChild("FEFloatingLayer")
    if not layer then
        layer = new("Frame", {Parent=ScreenGui, Name="FEFloatingLayer", BackgroundTransparency=1, Position=UDim2.new(0,0,0,0), Size=UDim2.new(1,0,1,0), ZIndex=150})
    end
    return layer
end

local function v12ReflowFloating()
    local layer = v12FloatingLayer()
    if not layer then return end
    local buttons = {}
    for _, child in ipairs(layer:GetChildren()) do
        if child:IsA("ImageButton") or child:IsA("TextButton") then table.insert(buttons, child) end
    end
    if V12.FloatingMode ~= "Autogrid" then return end
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280,720)
    local size, gap = 52, 8
    for i, btn in ipairs(buttons) do
        local col = (i-1) % 4
        local row = math.floor((i-1) / 4)
        local x, y
        if V12.FloatingPlacement == "Top left" then
            x = 12 + col*(size+gap); y = 90 + row*(size+gap)
        elseif V12.FloatingPlacement == "Bottom left" then
            x = 12 + col*(size+gap); y = vp.Y - 90 - size - row*(size+gap)
        elseif V12.FloatingPlacement == "Bottom right" then
            x = vp.X - 12 - size - col*(size+gap); y = vp.Y - 90 - size - row*(size+gap)
        else
            x = vp.X - 12 - size - col*(size+gap); y = 90 + row*(size+gap)
        end
        btn.Position = UDim2.new(0, math.floor(x), 0, math.floor(y))
    end
end

local function v12CreateFloatingButton(item)
    local id = tostring(item.id or item.Id or "")
    if id == "" then return end
    for _, f in ipairs(V12.Floating) do
        if tostring(f.id) == id then
            v12Notify("Floating button already exists.", false)
            return
        end
    end
    table.insert(V12.Floating, {id=id, name=tostring(item.name or item.Name or id), kind="Emote", x=nil, y=nil})
    saveData()
    local layer = v12FloatingLayer()
    if not layer then return end
    local btn = new("ImageButton", {Parent=layer, Name="FEFloat_"..id, Size=UDim2.new(0,52,0,52), BackgroundColor3=Theme.Card, BorderSizePixel=0, Image=assetThumbnail(id), Active=true, AutoButtonColor=true, ZIndex=151})
    corner(btn, 12); stroke(btn, Theme.Black, 1, 0)
    add(FloatingConnections, btn.MouseButton1Click:Connect(function() playEmote(id, item.name or item.Name or id) end))
    local dragging=false; local dragInput, dragStart, startPos
    add(FloatingConnections, btn.InputBegan:Connect(function(input)
        if V12.FloatingMode ~= "Freeform" then return end
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; dragInput=input; dragStart=input.Position; startPos=btn.Position
            input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then
                    dragging=false
                    for _, f in ipairs(V12.Floating) do
                        if tostring(f.id)==id then f.x=btn.Position.X.Offset; f.y=btn.Position.Y.Offset end
                    end
                    saveData()
                end
            end)
        end
    end))
    add(FloatingConnections, btn.InputChanged:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end end))
    add(FloatingConnections, UserInputService.InputChanged:Connect(function(input)
        if dragging and input==dragInput then
            local d=input.Position-dragStart
            local cam=workspace.CurrentCamera; local vp=cam and cam.ViewportSize or Vector2.new(1280,720)
            local nx=math.clamp(startPos.X.Offset+d.X, -20, vp.X-32)
            local ny=math.clamp(startPos.Y.Offset+d.Y, -20, vp.Y-32)
            btn.Position=UDim2.new(0,nx,0,ny)
        end
    end))
    v12ReflowFloating()
    v12Notify("Floating button created.", true)
end

local function v12RestoreFloatingButtons()
    disconnectList(FloatingConnections)
    local layer = v12FloatingLayer()
    if not layer then return end
    clear(layer)
    for _, f in ipairs(V12.Floating) do
        local item = {id=f.id, name=f.name, Name=f.name}
        local btn = new("ImageButton", {Parent=layer, Name="FEFloat_"..tostring(f.id), Size=UDim2.new(0,52,0,52), BackgroundColor3=Theme.Card, BorderSizePixel=0, Image=assetThumb(f.id), Active=true, AutoButtonColor=true, ZIndex=151})
        corner(btn,12); stroke(btn,Theme.Black,1,0)
        if V12.FloatingMode == "Freeform" and f.x and f.y then btn.Position = UDim2.new(0,f.x,0,f.y) end
        add(FloatingConnections, btn.MouseButton1Click:Connect(function() playEmote(f.id, f.name) end))
    end
    v12ReflowFloating()
end

-- Override item rendering to use real emote AnimationId in INFO and PLAY.
renderItemCard = function(parent, item, index, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local creator = tostring(item.creatorName or item.CreatorName or item.creator and item.creator.name or "Unknown")
    local desc = tostring(item.description or item.Description or "No description available.")
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = 12 + col * 250
    local y = 12 + row * 142
    local card = makePanel(parent, UDim2.new(0,x,0,y), UDim2.new(0,238,0,130), Theme.Card)
    local imgId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img = new("ImageLabel", {Parent=card, Position=UDim2.new(0,10,0,10), Size=UDim2.new(0,80,0,72), BackgroundColor3=Theme.Field, BorderSizePixel=0, Image=imgId, ScaleType=Enum.ScaleType.Fit, ZIndex=card.ZIndex+2})
    corner(img,8)
    makeLabel(card, name, UDim2.new(0,100,0,10), UDim2.new(1,-110,0,36), 13, Theme.Text)
    makeLabel(card, creator, UDim2.new(0,100,0,46), UDim2.new(1,-110,0,18), 11, Theme.Muted)
    makeLabel(card, kind .. " ID: " .. id, UDim2.new(0,100,0,64), UDim2.new(1,-110,0,18), 10, Theme.Muted)
    makeButton(card, kind=="Emote" and "PLAY" or (ChoosingState and ("SET "..string.upper(ChoosingState)) or "APPLY"), UDim2.new(0,10,1,-36), UDim2.new(0,92,0,26), function()
        if kind=="Emote" then playEmote(id,name) else if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end
    end, kind=="Emote" and Theme.Green or Theme.Orange)
    makeButton(card, "INFO", UDim2.new(0,110,1,-36), UDim2.new(0,58,0,26), function()
        local realId = kind=="Emote" and v12ResolveEmoteAnimationId(id) or nil
        local body = kind .. ": " .. name .. "\nCreator: " .. creator .. "\nSource: " .. (kind=="Emote" and V12.SourceFilter or "Bundle") .. "\nID: " .. id .. (realId and ("\nAnimation ID: "..realId) or "") .. "\nLink: https://www.roblox.com/catalog/" .. id .. "\n\n" .. desc
        local actions = {}
        if kind=="Emote" then
            table.insert(actions, {Text="PLAY", Color=Theme.Green, Callback=function() playEmote(id,name) end, Close=false})
            table.insert(actions, {Text="COPY ANIM.", Color=Theme.Cyan, Callback=function() copyToClipboard(realId or id) end, Close=false})
            table.insert(actions, {Text="FLOATING B.", Color=Theme.Orange, Callback=function() v12CreateFloatingButton(item) end, Close=false})
        else
            table.insert(actions, {Text=ChoosingState and "SET" or "APPLY", Color=Theme.Green, Callback=function() if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end})
        end
        table.insert(actions, {Text=v12IsFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "FAVORITED" or "FAVORITE", Color=Theme.Yellow, Callback=function() toggleFavorite(kind,item) end, Close=false})
        showInfoModal(name, body, imgId, actions, kind=="Emote" and realId or nil)
    end, Theme.Cyan)
    makeButton(card, v12IsFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "★" or "☆", UDim2.new(0,176,1,-36), UDim2.new(0,42,0,26), function()
        toggleFavorite(kind,item)
        if CurrentPage=="Bundles" then renderHome("Bundle") elseif CurrentPage=="Emotes" then renderHome("Emote") end
    end, Theme.Yellow)
end

local oldRenderSettings_V12 = renderSettings
renderSettings = function()
    oldRenderSettings_V12()
    -- Add extra functional settings in an overlay row at bottom of settings page.
    makeLabel(Body, "Picker / UI", UDim2.new(0,12,0,458), UDim2.new(1,-24,0,22), 13, Theme.Muted)
    makeButton(Body, "PICK: "..V12.PickerProvider, UDim2.new(0,12,0,482), UDim2.new(0,130,0,30), function()
        V12.PickerProvider = V12.PickerProvider == "Floating" and "Quick" or "Floating"
        saveData(); renderSettings(); v12Notify("Picker provider changed.", true)
    end, Theme.Cyan)
    makeButton(Body, "FLOAT: "..V12.FloatingMode, UDim2.new(0,154,0,482), UDim2.new(0,140,0,30), function()
        V12.FloatingMode = V12.FloatingMode == "Autogrid" and "Freeform" or "Autogrid"
        saveData(); v12RestoreFloatingButtons(); renderSettings(); v12Notify("Floating mode changed.", true)
    end, Theme.Cyan)
    makeButton(Body, V12.WidthMode, UDim2.new(0,306,0,482), UDim2.new(0,82,0,30), function()
        V12.WidthMode = V12.WidthMode == "Wide" and "Compact" or "Wide"
        saveData(); renderSettings(); v12Notify("Width mode changed.", true)
    end, Theme.Yellow)
end

local oldRenderHome_V12 = renderHome
renderHome = function(kind)
    oldRenderHome_V12(kind)
    if kind == "Emote" or CurrentPage == "Emotes" then
        -- Source filter row, real state change.
        local y = 120
        makeButton(Body, "Favorites", UDim2.new(0,12,0,y), UDim2.new(0,92,0,28), function()
            V12.SourceFilter = "Favorites"; EmoteResults = FavoritesEmotes; renderHome("Emote")
        end, V12.SourceFilter=="Favorites" and Theme.Green or Theme.Card)
        makeButton(Body, "Roblox", UDim2.new(0,112,0,y), UDim2.new(0,82,0,28), function()
            V12.SourceFilter = "Roblox"; EmoteResults = {}; searchCatalog("Emote", LastEmoteKeyword, false); renderHome("Emote")
        end, V12.SourceFilter=="Roblox" and Theme.Green or Theme.Card)
        makeButton(Body, "UGC", UDim2.new(0,202,0,y), UDim2.new(0,72,0,28), function()
            V12.SourceFilter = "UGC"; EmoteResults = {}; searchCatalog("Emote", LastEmoteKeyword, false); renderHome("Emote")
        end, V12.SourceFilter=="UGC" and Theme.Green or Theme.Card)
    end
end

local function v12ControllerTracks()
    local _, hum = getCharHum()
    if not hum then return {} end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return {} end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if ok then return tracks end
    return {}
end

local function v12SelectedTrack()
    local tracks = v12ControllerTracks()
    return tracks[V12.SelectedTrackIndex], tracks
end

local function v12ApplyControllerToTrack(track)
    if not track then return end
    pcall(function() track.Looped = V12.ControllerLoop end)
    pcall(function() track:AdjustSpeed(V12.ControllerSpeed * (V12.ControllerReverse and -1 or 1)) end)
    pcall(function() track:AdjustWeight(V12.ControllerIntensity, 0.1) end)
end

local function renderController()
    setPage("Controller"); tabs()
    makeLabel(Body, "Animation controller", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    makeLabel(Body, "Select track to control", UDim2.new(0,12,0,82), UDim2.new(1,-24,0,22), 13, Theme.Muted)
    local tracks = v12ControllerTracks()
    if #tracks == 0 then
        makeLabel(Body, "No active animation tracks.", UDim2.new(0,12,0,116), UDim2.new(1,-24,0,40), 14, Theme.Muted)
        return
    end
    local y = 116
    for i, track in ipairs(tracks) do
        local animId = track.Animation and track.Animation.AnimationId or "unknown"
        makeButton(Body, (i==V12.SelectedTrackIndex and "● " or "○ ") .. "Track "..i, UDim2.new(0,12,0,y), UDim2.new(0,120,0,30), function()
            V12.SelectedTrackIndex=i; renderController()
        end, i==V12.SelectedTrackIndex and Theme.Green or Theme.Card)
        makeLabel(Body, animId, UDim2.new(0,142,0,y), UDim2.new(1,-160,0,30), 11, Theme.Muted)
        y = y + 36
        if y > 220 then break end
    end
    local track = tracks[V12.SelectedTrackIndex] or tracks[1]
    makeButton(Body, V12.ControllerLoop and "Looping: ON" or "Looping: OFF", UDim2.new(0,12,0,250), UDim2.new(0,140,0,32), function()
        V12.ControllerLoop = not V12.ControllerLoop; v12ApplyControllerToTrack(track); renderController()
    end, V12.ControllerLoop and Theme.Green or Theme.Card)
    makeButton(Body, V12.ControllerReverse and "Reverse: ON" or "Reverse: OFF", UDim2.new(0,164,0,250), UDim2.new(0,140,0,32), function()
        V12.ControllerReverse = not V12.ControllerReverse; v12ApplyControllerToTrack(track); renderController()
    end, V12.ControllerReverse and Theme.Green or Theme.Card)
    local x = 12
    for _, sp in ipairs(SpeedPresets) do
        makeButton(Body, sp[1], UDim2.new(0,x,0,300), UDim2.new(0,82,0,30), function()
            V12.ControllerSpeedName=sp[1]; V12.ControllerSpeed=sp[2]; v12ApplyControllerToTrack(track); renderController()
        end, V12.ControllerSpeedName==sp[1] and Theme.Green or Theme.Card)
        x = x + 88
        if x > 470 then x = 12 end
    end
    makeLabel(Body, "Animation intensity", UDim2.new(0,12,0,350), UDim2.new(1,-24,0,24), 13, Theme.Muted)
    makeButton(Body, "-", UDim2.new(0,12,0,382), UDim2.new(0,48,0,30), function()
        V12.ControllerIntensity=math.max(0,V12.ControllerIntensity-0.1); v12ApplyControllerToTrack(track); renderController()
    end, Theme.Card)
    makeLabel(Body, tostring(math.floor(V12.ControllerIntensity*100)).."%", UDim2.new(0,72,0,382), UDim2.new(0,80,0,30), 13, Theme.Text)
    makeButton(Body, "+", UDim2.new(0,150,0,382), UDim2.new(0,48,0,30), function()
        V12.ControllerIntensity=math.min(2,V12.ControllerIntensity+0.1); v12ApplyControllerToTrack(track); renderController()
    end, Theme.Card)
end

local oldTabs_V12 = tabs
tabs = function()
    makeButton(Body, "EMOTES", UDim2.new(0,12,0,8), UDim2.new(0,76,0,32), function() renderHome("Emote") end, CurrentPage=="Emotes" and Theme.Cyan or Theme.Card)
    makeButton(Body, "BUND", UDim2.new(0,96,0,8), UDim2.new(0,64,0,32), function() renderHome("Bundle") end, CurrentPage=="Bundles" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CTRL", UDim2.new(0,168,0,8), UDim2.new(0,64,0,32), function() renderController() end, CurrentPage=="Controller" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CUST", UDim2.new(0,240,0,8), UDim2.new(0,64,0,32), function() renderCustom() end, CurrentPage=="Custom" and Theme.Cyan or Theme.Card)
    makeButton(Body, "FAV", UDim2.new(0,312,0,8), UDim2.new(0,56,0,32), function() renderFavorites() end, CurrentPage=="Favorites" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SAVE", UDim2.new(0,376,0,8), UDim2.new(0,62,0,32), function() renderSave() end, CurrentPage=="Save" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SET", UDim2.new(0,446,0,8), UDim2.new(0,52,0,32), function() renderSettings() end, CurrentPage=="Settings" and Theme.Cyan or Theme.Card)
end

v12RestoreFloatingButtons()
renderHome("Emote")
v12Notify("V12 system patch applied", true)

---------------------------------------------------------------------
-- V13 REAL SYSTEM PATCH: AFEM-LIKE CONTROLLER, QUICK SELECTOR,
-- SETTINGS, PICKER PROVIDER, AND ROBUST EMOTE SHORTCUTS
-- This patch does not remove older working systems; it overrides only the
-- incomplete handlers and connects every option to a real behavior.
---------------------------------------------------------------------

-- Match AFEM-like controller speed semantics more closely.
SpeedPresets = {
    {"Paused", 0},
    {"Slower", 0.2},
    {"Slow", 0.65},
    {"Normal", 1},
    {"Fast", 1.25},
    {"Faster", 1.75},
}

local V13 = {
    QuickEntries = {},
    QuickLayer = nil,
    QuickPanel = nil,
    QuickButton = nil,
    ControllerReverseConn = nil,
    LastSettingsPage = 1,
}

local oldSaveData_V13 = saveData
saveData = function()
    local ok = false
    pcall(function() ok = oldSaveData_V13() end)
    if CAN_SAVE then
        pcall(function()
            writefile("FE_BUNDLE_V13_EXTRA.json", HttpService:JSONEncode({
                QuickEntries = V13.QuickEntries,
                PickerProvider = V12.PickerProvider,
                FloatingMode = V12.FloatingMode,
                FloatingPlacement = V12.FloatingPlacement,
                WidthMode = V12.WidthMode,
                AvoidScaling = V12.AvoidScaling,
                ScreenBlur = V12.ScreenBlur,
                StartClosed = V12.StartClosed,
                Crowdsource = V12.Crowdsource,
                CacheUGCIds = V12.CacheUGCIds,
                CacheUGCTracks = V12.CacheUGCTracks,
                Suggestions = V12.Suggestions,
            }))
        end)
    end
    return ok
end

local function v13LoadData()
    if not CAN_SAVE then return end
    local exists = false
    pcall(function() exists = isfile("FE_BUNDLE_V13_EXTRA.json") end)
    if not exists then return end
    local raw
    local ok = pcall(function() raw = readfile("FE_BUNDLE_V13_EXTRA.json") end)
    if not ok or not raw then return end
    local data
    pcall(function() data = HttpService:JSONDecode(raw) end)
    if type(data) ~= "table" then return end
    if type(data.QuickEntries) == "table" then V13.QuickEntries = data.QuickEntries end
    for _, key in ipairs({"PickerProvider","FloatingMode","FloatingPlacement","WidthMode","AvoidScaling","ScreenBlur","StartClosed","Crowdsource","CacheUGCIds","CacheUGCTracks","Suggestions"}) do
        if data[key] ~= nil and V12[key] ~= nil then
            V12[key] = data[key]
        end
    end
end
v13LoadData()

local function v13Toast(text, good)
    v12Notify(text, good ~= false)
end

local function v13ClampToScreen(frame)
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local x = math.clamp(frame.Position.X.Offset, -20, math.max(20, vp.X - frame.AbsoluteSize.X + 20))
    local y = math.clamp(frame.Position.Y.Offset, -20, math.max(20, vp.Y - frame.AbsoluteSize.Y + 20))
    frame.Position = UDim2.new(0, x, 0, y)
end

---------------------------------------------------------------------
-- QUICK SELECTOR SYSTEM
---------------------------------------------------------------------

local function v13QuickLayer()
    if V13.QuickLayer and V13.QuickLayer.Parent then return V13.QuickLayer end
    if not ScreenGui then return nil end
    V13.QuickLayer = new("Frame", {
        Parent = ScreenGui,
        Name = "FEQuickSelectorLayer",
        BackgroundTransparency = 1,
        Position = UDim2.new(0,0,0,0),
        Size = UDim2.new(1,0,1,0),
        ZIndex = 175
    })
    return V13.QuickLayer
end

local function v13RebuildQuickPanel()
    local layer = v13QuickLayer()
    if not layer then return end
    if V13.QuickPanel then V13.QuickPanel:Destroy(); V13.QuickPanel = nil end
    if V13.QuickButton then V13.QuickButton:Destroy(); V13.QuickButton = nil end

    V13.QuickButton = new("TextButton", {
        Parent = layer,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -18),
        Size = UDim2.new(0, 72, 0, 38),
        BackgroundColor3 = Theme.Orange,
        BorderSizePixel = 0,
        Text = "QS",
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        ZIndex = 176,
        Active = true
    })
    corner(V13.QuickButton, 14)
    stroke(V13.QuickButton, Theme.Black, 1, 0)

    V13.QuickPanel = new("Frame", {
        Parent = layer,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -62),
        Size = UDim2.new(0, 420, 0, 84),
        BackgroundColor3 = Theme.Page,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 176
    })
    corner(V13.QuickPanel, 14)
    stroke(V13.QuickPanel, Theme.Black, 1, 0)

    local scroll = new("ScrollingFrame", {
        Parent = V13.QuickPanel,
        Position = UDim2.new(0, 10, 0, 10),
        Size = UDim2.new(1, -20, 1, -20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Orange,
        CanvasSize = UDim2.new(0, math.max(400, #V13.QuickEntries * 66), 0, 0),
        ZIndex = 177
    })

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 8)
    layout.Parent = scroll

    for _, entry in ipairs(V13.QuickEntries) do
        local b = new("ImageButton", {
            Parent = scroll,
            Size = UDim2.new(0, 58, 0, 58),
            BackgroundColor3 = Theme.Card,
            BorderSizePixel = 0,
            Image = assetThumbnail(entry.id),
            ZIndex = 178,
            Active = true,
            AutoButtonColor = true
        })
        corner(b, 12)
        stroke(b, Theme.Black, 1, 0)
        add(Connections, b.MouseButton1Click:Connect(function()
            playEmote(entry.id, entry.name)
            V13.QuickPanel.Visible = false
        end))
    end

    add(Connections, V13.QuickButton.MouseButton1Click:Connect(function()
        V13.QuickPanel.Visible = not V13.QuickPanel.Visible
        if V13.QuickPanel.Visible then
            V13.QuickPanel.Size = UDim2.new(0, 40, 0, 40)
            tween(V13.QuickPanel, {Size = UDim2.new(0, 420, 0, 84)}, 0.16)
        end
    end))

    if V12.PickerProvider ~= "Quick" then
        V13.QuickButton.Visible = false
        V13.QuickPanel.Visible = false
    end
end

local function v13CreateQuickEntry(item)
    local id = tostring(item.id or item.Id or "")
    if id == "" then return end
    for _, entry in ipairs(V13.QuickEntries) do
        if tostring(entry.id) == id then
            v13Toast("Quick selector entry already exists.", false)
            return
        end
    end
    table.insert(V13.QuickEntries, {id = id, name = tostring(item.name or item.Name or id)})
    saveData()
    v13RebuildQuickPanel()
    v13Toast("Quick selector entry created.", true)
end

local function v13CreatePickerShortcut(item)
    if V12.PickerProvider == "Quick" then
        v13CreateQuickEntry(item)
    else
        v12CreateFloatingButton(item)
    end
end

---------------------------------------------------------------------
-- FLOATING BUTTON UPDATE OVERRIDES
---------------------------------------------------------------------

local oldFloatingRestore_V13 = v12RestoreFloatingButtons
v12RestoreFloatingButtons = function()
    pcall(oldFloatingRestore_V13)
    if V12.PickerProvider == "Quick" then
        local layer = v12FloatingLayer()
        if layer then layer.Visible = false end
    else
        local layer = v12FloatingLayer()
        if layer then layer.Visible = true end
        v12ReflowFloating()
    end
end

---------------------------------------------------------------------
-- ITEM CARD OVERRIDE WITH REAL INFO ACTIONS
---------------------------------------------------------------------

renderItemCard = function(parent, item, index, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local creator = tostring(item.creatorName or item.CreatorName or "Unknown")
    local desc = tostring(item.description or item.Description or "No description available.")
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = 12 + col * 250
    local y = 12 + row * 142
    local card = makePanel(parent, UDim2.new(0,x,0,y), UDim2.new(0,238,0,130), Theme.Card)
    local imgId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img = new("ImageLabel", {
        Parent = card,
        Position = UDim2.new(0,10,0,10),
        Size = UDim2.new(0,80,0,72),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Image = imgId,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = getZ(card, 2)
    })
    corner(img, 8)
    makeLabel(card, name, UDim2.new(0,100,0,10), UDim2.new(1,-110,0,36), 13, Theme.Text)
    makeLabel(card, creator, UDim2.new(0,100,0,46), UDim2.new(1,-110,0,18), 11, Theme.Muted)
    makeLabel(card, kind .. " ID: " .. id, UDim2.new(0,100,0,64), UDim2.new(1,-110,0,18), 10, Theme.Muted)

    makeButton(card, kind == "Emote" and "PLAY" or (ChoosingState and ("SET "..string.upper(ChoosingState)) or "APPLY"), UDim2.new(0,10,1,-36), UDim2.new(0,92,0,26), function()
        if kind == "Emote" then
            playEmote(id, name)
        else
            if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end
        end
    end, kind == "Emote" and Theme.Green or Theme.Orange)

    makeButton(card, "INFO", UDim2.new(0,110,1,-36), UDim2.new(0,58,0,26), function()
        local realId = kind == "Emote" and v12ResolveEmoteAnimationId(id) or nil
        local link = "https://www.roblox.com/catalog/" .. id
        local body = kind .. ": " .. name .. "\nCreator: " .. creator .. "\nSource: " .. (kind == "Emote" and V12.SourceFilter or "Bundle") .. "\nID: " .. id .. (realId and ("\nAnimation ID: " .. realId) or "") .. "\nLink: " .. link .. "\n\n" .. desc
        local actions = {}
        if kind == "Emote" then
            table.insert(actions, {Text="PLAY", Color=Theme.Green, Callback=function() playEmote(id,name) end, Close=false})
            if realId and realId ~= "" then
                table.insert(actions, {Text="COPY ANIM.", Color=Theme.Cyan, Callback=function() copyToClipboard(realId) end, Close=false})
            end
            table.insert(actions, {Text=(V12.PickerProvider == "Quick" and "QUICK S." or "FLOATING B."), Color=Theme.Orange, Callback=function() v13CreatePickerShortcut(item) end, Close=false})
        else
            table.insert(actions, {Text=ChoosingState and "SET" or "APPLY", Color=Theme.Green, Callback=function() if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end})
        end
        table.insert(actions, {Text=v12IsFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "FAVORITED" or "FAVORITE", Color=Theme.Yellow, Callback=function() toggleFavorite(kind,item) end, Close=false})
        showInfoModal(name, body, imgId, actions, kind == "Emote" and realId or nil)
    end, Theme.Cyan)

    makeButton(card, v12IsFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "★" or "☆", UDim2.new(0,176,1,-36), UDim2.new(0,42,0,26), function()
        toggleFavorite(kind,item)
        if CurrentPage=="Bundles" then renderHome("Bundle") elseif CurrentPage=="Emotes" then renderHome("Emote") end
    end, Theme.Yellow)
end

---------------------------------------------------------------------
-- SOURCE FILTER AND SEARCH ENHANCEMENTS
---------------------------------------------------------------------

local oldRenderHome_V13 = renderHome
renderHome = function(kind)
    kind = kind or (CurrentPage == "Emotes" and "Emote" or "Bundle")
    oldRenderHome_V13(kind)
    if kind == "Emote" or CurrentPage == "Emotes" then
        local y = 120
        makeButton(Body, "Favorites", UDim2.new(0,12,0,y), UDim2.new(0,92,0,28), function()
            V12.SourceFilter = "Favorites"
            EmoteResults = FavoritesEmotes
            renderHome("Emote")
        end, V12.SourceFilter=="Favorites" and Theme.Green or Theme.Card)
        makeButton(Body, "Roblox", UDim2.new(0,112,0,y), UDim2.new(0,82,0,28), function()
            V12.SourceFilter = "Roblox"
            EmoteResults = {}
            searchCatalog("Emote", LastEmoteKeyword, false)
            renderHome("Emote")
        end, V12.SourceFilter=="Roblox" and Theme.Green or Theme.Card)
        makeButton(Body, "UGC", UDim2.new(0,202,0,y), UDim2.new(0,72,0,28), function()
            V12.SourceFilter = "UGC"
            EmoteResults = {}
            searchCatalog("Emote", LastEmoteKeyword, false)
            renderHome("Emote")
        end, V12.SourceFilter=="UGC" and Theme.Green or Theme.Card)

        if V12.Suggestions and SearchBox and SearchBox.Text and #SearchBox.Text > 0 then
            local baseY = 154
            local n = 0
            for _, word in ipairs(SuggestionBase) do
                if string.find(string.lower(word), string.lower(SearchBox.Text), 1, true) and n < 4 then
                    local bx = 12 + n * 88
                    makeButton(Body, word, UDim2.new(0,bx,0,baseY), UDim2.new(0,80,0,24), function()
                        SearchBox.Text = word
                        searchCatalog("Emote", word, false)
                        renderHome("Emote")
                    end, Theme.Cyan)
                    n += 1
                end
            end
        end
    end
end

---------------------------------------------------------------------
-- ANIMATION CONTROLLER REBUILD
---------------------------------------------------------------------

local function v13StopReverseLoop()
    if V13.ControllerReverseConn then
        pcall(function() V13.ControllerReverseConn:Disconnect() end)
        V13.ControllerReverseConn = nil
    end
end

local function v13GetTracks()
    local _, hum = getCharHum()
    if not hum then return {} end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return {} end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if ok and type(tracks) == "table" then return tracks end
    return {}
end

local function v13SelectedTrack()
    local tracks = v13GetTracks()
    return tracks[V12.SelectedTrackIndex] or tracks[1], tracks
end

local function v13ApplyTrackControls(track)
    if not track then return end
    v13StopReverseLoop()
    pcall(function() track.Looped = V12.ControllerLoop end)
    pcall(function() track:AdjustWeight(V12.ControllerIntensity, 0.1) end)
    if V12.ControllerReverse then
        pcall(function() track:AdjustSpeed(0) end)
        V13.ControllerReverseConn = RunService.Heartbeat:Connect(function(dt)
            if not track or not track.IsPlaying then v13StopReverseLoop(); return end
            local len = track.Length
            if not len or len <= 0 then return end
            local newTime = track.TimePosition - (math.max(0.01, V12.ControllerSpeed) * dt)
            if newTime <= 0 then
                if V12.ControllerLoop then
                    newTime = len
                else
                    pcall(function() track:Stop(0.05) end)
                    v13StopReverseLoop()
                    return
                end
            end
            pcall(function() track.TimePosition = newTime end)
        end)
    else
        pcall(function() track:AdjustSpeed(V12.ControllerSpeed) end)
    end
end

renderController = function()
    setPage("Controller"); tabs()
    makeLabel(Body, "Animation controller", UDim2.new(0,12,0,52), UDim2.new(1,-24,0,24), 15, Theme.Text)
    makeLabel(Body, "Select track to control", UDim2.new(0,12,0,82), UDim2.new(1,-24,0,22), 13, Theme.Muted)
    local tracks = v13GetTracks()
    if #tracks == 0 then
        makeLabel(Body, "No active animation tracks. Play an emote first.", UDim2.new(0,12,0,116), UDim2.new(1,-24,0,40), 14, Theme.Muted)
        return
    end
    local y = 116
    for i, track in ipairs(tracks) do
        local animId = track.Animation and track.Animation.AnimationId or "unknown"
        makeButton(Body, (i==V12.SelectedTrackIndex and "● " or "○ ") .. "Track "..i, UDim2.new(0,12,0,y), UDim2.new(0,120,0,30), function()
            V12.SelectedTrackIndex=i; renderController()
        end, i==V12.SelectedTrackIndex and Theme.Green or Theme.Card)
        makeLabel(Body, animId, UDim2.new(0,142,0,y), UDim2.new(1,-160,0,30), 11, Theme.Muted)
        y += 36
        if y > 220 then break end
    end
    local track = tracks[V12.SelectedTrackIndex] or tracks[1]
    makeButton(Body, V12.ControllerLoop and "Looping: ON" or "Looping: OFF", UDim2.new(0,12,0,250), UDim2.new(0,140,0,32), function()
        V12.ControllerLoop = not V12.ControllerLoop; v13ApplyTrackControls(track); renderController()
    end, V12.ControllerLoop and Theme.Green or Theme.Card)
    makeButton(Body, V12.ControllerReverse and "Reverse: ON" or "Reverse: OFF", UDim2.new(0,164,0,250), UDim2.new(0,140,0,32), function()
        V12.ControllerReverse = not V12.ControllerReverse; v13ApplyTrackControls(track); renderController()
    end, V12.ControllerReverse and Theme.Green or Theme.Card)
    local x = 12
    for _, sp in ipairs(SpeedPresets) do
        makeButton(Body, sp[1], UDim2.new(0,x,0,300), UDim2.new(0,82,0,30), function()
            V12.ControllerSpeedName=sp[1]; V12.ControllerSpeed=sp[2]; v13ApplyTrackControls(track); renderController()
        end, V12.ControllerSpeedName==sp[1] and Theme.Green or Theme.Card)
        x += 88
        if x > 470 then x = 12 end
    end
    makeLabel(Body, "Animation intensity", UDim2.new(0,12,0,350), UDim2.new(1,-24,0,24), 13, Theme.Muted)
    makeButton(Body, "-", UDim2.new(0,12,0,382), UDim2.new(0,48,0,30), function()
        V12.ControllerIntensity=math.max(0,V12.ControllerIntensity-0.1); v13ApplyTrackControls(track); renderController()
    end, Theme.Card)
    makeLabel(Body, tostring(math.floor(V12.ControllerIntensity*100)).."%", UDim2.new(0,72,0,382), UDim2.new(0,80,0,30), 13, Theme.Text)
    makeButton(Body, "+", UDim2.new(0,150,0,382), UDim2.new(0,48,0,30), function()
        V12.ControllerIntensity=math.min(2,V12.ControllerIntensity+0.1); v13ApplyTrackControls(track); renderController()
    end, Theme.Card)
end

---------------------------------------------------------------------
-- SETTINGS OVERRIDE WITH REAL OPTIONS
---------------------------------------------------------------------

local oldRenderSettings_V13 = renderSettings
renderSettings = function()
    oldRenderSettings_V13()
    makeLabel(Body, "Picker / UI", UDim2.new(0,12,0,458), UDim2.new(1,-24,0,22), 13, Theme.Muted)
    makeButton(Body, "PICK: "..V12.PickerProvider, UDim2.new(0,12,0,482), UDim2.new(0,130,0,30), function()
        V12.PickerProvider = V12.PickerProvider == "Floating" and "Quick" or "Floating"
        saveData(); v12RestoreFloatingButtons(); v13RebuildQuickPanel(); renderSettings(); v13Toast("Picker provider changed.", true)
    end, Theme.Cyan)
    makeButton(Body, "FLOAT: "..V12.FloatingMode, UDim2.new(0,154,0,482), UDim2.new(0,140,0,30), function()
        V12.FloatingMode = V12.FloatingMode == "Autogrid" and "Freeform" or "Autogrid"
        saveData(); v12RestoreFloatingButtons(); renderSettings(); v13Toast("Floating mode changed.", true)
    end, Theme.Cyan)
    makeButton(Body, V12.WidthMode, UDim2.new(0,306,0,482), UDim2.new(0,82,0,30), function()
        V12.WidthMode = V12.WidthMode == "Wide" and "Compact" or "Wide"
        saveData(); renderSettings(); v13Toast("Width mode changed.", true)
    end, Theme.Yellow)
end

---------------------------------------------------------------------
-- TABS OVERRIDE
---------------------------------------------------------------------

tabs = function()
    makeButton(Body, "EMOTES", UDim2.new(0,12,0,8), UDim2.new(0,76,0,32), function() renderHome("Emote") end, CurrentPage=="Emotes" and Theme.Cyan or Theme.Card)
    makeButton(Body, "BUND", UDim2.new(0,96,0,8), UDim2.new(0,64,0,32), function() renderHome("Bundle") end, CurrentPage=="Bundles" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CTRL", UDim2.new(0,168,0,8), UDim2.new(0,64,0,32), function() renderController() end, CurrentPage=="Controller" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CUST", UDim2.new(0,240,0,8), UDim2.new(0,64,0,32), function() renderCustom() end, CurrentPage=="Custom" and Theme.Cyan or Theme.Card)
    makeButton(Body, "FAV", UDim2.new(0,312,0,8), UDim2.new(0,56,0,32), function() renderFavorites() end, CurrentPage=="Favorites" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SAVE", UDim2.new(0,376,0,8), UDim2.new(0,62,0,32), function() renderSave() end, CurrentPage=="Save" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SET", UDim2.new(0,446,0,8), UDim2.new(0,52,0,32), function() renderSettings() end, CurrentPage=="Settings" and Theme.Cyan or Theme.Card)
end

v13LoadData()
v12RestoreFloatingButtons()
v13RebuildQuickPanel()
renderHome("Emote")
v13Toast("V13 real controller patch applied", true)

---------------------------------------------------------------------
-- V14 UI/INFO/DRAG FIX PATCH
-- Purpose: fix INFO buttons, modal content, mobile layout, icon dragging,
-- settings scroll, and add UI transparency controls without removing features.
---------------------------------------------------------------------

local V14 = {
    UITransparency = 0,
    GlassBlur = 0,
    LastIconDrag = 0,
}

local function v14ApplyGlass()
    if Main then
        Main.BackgroundTransparency = math.clamp(V14.UITransparency, 0, 0.85)
    elseif Gui and Gui.Main then
        Gui.Main.BackgroundTransparency = math.clamp(V14.UITransparency, 0, 0.85)
    end
    pcall(function()
        local blur = Lighting:FindFirstChild("FE_BUNDLE_BLUR")
        if V14.GlassBlur > 0 then
            if not blur then
                blur = Instance.new("BlurEffect")
                blur.Name = "FE_BUNDLE_BLUR"
                blur.Parent = Lighting
            end
            blur.Size = V14.GlassBlur
        elseif blur then
            blur:Destroy()
        end
    end)
end

local function v14SaveExtra()
    pcall(saveData)
    if CAN_SAVE then
        pcall(function()
            writefile("FE_BUNDLE_V14_EXTRA.json", HttpService:JSONEncode({
                UITransparency = V14.UITransparency,
                GlassBlur = V14.GlassBlur,
            }))
        end)
    end
end

local function v14LoadExtra()
    if not CAN_SAVE then return end
    local exists = false
    pcall(function() exists = isfile("FE_BUNDLE_V14_EXTRA.json") end)
    if not exists then return end
    local raw
    local ok = pcall(function() raw = readfile("FE_BUNDLE_V14_EXTRA.json") end)
    if not ok or not raw then return end
    local data
    pcall(function() data = HttpService:JSONDecode(raw) end)
    if type(data) == "table" then
        if type(data.UITransparency) == "number" then V14.UITransparency = math.clamp(data.UITransparency, 0, 0.85) end
        if type(data.GlassBlur) == "number" then V14.GlassBlur = math.clamp(data.GlassBlur, 0, 50) end
    end
end
v14LoadExtra()
v14ApplyGlass()

local function v14Button(parent, text, pos, size, callback, color, bucket)
    bucket = bucket or PageConnections
    local b = new("TextButton", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = color or Theme.Card,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
        Active = true,
        ZIndex = getZ and getZ(parent, 5) or z(parent, 5)
    })
    corner(b, 8)
    stroke(b, Theme.Black, 1, 0.15)
    local fired = false
    local function fire()
        if fired then return end
        fired = true
        task.delay(0.18, function() fired = false end)
        tween(b, {Size = size}, 0.06)
        if callback then callback() end
    end
    add(bucket, b.MouseButton1Click:Connect(fire))
    pcall(function() add(bucket, b.Activated:Connect(fire)) end)
    add(bucket, b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            tween(b, {Position = UDim2.new(pos.X.Scale, pos.X.Offset + 2, pos.Y.Scale, pos.Y.Offset + 2)}, 0.05)
        end
    end))
    add(bucket, b.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            tween(b, {Position = pos}, 0.05)
            if input.UserInputType == Enum.UserInputType.Touch then fire() end
        end
    end))
    return b
end

local function v14Label(parent, text, pos, size, textSize, color)
    return new("TextLabel", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundTransparency = 1,
        Text = tostring(text or ""),
        TextColor3 = color or Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = textSize or 13,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true,
        ZIndex = getZ and getZ(parent, 5) or z(parent, 5)
    })
end

local function v14Box(parent, placeholder, pos, size, text)
    local box = new("TextBox", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = text or "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.LightMuted,
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 13,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = getZ and getZ(parent, 5) or z(parent, 5)
    })
    corner(box, 8)
    stroke(box, Theme.Black, 1, 0.25)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = box
    return box
end

local function v14Panel(parent, pos, size, color)
    local p = new("Frame", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = color or Theme.Card,
        BorderSizePixel = 0,
        ZIndex = getZ and getZ(parent, 2) or z(parent, 2)
    })
    corner(p, 10)
    stroke(p, Theme.Black, 1, 0.1)
    tween(p, {BackgroundTransparency = 0}, 0.10)
    return p
end

local function v14CloseModal()
    if ModalCard then
        local card = ModalCard
        local dim = ModalDim
        ModalCard = nil
        ModalDim = nil
        tween(card, {Size = UDim2.new(0, 30, 0, 30), BackgroundTransparency = 1}, 0.12)
        if dim then tween(dim, {BackgroundTransparency = 1}, 0.12) end
        task.delay(0.14, function()
            if card then card:Destroy() end
            if dim then dim:Destroy() end
        end)
    end
end

closeInfoModal = v14CloseModal

showInfoModal = function(titleText, bodyText, imageId, actions, previewAnimId)
    v14CloseModal()
    ModalDim = new("Frame", {Parent = ScreenGui, Position = UDim2.new(0,0,0,0), Size = UDim2.new(1,0,1,0), BackgroundColor3 = Theme.Black, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6000})
    tween(ModalDim, {BackgroundTransparency = ModalDimTransparency}, 0.12)
    ModalCard = new("Frame", {Parent = ScreenGui, AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(0.5,0,0.5,0), Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = Theme.Page, BorderSizePixel = 0, ZIndex = 6001})
    corner(ModalCard, 16)
    stroke(ModalCard, Theme.Black, 2, 0)
    tween(ModalCard, {Size = UDim2.new(0, 500, 0, 350)}, 0.16)
    task.delay(0.03, function()
        if not ModalCard then return end
        if previewAnimId and normalizeId(previewAnimId) ~= "" then
            createAvatarPreview(ModalCard, previewAnimId)
        else
            local img = new("ImageLabel", {Parent = ModalCard, Position = UDim2.new(0,18,0,18), Size = UDim2.new(0,150,0,132), BackgroundColor3 = Theme.Field, BorderSizePixel = 0, Image = imageId or "", ScaleType = Enum.ScaleType.Fit, ZIndex = 6002})
            corner(img, 10)
            stroke(img, Theme.Black, 1, 0.25)
        end
        v14Label(ModalCard, titleText or "Info", UDim2.new(0, 186, 0, 18), UDim2.new(1, -230, 0, 44), 18, Theme.Text)
        local descScroll = new("ScrollingFrame", {Parent = ModalCard, Position = UDim2.new(0,186,0,68), Size = UDim2.new(1,-210,0,185), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0,0,0,260), ZIndex = 6002})
        v14Label(descScroll, bodyText or "No information.", UDim2.new(0,0,0,0), UDim2.new(1,-8,0,250), 13, Theme.Muted)
        v14Button(ModalCard, "X", UDim2.new(1,-42,0,12), UDim2.new(0,30,0,30), v14CloseModal, Theme.Red, Connections)
        v14Button(ModalCard, "CLOSE", UDim2.new(0,18,1,-48), UDim2.new(0,88,0,30), v14CloseModal, Theme.Red, Connections)
        local x = 116
        for _, act in ipairs(actions or {}) do
            v14Button(ModalCard, act.Text or "OK", UDim2.new(0,x,1,-48), UDim2.new(0,102,0,30), function()
                if act.Callback then act.Callback() end
                if act.Close ~= false then v14CloseModal() end
            end, act.Color or Theme.Cyan, Connections)
            x += 110
            if x > 420 then break end
        end
    end)
end

local function v14ShowItemInfo(item, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local creator = tostring(item.creatorName or item.CreatorName or "Unknown")
    local desc = tostring(item.description or item.Description or "No description available.")
    local imageId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    if kind == "Emote" then
        showLoading("Resolving emote preview...")
        task.spawn(function()
            local realId = v12ResolveEmoteAnimationId and v12ResolveEmoteAnimationId(id) or id
            hideLoading()
            local body = "Name: " .. name .. "\nCreator: " .. creator .. "\nSource: " .. tostring(V12 and V12.SourceFilter or "Roblox") .. "\nCatalog ID: " .. id .. "\nAnimation ID: " .. tostring(realId or "unknown") .. "\nLink: https://www.roblox.com/catalog/" .. id .. "\n\n" .. desc
            local actions = {
                {Text = "PLAY", Color = Theme.Green, Callback = function() playEmote(id, name) end, Close = false},
                {Text = "COPY ANIM.", Color = Theme.Cyan, Callback = function() copyToClipboard(realId or id) end, Close = false},
                {Text = (V12 and V12.PickerProvider == "Quick") and "QUICK S." or "FLOATING B.", Color = Theme.Orange, Callback = function() if v13CreatePickerShortcut then v13CreatePickerShortcut(item) elseif v12CreateFloatingButton then v12CreateFloatingButton(item) end end, Close = false},
                {Text = "FAVORITE", Color = Theme.Yellow, Callback = function() toggleFavorite(kind, item) end, Close = false},
            }
            showInfoModal(name, body, imageId, actions, realId)
        end)
    else
        local body = "Name: " .. name .. "\nCreator: " .. creator .. "\nBundle ID: " .. id .. "\nLink: https://www.roblox.com/bundles/" .. id .. "\n\n" .. desc
        local actions = {
            {Text = ChoosingState and "SET" or "APPLY", Color = Theme.Green, Callback = function() if ChoosingState then setCustomSlotFromBundle(ChoosingState, id, name) else applyBundleFull(id, name) end end},
            {Text = "FAVORITE", Color = Theme.Yellow, Callback = function() toggleFavorite(kind, item) end, Close = false},
        }
        showInfoModal(name, body, imageId, actions, nil)
    end
end

-- Override renderItemCard one last time with reliable INFO action and bigger mobile buttons.
renderItemCard = function(parent, item, index, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local creator = tostring(item.creatorName or item.CreatorName or "Unknown")
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = 12 + col * 250
    local y = 12 + row * 146
    local card = v14Panel(parent, UDim2.new(0,x,0,y), UDim2.new(0,238,0,134), Theme.Card)
    local imgId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img = new("ImageLabel", {Parent=card, Position=UDim2.new(0,10,0,10), Size=UDim2.new(0,82,0,74), BackgroundColor3=Theme.Field, BorderSizePixel=0, Image=imgId, ScaleType=Enum.ScaleType.Fit, ZIndex=getZ(card,4)})
    corner(img, 8)
    v14Label(card, name, UDim2.new(0,102,0,10), UDim2.new(1,-112,0,40), 13, Theme.Text)
    v14Label(card, creator, UDim2.new(0,102,0,50), UDim2.new(1,-112,0,18), 11, Theme.Muted)
    v14Label(card, kind .. " ID: " .. id, UDim2.new(0,102,0,68), UDim2.new(1,-112,0,18), 10, Theme.Muted)
    v14Button(card, kind == "Emote" and "PLAY" or (ChoosingState and ("SET "..string.upper(ChoosingState)) or "APPLY"), UDim2.new(0,10,1,-38), UDim2.new(0,88,0,28), function()
        if kind == "Emote" then playEmote(id, name) else if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end
    end, kind == "Emote" and Theme.Green or Theme.Orange)
    v14Button(card, "INFO", UDim2.new(0,106,1,-38), UDim2.new(0,70,0,28), function()
        v14ShowItemInfo(item, kind)
    end, Theme.Cyan)
    v14Button(card, isFavorite(kind=="Emote" and FavoritesEmotes or FavoritesBundles, id) and "★" or "☆", UDim2.new(0,184,1,-38), UDim2.new(0,42,0,28), function()
        toggleFavorite(kind, item)
        if CurrentPage == "Bundles" then renderHome("Bundle") elseif CurrentPage == "Emotes" then renderHome("Emote") end
    end, Theme.Yellow)
end

-- Re-render current visible page with final card implementation.
if Main and Main.Visible then
    if CurrentPage == "Emotes" then renderHome("Emote")
    elseif CurrentPage == "Bundles" then renderHome("Bundle")
    elseif CurrentPage == "Favorites" then renderFavorites()
    end
end

v14ApplyGlass()
notify("V14 UI/info fix applied", true)
