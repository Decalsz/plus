--[[
    Irenk Bundle + Emote Hub v8.4 - Saweria Pop
    One-file LocalScript for Delta / mobile

    Fixes:
    - Icon open/close stabil (threshold drag vs tap, no event conflict)
    - Icon & panel bisa di-drag lancar di Delta/mobile
    - Open/Close pakai pop-in & pop-out (scale + fade)
    - INFO modal: preview avatar kamu yang memainkan emote (bukan cuma gambar)
    - Tema Saweria lebih rapi, contrast bagus, font readable

    Fitur tetap:
    - Bundle search / apply full / custom mix
    - Emote search / play + INFO preview
    - Favorites, Save packs, Auto-load
    - Settings: speed, loop, move while emote, apply method, modal dim
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local SaveFile = "Irenk_BundleEmoteHub_v8_Save.json"
local CAN_FILES = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local Alive = true
local CurrentPage = "Bundles"
local ChoosingState = nil
local ApplyMethod = "Animate" -- Animate / Description / Both
local AutoLoad = true
local ModalDimTransparency = 0.45

local EmoteSpeed = 1
local EmoteLoop = true
local MoveWhileEmote = true
local CurrentEmoteTrack = nil
local PreviewTracks = {} -- tracks di modal preview

local BundleResults = {}
local EmoteResults = {}
local FavoriteBundles = {}
local FavoriteEmotes = {}
local SavedPacks = {}
local AutoLoadName = ""
local LastAppliedName = ""
local NextBundleCursor = nil
local NextEmoteCursor = nil
local LastBundleKeyword = "animation"
local LastEmoteKeyword = "dance"
local AnimationObjectCache = {}
local OriginalIds = {}

local States = {"Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim"}
local CurrentForm = {Idle="", Walk="", Run="", Jump="", Fall="", Climb="", Swim=""}
local SlotMeta = {Idle=nil, Walk=nil, Run=nil, Jump=nil, Fall=nil, Climb=nil, Swim=nil}

local Connections = {}
local PageConnections = {}
local LoadingActive = false
local AutoLoadingMore = false
local MainOpen = false
local MainAnimating = false

local ScreenGui, IconButton, Main, Body, HeaderTitle, StatusLabel
local ModalDim, ModalCard, LoadingDim, LoadingCard, LoadingBar
local SearchBox

-- Saweria-inspired theme (lebih hangat & clean)
local Theme = {
    Page = Color3.fromRGB(255, 252, 248),
    Paper = Color3.fromRGB(250, 246, 240),
    Card = Color3.fromRGB(245, 240, 232),
    Field = Color3.fromRGB(255, 255, 255),
    Header = Color3.fromRGB(255, 176, 32),
    Cyan = Color3.fromRGB(100, 210, 220),
    Orange = Color3.fromRGB(255, 176, 32),
    OrangeDeep = Color3.fromRGB(255, 140, 20),
    Green = Color3.fromRGB(90, 210, 160),
    Yellow = Color3.fromRGB(255, 210, 90),
    Red = Color3.fromRGB(255, 95, 110),
    Text = Color3.fromRGB(28, 28, 28),
    Muted = Color3.fromRGB(90, 95, 105),
    LightMuted = Color3.fromRGB(155, 160, 170),
    Black = Color3.fromRGB(18, 18, 18),
    Shadow = Color3.fromRGB(0, 0, 0)
}

local AnimateNames = {
    Idle = {"idle"}, Walk = {"walk"}, Run = {"run"}, Jump = {"jump"},
    Fall = {"fall"}, Climb = {"climb"}, Swim = {"swim", "swimidle"}
}

---------------------------------------------------------------------
-- BASIC HELPERS
---------------------------------------------------------------------

local function add(list, conn)
    table.insert(list or Connections, conn)
    return conn
end

local function disconnectList(list)
    for _, conn in ipairs(list) do
        pcall(function() conn:Disconnect() end)
    end
    for i = #list, 1, -1 do table.remove(list, i) end
end

local function new(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
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

local function tween(obj, props, time, style, dir)
    local ti = TweenInfo.new(
        time or 0.2,
        style or Enum.EasingStyle.Back,
        dir or Enum.EasingDirection.Out
    )
    local tw = TweenService:Create(obj, ti, props)
    pcall(function() tw:Play() end)
    return tw
end

local function clear(parent)
    if not parent then return end
    for _, c in ipairs(parent:GetChildren()) do c:Destroy() end
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

local function getParentGui()
    local pg = nil
    -- Delta / Synapse / Fluxus style
    pcall(function()
        if gethui then pg = gethui() end
    end)
    if pg then return pg end
    pcall(function()
        pg = game:GetService("CoreGui")
    end)
    if pg then return pg end
    pcall(function()
        pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
    end)
    return pg
end

local function safePrint(...)
    pcall(function()
        print("[IrenkHub]", ...)
    end)
end

local function status(text, good)
    if not StatusLabel then return end
    StatusLabel.Text = tostring(text or "")
    if good == true then
        StatusLabel.TextColor3 = Color3.fromRGB(40, 140, 100)
    elseif good == false then
        StatusLabel.TextColor3 = Theme.Red
    else
        StatusLabel.TextColor3 = Theme.Muted
    end
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

local function bundleThumbnail(id)
    return "rbxthumb://type=BundleThumbnail&id=" .. tostring(id) .. "&w=150&h=150"
end

local function assetThumbnail(id)
    return "rbxthumb://type=Asset&id=" .. tostring(id) .. "&w=150&h=150"
end

local function getCharHum()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animate = char and char:FindFirstChild("Animate")
    return char, hum, animate
end

---------------------------------------------------------------------
-- SAVE / LOAD
---------------------------------------------------------------------

local function saveData()
    if not CAN_FILES then return false end
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
        FavoriteBundles = FavoriteBundles,
        FavoriteEmotes = FavoriteEmotes,
        SavedPacks = SavedPacks
    }
    local ok = pcall(function() writefile(SaveFile, HttpService:JSONEncode(data)) end)
    return ok
end

local function loadData()
    if not CAN_FILES then return false end
    local exists = false
    pcall(function() exists = isfile(SaveFile) end)
    if not exists then return false end
    local raw
    local okRead = pcall(function() raw = readfile(SaveFile) end)
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
    if type(data.FavoriteBundles) == "table" then FavoriteBundles = data.FavoriteBundles end
    if type(data.FavoriteEmotes) == "table" then FavoriteEmotes = data.FavoriteEmotes end
    if type(data.SavedPacks) == "table" then SavedPacks = data.SavedPacks end
    return true
end

---------------------------------------------------------------------
-- HTTP / CATALOG
---------------------------------------------------------------------

local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" then return res end
    return nil, res
end

local function decodeJson(raw)
    if not raw then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok then return data end
    return nil
end

local function searchCatalog(kind, keyword, append)
    keyword = tostring(keyword or "")
    if keyword == "" then keyword = kind == "Emote" and "dance" or "animation" end
    local encoded = HttpService:UrlEncode(keyword)
    local cursor = kind == "Emote" and NextEmoteCursor or NextBundleCursor
    if not append then
        if kind == "Emote" then EmoteResults = {}; NextEmoteCursor = nil else BundleResults = {}; NextBundleCursor = nil end
        cursor = nil
    end
    local cursorParam = cursor and ("&Cursor=" .. HttpService:UrlEncode(cursor)) or ""
    local subcategory = kind == "Emote" and "39" or "38"
    local url = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=" .. subcategory .. "&Keyword=" .. encoded .. "&Limit=30&SortType=0" .. cursorParam
    local data = decodeJson(httpGet(url))
    if not data or type(data.data) ~= "table" then
        if kind == "Bundle" then
            local url2 = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=27&Keyword=" .. encoded .. "&Limit=30&SortType=0" .. cursorParam
            data = decodeJson(httpGet(url2))
        end
    end
    if not data or type(data.data) ~= "table" then return false, 0 end
    if kind == "Emote" then
        for _, item in ipairs(data.data) do table.insert(EmoteResults, item) end
        NextEmoteCursor = data.nextPageCursor
        LastEmoteKeyword = keyword
        return true, #EmoteResults
    else
        for _, item in ipairs(data.data) do table.insert(BundleResults, item) end
        NextBundleCursor = data.nextPageCursor
        LastBundleKeyword = keyword
        return true, #BundleResults
    end
end

local function fetchBundleDetails(bundleId)
    bundleId = normalizeId(bundleId)
    if bundleId == "" then return nil end
    return decodeJson(httpGet("https://catalog.roblox.com/v1/bundles/" .. bundleId .. "/details"))
end

---------------------------------------------------------------------
-- BUNDLE RESOLVER
---------------------------------------------------------------------

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
        local p = path .. "." .. child.Name
        if child:IsA("Animation") then
            local id = normalizeId(child.AnimationId)
            local state = categorizeAnimation(p)
            if id ~= "" and state and not output[state] then output[state] = id end
        end
        if #child:GetChildren() > 0 then scanAnimationTree(child, p, output) end
    end
end

local function resolveAnimationsFromAsset(assetId)
    assetId = normalizeId(assetId)
    if assetId == "" then return {} end
    if AnimationObjectCache[assetId] then return AnimationObjectCache[assetId] end
    local found = {}
    local ok, objects = pcall(function() return game:GetObjects("rbxassetid://" .. assetId) end)
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
        local itemId = tostring(item.id or item.Id or "")
        local assetType = tonumber(item.assetType or item.AssetType or item.assetTypeId or item.AssetTypeId)
        local state = assetTypeToState[assetType] or categorizeAnimation(item.name or item.Name)
        if state and not form[state] then form[state] = itemId end
    end

    return form
end

---------------------------------------------------------------------
-- APPLY ANIMATION
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
        for _, anim in ipairs(getAnimationsForState(state)) do table.insert(OriginalIds[state], anim.AnimationId) end
    end
end

local function restartAnimate()
    local _, _, animate = getCharHum()
    if animate then
        pcall(function()
            animate.Disabled = true
            task.wait(0.1)
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
            if id ~= "" then desc[prop] = tonumber(id) or 0; changed = changed + 1 end
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

local function showLoading(text)
    -- forward declare filled later
end

local function hideLoading()
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
        if renderCustom then renderCustom() end
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

---------------------------------------------------------------------
-- EMOTE
---------------------------------------------------------------------

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
        track.Priority = MoveWhileEmote and Enum.AnimationPriority.Action or Enum.AnimationPriority.Action4
        track.Looped = EmoteLoop
        track:Play(0.15, 1, EmoteSpeed)
    end)
    status("Playing emote: " .. tostring(name or assetId), true)
end

---------------------------------------------------------------------
-- LOADING OVERLAY
---------------------------------------------------------------------

showLoading = function(text)
    hideLoading()
    LoadingActive = true
    LoadingDim = new("Frame", {
        Parent = ScreenGui,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        ZIndex = 250
    })
    LoadingCard = new("Frame", {
        Parent = ScreenGui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 300, 0, 100),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        ZIndex = 251
    })
    corner(LoadingCard, 14)
    stroke(LoadingCard, Theme.Black, 2, 0)
    makeLabel(LoadingCard, text or "Loading...", UDim2.new(0, 16, 0, 14), UDim2.new(1, -32, 0, 28), 15, Theme.Text)
    local bg = new("Frame", {
        Parent = LoadingCard,
        Position = UDim2.new(0, 16, 0, 58),
        Size = UDim2.new(1, -32, 0, 14),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        ZIndex = 252
    })
    corner(bg, 8)
    stroke(bg, Theme.Black, 1, 0.4)
    LoadingBar = new("Frame", {
        Parent = bg,
        Position = UDim2.new(-0.35, 0, 0, 0),
        Size = UDim2.new(0.35, 0, 1, 0),
        BackgroundColor3 = Theme.Orange,
        BorderSizePixel = 0,
        ZIndex = 253
    })
    corner(LoadingBar, 8)
    task.spawn(function()
        while LoadingActive and LoadingBar and LoadingBar.Parent do
            LoadingBar.Position = UDim2.new(-0.35, 0, 0, 0)
            tween(LoadingBar, {Position = UDim2.new(1, 0, 0, 0)}, 0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            task.wait(0.9)
        end
    end)
end

hideLoading = function()
    LoadingActive = false
    if LoadingDim then LoadingDim:Destroy(); LoadingDim = nil end
    if LoadingCard then LoadingCard:Destroy(); LoadingCard = nil end
    LoadingBar = nil
end

---------------------------------------------------------------------
-- GUI HELPERS
---------------------------------------------------------------------

function makeLabel(parent, text, pos, size, textSize, color)
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
        ZIndex = 20
    })
end

local function makeButton(parent, text, pos, size, callback, color)
    local shadow = new("Frame", {
        Parent = parent,
        Position = UDim2.new(pos.X.Scale, pos.X.Offset + 2, pos.Y.Scale, pos.Y.Offset + 3),
        Size = size,
        BackgroundColor3 = Theme.Shadow,
        BackgroundTransparency = 0.78,
        BorderSizePixel = 0,
        ZIndex = 18
    })
    corner(shadow, 9)
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
        ZIndex = 21
    })
    corner(b, 9)
    stroke(b, Theme.Black, 1, 0.15)
    add(PageConnections, b.MouseButton1Down:Connect(function()
        tween(b, {Position = UDim2.new(pos.X.Scale, pos.X.Offset + 1, pos.Y.Scale, pos.Y.Offset + 1)}, 0.06, Enum.EasingStyle.Quad)
    end))
    add(PageConnections, b.MouseButton1Up:Connect(function()
        tween(b, {Position = pos}, 0.06, Enum.EasingStyle.Quad)
    end))
    add(PageConnections, b.MouseButton1Click:Connect(function()
        if callback then callback() end
    end))
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
        ZIndex = 21
    })
    corner(box, 9)
    stroke(box, Theme.Black, 1, 0.25)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = box
    return box
end

local function makePanel(parent, pos, size, color)
    local panel = new("Frame", {
        Parent = parent,
        Position = pos,
        Size = size,
        BackgroundColor3 = color or Theme.Card,
        BorderSizePixel = 0,
        ZIndex = 19
    })
    corner(panel, 11)
    stroke(panel, Theme.Black, 1, 0.12)
    return panel
end

---------------------------------------------------------------------
-- AVATAR PREVIEW (benar: clone avatar kamu + play emote)
---------------------------------------------------------------------

local function clearPreviewTracks()
    for _, t in ipairs(PreviewTracks) do
        pcall(function() t:Stop(0); t:Destroy() end)
    end
    PreviewTracks = {}
end

local function createAvatarPreview(parent, animId)
    clearPreviewTracks()

    local viewport = new("ViewportFrame", {
        Parent = parent,
        Position = UDim2.new(0, 16, 0, 16),
        Size = UDim2.new(0, 140, 0, 140),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Ambient = Color3.fromRGB(200, 200, 200),
        LightColor = Color3.fromRGB(255, 255, 255),
        LightDirection = Vector3.new(-1, -1, -1),
        ZIndex = 202
    })
    corner(viewport, 12)
    stroke(viewport, Theme.Black, 1, 0.2)

    local world = Instance.new("WorldModel")
    world.Parent = viewport

    local char = LocalPlayer.Character
    if not char then
        makeLabel(viewport, "No character", UDim2.new(0, 8, 0.4, 0), UDim2.new(1, -16, 0, 24), 12, Theme.Muted)
        return viewport
    end

    local oldArchivable = char.Archivable
    pcall(function() char.Archivable = true end)
    local clone = nil
    pcall(function() clone = char:Clone() end)
    pcall(function() char.Archivable = oldArchivable end)

    if not clone then
        makeLabel(viewport, "Clone failed", UDim2.new(0, 8, 0.4, 0), UDim2.new(1, -16, 0, 24), 12, Theme.Muted)
        return viewport
    end

    -- hapus script biar aman
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            d:Destroy()
        end
    end
    -- matikan Animate di clone
    local animScript = clone:FindFirstChild("Animate")
    if animScript then animScript:Destroy() end

    clone.Parent = world

    local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if root then
        clone.PrimaryPart = root
        pcall(function()
            root.Anchored = true
            clone:SetPrimaryPartCFrame(CFrame.new(0, -0.5, 0) * CFrame.Angles(0, math.rad(180), 0))
        end)
    end

    local cam = Instance.new("Camera")
    cam.Parent = viewport
    viewport.CurrentCamera = cam
    cam.CFrame = CFrame.new(Vector3.new(0, 1.8, 5.2), Vector3.new(0, 1.4, 0))
    cam.FieldOfView = 40

    local hum = clone:FindFirstChildOfClass("Humanoid")
    if hum and normalizeId(animId) ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = toAnimUrl(animId)
        local ok, track = pcall(function()
            return hum:LoadAnimation(anim)
        end)
        if ok and track then
            pcall(function()
                track.Looped = true
                track.Priority = Enum.AnimationPriority.Action4
                track:Play(0.12, 1, EmoteSpeed)
            end)
            table.insert(PreviewTracks, track)
        else
            makeLabel(viewport, "Anim load fail", UDim2.new(0, 6, 0.85, 0), UDim2.new(1, -12, 0, 18), 11, Theme.Red)
        end
    end

    return viewport
end

---------------------------------------------------------------------
-- INFO MODAL (pop style)
---------------------------------------------------------------------

function closeInfoModal()
    clearPreviewTracks()
    if not ModalCard then return end
    local card = ModalCard
    local dim = ModalDim
    ModalCard = nil
    ModalDim = nil
    tween(card, {
        Size = UDim2.new(0, 24, 0, 24),
        BackgroundTransparency = 1
    }, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    if dim then
        tween(dim, {BackgroundTransparency = 1}, 0.16, Enum.EasingStyle.Quad)
    end
    task.delay(0.18, function()
        if card then card:Destroy() end
        if dim then dim:Destroy() end
    end)
end

local function showInfoModal(titleText, bodyText, imageId, actions, previewAnimId)
    closeInfoModal()

    ModalDim = new("Frame", {
        Parent = ScreenGui,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 200
    })
    tween(ModalDim, {BackgroundTransparency = ModalDimTransparency}, 0.2, Enum.EasingStyle.Quad)

    ModalCard = new("Frame", {
        Parent = ScreenGui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 20, 0, 20),
        BackgroundColor3 = Theme.Page,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 201
    })
    corner(ModalCard, 16)
    stroke(ModalCard, Theme.Black, 2, 0)

    -- pop in
    tween(ModalCard, {Size = UDim2.new(0, 460, 0, 340)}, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    task.delay(0.05, function()
        if not ModalCard then return end

        if previewAnimId then
            createAvatarPreview(ModalCard, previewAnimId)
        else
            local img = new("ImageLabel", {
                Parent = ModalCard,
                Position = UDim2.new(0, 16, 0, 16),
                Size = UDim2.new(0, 140, 0, 140),
                BackgroundColor3 = Theme.Field,
                BorderSizePixel = 0,
                Image = imageId or "",
                ScaleType = Enum.ScaleType.Fit,
                ZIndex = 202
            })
            corner(img, 12)
            stroke(img, Theme.Black, 1, 0.2)
        end

        makeLabel(ModalCard, titleText or "Info", UDim2.new(0, 172, 0, 18), UDim2.new(1, -196, 0, 40), 17, Theme.Text)
        makeLabel(ModalCard, bodyText or "No information.", UDim2.new(0, 172, 0, 62), UDim2.new(1, -190, 0, 180), 13, Theme.Muted)

        makeButton(ModalCard, "CLOSE", UDim2.new(0, 16, 1, -48), UDim2.new(0, 90, 0, 32), closeInfoModal, Theme.Red)

        local x = 116
        for _, act in ipairs(actions or {}) do
            makeButton(ModalCard, act.Text or "OK", UDim2.new(0, x, 1, -48), UDim2.new(0, 100, 0, 32), function()
                if act.Callback then act.Callback() end
                if act.Close ~= false then closeInfoModal() end
            end, act.Color or Theme.Cyan)
            x = x + 108
        end
    end)
end

---------------------------------------------------------------------
-- MAIN OPEN / CLOSE (pop in / pop out)
---------------------------------------------------------------------

local function openMain()
    if MainAnimating or MainOpen then return end
    MainAnimating = true
    Main.Visible = true
    Main.Size = UDim2.new(0, 40, 0, 40)
    Main.BackgroundTransparency = 0.4
    Main.Position = UDim2.new(0.5, 0, 0.5, 0)

    local targetSize = UDim2.new(0, 580, 0, 540)
    tween(Main, {
        Size = targetSize,
        BackgroundTransparency = 0
    }, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    task.delay(0.05, function()
        if not Body:FindFirstChildWhichIsA("GuiObject") then
            local ok, err = pcall(function() renderHome("Bundle") end)
            if not ok then status("Open error: " .. tostring(err), false) end
        end
    end)

    task.delay(0.35, function()
        MainOpen = true
        MainAnimating = false
    end)
end

local function closeMain()
    if MainAnimating or not MainOpen then return end
    MainAnimating = true
    closeInfoModal()
    hideLoading()

    tween(Main, {
        Size = UDim2.new(0, 36, 0, 36),
        BackgroundTransparency = 0.6
    }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In)

    task.delay(0.24, function()
        Main.Visible = false
        Main.BackgroundTransparency = 0
        Main.Size = UDim2.new(0, 580, 0, 540)
        MainOpen = false
        MainAnimating = false
    end)
end

local function toggleMain()
    if MainAnimating then return end
    if MainOpen then
        closeMain()
    else
        openMain()
    end
end

---------------------------------------------------------------------
-- PAGES
---------------------------------------------------------------------

local renderHome, renderCustom, renderFavorites, renderSave, renderSettings

local function setPage(page)
    CurrentPage = page
    disconnectList(PageConnections)
    clear(Body)
    if HeaderTitle then
        HeaderTitle.Text = page == "Bundles" and "Irenk Bundle Hub" or page
    end
end

local function tabs()
    makeButton(Body, "BUNDLES", UDim2.new(0, 10, 0, 6), UDim2.new(0, 84, 0, 30), function() renderHome("Bundle") end, CurrentPage == "Bundles" and Theme.Cyan or Theme.Card)
    makeButton(Body, "EMOTES", UDim2.new(0, 100, 0, 6), UDim2.new(0, 78, 0, 30), function() renderHome("Emote") end, CurrentPage == "Emotes" and Theme.Cyan or Theme.Card)
    makeButton(Body, "CUSTOM", UDim2.new(0, 184, 0, 6), UDim2.new(0, 84, 0, 30), function() renderCustom() end, CurrentPage == "Custom" and Theme.Cyan or Theme.Card)
    makeButton(Body, "FAVS", UDim2.new(0, 274, 0, 6), UDim2.new(0, 62, 0, 30), function() renderFavorites() end, CurrentPage == "Favorites" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SAVE", UDim2.new(0, 342, 0, 6), UDim2.new(0, 62, 0, 30), function() renderSave() end, CurrentPage == "Save" and Theme.Cyan or Theme.Card)
    makeButton(Body, "SET", UDim2.new(0, 410, 0, 6), UDim2.new(0, 54, 0, 30), function() renderSettings() end, CurrentPage == "Settings" and Theme.Cyan or Theme.Card)
end

local function isFavorite(list, id)
    id = tostring(id)
    for _, item in ipairs(list) do
        if tostring(item.id) == id then return true end
    end
    return false
end

local function toggleFavorite(kind, item)
    local list = kind == "Emote" and FavoriteEmotes or FavoriteBundles
    local id = tostring(item.id or item.Id or "")
    for i, fav in ipairs(list) do
        if tostring(fav.id) == id then
            table.remove(list, i)
            saveData()
            status("Removed favorite", true)
            return
        end
    end
    table.insert(list, {
        id = id,
        name = tostring(item.name or item.Name or (kind .. " " .. id)),
        kind = kind
    })
    saveData()
    status("Added favorite", true)
end

local function renderItemCard(parent, item, index, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or (kind .. " " .. id))
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local x = 10 + col * 252
    local y = 10 + row * 138
    local card = makePanel(parent, UDim2.new(0, x, 0, y), UDim2.new(0, 240, 0, 126), Theme.Card)

    local imgId = kind == "Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img = new("ImageLabel", {
        Parent = card,
        Position = UDim2.new(0, 10, 0, 10),
        Size = UDim2.new(0, 78, 0, 70),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Image = imgId,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 20
    })
    corner(img, 9)

    makeLabel(card, name, UDim2.new(0, 98, 0, 10), UDim2.new(1, -108, 0, 42), 12, Theme.Text)
    makeLabel(card, kind .. " ID: " .. id, UDim2.new(0, 98, 0, 54), UDim2.new(1, -108, 0, 18), 11, Theme.Muted)

    makeButton(card, kind == "Emote" and "PLAY" or (ChoosingState and ("SET " .. string.upper(ChoosingState)) or "APPLY"),
        UDim2.new(0, 10, 1, -34), UDim2.new(0, 90, 0, 24), function()
            if kind == "Emote" then
                playEmote(id, name)
            else
                if ChoosingState then
                    setCustomSlotFromBundle(ChoosingState, id, name)
                else
                    applyBundleFull(id, name)
                end
            end
        end, kind == "Emote" and Theme.Green or Theme.Orange)

    makeButton(card, "INFO", UDim2.new(0, 108, 1, -34), UDim2.new(0, 58, 0, 24), function()
        local body = kind .. ": " .. name .. "\nID: " .. id .. "\n\n"
        if kind == "Emote" then
            body = body .. "Preview avatar kamu di kiri.\nSpeed / loop bisa diubah di Settings."
        else
            body = body .. (ChoosingState and ("Akan di-set ke: " .. ChoosingState) or "Apply full bundle atau mix di Custom.")
        end
        local actions = {}
        if kind == "Emote" then
            table.insert(actions, {
                Text = "PLAY",
                Color = Theme.Green,
                Callback = function() playEmote(id, name) end,
                Close = false
            })
        else
            table.insert(actions, {
                Text = ChoosingState and "SET" or "APPLY",
                Color = Theme.Green,
                Callback = function()
                    if ChoosingState then
                        setCustomSlotFromBundle(ChoosingState, id, name)
                    else
                        applyBundleFull(id, name)
                    end
                end
            })
        end
        table.insert(actions, {
            Text = "FAV",
            Color = Theme.Yellow,
            Callback = function() toggleFavorite(kind, item) end,
            Close = false
        })
        -- previewAnimId hanya untuk emote → avatar kamu main emote
        showInfoModal(name, body, imgId, actions, kind == "Emote" and id or nil)
    end, Theme.Cyan)

    makeButton(card, isFavorite(kind == "Emote" and FavoriteEmotes or FavoriteBundles, id) and "★" or "☆",
        UDim2.new(0, 174, 1, -34), UDim2.new(0, 42, 0, 24), function()
            toggleFavorite(kind, item)
            if CurrentPage == "Bundles" then renderHome("Bundle")
            elseif CurrentPage == "Emotes" then renderHome("Emote") end
        end, Theme.Yellow)
end

renderHome = function(kind)
    kind = kind or (CurrentPage == "Emotes" and "Emote" or "Bundle")
    setPage(kind == "Emote" and "Emotes" or "Bundles")
    tabs()

    local placeholder = kind == "Emote" and "Search emotes: dance, pose, laugh..." or "Search bundles: ninja, robot, zombie..."
    SearchBox = makeBox(Body, placeholder, UDim2.new(0, 10, 0, 46), UDim2.new(1, -140, 0, 36))
    SearchBox.Text = kind == "Emote" and (LastEmoteKeyword ~= "dance" and LastEmoteKeyword or "") or (LastBundleKeyword ~= "animation" and LastBundleKeyword or "")

    makeButton(Body, "SEARCH", UDim2.new(1, -120, 0, 46), UDim2.new(0, 110, 0, 36), function()
        showLoading("Loading " .. string.lower(kind) .. "s...")
        task.spawn(function()
            local ok, count = searchCatalog(kind, SearchBox.Text, false)
            hideLoading()
            if ok then
                renderHome(kind)
                status("Loaded " .. tostring(count) .. " " .. string.lower(kind) .. "s", true)
            else
                status("Search failed. Check HTTP support.", false)
            end
        end)
    end, Theme.Cyan)

    local hint = kind == "Emote" and "Tap INFO → lihat preview avatar kamu main emote." or (ChoosingState and ("Choosing: " .. ChoosingState .. " | tap card untuk set.") or "Apply full bundle atau mix di Custom.")
    makeLabel(Body, hint, UDim2.new(0, 10, 0, 90), UDim2.new(1, -20, 0, 22), 12, kind == "Bundle" and ChoosingState and Theme.Red or Theme.Muted)

    local scroll = new("ScrollingFrame", {
        Parent = Body,
        Position = UDim2.new(0, 10, 0, 116),
        Size = UDim2.new(1, -20, 1, -150),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Theme.Orange,
        CanvasSize = UDim2.new(0, 0, 0, 380),
        ZIndex = 19
    })
    corner(scroll, 10)
    stroke(scroll, Theme.Black, 1, 0.3)

    local list = kind == "Emote" and EmoteResults or BundleResults
    if #list == 0 then
        makeLabel(scroll, "Loading popular " .. string.lower(kind) .. "s...", UDim2.new(0, 14, 0, 14), UDim2.new(0, 260, 0, 28), 15, Theme.Muted)
    else
        for i, item in ipairs(list) do
            renderItemCard(scroll, item, i, kind)
        end
        local rows = math.ceil(#list / 2)
        scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(360, rows * 138 + 50))

        local hasNext = kind == "Emote" and NextEmoteCursor or NextBundleCursor
        if hasNext then
            makeLabel(scroll, "Scroll ke bawah untuk load more...", UDim2.new(0, 14, 0, rows * 138 + 14), UDim2.new(0, 280, 0, 24), 12, Theme.Muted)
            add(PageConnections, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if AutoLoadingMore then return end
                local bottom = scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y
                local limit = scroll.CanvasSize.Y.Offset - 40
                if bottom >= limit then
                    AutoLoadingMore = true
                    showLoading("Loading more...")
                    task.spawn(function()
                        local ok = searchCatalog(kind, kind == "Emote" and LastEmoteKeyword or LastBundleKeyword, true)
                        hideLoading()
                        AutoLoadingMore = false
                        if ok then renderHome(kind) end
                    end)
                end
            end))
        end
    end
end

renderCustom = function()
    setPage("Custom")
    tabs()
    makeLabel(Body, "Customize / mix animation pack", UDim2.new(0, 10, 0, 46), UDim2.new(1, -20, 0, 22), 14, Theme.Text)

    local scroll = new("ScrollingFrame", {
        Parent = Body,
        Position = UDim2.new(0, 10, 0, 76),
        Size = UDim2.new(1, -20, 1, -110),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Theme.Orange,
        CanvasSize = UDim2.new(0, 0, 0, 430),
        ZIndex = 19
    })
    corner(scroll, 10)
    stroke(scroll, Theme.Black, 1, 0.3)

    local y = 10
    for _, state in ipairs(States) do
        local panel = makePanel(scroll, UDim2.new(0, 10, 0, y), UDim2.new(1, -30, 0, 48), Theme.Card)
        makeLabel(panel, state, UDim2.new(0, 10, 0, 4), UDim2.new(0, 60, 0, 40), 13, Theme.Text)
        local meta = SlotMeta[state]
        local text = meta and ((meta.Bundle or "Bundle") .. " | ID " .. tostring(meta.Id or "")) or "not set"
        makeLabel(panel, text, UDim2.new(0, 78, 0, 4), UDim2.new(1, -240, 0, 40), 12, meta and Theme.Muted or Theme.LightMuted)
        makeButton(panel, "SET", UDim2.new(1, -150, 0, 9), UDim2.new(0, 44, 0, 28), function()
            ChoosingState = state
            renderHome("Bundle")
        end, Theme.Green)
        makeButton(panel, "INFO", UDim2.new(1, -100, 0, 9), UDim2.new(0, 52, 0, 28), function()
            local body = meta and ("State: " .. state .. "\nBundle: " .. tostring(meta.Bundle) .. "\nBundle ID: " .. tostring(meta.BundleId) .. "\nAnimation ID: " .. tostring(meta.Id)) or ("State: " .. state .. "\nBelum ada animasi.")
            showInfoModal("Custom Slot: " .. state, body, meta and bundleThumbnail(meta.BundleId) or "", {})
        end, Theme.Cyan)
        makeButton(panel, "X", UDim2.new(1, -42, 0, 9), UDim2.new(0, 30, 0, 28), function()
            CurrentForm[state] = ""
            SlotMeta[state] = nil
            saveData()
            renderCustom()
        end, Theme.Red)
        y = y + 56
    end

    makeButton(scroll, "APPLY CUSTOM PACK", UDim2.new(0, 10, 0, y + 6), UDim2.new(0, 180, 0, 32), function()
        LastAppliedName = "Custom Mix"
        applyCurrentForm("Custom Mix")
    end, Theme.Orange)
    makeButton(scroll, "CLEAR MIX", UDim2.new(0, 200, 0, y + 6), UDim2.new(0, 110, 0, 32), function()
        for _, st in ipairs(States) do
            CurrentForm[st] = ""
            SlotMeta[st] = nil
        end
        saveData()
        renderCustom()
    end, Theme.Red)
    scroll.CanvasSize = UDim2.new(0, 0, 0, y + 55)
end

renderFavorites = function()
    setPage("Favorites")
    tabs()
    makeLabel(Body, "Favorite bundles & emotes", UDim2.new(0, 10, 0, 46), UDim2.new(1, -20, 0, 22), 14, Theme.Text)

    local scroll = new("ScrollingFrame", {
        Parent = Body,
        Position = UDim2.new(0, 10, 0, 76),
        Size = UDim2.new(1, -20, 1, -110),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Theme.Orange,
        CanvasSize = UDim2.new(0, 0, 0, 380),
        ZIndex = 19
    })
    corner(scroll, 10)
    stroke(scroll, Theme.Black, 1, 0.3)

    local idx = 1
    for _, fav in ipairs(FavoriteBundles) do
        renderItemCard(scroll, fav, idx, "Bundle")
        idx = idx + 1
    end
    for _, fav in ipairs(FavoriteEmotes) do
        renderItemCard(scroll, fav, idx, "Emote")
        idx = idx + 1
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(360, math.ceil((idx - 1) / 2) * 138 + 50))
end

renderSave = function()
    setPage("Save")
    tabs()
    makeLabel(Body, "Save / Auto-load current pack", UDim2.new(0, 10, 0, 46), UDim2.new(1, -20, 0, 22), 14, Theme.Text)

    local nameBox = makeBox(Body, "Name save as...", UDim2.new(0, 10, 0, 76), UDim2.new(0, 220, 0, 34))
    makeButton(Body, "SAVE CURRENT", UDim2.new(0, 240, 0, 76), UDim2.new(0, 140, 0, 34), function()
        local name = tostring(nameBox.Text or "")
        if name == "" then name = "Saved Pack " .. tostring(#SavedPacks + 1) end
        table.insert(SavedPacks, {
            Name = name,
            Form = tableCopy(CurrentForm),
            Meta = tableCopy(SlotMeta)
        })
        saveData()
        renderSave()
        status("Saved: " .. name, true)
    end, Theme.Green)

    local scroll = new("ScrollingFrame", {
        Parent = Body,
        Position = UDim2.new(0, 10, 0, 122),
        Size = UDim2.new(1, -20, 1, -156),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Theme.Orange,
        CanvasSize = UDim2.new(0, 0, 0, 360),
        ZIndex = 19
    })
    corner(scroll, 10)
    stroke(scroll, Theme.Black, 1, 0.3)

    local y = 10
    for i, pack in ipairs(SavedPacks) do
        local panel = makePanel(scroll, UDim2.new(0, 10, 0, y), UDim2.new(1, -30, 0, 54), Theme.Card)
        local name = tostring(pack.Name or ("Pack " .. i))
        local auto = AutoLoadName == name and " [AUTO]" or ""
        makeLabel(panel, name .. auto, UDim2.new(0, 10, 0, 4), UDim2.new(1, -240, 0, 22), 13, Theme.Text)
        makeLabel(panel, "Use / edit / delete / set autoload", UDim2.new(0, 10, 0, 28), UDim2.new(1, -240, 0, 18), 11, Theme.Muted)
        makeButton(panel, "AUTO", UDim2.new(1, -220, 0, 12), UDim2.new(0, 50, 0, 28), function()
            AutoLoadName = name
            AutoLoad = true
            saveData()
            renderSave()
        end, AutoLoadName == name and Theme.Green or Theme.Cyan)
        makeButton(panel, "USE", UDim2.new(1, -162, 0, 12), UDim2.new(0, 46, 0, 28), function()
            CurrentForm = tableCopy(pack.Form)
            SlotMeta = tableCopy(pack.Meta)
            LastAppliedName = name
            applyCurrentForm(name)
        end, Theme.Orange)
        makeButton(panel, "EDIT", UDim2.new(1, -108, 0, 12), UDim2.new(0, 48, 0, 28), function()
            CurrentForm = tableCopy(pack.Form)
            SlotMeta = tableCopy(pack.Meta)
            renderCustom()
        end, Theme.Cyan)
        makeButton(panel, "DEL", UDim2.new(1, -52, 0, 12), UDim2.new(0, 40, 0, 28), function()
            table.remove(SavedPacks, i)
            saveData()
            renderSave()
        end, Theme.Red)
        y = y + 62
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(360, y + 16))
end

renderSettings = function()
    setPage("Settings")
    tabs()
    makeLabel(Body, "Settings", UDim2.new(0, 10, 0, 46), UDim2.new(1, -20, 0, 22), 14, Theme.Text)

    makeLabel(Body, "Emote Speed", UDim2.new(0, 10, 0, 80), UDim2.new(0, 160, 0, 20), 12, Theme.Muted)
    local speedBox = makeBox(Body, "Speed: 1, 1.5, 2, 5...", UDim2.new(0, 10, 0, 106), UDim2.new(0, 210, 0, 32))
    speedBox.Text = tostring(EmoteSpeed)

    makeButton(Body, "APPLY", UDim2.new(0, 230, 0, 106), UDim2.new(0, 90, 0, 32), function()
        local n = tonumber(speedBox.Text)
        if not n then status("Invalid speed", false); return end
        EmoteSpeed = n
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end
        saveData()
        status("Speed = " .. tostring(EmoteSpeed) .. "x", true)
        renderSettings()
    end, Theme.Green)

    makeButton(Body, "1x", UDim2.new(0, 330, 0, 106), UDim2.new(0, 44, 0, 32), function()
        EmoteSpeed = 1
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(1) end) end
        saveData()
        renderSettings()
    end, EmoteSpeed == 1 and Theme.Green or Theme.Card)

    makeButton(Body, "+0.5", UDim2.new(0, 382, 0, 106), UDim2.new(0, 52, 0, 32), function()
        EmoteSpeed = EmoteSpeed + 0.5
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end
        saveData()
        renderSettings()
    end, Theme.Card)

    makeButton(Body, "-0.5", UDim2.new(0, 442, 0, 106), UDim2.new(0, 50, 0, 32), function()
        EmoteSpeed = EmoteSpeed - 0.5
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end
        saveData()
        renderSettings()
    end, Theme.Card)

    makeLabel(Body, "Current: " .. tostring(EmoteSpeed) .. "x", UDim2.new(0, 10, 0, 146), UDim2.new(1, -20, 0, 20), 12, Theme.Muted)

    makeButton(Body, EmoteLoop and "LOOP: ON" or "LOOP: OFF", UDim2.new(0, 10, 0, 176), UDim2.new(0, 120, 0, 32), function()
        EmoteLoop = not EmoteLoop
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack.Looped = EmoteLoop end) end
        saveData()
        renderSettings()
    end, EmoteLoop and Theme.Green or Theme.Card)

    makeButton(Body, MoveWhileEmote and "MOVE: ON" or "MOVE: OFF", UDim2.new(0, 140, 0, 176), UDim2.new(0, 120, 0, 32), function()
        MoveWhileEmote = not MoveWhileEmote
        saveData()
        renderSettings()
    end, MoveWhileEmote and Theme.Green or Theme.Card)

    makeLabel(Body, "Modal background transparency", UDim2.new(0, 10, 0, 224), UDim2.new(1, -20, 0, 20), 12, Theme.Muted)
    local dims = {{"25%", 0.25}, {"45%", 0.45}, {"65%", 0.65}, {"80%", 0.80}}
    local x = 10
    for _, d in ipairs(dims) do
        makeButton(Body, d[1], UDim2.new(0, x, 0, 250), UDim2.new(0, 68, 0, 30), function()
            ModalDimTransparency = d[2]
            saveData()
            renderSettings()
        end, math.abs(ModalDimTransparency - d[2]) < 0.01 and Theme.Green or Theme.Card)
        x = x + 76
    end

    makeLabel(Body, "Apply Method", UDim2.new(0, 10, 0, 298), UDim2.new(0, 160, 0, 20), 12, Theme.Muted)
    makeButton(Body, "ANIMATE", UDim2.new(0, 10, 0, 324), UDim2.new(0, 96, 0, 30), function()
        ApplyMethod = "Animate"; saveData(); renderSettings()
    end, ApplyMethod == "Animate" and Theme.Green or Theme.Card)
    makeButton(Body, "DESCRIPTION", UDim2.new(0, 116, 0, 324), UDim2.new(0, 120, 0, 30), function()
        ApplyMethod = "Description"; saveData(); renderSettings()
    end, ApplyMethod == "Description" and Theme.Green or Theme.Card)
    makeButton(Body, "BOTH", UDim2.new(0, 246, 0, 324), UDim2.new(0, 80, 0, 30), function()
        ApplyMethod = "Both"; saveData(); renderSettings()
    end, ApplyMethod == "Both" and Theme.Green or Theme.Card)

    makeButton(Body, AutoLoad and "AUTOLOAD: ON" or "AUTOLOAD: OFF", UDim2.new(0, 10, 0, 374), UDim2.new(0, 140, 0, 30), function()
        AutoLoad = not AutoLoad; saveData(); renderSettings()
    end, AutoLoad and Theme.Green or Theme.Card)

    makeButton(Body, "STOP EMOTE", UDim2.new(0, 160, 0, 374), UDim2.new(0, 110, 0, 30), stopEmote, Theme.Red)
    makeButton(Body, "RESET ORIGINAL", UDim2.new(0, 280, 0, 374), UDim2.new(0, 130, 0, 30), restoreOriginal, Theme.Yellow)
end

---------------------------------------------------------------------
-- PIXEL ICON (Saweria-ish)
---------------------------------------------------------------------

local function drawPixelIcon(parent)
    local grid = {
        "000011110000",
        "000111111000",
        "001111111100",
        "011112211110",
        "011122221110",
        "111233332111",
        "112333333211",
        "112393393211",
        "112333333211",
        "011233332110",
        "001122221100",
        "000111111000"
    }
    local colors = {
        ["1"] = Color3.fromRGB(12, 24, 60),
        ["2"] = Color3.fromRGB(36, 52, 100),
        ["3"] = Color3.fromRGB(240, 140, 170),
        ["9"] = Color3.fromRGB(255, 50, 75)
    }
    local holder = new("Frame", {
        Parent = parent,
        Position = UDim2.new(0, 8, 0, 8),
        Size = UDim2.new(1, -16, 1, -16),
        BackgroundTransparency = 1,
        Active = false,
        ZIndex = 82
    })
    local n = 12
    for yy, row in ipairs(grid) do
        for xx = 1, n do
            local col = colors[string.sub(row, xx, xx)]
            if col then
                new("Frame", {
                    Parent = holder,
                    Position = UDim2.new((xx - 1) / n, 0, (yy - 1) / n, 0),
                    Size = UDim2.new(1 / n, 1, 1 / n, 1),
                    BackgroundColor3 = col,
                    BorderSizePixel = 0,
                    Active = false,
                    ZIndex = 83
                })
            end
        end
    end
end

---------------------------------------------------------------------
-- GUI CREATE + FIXED DRAG / TAP
---------------------------------------------------------------------

local function createGui()
    local pg = getParentGui()
    if not pg then
        safePrint("ERROR: no parent GUI (PlayerGui/CoreGui/gethui failed)")
        return false
    end
    safePrint("Parent GUI:", pg:GetFullName())

    pcall(function()
        for _, name in ipairs({
            "IrenkBundleAnimationHub", "IrenkBundleAnimationHubV2", "IrenkBundleAnimationHubV3",
            "IrenkBundleAnimationHubV4Saweria", "IrenkBundleAnimationHubV5CleanSaweria",
            "IrenkBundleAnimationHubV6CleanSaweria", "IrenkBundleAnimationHubV7OriginalSaweria",
            "IrenkBundleEmoteHubV8InfoSaweria", "IrenkBundleEmoteHubV83InfoSaweria",
            "IrenkBundleEmoteHubV84SaweriaPop"
        }) do
            local old = pg:FindFirstChild(name)
            if old then old:Destroy() end
        end
        -- also clean PlayerGui / CoreGui leftovers
        for _, svc in ipairs({game:GetService("CoreGui"), LocalPlayer:FindFirstChild("PlayerGui")}) do
            if svc then
                for _, name in ipairs({"IrenkBundleEmoteHubV84SaweriaPop", "IrenkBundleEmoteHubV83InfoSaweria"}) do
                    local o = svc:FindFirstChild(name)
                    if o then o:Destroy() end
                end
            end
        end
    end)

    ScreenGui = new("ScreenGui", {
        Name = "IrenkBundleEmoteHubV84SaweriaPop",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
        Enabled = true
    })

    -- protect GUI on executors that support it
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
    end)
    pcall(function()
        if protect_gui then protect_gui(ScreenGui) end
    end)

    local parentOk = pcall(function()
        ScreenGui.Parent = pg
    end)
    if not parentOk or not ScreenGui.Parent then
        -- fallback PlayerGui
        pcall(function()
            ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui", 3)
        end)
    end
    if not ScreenGui.Parent then
        safePrint("ERROR: failed to parent ScreenGui")
        return false
    end
    safePrint("ScreenGui parented to", ScreenGui.Parent:GetFullName())

    -- ICON BUTTON (lebih besar + label biar kelihatan)
    IconButton = new("TextButton", {
        Parent = ScreenGui,
        Position = UDim2.new(0, 16, 0.45, 0),
        Size = UDim2.new(0, 64, 0, 64),
        BackgroundColor3 = Theme.Orange,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 100,
        Active = true,
        Visible = true
    })
    corner(IconButton, 16)
    stroke(IconButton, Theme.Black, 2.5, 0)
    drawPixelIcon(IconButton)

    -- label kecil di bawah icon biar user tau ini hub
    local IconTag = new("TextLabel", {
        Parent = ScreenGui,
        Position = UDim2.new(0, 10, 0.45, 66),
        Size = UDim2.new(0, 76, 0, 16),
        BackgroundTransparency = 1,
        Text = "IRENK",
        TextColor3 = Theme.Orange,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 101
    })
    -- simpan biar ikut gerak saat drag
    IconButton:SetAttribute("HasTag", true)

    -- MAIN FRAME
    Main = new("Frame", {
        Parent = ScreenGui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 580, 0, 540),
        BackgroundColor3 = Theme.Page,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 10
    })
    corner(Main, 16)
    stroke(Main, Theme.Black, 2, 0)

    local header = new("Frame", {
        Parent = Main,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = Theme.Orange,
        BorderSizePixel = 0,
        ZIndex = 11
    })
    corner(header, 16)
    new("Frame", {
        Parent = header,
        Position = UDim2.new(0, 0, 1, -16),
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundColor3 = Theme.Orange,
        BorderSizePixel = 0,
        ZIndex = 11
    })

    HeaderTitle = makeLabel(Main, "Irenk Bundle Hub", UDim2.new(0, 16, 0, 6), UDim2.new(1, -90, 0, 26), 20, Theme.Text)
    makeLabel(Main, "bundles · emotes · custom mix · favorites", UDim2.new(0, 16, 0, 32), UDim2.new(1, -100, 0, 16), 11, Theme.Muted)

    -- Close button (permanent, bukan page connection)
    local CloseButton = new("TextButton", {
        Parent = Main,
        Position = UDim2.new(1, -46, 0, 11),
        Size = UDim2.new(0, 32, 0, 30),
        BackgroundColor3 = Theme.Red,
        BorderSizePixel = 0,
        Text = "X",
        TextColor3 = Theme.Text,
        TextStrokeTransparency = 1,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        ZIndex = 120
    })
    corner(CloseButton, 8)
    stroke(CloseButton, Theme.Black, 1, 0)
    add(Connections, CloseButton.MouseButton1Click:Connect(function()
        closeMain()
    end))

    Body = new("Frame", {
        Parent = Main,
        Position = UDim2.new(0, 10, 0, 62),
        Size = UDim2.new(1, -20, 1, -96),
        BackgroundTransparency = 1,
        ZIndex = 18
    })

    StatusLabel = makeLabel(Main, "Ready", UDim2.new(0, 14, 1, -30), UDim2.new(1, -28, 0, 22), 12, Theme.Muted)

    -----------------------------------------------------------------
    -- HEADER DRAG (panel)
    -----------------------------------------------------------------
    local HeaderDrag = new("TextButton", {
        Parent = Main,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, -50, 0, 56),
        BackgroundTransparency = 1,
        Text = "",
        BorderSizePixel = 0,
        Active = true,
        AutoButtonColor = false,
        ZIndex = 115
    })

    local mainDragging = false
    local mainDragInput, mainStart, mainPos

    add(Connections, HeaderDrag.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            mainDragging = true
            mainDragInput = input
            mainStart = input.Position
            mainPos = Main.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    mainDragging = false
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end))

    add(Connections, UserInputService.InputChanged:Connect(function(input)
        if mainDragging and input == mainDragInput then
            local d = input.Position - mainStart
            Main.Position = UDim2.new(
                mainPos.X.Scale, mainPos.X.Offset + d.X,
                mainPos.Y.Scale, mainPos.Y.Offset + d.Y
            )
        end
    end))

    -----------------------------------------------------------------
    -- ICON: TAP vs DRAG (threshold) — ini yang bikin stabil di Delta
    -----------------------------------------------------------------
    local iconDragging = false
    local iconMoved = false
    local iconDragInput, iconStart, iconPos
    local DRAG_THRESHOLD = 12 -- pixel; di bawah ini dianggap TAP

    add(Connections, IconButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            iconDragging = true
            iconMoved = false
            iconDragInput = input
            iconStart = input.Position
            iconPos = IconButton.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    iconDragging = false
                    -- kalau hampir tidak digeser → TAP → toggle
                    if not iconMoved then
                        toggleMain()
                    end
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end))

    add(Connections, UserInputService.InputChanged:Connect(function(input)
        if iconDragging and input == iconDragInput then
            local d = input.Position - iconStart
            if math.abs(d.X) > DRAG_THRESHOLD or math.abs(d.Y) > DRAG_THRESHOLD then
                iconMoved = true
            end
            if iconMoved then
                local newPos = UDim2.new(
                    iconPos.X.Scale, iconPos.X.Offset + d.X,
                    iconPos.Y.Scale, iconPos.Y.Offset + d.Y
                )
                IconButton.Position = newPos
                if IconTag then
                    IconTag.Position = UDim2.new(
                        newPos.X.Scale, newPos.X.Offset - 6,
                        newPos.Y.Scale, newPos.Y.Offset + 66
                    )
                end
            end
        end
    end))

    return true
end

---------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------

safePrint("Booting Irenk Bundle Emote Hub v8.4...")

local bootOk, bootErr = pcall(function()
    loadData()
    local guiOk = createGui()
    if guiOk == false then
        error("createGui returned false")
    end
end)

if not bootOk then
    safePrint("BOOT ERROR:", tostring(bootErr))
    -- last resort: minimal visible button so user sees something
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui") or game:GetService("CoreGui")
        if not pg then return end
        local sg = Instance.new("ScreenGui")
        sg.Name = "IrenkHubFallback"
        sg.ResetOnSpawn = false
        sg.Parent = pg
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 160, 0, 40)
        b.Position = UDim2.new(0.5, -80, 0.1, 0)
        b.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        b.Text = "Hub failed: " .. tostring(bootErr):sub(1, 40)
        b.TextSize = 12
        b.Font = Enum.Font.Gotham
        b.Parent = sg
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    end)
else
    safePrint("GUI created OK. Look for orange IRENK icon on the left.")
end

-- character hooks (never top-level wait)
pcall(function()
    LocalPlayer.CharacterAdded:Connect(function()
        task.delay(1, function()
            pcall(captureOriginals)
        end)
    end)
    if LocalPlayer.Character then
        task.delay(0.5, function()
            pcall(captureOriginals)
        end)
    end
end)

-- auto load / search after short delay
task.spawn(function()
    task.wait(1.2)
    local hasAny = false
    for _, st in ipairs(States) do
        if normalizeId(CurrentForm[st]) ~= "" then hasAny = true; break end
    end
    if AutoLoad and hasAny then
        pcall(function()
            applyCurrentForm(LastAppliedName ~= "" and LastAppliedName or "Saved Pack")
            status("Auto-loaded: " .. tostring(LastAppliedName ~= "" and LastAppliedName or "Saved Pack"), true)
        end)
    else
        status("Loading popular bundles...", nil)
        local ok = false
        pcall(function()
            ok = searchCatalog("Bundle", "animation", false)
        end)
        if ok then
            status("Popular bundles loaded — tap orange icon", true)
        else
            status("Tap orange IRENK icon to open hub", true)
        end
    end
end)

-- pulse icon sekali biar kelihatan
task.spawn(function()
    task.wait(0.3)
    if IconButton and IconButton.Parent then
        local orig = IconButton.Size
        pcall(function()
            tween(IconButton, {Size = UDim2.new(0, 72, 0, 72)}, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            task.wait(0.3)
            tween(IconButton, {Size = orig}, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end)
    end
end)

safePrint("Script finished loading.")
