--[[
====================================================================
FE_BUNDLE v12 — EXPANDED ARCHITECTURE REBUILD
====================================================================
Version: 12.2.0 — thin systems filled
Schema: 1
Architecture: single coherent application (NO patch-stack overrides)
Expanded: cache-first search, seek bar, skeleton loaders, page error recovery,
icon position persistence, empty/error/retry states

Layers:
  STATE | DATA/API | ANIMATION | UI | CONTROLLER
  FLOATING | QUICK SELECTOR | SETTINGS | PERSISTENCE | LIFECYCLE

Features preserved:
  Emotes search/play/INFO/preview, Bundles apply, Custom mix,
  Favorites, Save packs, Autoload, Animation controller (loop/speed/reverse),
  Floating buttons (autogrid/freeform), Quick selector, Settings,
  UGC ID resolve/cache, responsive layout, mobile drag/tap

Known limits:
  - Reverse uses TimePosition heartbeat (engine has no native reverse)
  - Intensity uses AdjustWeight when available, else no-op gracefully
  - AI suggestions optional stub (search works without AI)
  - Some executors block HttpGet/GetObjects

Executor: Delta/mobile friendly. Parent: gethui > CoreGui > PlayerGui
====================================================================
]]

print("[FE12] boot start")

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local StarterGui        = game:GetService("StarterGui")
local LocalPlayer       = Players.LocalPlayer

---------------------------------------------------------------------
-- THEME
---------------------------------------------------------------------
local Theme = {
    Page        = Color3.fromRGB(18, 20, 24),
    Surface     = Color3.fromRGB(28, 30, 36),
    Card        = Color3.fromRGB(36, 40, 48),
    Field       = Color3.fromRGB(44, 48, 58),
    Accent      = Color3.fromRGB(255, 176, 32),
    Accent2     = Color3.fromRGB(90, 200, 220),
    Green       = Color3.fromRGB(70, 200, 140),
    Yellow      = Color3.fromRGB(255, 210, 90),
    Red         = Color3.fromRGB(255, 95, 110),
    Text        = Color3.fromRGB(240, 242, 248),
    Muted       = Color3.fromRGB(140, 148, 160),
    LightMuted  = Color3.fromRGB(100, 108, 120),
    Black       = Color3.fromRGB(0, 0, 0),
    White       = Color3.fromRGB(255, 255, 255),
}

---------------------------------------------------------------------
-- APP STATE (single source of truth)
---------------------------------------------------------------------
local App = {
    Version = "12.2.0",
    Schema  = 2,

    Page = "Emotes",
    MenuOpen = false,
    MenuAnimating = false,
    ChoosingState = nil, -- custom slot picker

    Settings = {
        SourceFilter      = "Roblox", -- Roblox | UGC | Favorites
        PickerProvider    = "Floating", -- Floating | Quick
        FloatingMode      = "Autogrid", -- Autogrid | Freeform
        FloatingPlacement = "TopRight", -- TopRight TopLeft BottomRight BottomLeft
        WidthMode         = "Wide", -- Wide | Compact
        AvoidScaling      = false,
        ScreenBlur        = false,
        StartClosed       = false,
        Crowdsource       = false,
        CacheUGCIds       = true,
        CacheUGCTracks    = false,
        Suggestions       = false,
        EmoteSpeed        = 1,
        EmoteLoop         = true,
        MoveWhileEmote    = true,
        ApplyMethod       = "Animate", -- Animate | Description | Both
        AutoLoad          = true,
        AutoLoadName      = "",
        ModalDim          = 0.55,
        UITransparency    = 0.05,
    },

    Controller = {
        Loop = true,
        Reverse = false,
        Speed = 1,
        SpeedName = "Normal",
        Intensity = 1,
        SelectedIndex = 1,
        Docked = true,
        Playing = true,
    },

    -- data
    EmoteResults = {},
    BundleResults = {},
    NextEmoteCursor = nil,
    NextBundleCursor = nil,
    LastEmoteKeyword = "dance",
    LastBundleKeyword = "animation",
    SearchToken = 0,
    SearchError = nil,
    SearchCache = {}, -- keyword->results
    FavoritesEmotes = {},
    FavoritesBundles = {},
    SavedPacks = {},
    FloatingButtons = {}, -- {id, name, animId, catalogId, pos}
    QuickEntries = {},
    EmoteAnimCache = {},
    AnimationObjectCache = {},
    OriginalIds = {},
    CurrentForm = {Idle="",Walk="",Run="",Jump="",Fall="",Climb="",Swim=""},
    SlotMeta = {Idle=nil,Walk=nil,Run=nil,Jump=nil,Fall=nil,Climb=nil,Swim=nil},
    LastAppliedName = "",

    -- runtime
    CurrentEmoteTrack = nil,
    PreviewTracks = {},
    ReverseConn = nil,
    ControllersTracks = {},
}

local States = {"Idle","Walk","Run","Jump","Fall","Climb","Swim"}
local AnimateNames = {
    Idle={"idle"}, Walk={"walk"}, Run={"run"}, Jump={"jump"},
    Fall={"fall"}, Climb={"climb"}, Swim={"swim","swimidle"}
}
local SpeedPresets = {
    {"Paused", 0}, {"Slower", 0.35}, {"Slow", 0.65},
    {"Normal", 1}, {"Fast", 1.5}, {"Faster", 2.2}
}

local CAN_SAVE = type(writefile)=="function" and type(readfile)=="function" and type(isfile)=="function"
local SAVE_FILE = "FE_BUNDLE_V12.json"

---------------------------------------------------------------------
-- CONNECTION MANAGER
---------------------------------------------------------------------
local Conn = {
    Global = {}, Page = {}, Modal = {}, Controller = {}, Floating = {}, Character = {}
}
local function connAdd(bucket, c)
    table.insert(Conn[bucket] or Conn.Global, c)
    return c
end
local function connClear(bucket)
    local list = Conn[bucket]
    if not list then return end
    for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
    Conn[bucket] = {}
end
local function connClearAll()
    for k in pairs(Conn) do connClear(k) end
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function new(className, props)
    local o = Instance.new(className)
    for k,v in pairs(props or {}) do pcall(function() o[k]=v end) end
    return o
end
local function corner(o, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = o; return c
end
local function stroke(o, col, th, tr)
    local s = Instance.new("UIStroke"); s.Color=col or Theme.Black; s.Thickness=th or 1; s.Transparency=tr or 0; s.Parent=o; return s
end
local function pad(o, t, r, b, l)
    local p = Instance.new("UIPadding")
    p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0)
    p.PaddingBottom=UDim.new(0,b or 0); p.PaddingLeft=UDim.new(0,l or 0)
    p.Parent=o; return p
end
local function tween(o, props, t, style, dir)
    local tw = TweenService:Create(o, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    pcall(function() tw:Play() end); return tw
end
local function clearChildren(parent)
    if not parent then return end
    for _, c in ipairs(parent:GetChildren()) do c:Destroy() end
end
local function tableCopy(t)
    local o = {}
    for k,v in pairs(t or {}) do
        if type(v)=="table" then
            local i = {}; for a,b in pairs(v) do i[a]=b end; o[k]=i
        else o[k]=v end
    end
    return o
end
local function normalizeId(raw)
    return string.match(tostring(raw or ""), "%d+") or ""
end
local function toAnimUrl(id)
    id = normalizeId(id); return id ~= "" and ("rbxassetid://"..id) or ""
end
local function assetThumb(id)
    return "rbxthumb://type=Asset&id="..tostring(id).."&w=150&h=150"
end
local function bundleThumb(id)
    return "rbxthumb://type=BundleThumbnail&id="..tostring(id).."&w=150&h=150"
end
local function getParentGui()
    local pg
    pcall(function() if gethui then pg = gethui() end end)
    if pg then return pg, "gethui" end
    pcall(function() pg = game:GetService("CoreGui") end)
    if pg then return pg, "CoreGui" end
    pcall(function() pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5) end)
    if pg then return pg, "PlayerGui" end
    return nil, "NONE"
end
local function getCharHum()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animate = char and char:FindFirstChild("Animate")
    return char, hum, animate
end
local function getAnimator()
    local _, hum = getCharHum()
    if not hum then return nil end
    local a = hum:FindFirstChildOfClass("Animator")
    if not a then a = Instance.new("Animator"); a.Parent = hum end
    return a, hum
end
local function viewportSize()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(800, 600)
end
local function isCompact()
    if App.Settings.WidthMode == "Compact" then return true end
    local vs = viewportSize()
    return vs.X < 700 or vs.Y < 500
end
local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title=tostring(title or "FE_BUNDLE"), Text=tostring(text or ""), Duration=2.5})
    end)
end
local function status(text, good)
    if UI and UI.StatusLabel then
        UI.StatusLabel.Text = tostring(text or "")
        if good == true then UI.StatusLabel.TextColor3 = Theme.Green
        elseif good == false then UI.StatusLabel.TextColor3 = Theme.Red
        else UI.StatusLabel.TextColor3 = Theme.Muted end
    end
end

---------------------------------------------------------------------
-- HTTP
---------------------------------------------------------------------
local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res)=="string" then return res end
    return nil
end
local function decodeJson(raw)
    if not raw then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    return ok and data or nil
end

---------------------------------------------------------------------
-- PERSISTENCE (single system, schema v1)
---------------------------------------------------------------------
local function buildSavePayload()
    return {
        version = App.Schema,
        settings = tableCopy(App.Settings),
        controller = {
            Loop=App.Controller.Loop, Reverse=App.Controller.Reverse,
            Speed=App.Controller.Speed, SpeedName=App.Controller.SpeedName,
            Intensity=App.Controller.Intensity, Docked=App.Controller.Docked
        },
        favorites = { emotes = App.FavoritesEmotes, bundles = App.FavoritesBundles },
        floatingButtons = App.FloatingButtons,
        quickEntries = App.QuickEntries,
        savedPacks = App.SavedPacks,
        currentForm = App.CurrentForm,
        slotMeta = App.SlotMeta,
        lastAppliedName = App.LastAppliedName,
        emoteAnimCache = App.Settings.CacheUGCIds and App.EmoteAnimCache or {},
        autoLoadName = App.Settings.AutoLoadName,
    }
end
local function saveData()
    if not CAN_SAVE then return false end
    local ok = pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(buildSavePayload()))
    end)
    return ok
end
local function loadData()
    if not CAN_SAVE then return false end
    local exists = false
    pcall(function() exists = isfile(SAVE_FILE) end)
    if not exists then return false end
    local raw
    if not pcall(function() raw = readfile(SAVE_FILE) end) or not raw then return false end
    local data = decodeJson(raw)
    if type(data) ~= "table" then return false end
    -- migrate: accept schema missing as v1
    if type(data.settings)=="table" then
        for k,v in pairs(data.settings) do
            if App.Settings[k] ~= nil then App.Settings[k] = v end
        end
    end
    if type(data.controller)=="table" then
        for k,v in pairs(data.controller) do
            if App.Controller[k] ~= nil then App.Controller[k] = v end
        end
    end
    if type(data.favorites)=="table" then
        if type(data.favorites.emotes)=="table" then App.FavoritesEmotes = data.favorites.emotes end
        if type(data.favorites.bundles)=="table" then App.FavoritesBundles = data.favorites.bundles end
    end
    if type(data.floatingButtons)=="table" then App.FloatingButtons = data.floatingButtons end
    if type(data.quickEntries)=="table" then App.QuickEntries = data.quickEntries end
    if type(data.savedPacks)=="table" then App.SavedPacks = data.savedPacks end
    if type(data.currentForm)=="table" then App.CurrentForm = data.currentForm end
    if type(data.slotMeta)=="table" then App.SlotMeta = data.slotMeta end
    if type(data.lastAppliedName)=="string" then App.LastAppliedName = data.lastAppliedName end
    if type(data.emoteAnimCache)=="table" then App.EmoteAnimCache = data.emoteAnimCache end
    if type(data.autoLoadName)=="string" then App.Settings.AutoLoadName = data.autoLoadName end
    return true
end

---------------------------------------------------------------------
-- DATA / CATALOG
---------------------------------------------------------------------
local function searchCatalog(kind, keyword, append)
    keyword = tostring(keyword or "")
    if keyword == "" then keyword = (kind=="Emote") and "dance" or "animation" end
    -- Cache-first for initial search (non-append)
    local cacheKey = kind .. "|" .. string.lower(keyword)
    if not append and App.SearchCache[cacheKey] and type(App.SearchCache[cacheKey].results) == "table" then
        local cached = App.SearchCache[cacheKey]
        if kind == "Emote" then
            App.EmoteResults = tableCopy(cached.results)
            App.NextEmoteCursor = cached.cursor
            App.LastEmoteKeyword = keyword
            return true, #App.EmoteResults
        else
            App.BundleResults = tableCopy(cached.results)
            App.NextBundleCursor = cached.cursor
            App.LastBundleKeyword = keyword
            return true, #App.BundleResults
        end
    end
    App.SearchToken = App.SearchToken + 1
    local token = App.SearchToken
    App.SearchError = nil
    local encoded = HttpService:UrlEncode(keyword)
    local cursor = (kind=="Emote") and App.NextEmoteCursor or App.NextBundleCursor
    if not append then
        if kind=="Emote" then App.EmoteResults={}; App.NextEmoteCursor=nil
        else App.BundleResults={}; App.NextBundleCursor=nil end
        cursor = nil
    end
    local cursorParam = cursor and ("&Cursor="..HttpService:UrlEncode(cursor)) or ""
    local sub = (kind=="Emote") and "39" or "38"
    local url = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory="
        ..sub.."&Keyword="..encoded.."&Limit=30&SortType=0"..cursorParam
    local data = decodeJson(httpGet(url))
    if (not data or type(data.data)~="table") and kind=="Bundle" then
        data = decodeJson(httpGet(
            "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=27&Keyword="
            ..encoded.."&Limit=30&SortType=0"..cursorParam))
    end
    if token ~= App.SearchToken then return false, 0 end -- stale
    if not data or type(data.data)~="table" then return false, 0 end
    if kind=="Emote" then
        for _, item in ipairs(data.data) do table.insert(App.EmoteResults, item) end
        App.NextEmoteCursor = data.nextPageCursor
        App.LastEmoteKeyword = keyword
        if not append then
            App.SearchCache[kind .. "|" .. string.lower(keyword)] = {
                results = tableCopy(App.EmoteResults),
                cursor = App.NextEmoteCursor,
                t = os.clock(),
            }
        end
        return true, #App.EmoteResults
    else
        for _, item in ipairs(data.data) do table.insert(App.BundleResults, item) end
        App.NextBundleCursor = data.nextPageCursor
        App.LastBundleKeyword = keyword
        if not append then
            App.SearchCache[kind .. "|" .. string.lower(keyword)] = {
                results = tableCopy(App.BundleResults),
                cursor = App.NextBundleCursor,
                t = os.clock(),
            }
        end
        return true, #App.BundleResults
    end
end

local function fetchBundleDetails(bundleId)
    bundleId = normalizeId(bundleId)
    if bundleId=="" then return nil end
    return decodeJson(httpGet("https://catalog.roblox.com/v1/bundles/"..bundleId.."/details"))
end

---------------------------------------------------------------------
-- ANIMATION RESOLVE + PLAYBACK (single system)
---------------------------------------------------------------------
local function resolveEmoteAnimationId(assetId)
    assetId = normalizeId(assetId)
    if assetId == "" then return nil end
    if App.EmoteAnimCache[assetId] then return App.EmoteAnimCache[assetId] end
    local found
    -- 1) GetObjects
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
    -- 2) assetdelivery
    if not found or found == "" then
        pcall(function()
            local delivery = decodeJson(httpGet("https://assetdelivery.roblox.com/v1/assetId/" .. assetId))
            if delivery and delivery.location then
                local content = httpGet(delivery.location)
                if content then
                    found = normalizeId(string.match(content, "rbxassetid://(%d+)") or string.match(content, "AnimationId[^%d]*(%d+)") or "")
                end
            end
        end)
    end
    -- 3) catalog details itemType
    if not found or found == "" then
        pcall(function()
            local info = decodeJson(httpGet("https://economy.roblox.com/v2/assets/" .. assetId .. "/details"))
            -- not always has anim id
        end)
    end
    -- 4) fallback: use catalog id itself (sometimes works for pure Animation assets)
    if not found or found == "" then
        found = assetId
    end
    if App.Settings.CacheUGCIds then
        App.EmoteAnimCache[assetId] = found
        pcall(saveData)
    end
    return found
end


local function logErr(tag, msg)
    local line = "[" .. tostring(tag) .. "] " .. tostring(msg)
    warn("[FE12] " .. line)
    App.LastError = line
    table.insert(App.Logs, line)
    if #App.Logs > 40 then table.remove(App.Logs, 1) end
end

local function updateEmoteRuntimeUI()
    if not UI or not UI.Root then return end
    local bar = UI.EmoteBar
    if App.EmoteState == "PLAYING" or App.EmoteState == "PAUSED" then
        if not bar then
            bar = new("Frame", {
                Parent = UI.Root,
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(0.5, 0, 1, -16),
                Size = UDim2.new(0, 320, 0, 54),
                BackgroundColor3 = Theme.Surface,
                BorderSizePixel = 0,
                ZIndex = 90,
            })
            corner(bar, 12)
            stroke(bar, Theme.Accent, 1.5, 0.25)
            UI.EmoteBar = bar
        end
        clearChildren(bar)
        local name = (App.ActiveEmote and App.ActiveEmote.name) or "Emote"
        local info = new("TextLabel", {
            Parent = bar,
            Position = UDim2.new(0, 12, 0, 4),
            Size = UDim2.new(1, -100, 0, 22),
            BackgroundTransparency = 1,
            Text = (App.EmoteState == "PAUSED" and "Paused: " or "Playing: ") .. tostring(name),
            TextColor3 = Theme.Text,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 91,
        })
        local meta = new("TextLabel", {
            Parent = bar,
            Position = UDim2.new(0, 12, 0, 26),
            Size = UDim2.new(1, -100, 0, 18),
            BackgroundTransparency = 1,
            Text = "Loop: " .. (App.Settings.EmoteLoop and "ON" or "OFF")
                .. "  ·  Move: " .. (App.Settings.MoveWhileEmote and "ON" or "OFF")
                .. "  ·  " .. tostring(App.Settings.EmoteSpeed) .. "x",
            TextColor3 = Theme.Muted,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 91,
        })
        local stopBtn = new("TextButton", {
            Parent = bar,
            Position = UDim2.new(1, -88, 0, 10),
            Size = UDim2.new(0, 76, 0, 34),
            BackgroundColor3 = Theme.Red,
            Text = "STOP",
            TextColor3 = Theme.Text,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = true,
            ZIndex = 92,
        })
        corner(stopBtn, 8)
        connAdd("Global", stopBtn.MouseButton1Click:Connect(function()
            stopEmote("ui")
        end))
        pcall(function()
            connAdd("Global", stopBtn.Activated:Connect(function()
                stopEmote("ui")
            end))
        end)
        bar.Visible = true
    else
        if bar then
            bar.Visible = false
        end
    end
    -- refresh current page card labels if on Emotes
    if App.Page == "Emotes" and navigate then
        -- soft refresh only card states would be heavy; status is enough
    end
end

function stopEmote(reason)
    reason = reason or "manual"
    App.EmoteState = "STOPPING"
    if App.EmoteEndedConn then
        pcall(function() App.EmoteEndedConn:Disconnect() end)
        App.EmoteEndedConn = nil
    end
    stopReverse()
    if App.CurrentEmoteTrack then
        pcall(function()
            App.CurrentEmoteTrack:Stop(0.12)
            App.CurrentEmoteTrack:Destroy()
        end)
        App.CurrentEmoteTrack = nil
    end
    App.ActiveEmote = nil
    App.EmoteState = "IDLE"
    status("Emote stopped", true)
    updateEmoteRuntimeUI()
    if refreshControllerTracks then pcall(refreshControllerTracks) end
end

local function playEmote(catalogOrAnimId, name)
    local catalogId = normalizeId(catalogOrAnimId)
    if catalogId == "" then
        status("Invalid ID", false)
        return false
    end
    status("Resolving...", true)
    local realId = resolveEmoteAnimationId(catalogOrAnimId)
    if not realId or realId == "" then
        realId = catalogId -- last resort: try catalog id as anim id
    end
    local char, hum = getCharHum()
    if not hum then
        App.EmoteState = "FAILED"
        status("No character/humanoid", false)
        notify("FE_BUNDLE", "No character")
        logErr("EMOTE", "no humanoid")
        return false
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end

    -- stop previous
    if App.CurrentEmoteTrack then
        if App.EmoteEndedConn then
            pcall(function() App.EmoteEndedConn:Disconnect() end)
            App.EmoteEndedConn = nil
        end
        pcall(function() App.CurrentEmoteTrack:Stop(0.05); App.CurrentEmoteTrack:Destroy() end)
        App.CurrentEmoteTrack = nil
    end
    stopReverse()

    local anim = Instance.new("Animation")
    anim.AnimationId = toAnimUrl(realId)

    -- Try Humanoid:LoadAnimation first (most compatible), then Animator
    local track
    local ok1, res1 = pcall(function() return hum:LoadAnimation(anim) end)
    if ok1 and res1 then
        track = res1
    else
        local ok2, res2 = pcall(function() return animator:LoadAnimation(anim) end)
        if ok2 and res2 then
            track = res2
        else
            App.EmoteState = "FAILED"
            status("Load failed: "..tostring(res1 or res2), false)
            notify("FE_BUNDLE", "Animation failed")
            logErr("EMOTE", "LoadAnimation failed "..tostring(realId).." "..tostring(res1).." "..tostring(res2))
            return false
        end
    end

    App.CurrentEmoteTrack = track
    App.ActiveEmote = {
        id = catalogId,
        name = tostring(name or catalogId),
        animId = realId,
    }
    App.EmoteState = "PLAYING"

    pcall(function()
        -- High priority so it is visible over default animate
        track.Priority = App.Settings.MoveWhileEmote and Enum.AnimationPriority.Action2 or Enum.AnimationPriority.Action4
        track.Looped = App.Settings.EmoteLoop == true
        local spd = tonumber(App.Settings.EmoteSpeed) or 1
        if spd == 0 then
            track:Play(0.1, 1, 0)
            App.EmoteState = "PAUSED"
        else
            track:Play(0.1, 1, spd)
        end
    end)

    if not App.Settings.EmoteLoop then
        App.EmoteEndedConn = track.Stopped:Connect(function()
            if App.CurrentEmoteTrack == track then
                App.CurrentEmoteTrack = nil
                App.ActiveEmote = nil
                App.EmoteState = "IDLE"
                updateEmoteRuntimeUI()
                status("Emote finished", true)
            end
        end)
        connAdd("Character", App.EmoteEndedConn)
    end

    applyTrackControls(track)
    status("Playing: " .. tostring(name or realId), true)
    updateEmoteRuntimeUI()
    if refreshControllerTracks then pcall(refreshControllerTracks) end

    if App.Settings.Crowdsource then
        task.spawn(function()
            pcall(function()
                httpGet("https://httpbin.org/get?fe_bundle_crowd=1&place="..tostring(game.PlaceId).."&anim="..tostring(realId))
            end)
        end)
    end
    return true
end

function toggleEmote(catalogOrAnimId, name)
    local id = normalizeId(catalogOrAnimId)
    if (App.EmoteState == "PLAYING" or App.EmoteState == "PAUSED")
        and App.ActiveEmote and tostring(App.ActiveEmote.id) == id then
        stopEmote("toggle")
        return "stopped"
    end
    if playEmote(catalogOrAnimId, name) then
        return "playing"
    end
    return "failed"
end

local function applyEmoteSpeed(spd)
    App.Settings.EmoteSpeed = spd
    if App.CurrentEmoteTrack then
        pcall(function()
            if spd == 0 then
                App.CurrentEmoteTrack:AdjustSpeed(0)
                App.EmoteState = "PAUSED"
            else
                App.CurrentEmoteTrack:AdjustSpeed(spd)
                if App.EmoteState == "PAUSED" then
                    App.EmoteState = "PLAYING"
                end
            end
        end)
        updateEmoteRuntimeUI()
    end
    saveData()
end

local function clearPreviewTracks()
    for _, t in ipairs(App.PreviewTracks) do pcall(function() t:Stop(0); t:Destroy() end) end
    App.PreviewTracks = {}
end

---------------------------------------------------------------------
-- BUNDLE APPLY
---------------------------------------------------------------------
local function categorizeAnimation(pathText)
    pathText = string.lower(tostring(pathText or ""))
    if string.find(pathText,"idle",1,true) then return "Idle" end
    if string.find(pathText,"walk",1,true) then return "Walk" end
    if string.find(pathText,"run",1,true) then return "Run" end
    if string.find(pathText,"jump",1,true) then return "Jump" end
    if string.find(pathText,"fall",1,true) then return "Fall" end
    if string.find(pathText,"climb",1,true) then return "Climb" end
    if string.find(pathText,"swim",1,true) then return "Swim" end
    return nil
end
local function scanAnimationTree(root, path, output)
    for _, child in ipairs(root:GetChildren()) do
        local p = path.."."..child.Name
        if child:IsA("Animation") then
            local id = normalizeId(child.AnimationId)
            local state = categorizeAnimation(p)
            if id~="" and state and not output[state] then output[state]=id end
        end
        if #child:GetChildren()>0 then scanAnimationTree(child, p, output) end
    end
end
local function resolveAnimationsFromAsset(assetId)
    assetId = normalizeId(assetId)
    if assetId=="" then return {} end
    if App.AnimationObjectCache[assetId] then return App.AnimationObjectCache[assetId] end
    local found = {}
    local ok, objects = pcall(function() return game:GetObjects("rbxassetid://"..assetId) end)
    if ok and objects then
        for _, obj in ipairs(objects) do
            scanAnimationTree(obj, obj.Name, found)
            pcall(function() obj:Destroy() end)
        end
    end
    App.AnimationObjectCache[assetId] = found
    return found
end
local function extractAnimationsFromBundle(details)
    local form = {}
    if not details then return form end
    local items = details.items or details.Items or {}
    for _, item in ipairs(items) do
        local itemId = tostring(item.id or item.Id or "")
        local resolved = resolveAnimationsFromAsset(itemId)
        for state, id in pairs(resolved) do if not form[state] then form[state]=id end end
    end
    local map = {[48]="Climb",[50]="Fall",[51]="Idle",[52]="Jump",[53]="Run",[54]="Swim",[55]="Walk"}
    for _, item in ipairs(items) do
        local itemId = tostring(item.id or item.Id or "")
        local at = tonumber(item.assetType or item.AssetType or item.assetTypeId or item.AssetTypeId)
        local state = map[at] or categorizeAnimation(item.name or item.Name)
        if state and not form[state] then form[state]=itemId end
    end
    return form
end
local function getAnimationsForState(state)
    local _,_, animate = getCharHum()
    if not animate then return {} end
    local result = {}
    for _, child in ipairs(animate:GetChildren()) do
        local ln = string.lower(child.Name)
        for _, expected in ipairs(AnimateNames[state] or {}) do
            if ln == expected then
                if child:IsA("Animation") then table.insert(result, child) end
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("Animation") then table.insert(result, d) end
                end
            end
        end
    end
    return result
end
local function captureOriginals()
    App.OriginalIds = {}
    for _, state in ipairs(States) do
        App.OriginalIds[state] = {}
        for _, anim in ipairs(getAnimationsForState(state)) do
            table.insert(App.OriginalIds[state], anim.AnimationId)
        end
    end
end
local function restartAnimate()
    local _,_, animate = getCharHum()
    if animate then
        pcall(function() animate.Disabled=true; task.wait(0.08); animate.Disabled=false end)
    end
end
local function setStateAnimation(state, id)
    id = normalizeId(id)
    if id=="" then return false end
    local anims = getAnimationsForState(state)
    if #anims==0 then return false end
    for _, anim in ipairs(anims) do anim.AnimationId = toAnimUrl(id) end
    return true
end
local function applyDescriptionAnimations()
    local _, hum = getCharHum()
    if not hum then return 0 end
    local props = {Idle="IdleAnimation",Walk="WalkAnimation",Run="RunAnimation",Jump="JumpAnimation",Fall="FallAnimation",Climb="ClimbAnimation",Swim="SwimAnimation"}
    local changed = 0
    pcall(function()
        local desc = hum:GetAppliedDescription()
        for state, prop in pairs(props) do
            local id = normalizeId(App.CurrentForm[state])
            if id~="" then desc[prop]=tonumber(id) or 0; changed = changed + 1 end
        end
        hum:ApplyDescription(desc)
    end)
    return changed
end
local function applyCurrentForm(name)
    local changed = 0
    if App.Settings.ApplyMethod=="Animate" or App.Settings.ApplyMethod=="Both" then
        for _, state in ipairs(States) do
            if normalizeId(App.CurrentForm[state])~="" and setStateAnimation(state, App.CurrentForm[state]) then
                changed = changed + 1
            end
        end
    end
    local descChanged = 0
    if App.Settings.ApplyMethod=="Description" or App.Settings.ApplyMethod=="Both" then
        descChanged = applyDescriptionAnimations()
    end
    restartAnimate()
    if name then App.LastAppliedName = name end
    saveData()
    status("Applied "..tostring(name or "pack").." | "..tostring(changed), changed>0 or descChanged>0)
end
local function restoreOriginal()
    for _, state in ipairs(States) do
        local originals = App.OriginalIds[state]
        local anims = getAnimationsForState(state)
        if originals and #originals>0 then
            for i, anim in ipairs(anims) do anim.AnimationId = originals[i] or originals[1] end
        end
    end
    restartAnimate()
    status("Original restored", true)
end

---------------------------------------------------------------------
-- FAVORITES
---------------------------------------------------------------------
local function isFavorite(list, id)
    id = tostring(id)
    for _, it in ipairs(list) do if tostring(it.id)==id then return true end end
    return false
end
local function toggleFavorite(kind, item)
    local list = (kind=="Emote") and App.FavoritesEmotes or App.FavoritesBundles
    local id = tostring(item.id or item.Id or "")
    for i, fav in ipairs(list) do
        if tostring(fav.id)==id then
            table.remove(list, i); saveData(); notify("FE_BUNDLE","Favorite removed"); return false
        end
    end
    table.insert(list, {
        id=id, name=tostring(item.name or item.Name or id), kind=kind,
        creatorName=item.creatorName or item.CreatorName
    })
    saveData(); notify("FE_BUNDLE","Favorite added"); return true
end

---------------------------------------------------------------------
-- UI ROOT (created in createGui)
---------------------------------------------------------------------
UI = nil -- global-ish table filled later

local function makeLabel(parent, text, size, color, bold)
    local l = new("TextLabel", {
        Parent=parent, BackgroundTransparency=1, Text=tostring(text or ""),
        TextColor3=color or Theme.Text, TextSize=size or 13,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Center,
        TextWrapped=true, Size=UDim2.new(1,0,0, size and (size+6) or 20),
        AutomaticSize=Enum.AutomaticSize.Y
    })
    return l
end

local function makeBtn(parent, text, callback, color, opts)
    opts = opts or {}
    local b = new("TextButton", {
        Parent=parent,
        BackgroundColor3=color or Theme.Card,
        BorderSizePixel=0, Text=tostring(text or ""),
        TextColor3=Theme.Text, TextSize=opts.textSize or 12,
        Font=Enum.Font.Gotham, AutoButtonColor=true, Active=true,
        Size=opts.size or UDim2.new(0, 90, 0, 30),
        AutomaticSize=opts.auto and Enum.AutomaticSize.X or Enum.AutomaticSize.None
    })
    corner(b, opts.radius or 8)
    stroke(b, Theme.Black, 1, 0.35)
    if opts.flex then
        local f = Instance.new("UIFlexItem"); f.FlexMode=Enum.UIFlexMode.Fill; f.Parent=b
    end
    local fired=false
    local function fire()
        if fired then return end
        fired=true; task.delay(0.14, function() fired=false end)
        if callback then callback() end
    end
    local bucket = opts.bucket or "Page"
    connAdd(bucket, b.MouseButton1Click:Connect(fire))
    pcall(function() connAdd(bucket, b.Activated:Connect(fire)) end)
    return b
end

local function makeBox(parent, placeholder, text)
    local box = new("TextBox", {
        Parent=parent, BackgroundColor3=Theme.Field, BorderSizePixel=0,
        Text=text or "", PlaceholderText=placeholder or "",
        PlaceholderColor3=Theme.LightMuted, TextColor3=Theme.Text,
        TextSize=13, Font=Enum.Font.Gotham, ClearTextOnFocus=false,
        TextXAlignment=Enum.TextXAlignment.Left, Size=UDim2.new(1,0,0,34)
    })
    corner(box, 8); stroke(box, Theme.Black, 1, 0.4); pad(box, 0, 10, 0, 10)
    return box
end

local function makeCard(parent)
    local c = new("Frame", {
        Parent=parent, BackgroundColor3=Theme.Card, BorderSizePixel=0,
        Size=UDim2.new(1,0,0,120)
    })
    corner(c, 12); stroke(c, Theme.Black, 1, 0.4)
    return c
end

---------------------------------------------------------------------
-- LOADING / MODAL / NOTIFY LAYERS
---------------------------------------------------------------------
local function hideLoading()
    if UI and UI.Loading then
        pcall(function() UI.Loading:Destroy() end)
        UI.Loading = nil
    end
end
local function showLoading(text)
    hideLoading()
    if not UI or not UI.Root then return end
    local dim = new("Frame", {
        Parent=UI.Root, Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Black,
        BackgroundTransparency=0.55, BorderSizePixel=0, ZIndex=200
    })
    local card = new("Frame", {
        Parent=dim, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0),
        Size=UDim2.new(0,280,0,96), BackgroundColor3=Theme.Surface, BorderSizePixel=0, ZIndex=201
    })
    corner(card, 14); stroke(card, Theme.Accent, 1.5, 0.25)
    local title = new("TextLabel", {
        Parent=card, Position=UDim2.new(0,16,0,14), Size=UDim2.new(1,-32,0,24),
        BackgroundTransparency=1, Text=tostring(text or "Loading..."), TextColor3=Theme.Text,
        TextSize=15, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=202
    })
    local barBg = new("Frame", {
        Parent=card, Position=UDim2.new(0,16,0,52), Size=UDim2.new(1,-32,0,12),
        BackgroundColor3=Theme.Field, BorderSizePixel=0, ClipsDescendants=true, ZIndex=202
    })
    corner(barBg, 6)
    local bar = new("Frame", {
        Parent=barBg, Size=UDim2.new(0.35,0,1,0), BackgroundColor3=Theme.Accent,
        BorderSizePixel=0, ZIndex=203
    })
    corner(bar, 6)
    local shimmer = new("Frame", {
        Parent=bar, Size=UDim2.new(0.4,0,1,0), BackgroundColor3=Theme.White,
        BackgroundTransparency=0.7, BorderSizePixel=0, ZIndex=204
    })
    task.spawn(function()
        while bar and bar.Parent do
            bar.Position = UDim2.new(-0.35,0,0,0)
            local tw = tween(bar, {Position=UDim2.new(1.05,0,0,0)}, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            task.wait(0.95)
        end
    end)
    UI.Loading = dim
end

local function closeModal()
    clearPreviewTracks()
    connClear("Modal")
    if UI and UI.Modal then
        pcall(function() UI.Modal:Destroy() end)
        UI.Modal = nil
    end
end

local function createAvatarPreview(parent, animId)
    clearPreviewTracks()
    connClear("Preview")
    local vp = new("ViewportFrame", {
        Parent=parent, Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Field,
        BorderSizePixel=0, Ambient=Color3.fromRGB(200,200,205),
        LightColor=Color3.fromRGB(255,255,255), LightDirection=Vector3.new(-0.35,-1,-0.55),
        ZIndex=220
    })
    corner(vp, 14)
    local world = Instance.new("WorldModel"); world.Parent = vp
    local char = LocalPlayer.Character
    if not char then
        makeLabel(vp, "No character", 12, Theme.Muted)
        return vp
    end
    local oldArch = char.Archivable
    pcall(function() char.Archivable = true end)
    local clone
    pcall(function() clone = char:Clone() end)
    pcall(function() char.Archivable = oldArch end)
    if not clone then return vp end
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then d:Destroy() end
    end
    local an = clone:FindFirstChild("Animate"); if an then an:Destroy() end
    clone.Parent = world
    local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if root then
        clone.PrimaryPart = root
        pcall(function()
            root.Anchored = true
            clone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0))
        end)
    end
    -- Auto bounds camera: fit full body
    local cam = Instance.new("Camera"); cam.Parent = vp; vp.CurrentCamera = cam
    local function fitCamera()
        local cf, size
        pcall(function() cf, size = clone:GetBoundingBox() end)
        if not cf or not size then
            cam.FieldOfView = App.Settings.PreviewFOV or 50
            cam.CFrame = CFrame.new(Vector3.new(0, 2.0, App.Settings.PreviewDistance or 7.5), Vector3.new(0, 1.2, 0))
            return
        end
        local maxDim = math.max(size.X, size.Y, size.Z)
        local dist = math.clamp(maxDim * 1.55, 5.5, 12)
        local lookAt = cf.Position
        local camPos = lookAt + Vector3.new(0, size.Y * 0.05, dist)
        cam.FieldOfView = math.clamp(40 + (maxDim * 2), 40, 55)
        cam.CFrame = CFrame.new(camPos, lookAt)
    end
    fitCamera()
    task.delay(0.15, fitCamera) -- refit after anim poses

    local hum = clone:FindFirstChildOfClass("Humanoid")
    local rid = normalizeId(animId)
    if hum and rid ~= "" then
        local anim = Instance.new("Animation"); anim.AnimationId = toAnimUrl(rid)
        local ok, track = pcall(function() return hum:LoadAnimation(anim) end)
        if ok and track then
            pcall(function()
                track.Looped = true
                track.Priority = Enum.AnimationPriority.Action4
                track:Play(0.1, 1, App.Settings.EmoteSpeed)
            end)
            table.insert(App.PreviewTracks, track)
            -- drag to rotate preview
            local dragBtn = new("TextButton", {
                Parent = vp, Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "", ZIndex = 221
            })
            local rotY = 0
            local dragging, startX
            connAdd("Preview", dragBtn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true; startX = input.Position.X
                end
            end))
            connAdd("Preview", UserInputService.InputChanged:Connect(function(input)
                if not dragging then return end
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    local dx = input.Position.X - (startX or input.Position.X)
                    startX = input.Position.X
                    rotY = rotY + dx * 0.01
                    if root then
                        pcall(function()
                            clone:SetPrimaryPartCFrame(CFrame.new(0,0,0) * CFrame.Angles(0, math.rad(180) + rotY, 0))
                        end)
                    end
                    fitCamera()
                end
            end))
            connAdd("Preview", UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end))
        end
    end
    return vp
end

local function showInfoModal(item, kind)
    closeModal()
    if not UI or not UI.Root then return end
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or id)
    local creator = tostring(item.creatorName or item.CreatorName or "Unknown")
    local desc = tostring(item.description or item.Description or "")
    local imageId = (kind=="Emote") and assetThumb(id) or bundleThumb(id)

    local function openWith(realId, body)
        local dim = new("Frame", {
            Parent=UI.Root, Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Black,
            BackgroundTransparency=1, BorderSizePixel=0, ZIndex=210
        })
        tween(dim, {BackgroundTransparency=App.Settings.ModalDim}, 0.15, Enum.EasingStyle.Quad)
        local card = new("Frame", {
            Parent=dim, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0),
            Size=UDim2.new(0, 36, 0, 36), BackgroundColor3=Theme.Surface, BorderSizePixel=0, ZIndex=211
        })
        corner(card, 16); stroke(card, Theme.Accent, 1.5, 0.2)
        local targetW = math.min(500, viewportSize().X - 40)
        local targetH = math.min(420, viewportSize().Y - 50)
        tween(card, {Size=UDim2.new(0, targetW, 0, targetH)}, 0.28, Enum.EasingStyle.Back)

        task.delay(0.05, function()
            if not card or not card.Parent then return end
            local left = new("Frame", {Parent=card, Position=UDim2.new(0,14,0,14), Size=UDim2.new(0,168,0,240), BackgroundTransparency=1, ZIndex=212})
            if realId and normalizeId(realId)~="" then createAvatarPreview(left, realId).Size=UDim2.new(1,0,1,0)
            else
                local img = new("ImageLabel", {Parent=left, Size=UDim2.new(1,0,1,0), BackgroundColor3=Theme.Field, Image=imageId, ScaleType=Enum.ScaleType.Fit, BorderSizePixel=0})
                corner(img, 12)
            end
            local title = new("TextLabel", {
                Parent=card, Position=UDim2.new(0,196,0,16), Size=UDim2.new(1,-230,0,36),
                BackgroundTransparency=1, Text=name, TextColor3=Theme.Text, TextSize=17,
                Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true, ZIndex=212
            })
            local scroll = new("ScrollingFrame", {
                Parent=card, Position=UDim2.new(0,196,0,56), Size=UDim2.new(1,-210,0, targetH-140),
                BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
                ScrollBarImageColor3=Theme.Accent, CanvasSize=UDim2.new(0,0,0,220), ZIndex=212
            })
            local bodyLbl = new("TextLabel", {
                Parent=scroll, Size=UDim2.new(1,-8,0,210), BackgroundTransparency=1, Text=body,
                TextColor3=Theme.Muted, TextSize=13, Font=Enum.Font.Gotham,
                TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, TextWrapped=true
            })
            local actions = new("Frame", {
                Parent=card, Position=UDim2.new(0,16,1,-48), Size=UDim2.new(1,-32,0,34),
                BackgroundTransparency=1, ZIndex=212
            })
            local lay = Instance.new("UIListLayout")
            lay.FillDirection=Enum.FillDirection.Horizontal; lay.Padding=UDim.new(0,8); lay.Parent=actions

            makeBtn(actions, "CLOSE", closeModal, Theme.Red, {bucket="Modal", size=UDim2.new(0,80,0,32)})
            if kind=="Emote" then
                local activeHere = App.ActiveEmote and tostring(App.ActiveEmote.id)==id
            makeBtn(actions, activeHere and "STOP" or "PLAY", function()
                toggleEmote(id, name)
                closeModal()
            end, activeHere and Theme.Red or Theme.Green, {bucket="Modal", size=UDim2.new(0,80,0,32)})
                makeBtn(actions, "COPY", function()
                    local copyId = realId or id
                    local ok = false
                    pcall(function() if setclipboard then setclipboard(tostring(copyId)); ok=true end end)
                    pcall(function() if toclipboard then toclipboard(tostring(copyId)); ok=true end end)
                    notify("FE_BUNDLE", ok and ("Copied "..tostring(copyId)) or "Clipboard unavailable")
                end, Theme.Accent2, {bucket="Modal", size=UDim2.new(0,80,0,32)})
                makeBtn(actions, App.Settings.PickerProvider=="Quick" and "QUICK" or "FLOAT", function()
                    if App.Settings.PickerProvider=="Quick" then addQuickEntry(item)
                    else addFloatingButton(item) end
                end, Theme.Accent, {bucket="Modal", size=UDim2.new(0,80,0,32)})
            else
                makeBtn(actions, App.ChoosingState and "SET" or "APPLY", function()
                    if App.ChoosingState then setCustomSlot(App.ChoosingState, id, name)
                    else applyBundle(id, name) end
                    closeModal()
                end, Theme.Green, {bucket="Modal", size=UDim2.new(0,90,0,32)})
            end
            makeBtn(actions, isFavorite((kind=="Emote") and App.FavoritesEmotes or App.FavoritesBundles, id) and "★" or "☆", function()
                toggleFavorite(kind, item)
            end, Theme.Yellow, {bucket="Modal", size=UDim2.new(0,44,0,32)})
        end)
        UI.Modal = dim
        connAdd("Modal", dim.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                -- click dim outside card closes? optional
            end
        end))
    end

    if kind=="Emote" then
        showLoading("Resolving preview...")
        task.spawn(function()
            local realId = resolveEmoteAnimationId(id)
            hideLoading()
            local body = "Name: "..name.."\nCreator: "..creator.."\nSource: "..App.Settings.SourceFilter
                .."\nCatalog ID: "..id.."\nAnimation ID: "..tostring(realId or "?")
                .."\nLink: https://www.roblox.com/catalog/"..id
                .."\n\n"..(desc~="" and desc or "Avatar preview plays this emote.")
            openWith(realId, body)
        end)
    else
        local body = "Name: "..name.."\nCreator: "..creator.."\nBundle ID: "..id
            .."\nLink: https://www.roblox.com/bundles/"..id
            ..(App.ChoosingState and ("\n\nWill set slot: "..App.ChoosingState) or "\n\nApply full animation pack.")
        openWith(nil, body)
    end
end

function applyBundle(bundleId, bundleName)
    showLoading("Resolving bundle...")
    task.spawn(function()
        local details = fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Bundle failed", false); return end
        local form = extractAnimationsFromBundle(details)
        local count = 0
        for _, state in ipairs(States) do
            App.CurrentForm[state] = form[state] or ""
            if App.CurrentForm[state]~="" then
                App.SlotMeta[state] = {Bundle=bundleName or details.name or "Bundle", BundleId=normalizeId(bundleId), Id=App.CurrentForm[state]}
                count = count + 1
            else App.SlotMeta[state]=nil end
        end
        hideLoading()
        if count<=0 then status("No anims", false); return end
        App.LastAppliedName = bundleName or details.name or "Bundle"
        applyCurrentForm(App.LastAppliedName)
    end)
end

function setCustomSlot(state, bundleId, bundleName)
    showLoading("Setting "..state.."...")
    task.spawn(function()
        local details = fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Failed", false); return end
        local form = extractAnimationsFromBundle(details)
        hideLoading()
        local id = form[state]
        if normalizeId(id)=="" then status("No "..state, false); return end
        App.CurrentForm[state]=id
        App.SlotMeta[state]={Bundle=bundleName or details.name, BundleId=normalizeId(bundleId), Id=id}
        App.ChoosingState=nil; saveData(); status("Set "..state, true)
        if navigate then navigate("Custom") end
    end)
end

---------------------------------------------------------------------
-- FLOATING BUTTONS
---------------------------------------------------------------------
local function clampIconToViewport(gui)
    if not gui then return end
    local vs = viewportSize()
    local abs = gui.AbsoluteSize
    local pos = gui.AbsolutePosition
    local x = math.clamp(pos.X, 4, math.max(4, vs.X - abs.X - 4))
    local y = math.clamp(pos.Y, 4, math.max(4, vs.Y - abs.Y - 4))
    -- convert to scale+offset relative to parent
    gui.Position = UDim2.new(0, x, 0, y)
end

local function reflowFloating()
    if not UI or not UI.FloatingLayer then return end
    clearChildren(UI.FloatingLayer)
    connClear("Floating")
    if App.Settings.PickerProvider ~= "Floating" then return end

    local vs = viewportSize()
    local mode = App.Settings.FloatingMode
    local place = App.Settings.FloatingPlacement

    local function bindFloatButton(b, captured)
        local pressT, longDone, dragging, moved, inputRef, start, startPos
        local THRESH = 12
        local LONG_MS = 0.55
        connAdd("Floating", b.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            pressT = os.clock(); longDone = false; dragging = true; moved = false
            inputRef = input; start = input.Position; startPos = b.Position
            task.delay(LONG_MS, function()
                if dragging and not moved and not longDone and (os.clock() - pressT) >= LONG_MS - 0.05 then
                    longDone = true
                    -- long press = remove
                    removeFloatingButton(captured.catalogId or captured.id)
                    notify("FE_BUNDLE", "Floating removed")
                end
            end)
            local c; c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and not longDone then
                        toggleEmote(captured.catalogId or captured.id, captured.name)
                    end
                    if c then c:Disconnect() end
                end
            end)
        end))
        connAdd("Floating", UserInputService.InputChanged:Connect(function(input)
            if not dragging or input ~= inputRef then return end
            local d = input.Position - start
            if math.abs(d.X) > THRESH or math.abs(d.Y) > THRESH then moved = true end
            if moved and mode == "Freeform" then
                local np = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                b.Position = np
                -- clamp later on end
            end
        end))
        connAdd("Floating", UserInputService.InputEnded:Connect(function(input)
            if input == inputRef and moved and mode == "Freeform" then
                clampIconToViewport(b)
                captured.posX = b.Position.X.Scale
                captured.posXO = b.Position.X.Offset
                captured.posY = b.Position.Y.Scale
                captured.posYO = b.Position.Y.Offset
                saveData()
            end
        end))
    end

    if mode == "Autogrid" then
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = UDim2.new(0, 52, 0, 52)
        grid.CellPadding = UDim2.new(0, 8, 0, 8)
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.Parent = UI.FloatingLayer
        local padF = Instance.new("UIPadding"); padF.Parent = UI.FloatingLayer
        if place == "TopRight" then
            UI.FloatingLayer.AnchorPoint = Vector2.new(1, 0)
            UI.FloatingLayer.Position = UDim2.new(1, -12, 0, 60)
            UI.FloatingLayer.Size = UDim2.new(0, 200, 0, 400)
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
            padF.PaddingTop = UDim.new(0, 8); padF.PaddingRight = UDim.new(0, 8)
        elseif place == "TopLeft" then
            UI.FloatingLayer.AnchorPoint = Vector2.new(0, 0)
            UI.FloatingLayer.Position = UDim2.new(0, 12, 0, 60)
            UI.FloatingLayer.Size = UDim2.new(0, 200, 0, 400)
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
        elseif place == "BottomRight" then
            UI.FloatingLayer.AnchorPoint = Vector2.new(1, 1)
            UI.FloatingLayer.Position = UDim2.new(1, -12, 1, -20)
            UI.FloatingLayer.Size = UDim2.new(0, 200, 0, 400)
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
            grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
        else
            UI.FloatingLayer.AnchorPoint = Vector2.new(0, 1)
            UI.FloatingLayer.Position = UDim2.new(0, 12, 1, -20)
            UI.FloatingLayer.Size = UDim2.new(0, 200, 0, 400)
            grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
        end
        for i, fb in ipairs(App.FloatingButtons) do
            local b = new("TextButton", {
                Parent = UI.FloatingLayer, Size = UDim2.new(0, 52, 0, 52),
                BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = true, LayoutOrder = i, ZIndex = 50
            })
            corner(b, 12); stroke(b, Theme.Black, 1, 0.2)
            local img = new("ImageLabel", {
                Parent = b, Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
                BackgroundTransparency = 1, Image = assetThumb(fb.catalogId or fb.id), ScaleType = Enum.ScaleType.Fit
            })
            corner(img, 8)
            bindFloatButton(b, fb)
        end
    else
        UI.FloatingLayer.AnchorPoint = Vector2.new(0, 0)
        UI.FloatingLayer.Position = UDim2.new(0, 0, 0, 0)
        UI.FloatingLayer.Size = UDim2.new(1, 0, 1, 0)
        for _, fb in ipairs(App.FloatingButtons) do
            local b = new("TextButton", {
                Parent = UI.FloatingLayer,
                Position = UDim2.new(fb.posX or 0.85, fb.posXO or 0, fb.posY or 0.2, fb.posYO or 0),
                Size = UDim2.new(0, 54, 0, 54), BackgroundColor3 = Theme.Accent, Text = "", AutoButtonColor = false, ZIndex = 50
            })
            corner(b, 12); stroke(b, Theme.Black, 1, 0.2)
            local img = new("ImageLabel", {
                Parent = b, Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
                BackgroundTransparency = 1, Image = assetThumb(fb.catalogId or fb.id), ScaleType = Enum.ScaleType.Fit
            })
            corner(img, 8)
            bindFloatButton(b, fb)
            task.defer(function() clampIconToViewport(b) end)
        end
    end

-- Persistent REAPPLY pack floating (if user has a mix/pack)
    local hasPack = false
    for _, st in ipairs(States) do
        if normalizeId(App.CurrentForm[st]) ~= "" then hasPack = true; break end
    end
    pcall(function()
        local oldp = UI.Root:FindFirstChild("FE_PACK_REAPPLY")
        if oldp then oldp:Destroy() end
    end)
    if hasPack then
        local rb = new("TextButton", {
            Parent = UI.Root,
            Name = "FE_PACK_REAPPLY",
            Size = UDim2.new(0, 56, 0, 56),
            Position = UDim2.new(1, -70, 1, -90),
            BackgroundColor3 = Theme.Green,
            Text = "PACK",
            TextColor3 = Theme.Black,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = true,
            ZIndex = 95,
        })
        corner(rb, 12); stroke(rb, Theme.Black, 1, 0.15)
        connAdd("Floating", rb.MouseButton1Click:Connect(function()
            applyCurrentForm(App.LastAppliedName ~= "" and App.LastAppliedName or "Pack")
            notify("FE_BUNDLE", "Pack applied")
        end))
        pcall(function()
            connAdd("Floating", rb.Activated:Connect(function()
                applyCurrentForm(App.LastAppliedName ~= "" and App.LastAppliedName or "Pack")
                notify("FE_BUNDLE", "Pack applied")
            end))
        end)
    end
end

function addFloatingButton(item)
    local id = tostring(item.id or item.Id or "")
    for _, fb in ipairs(App.FloatingButtons) do
        if tostring(fb.catalogId)==id or tostring(fb.id)==id then
            notify("FE_BUNDLE","Already added"); return
        end
    end
    local animId = resolveEmoteAnimationId(id)
    table.insert(App.FloatingButtons, {
        id=id, catalogId=id, animId=animId, name=tostring(item.name or item.Name or id),
        posX=0.85, posXO=0, posY=0.25, posYO=0
    })
    saveData(); reflowFloating(); notify("FE_BUNDLE","Floating button created")
end

local function removeFloatingButton(id)
    id = tostring(id)
    for i, fb in ipairs(App.FloatingButtons) do
        if tostring(fb.id)==id or tostring(fb.catalogId)==id then
            table.remove(App.FloatingButtons, i); saveData(); reflowFloating(); return
        end
    end
end

---------------------------------------------------------------------
-- QUICK SELECTOR
---------------------------------------------------------------------
local function rebuildQuickPanel()
    if not UI or not UI.QuickBar then return end
    clearChildren(UI.QuickBar)
    if App.Settings.PickerProvider ~= "Quick" then
        UI.QuickBar.Visible=false; return
    end
    UI.QuickBar.Visible=true
    local lay = Instance.new("UIListLayout")
    lay.FillDirection=Enum.FillDirection.Horizontal
    lay.Padding=UDim.new(0,8)
    lay.HorizontalAlignment=Enum.HorizontalAlignment.Center
    lay.Parent=UI.QuickBar
    pad(UI.QuickBar, 8, 8, 8, 8)
    for _, qe in ipairs(App.QuickEntries) do
        local b = new("TextButton", {
            Parent=UI.QuickBar, Size=UDim2.new(0,56,0,56), BackgroundColor3=Theme.Card,
            Text="", AutoButtonColor=true
        })
        corner(b, 10); stroke(b, Theme.Accent, 1, 0.3)
        local img = new("ImageLabel", {
            Parent=b, Size=UDim2.new(1,-6,1,-6), Position=UDim2.new(0,3,0,3),
            BackgroundTransparency=1, Image=assetThumb(qe.catalogId or qe.id), ScaleType=Enum.ScaleType.Fit
        })
        corner(img, 8)
        local captured = qe
        connAdd("Page", b.MouseButton1Click:Connect(function()
            toggleEmote(captured.catalogId or captured.id, captured.name)
        end))
    end
end

function addQuickEntry(item)
    local id = tostring(item.id or item.Id or "")
    for _, qe in ipairs(App.QuickEntries) do
        if tostring(qe.catalogId)==id then notify("FE_BUNDLE","Already in Quick"); return end
    end
    local animId = resolveEmoteAnimationId(id)
    table.insert(App.QuickEntries, {id=id, catalogId=id, animId=animId, name=tostring(item.name or item.Name or id)})
    saveData(); rebuildQuickPanel(); notify("FE_BUNDLE","Added to Quick Selector")
end

---------------------------------------------------------------------
-- CONTROLLER
---------------------------------------------------------------------
function refreshControllerTracks()
    App.ControllersTracks = {}
    local animator = getAnimator()
    if animator then
        pcall(function()
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                table.insert(App.ControllersTracks, t)
            end
        end)
    end
    if App.CurrentEmoteTrack then
        local found=false
        for _, t in ipairs(App.ControllersTracks) do if t==App.CurrentEmoteTrack then found=true break end end
        if not found then table.insert(App.ControllersTracks, 1, App.CurrentEmoteTrack) end
    end
end

local function getSelectedTrack()
    refreshControllerTracks()
    return App.ControllersTracks[App.Controller.SelectedIndex] or App.ControllersTracks[1]
end

local function renderController(parent)
    refreshControllerTracks()
    local title = makeLabel(parent, "Animation Controller", 16, Theme.Text, true)
    title.Size = UDim2.new(1,-16,0,28)

    local dockRow = new("Frame", {Parent=parent, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local dl = Instance.new("UIListLayout"); dl.FillDirection=Enum.FillDirection.Horizontal; dl.Padding=UDim.new(0,8); dl.Parent=dockRow
    makeBtn(dockRow, App.Controller.Docked and "UNDOCK" or "REDOCK", function()
        App.Controller.Docked = not App.Controller.Docked
        saveData()
        if App.Controller.Docked then
            if UI.ControllerFloat then UI.ControllerFloat.Visible=false end
        else
            showControllerFloat()
        end
        navigate("Controller")
    end, Theme.Accent2, {size=UDim2.new(0,100,0,30)})

    makeLabel(parent, "Tracks", 13, Theme.Muted).Size=UDim2.new(1,0,0,20)
    local tracks = App.ControllersTracks
    if #tracks==0 then
        makeLabel(parent, "No active tracks. Play an emote first.", 13, Theme.LightMuted)
    else
        for i, track in ipairs(tracks) do
            local animId = "?"
            pcall(function() animId = track.Animation and track.Animation.AnimationId or "?" end)
            local label = "Track "..i.." · "..tostring(animId):sub(1,40)
            makeBtn(parent, (App.Controller.SelectedIndex==i and "► " or "")..label, function()
                App.Controller.SelectedIndex=i; navigate("Controller")
            end, App.Controller.SelectedIndex==i and Theme.Green or Theme.Card, {size=UDim2.new(1,-8,0,30)})
        end
    end

    local track = getSelectedTrack()
    local row = new("Frame", {Parent=parent, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local rl = Instance.new("UIListLayout"); rl.FillDirection=Enum.FillDirection.Horizontal; rl.Padding=UDim.new(0,8); rl.Parent=row
    makeBtn(row, App.Controller.Loop and "LOOP: ON" or "LOOP: OFF", function()
        App.Controller.Loop = not App.Controller.Loop
        applyTrackControls(getSelectedTrack()); saveData(); navigate("Controller")
    end, App.Controller.Loop and Theme.Green or Theme.Card, {size=UDim2.new(0,110,0,30)})
    makeBtn(row, App.Controller.Reverse and "REVERSE: ON" or "REVERSE: OFF", function()
        App.Controller.Reverse = not App.Controller.Reverse
        applyTrackControls(getSelectedTrack()); saveData(); navigate("Controller")
    end, App.Controller.Reverse and Theme.Green or Theme.Card, {size=UDim2.new(0,120,0,30)})

    makeLabel(parent, "Speed", 13, Theme.Muted).Size=UDim2.new(1,0,0,20)
    local speedRow = new("Frame", {Parent=parent, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local sl = Instance.new("UIListLayout"); sl.FillDirection=Enum.FillDirection.Horizontal; sl.Padding=UDim.new(0,6); sl.Parent=speedRow
    for _, sp in ipairs(SpeedPresets) do
        makeBtn(speedRow, sp[1], function()
            App.Controller.SpeedName=sp[1]; App.Controller.Speed=sp[2]
            applyTrackControls(getSelectedTrack()); saveData(); navigate("Controller")
        end, App.Controller.SpeedName==sp[1] and Theme.Green or Theme.Card, {size=UDim2.new(0,70,0,28)})
    end

    
    -- Seek bar for selected track (live + drag)
    makeLabel(parent, "Seek", 13, Theme.Muted).Size = UDim2.new(1,0,0,18)
    local seekRow = new("Frame", {Parent=parent, BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)})
    local seekBg = new("Frame", {
        Parent=seekRow, Size=UDim2.new(1,-110,0,12), Position=UDim2.new(0,0,0.5,-6),
        BackgroundColor3=Theme.Field, BorderSizePixel=0
    })
    corner(seekBg, 6)
    local seekFill = new("Frame", {
        Parent=seekBg, Size=UDim2.new(0,0,1,0), BackgroundColor3=Theme.Accent, BorderSizePixel=0
    })
    corner(seekFill, 6)
    local seekLbl = new("TextLabel", {
        Parent=seekRow, Position=UDim2.new(1,-106,0,0), Size=UDim2.new(0,106,1,0),
        BackgroundTransparency=1, Text="0.0 / 0.0", TextColor3=Theme.Muted, TextSize=11,
        Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Right
    })
    local function refreshSeek()
        local tr = getSelectedTrack and getSelectedTrack() or nil
        if not tr then
            seekFill.Size = UDim2.new(0,0,1,0)
            seekLbl.Text = "— / —"
            return
        end
        pcall(function()
            local len = tr.Length or 0
            local pos = tr.TimePosition or 0
            if len > 0 then
                seekFill.Size = UDim2.new(math.clamp(pos/len, 0, 1), 0, 1, 0)
            else
                seekFill.Size = UDim2.new(0,0,1,0)
            end
            seekLbl.Text = string.format("%.1f / %.1f", pos, len)
        end)
    end
    refreshSeek()
    connAdd("Page", RunService.Heartbeat:Connect(function()
        if App.Page ~= "Controller" then return end
        refreshSeek()
    end))
    local seekDragging = false
    local seekBtn = new("TextButton", {
        Parent=seekBg, Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", ZIndex=5
    })
    local function seekToInput(input)
        local tr = getSelectedTrack and getSelectedTrack()
        if not tr then return end
        local abs = seekBg.AbsolutePosition
        local size = seekBg.AbsoluteSize
        if size.X <= 0 then return end
        local px = input.Position.X
        local alpha = math.clamp((px - abs.X) / size.X, 0, 1)
        pcall(function()
            local len = tr.Length or 0
            if len > 0 then tr.TimePosition = alpha * len end
        end)
        refreshSeek()
    end
    connAdd("Page", seekBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            seekDragging = true
            seekToInput(input)
        end
    end))
    connAdd("Page", UserInputService.InputChanged:Connect(function(input)
        if not seekDragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            seekToInput(input)
        end
    end))
    connAdd("Page", UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            seekDragging = false
        end
    end))

    makeLabel(parent, "Intensity: "..tostring(math.floor(App.Controller.Intensity*100)).."%", 13, Theme.Muted).Size=UDim2.new(1,0,0,20)
    local irow = new("Frame", {Parent=parent, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local il = Instance.new("UIListLayout"); il.FillDirection=Enum.FillDirection.Horizontal; il.Padding=UDim.new(0,8); il.Parent=irow
    makeBtn(irow, "-", function()
        App.Controller.Intensity = math.max(0.05, App.Controller.Intensity - 0.1)
        applyTrackControls(getSelectedTrack()); saveData(); navigate("Controller")
    end, Theme.Card, {size=UDim2.new(0,44,0,30)})
    makeBtn(irow, "+", function()
        App.Controller.Intensity = math.min(2, App.Controller.Intensity + 0.1)
        applyTrackControls(getSelectedTrack()); saveData(); navigate("Controller")
    end, Theme.Card, {size=UDim2.new(0,44,0,30)})
    makeBtn(irow, "STOP EMOTE", function() stopEmote(); stopReverse(); refreshControllerTracks(); navigate("Controller") end, Theme.Red, {size=UDim2.new(0,110,0,30)})
end

function showControllerFloat()
    if not UI or not UI.Root then return end
    if UI.ControllerFloat then UI.ControllerFloat:Destroy() end
    local f = new("Frame", {
        Parent=UI.Root, Size=UDim2.new(0,280,0,220), Position=UDim2.new(1,-300,0.3,0),
        BackgroundColor3=Theme.Surface, BorderSizePixel=0, ZIndex=80
    })
    corner(f, 12); stroke(f, Theme.Accent, 1, 0.3)
    local handle = new("TextButton", {
        Parent=f, Size=UDim2.new(1,0,0,28), BackgroundColor3=Theme.Accent, Text="Controller · drag", TextColor3=Theme.Black,
        TextSize=12, Font=Enum.Font.GothamBold, AutoButtonColor=false, ZIndex=81
    })
    corner(handle, 12)
    local body = new("ScrollingFrame", {
        Parent=f, Position=UDim2.new(0,8,0,32), Size=UDim2.new(1,-16,1,-40),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4, CanvasSize=UDim2.new(0,0,0,300), ZIndex=81
    })
    local lay = Instance.new("UIListLayout"); lay.Padding=UDim.new(0,6); lay.Parent=body
    renderController(body)
    -- drag
    local dragging, inputRef, start, startPos
    connAdd("Controller", handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; inputRef=input; start=input.Position; startPos=f.Position
            local c; c=input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then dragging=false; if c then c:Disconnect() end end
            end)
        end
    end))
    connAdd("Controller", UserInputService.InputChanged:Connect(function(input)
        if dragging and input==inputRef then
            local d=input.Position-start
            f.Position=UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        end
    end))
    UI.ControllerFloat = f
end

---------------------------------------------------------------------
-- PAGES
---------------------------------------------------------------------
local function pageShell()
    connClear("Page")
    clearChildren(UI.Content)
    local scroll = new("ScrollingFrame", {
        Parent=UI.Content, Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
        BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=Theme.Accent,
        CanvasSize=UDim2.new(0,0,0,600), AutomaticCanvasSize=Enum.AutomaticSize.Y
    })
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 8)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = scroll
    pad(scroll, 8, 10, 16, 10)
    return scroll
end


local function makeSkeletonCards(parent, count)
    for i = 1, (count or 4) do
        local sk = new("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, isCompact() and 100 or 110),
            BackgroundColor3 = Theme.Skeleton,
            BorderSizePixel = 0,
            LayoutOrder = i,
        })
        corner(sk, 12)
        local pulse = new("Frame", {
            Parent = sk, Size = UDim2.new(0.4, 0, 1, 0), BackgroundColor3 = Theme.White,
            BackgroundTransparency = 0.85, BorderSizePixel = 0
        })
        task.spawn(function()
            while pulse and pulse.Parent do
                pulse.Position = UDim2.new(-0.4, 0, 0, 0)
                tween(pulse, {Position = UDim2.new(1.1, 0, 0, 0)}, 1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
                task.wait(1.1)
            end
        end)
    end
end

local function renderItemCard(parent, item, kind)
    local id = tostring(item.id or item.Id or "")
    local name = tostring(item.name or item.Name or id)
    local creator = tostring(item.creatorName or item.CreatorName or "")
    local card = makeCard(parent)
    card.Size = UDim2.new(1, 0, 0, isCompact() and 96 or 108)

    local img = new("ImageLabel", {
        Parent=card, Position=UDim2.new(0,10,0,10), Size=UDim2.new(0, isCompact() and 70 or 80, 0, isCompact() and 70 or 80),
        BackgroundColor3=Theme.Field, BorderSizePixel=0,
        Image=(kind=="Emote") and assetThumb(id) or bundleThumb(id), ScaleType=Enum.ScaleType.Fit
    })
    corner(img, 8)

    local title = new("TextLabel", {
        Parent=card, Position=UDim2.new(0, isCompact() and 90 or 100, 0, 8),
        Size=UDim2.new(1, isCompact() and -100 or -110, 0, 36),
        BackgroundTransparency=1, Text=name, TextColor3=Theme.Text, TextSize=13,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true, TextYAlignment=Enum.TextYAlignment.Top
    })
    if creator~="" then
        new("TextLabel", {
            Parent=card, Position=UDim2.new(0, isCompact() and 90 or 100, 0, 44),
            Size=UDim2.new(1,-110,0,16), BackgroundTransparency=1, Text=creator,
            TextColor3=Theme.Muted, TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left
        })
    end

    local actions = new("Frame", {
        Parent=card, Position=UDim2.new(0,10,1,-38), Size=UDim2.new(1,-20,0,28), BackgroundTransparency=1
    })
    local al = Instance.new("UIListLayout"); al.FillDirection=Enum.FillDirection.Horizontal; al.Padding=UDim.new(0,6); al.Parent=actions

    local capturedItem, capturedKind = item, kind
    local isActive = capturedKind=="Emote" and App.ActiveEmote and tostring(App.ActiveEmote.id)==tostring(capturedItem.id or capturedItem.Id)
    local playLabel = kind=="Emote" and (isActive and "STOP" or "PLAY") or (App.ChoosingState and "SET" or "APPLY")
    makeBtn(actions, playLabel, function()
        if capturedKind=="Emote" then
            toggleEmote(tostring(capturedItem.id or capturedItem.Id), tostring(capturedItem.name or ""))
            if App.Page=="Emotes" then navigate("Emotes") end
        elseif App.ChoosingState then setCustomSlot(App.ChoosingState, tostring(capturedItem.id or capturedItem.Id), tostring(capturedItem.name or ""))
        else applyBundle(tostring(capturedItem.id or capturedItem.Id), tostring(capturedItem.name or "")) end
    end, kind=="Emote" and (isActive and Theme.Red or Theme.Green) or Theme.Accent, {size=UDim2.new(0,78,0,28)})

    makeBtn(actions, "INFO", function()
        showInfoModal(capturedItem, capturedKind)
    end, Theme.Accent2, {size=UDim2.new(0,60,0,28)})

    local favList = (kind=="Emote") and App.FavoritesEmotes or App.FavoritesBundles
    makeBtn(actions, isFavorite(favList, id) and "★" or "☆", function()
        toggleFavorite(capturedKind, capturedItem)
        navigate(App.Page)
    end, Theme.Yellow, {size=UDim2.new(0,40,0,28)})
end

local function renderEmotesPage()
    local scroll = pageShell()
    makeLabel(scroll, "Emotes", 18, Theme.Text, true)

    -- source filter
    local src = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)})
    local sl = Instance.new("UIListLayout"); sl.FillDirection=Enum.FillDirection.Horizontal; sl.Padding=UDim.new(0,6); sl.Parent=src
    for _, s in ipairs({"Roblox","UGC","Favorites"}) do
        makeBtn(src, s, function()
            App.Settings.SourceFilter=s; saveData(); navigate("Emotes")
        end, App.Settings.SourceFilter==s and Theme.Green or Theme.Card, {size=UDim2.new(0,90,0,28)})
    end

    local searchBox = makeBox(scroll, "Search emotes...", App.LastEmoteKeyword~="dance" and App.LastEmoteKeyword or "")
    local searchRow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local srl = Instance.new("UIListLayout"); srl.FillDirection=Enum.FillDirection.Horizontal; srl.Padding=UDim.new(0,8); srl.Parent=searchRow
    local function doEmoteSearch(kw)
        if App.Settings.SourceFilter=="Favorites" then navigate("Emotes"); return end
        showLoading("Searching...")
        task.spawn(function()
            local ok, count = searchCatalog("Emote", kw, false)
            hideLoading()
            -- AI suggestions optional (non-blocking)
            if App.Settings.Suggestions and ok then
                task.spawn(function()
                    -- lightweight local suggestions from results names
                    local tips = {}
                    for _, it in ipairs(App.EmoteResults) do
                        local n = tostring(it.name or it.Name or "")
                        if n ~= "" and #tips < 5 then table.insert(tips, n) end
                    end
                    if #tips > 0 then
                        status("Suggestions: "..table.concat(tips, " · "), true)
                    end
                end)
            end
            if ok then App.SearchError=nil; navigate("Emotes"); status("Loaded "..tostring(count), true)
            else App.SearchError=true; navigate("Emotes"); status("Search failed", false) end
        end)
    end
    makeBtn(searchRow, "SEARCH", function() doEmoteSearch(searchBox.Text) end, Theme.Accent, {size=UDim2.new(0,100,0,32)})
    -- Debounce: type then wait 0.45s
    local debounceToken = 0
    connAdd("Page", searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        debounceToken = debounceToken + 1
        local my = debounceToken
        local text = searchBox.Text
        task.delay(0.45, function()
            if my ~= debounceToken then return end
            if App.Page ~= "Emotes" then return end
            if text == "" or text == App.LastEmoteKeyword then return end
            doEmoteSearch(text)
        end)
    end))

    makeLabel(scroll, "INFO = avatar preview · PLAY = use now", 11, Theme.Muted)
    -- Auto recommendations: no need to press SEARCH
    if #App.EmoteResults == 0 and App.Settings.SourceFilter ~= "Favorites" and not App.SearchError then
        task.spawn(function()
            local gen = App.PageGeneration
            status("Loading recommendations...", true)
            local ok, count = searchCatalog("Emote", App.LastEmoteKeyword ~= "" and App.LastEmoteKeyword or "dance", false)
            if gen == App.PageGeneration and App.Page == "Emotes" then
                if ok then
                    App.SearchError = nil
                    navigate("Emotes")
                    status("Recommended · "..tostring(count), true)
                else
                    App.SearchError = true
                    navigate("Emotes")
                end
            end
        end)
    end

    local list
    if App.Settings.SourceFilter=="Favorites" then list = App.FavoritesEmotes
    else list = App.EmoteResults end

    if #list==0 then
        if App.SearchError then
        makeLabel(scroll, "Failed to load emotes.", 14, Theme.Red)
        makeBtn(scroll, "RETRY", function()
            showLoading("Retrying...")
            task.spawn(function()
                local ok, count = searchCatalog("Emote", App.LastEmoteKeyword, false)
                hideLoading()
                if ok then navigate("Emotes"); status("Loaded "..tostring(count), true)
                else App.SearchError = true; navigate("Emotes"); status("Search failed", false) end
            end)
        end, Theme.Accent, {size=UDim2.new(0,100,0,32)})
    else
        makeLabel(scroll, "No results. Search or switch source.", 14, Theme.LightMuted)
        makeBtn(scroll, "CLEAR SEARCH", function()
            App.LastEmoteKeyword = "dance"
            navigate("Emotes")
        end, Theme.Card, {size=UDim2.new(0,120,0,30)})
    end
    else
        for _, item in ipairs(list) do
            renderItemCard(scroll, item, "Emote")
        end
        -- Infinite scroll: load more when near bottom
        if App.Settings.SourceFilter ~= "Favorites" then
            local loadingMore = false
            connAdd("Page", scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if loadingMore then return end
                if not App.NextEmoteCursor then return end
                local y = scroll.CanvasPosition.Y
                local maxY = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
                if maxY > 0 and y >= maxY - 80 then
                    loadingMore = true
                    status("Loading more emotes...", true)
                    task.spawn(function()
                        local ok = searchCatalog("Emote", App.LastEmoteKeyword, true)
                        loadingMore = false
                        if ok and App.Page == "Emotes" then
                            navigate("Emotes")
                        end
                    end)
                end
            end))
            if App.NextEmoteCursor then
                makeLabel(scroll, "Scroll down for more…", 11, Theme.LightMuted)
            end
        end
    end
end

local function renderBundlesPage()
    local scroll = pageShell()
    makeLabel(scroll, App.ChoosingState and ("Choose bundle for "..App.ChoosingState) or "Bundles", 18, Theme.Text, true)
    local searchBox = makeBox(scroll, "Search bundles...", App.LastBundleKeyword~="animation" and App.LastBundleKeyword or "")
    local searchRow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local srl = Instance.new("UIListLayout"); srl.FillDirection=Enum.FillDirection.Horizontal; srl.Padding=UDim.new(0,8); srl.Parent=searchRow
    local function doBundleSearch(kw)
        showLoading("Searching...")
        task.spawn(function()
            local ok, count = searchCatalog("Bundle", kw, false)
            hideLoading()
            if ok then navigate("Bundles"); status("Loaded "..tostring(count), true)
            else status("Search failed", false) end
        end)
    end
    makeBtn(searchRow, "SEARCH", function() doBundleSearch(searchBox.Text) end, Theme.Accent, {size=UDim2.new(0,100,0,32)})
    local debB = 0
    connAdd("Page", searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        debB = debB + 1
        local my = debB
        local text = searchBox.Text
        task.delay(0.45, function()
            if my ~= debB or App.Page ~= "Bundles" then return end
            if text == "" or text == App.LastBundleKeyword then return end
            doBundleSearch(text)
        end)
    end))
    if App.ChoosingState then
        makeBtn(searchRow, "CANCEL SET", function() App.ChoosingState=nil; navigate("Custom") end, Theme.Red, {size=UDim2.new(0,100,0,32)})
    end
    local list = App.BundleResults
    if #list==0 then
        makeLabel(scroll, "Loading recommendations...", 14, Theme.Muted)
        task.spawn(function()
            local gen = App.PageGeneration
            local ok, count = searchCatalog("Bundle", App.LastBundleKeyword ~= "" and App.LastBundleKeyword or "animation", false)
            if gen == App.PageGeneration and App.Page == "Bundles" then
                if ok then navigate("Bundles"); status("Bundles · "..tostring(count), true)
                else status("Bundle search failed", false) end
            end
        end)
    elseif false then makeLabel(scroll, "No bundles. Search first.", 14, Theme.LightMuted)
    else
        for _, item in ipairs(list) do renderItemCard(scroll, item, "Bundle") end
        -- Infinite scroll bundles
        local loadingMoreB = false
        connAdd("Page", scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            if loadingMoreB then return end
            if not App.NextBundleCursor then return end
            local y = scroll.CanvasPosition.Y
            local maxY = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
            if maxY > 0 and y >= maxY - 80 then
                loadingMoreB = true
                status("Loading more bundles...", true)
                task.spawn(function()
                    local ok = searchCatalog("Bundle", App.LastBundleKeyword, true)
                    loadingMoreB = false
                    if ok and App.Page == "Bundles" then navigate("Bundles") end
                end)
            end
        end))
        if App.NextBundleCursor then
            makeLabel(scroll, "Scroll down for more…", 11, Theme.LightMuted)
        end
    end
end

local function renderCustomPage()
    local scroll = pageShell()
    makeLabel(scroll, "Custom Mix", 18, Theme.Text, true)
    for _, state in ipairs(States) do
        local row = makeCard(scroll)
        row.Size = UDim2.new(1,0,0,52)
        local meta = App.SlotMeta[state]
        new("TextLabel", {
            Parent=row, Position=UDim2.new(0,12,0,6), Size=UDim2.new(0,60,0,40),
            BackgroundTransparency=1, Text=state, TextColor3=Theme.Text, TextSize=13, Font=Enum.Font.GothamBold,
            TextXAlignment=Enum.TextXAlignment.Left
        })
        new("TextLabel", {
            Parent=row, Position=UDim2.new(0,80,0,6), Size=UDim2.new(1,-220,0,40),
            BackgroundTransparency=1, Text=meta and ((meta.Bundle or "?").." · "..tostring(meta.Id or "")) or "not set",
            TextColor3=meta and Theme.Muted or Theme.LightMuted, TextSize=12, Font=Enum.Font.Gotham,
            TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true
        })
        local actions = new("Frame", {Parent=row, Position=UDim2.new(1,-150,0,10), Size=UDim2.new(0,140,0,32), BackgroundTransparency=1})
        local al = Instance.new("UIListLayout"); al.FillDirection=Enum.FillDirection.Horizontal; al.Padding=UDim.new(0,6); al.Parent=actions
        local st = state
        makeBtn(actions, "SET", function() App.ChoosingState=st; navigate("Bundles") end, Theme.Green, {size=UDim2.new(0,44,0,28)})
        makeBtn(actions, "X", function()
            App.CurrentForm[st]=""; App.SlotMeta[st]=nil; saveData(); navigate("Custom")
        end, Theme.Red, {size=UDim2.new(0,32,0,28)})
    end
    local row = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,36)})
    local rl = Instance.new("UIListLayout"); rl.FillDirection=Enum.FillDirection.Horizontal; rl.Padding=UDim.new(0,8); rl.Parent=row
    makeBtn(row, "APPLY MIX", function() App.LastAppliedName="Custom Mix"; applyCurrentForm("Custom Mix") end, Theme.Accent, {size=UDim2.new(0,120,0,32)})
    makeBtn(row, "CLEAR", function()
        for _, st in ipairs(States) do App.CurrentForm[st]=""; App.SlotMeta[st]=nil end
        saveData(); navigate("Custom")
    end, Theme.Red, {size=UDim2.new(0,80,0,32)})
end

local function renderFavoritesPage()
    local scroll = pageShell()
    makeLabel(scroll, "Favorites", 18, Theme.Text, true)
    local n = 0
    for _, fav in ipairs(App.FavoritesBundles) do renderItemCard(scroll, fav, "Bundle"); n=n+1 end
    for _, fav in ipairs(App.FavoritesEmotes) do renderItemCard(scroll, fav, "Emote"); n=n+1 end
    if n==0 then makeLabel(scroll, "No favorites yet. Tap ★ on a card.", 14, Theme.LightMuted) end
end

local function renderSavePage()
    local scroll = pageShell()
    makeLabel(scroll, "Save Packs", 18, Theme.Text, true)
    local nameBox = makeBox(scroll, "Pack name...")
    makeBtn(scroll, "SAVE CURRENT", function()
        local name = nameBox.Text
        if name=="" then name = "Pack "..tostring(#App.SavedPacks+1) end
        table.insert(App.SavedPacks, {Name=name, Form=tableCopy(App.CurrentForm), Meta=tableCopy(App.SlotMeta)})
        saveData(); navigate("Save"); notify("FE_BUNDLE","Saved "..name)
    end, Theme.Green, {size=UDim2.new(0,140,0,32)})
    for i, pack in ipairs(App.SavedPacks) do
        local card = makeCard(scroll); card.Size=UDim2.new(1,0,0,56)
        local name = tostring(pack.Name or ("Pack "..i))
        local auto = App.Settings.AutoLoadName==name and " [AUTO]" or ""
        new("TextLabel", {
            Parent=card, Position=UDim2.new(0,12,0,8), Size=UDim2.new(1,-180,0,40),
            BackgroundTransparency=1, Text=name..auto, TextColor3=Theme.Text, TextSize=13,
            Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left
        })
        local actions = new("Frame", {Parent=card, Position=UDim2.new(1,-170,0,12), Size=UDim2.new(0,160,0,32), BackgroundTransparency=1})
        local al = Instance.new("UIListLayout"); al.FillDirection=Enum.FillDirection.Horizontal; al.Padding=UDim.new(0,4); al.Parent=actions
        local idx = i
        makeBtn(actions, "USE", function()
            App.CurrentForm=tableCopy(App.SavedPacks[idx].Form)
            App.SlotMeta=tableCopy(App.SavedPacks[idx].Meta)
            applyCurrentForm(name)
        end, Theme.Accent, {size=UDim2.new(0,48,0,28)})
        makeBtn(actions, "AUTO", function()
            App.Settings.AutoLoadName=name; App.Settings.AutoLoad=true; saveData(); navigate("Save")
        end, Theme.Accent2, {size=UDim2.new(0,48,0,28)})
        makeBtn(actions, "DEL", function()
            table.remove(App.SavedPacks, idx); saveData(); navigate("Save")
        end, Theme.Red, {size=UDim2.new(0,40,0,28)})
    end
end

local function renderSettingsPage()
    local scroll = pageShell()
    makeLabel(scroll, "Settings", 18, Theme.Text, true)

    local function section(title)
        makeLabel(scroll, title, 14, Theme.Accent, true).Size=UDim2.new(1,0,0,24)
    end
    local function toggleRow(label, get, set)
        local row = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
        local rl = Instance.new("UIListLayout"); rl.FillDirection=Enum.FillDirection.Horizontal; rl.Padding=UDim.new(0,8); rl.Parent=row
        local on = get()
        makeBtn(row, label..": "..(on and "ON" or "OFF"), function()
            set(not get()); saveData(); applyRuntimeSettings(); navigate("Settings")
        end, on and Theme.Green or Theme.Card, {size=UDim2.new(0, 220, 0, 30)})
    end

    section("PICKER")
    local prow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local pl = Instance.new("UIListLayout"); pl.FillDirection=Enum.FillDirection.Horizontal; pl.Padding=UDim.new(0,8); pl.Parent=prow
    makeBtn(prow, "Floating", function()
        App.Settings.PickerProvider="Floating"; saveData(); reflowFloating(); rebuildQuickPanel(); navigate("Settings")
    end, App.Settings.PickerProvider=="Floating" and Theme.Green or Theme.Card, {size=UDim2.new(0,100,0,30)})
    makeBtn(prow, "Quick", function()
        App.Settings.PickerProvider="Quick"; saveData(); reflowFloating(); rebuildQuickPanel(); navigate("Settings")
    end, App.Settings.PickerProvider=="Quick" and Theme.Green or Theme.Card, {size=UDim2.new(0,100,0,30)})

    section("FLOATING BUTTONS")
    local frow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local fl = Instance.new("UIListLayout"); fl.FillDirection=Enum.FillDirection.Horizontal; fl.Padding=UDim.new(0,8); fl.Parent=frow
    makeBtn(frow, "Autogrid", function()
        App.Settings.FloatingMode="Autogrid"; saveData(); reflowFloating(); navigate("Settings")
    end, App.Settings.FloatingMode=="Autogrid" and Theme.Green or Theme.Card, {size=UDim2.new(0,90,0,30)})
    makeBtn(frow, "Freeform", function()
        App.Settings.FloatingMode="Freeform"; saveData(); reflowFloating(); navigate("Settings")
    end, App.Settings.FloatingMode=="Freeform" and Theme.Green or Theme.Card, {size=UDim2.new(0,90,0,30)})
    local placeRow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local prl = Instance.new("UIListLayout"); prl.FillDirection=Enum.FillDirection.Horizontal; prl.Padding=UDim.new(0,6); prl.Parent=placeRow
    for _, p in ipairs({"TopRight","TopLeft","BottomRight","BottomLeft"}) do
        makeBtn(placeRow, p, function()
            App.Settings.FloatingPlacement=p; saveData(); reflowFloating(); navigate("Settings")
        end, App.Settings.FloatingPlacement==p and Theme.Green or Theme.Card, {size=UDim2.new(0,90,0,28)})
    end
    makeBtn(scroll, "Clear all floating", function()
        App.FloatingButtons={}; saveData(); reflowFloating(); notify("FE_BUNDLE","Floating cleared")
    end, Theme.Red, {size=UDim2.new(0,160,0,30)})

    section("LAYOUT")
    local wrow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local wl = Instance.new("UIListLayout"); wl.FillDirection=Enum.FillDirection.Horizontal; wl.Padding=UDim.new(0,8); wl.Parent=wrow
    makeBtn(wrow, "Wide", function() App.Settings.WidthMode="Wide"; saveData(); applyLayout(); navigate("Settings") end,
        App.Settings.WidthMode=="Wide" and Theme.Green or Theme.Card, {size=UDim2.new(0,80,0,30)})
    makeBtn(wrow, "Compact", function() App.Settings.WidthMode="Compact"; saveData(); applyLayout(); navigate("Settings") end,
        App.Settings.WidthMode=="Compact" and Theme.Green or Theme.Card, {size=UDim2.new(0,90,0,30)})

    section("PERFORMANCE")
    toggleRow("Avoid scaling", function() return App.Settings.AvoidScaling end, function(v) App.Settings.AvoidScaling=v end)
    toggleRow("Screen blur", function() return App.Settings.ScreenBlur end, function(v) App.Settings.ScreenBlur=v end)

    section("UGC CACHE")
    toggleRow("Cache UGC IDs", function() return App.Settings.CacheUGCIds end, function(v) App.Settings.CacheUGCIds=v end)
    toggleRow("Cache UGC tracks", function() return App.Settings.CacheUGCTracks end, function(v) App.Settings.CacheUGCTracks=v end)

    section("SEARCH / AI")
    toggleRow("AI suggestions", function() return App.Settings.Suggestions end, function(v) App.Settings.Suggestions=v end)
    makeLabel(scroll, "AI is optional. Search works without it.", 11, Theme.LightMuted)

    section("EMOTE DEFAULTS")
    makeLabel(scroll, "Speed: "..tostring(App.Settings.EmoteSpeed).."x", 12, Theme.Muted)
    local srow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local srl = Instance.new("UIListLayout"); srl.FillDirection=Enum.FillDirection.Horizontal; srl.Padding=UDim.new(0,6); srl.Parent=srow
    for _, n in ipairs({0,0.5,1,1.5,2}) do
        makeBtn(srow, tostring(n).."x", function()
            applyEmoteSpeed(n)
            navigate("Settings")
        end, App.Settings.EmoteSpeed==n and Theme.Green or Theme.Card, {size=UDim2.new(0,50,0,28)})
    end
    toggleRow("Emote loop", function() return App.Settings.EmoteLoop end, function(v) App.Settings.EmoteLoop=v end)
    toggleRow("Move while emote", function() return App.Settings.MoveWhileEmote end, function(v) App.Settings.MoveWhileEmote=v end)

    section("APPLY METHOD")
    local arow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local arl = Instance.new("UIListLayout"); arl.FillDirection=Enum.FillDirection.Horizontal; arl.Padding=UDim.new(0,6); arl.Parent=arow
    for _, m in ipairs({"Animate","Description","Both"}) do
        makeBtn(arow, m, function() App.Settings.ApplyMethod=m; saveData(); navigate("Settings") end,
            App.Settings.ApplyMethod==m and Theme.Green or Theme.Card, {size=UDim2.new(0,100,0,28)})
    end

    section("MISCELLANEOUS")
    toggleRow("Start closed", function() return App.Settings.StartClosed end, function(v) App.Settings.StartClosed=v end)
    toggleRow("Autoload pack", function() return App.Settings.AutoLoad end, function(v) App.Settings.AutoLoad=v end)

    section("PRIVACY")
    toggleRow("Crowdsource", function() return App.Settings.Crowdsource end, function(v) App.Settings.Crowdsource=v end)
    makeLabel(scroll, "OFF = no crowdsource data sent.", 11, Theme.LightMuted)

    section("ACTIONS")
    local brow = new("Frame", {Parent=scroll, BackgroundTransparency=1, Size=UDim2.new(1,0,0,34)})
    local bl = Instance.new("UIListLayout"); bl.FillDirection=Enum.FillDirection.Horizontal; bl.Padding=UDim.new(0,8); bl.Parent=brow
    makeBtn(brow, "STOP EMOTE", function() stopEmote(); stopReverse() end, Theme.Red, {size=UDim2.new(0,110,0,30)})
    makeBtn(brow, "RESET ORIG", restoreOriginal, Theme.Yellow, {size=UDim2.new(0,110,0,30)})
    makeLabel(scroll, "FE_BUNDLE v"..App.Version.." · schema "..tostring(App.Schema), 11, Theme.LightMuted)
end

local function renderControllerPage()
    local scroll = pageShell()
    renderController(scroll)
end

---------------------------------------------------------------------
-- NAVIGATION
---------------------------------------------------------------------
function navigate(page)
    App.Page = page
    App.PageGeneration = (App.PageGeneration or 0) + 1
    local gen = App.PageGeneration
    -- update nav visual
    if UI and UI.NavButtons then
        for name, btn in pairs(UI.NavButtons) do
            btn.BackgroundColor3 = (name==page) and Theme.Accent2 or Theme.Card
        end
    end
    local ok, err = pcall(function()
        if page=="Emotes" then renderEmotesPage()
        elseif page=="Bundles" then renderBundlesPage()
        elseif page=="Controller" then renderControllerPage()
        elseif page=="Custom" then renderCustomPage()
        elseif page=="Favorites" then renderFavoritesPage()
        elseif page=="Save" then renderSavePage()
        elseif page=="Settings" then renderSettingsPage()
        end
    end)
    if not ok then
        logErr("PAGE", tostring(err))
        if UI and UI.Content then
            clearChildren(UI.Content)
            local scroll = pageShell and pageShell() or UI.Content
            if type(makeLabel)=="function" then
                makeLabel(scroll, "Page failed to load.", 14, Theme.Red)
                makeBtn(scroll, "RETRY", function() navigate(page) end, Theme.Accent, {size=UDim2.new(0,100,0,32)})
                makeBtn(scroll, "HOME", function() navigate("Emotes") end, Theme.Card, {size=UDim2.new(0,100,0,32)})
            end
        end
        status("Page error", false)
    end
    if gen == App.PageGeneration then
        rebuildQuickPanel()
    end
end

---------------------------------------------------------------------
-- RUNTIME SETTINGS APPLY
---------------------------------------------------------------------
function applyRuntimeSettings()
    -- blur
    local blur = Lighting:FindFirstChild("FE_BUNDLE_BLUR")
    if App.Settings.ScreenBlur then
        if not blur then
            blur = Instance.new("BlurEffect"); blur.Name="FE_BUNDLE_BLUR"; blur.Parent=Lighting
        end
        blur.Size = 12
    elseif blur then
        blur:Destroy()
    end
    if UI and UI.Main then
        UI.Main.BackgroundTransparency = App.Settings.UITransparency
    end
    reflowFloating()
    rebuildQuickPanel()
end

function applyLayout()
    if not UI or not UI.Main then return end
    local vs = viewportSize()
    local compact = isCompact()
    local w = compact and math.min(420, vs.X - 24) or math.min(560, vs.X - 40)
    local h = compact and math.min(480, vs.Y - 40) or math.min(540, vs.Y - 50)
    UI.Main.Size = UDim2.new(0, w, 0, h)
end

---------------------------------------------------------------------
-- OPEN / CLOSE MENU
---------------------------------------------------------------------
local function openMenu()
    if App.MenuAnimating or App.MenuOpen or not UI or not UI.Main then return end
    App.MenuAnimating = true
    UI.Main.Visible = true
    if App.Settings.AvoidScaling then
        UI.Main.Size = UDim2.new(0, 10, 0, 10)
        applyLayout()
        App.MenuOpen=true; App.MenuAnimating=false
    else
        local target = UI.Main.Size
        UI.Main.Size = UDim2.new(0, 40, 0, 40)
        applyLayout()
        local tw = tween(UI.Main, {Size = UI.Main.Size}, 0.01) -- size already applied
        -- re-apply target with tween from small
        local w, h = UI.Main.Size.X.Offset, UI.Main.Size.Y.Offset
        UI.Main.Size = UDim2.new(0, 40, 0, 40)
        tween(UI.Main, {Size=UDim2.new(0,w,0,h)}, 0.28, Enum.EasingStyle.Back)
        task.delay(0.3, function() App.MenuOpen=true; App.MenuAnimating=false end)
    end
    if not UI.Content:FindFirstChildWhichIsA("GuiObject") then
        navigate("Emotes")
    end
end

local function closeMenu()
    if App.MenuAnimating or not App.MenuOpen or not UI or not UI.Main then return end
    App.MenuAnimating = true
    closeModal(); hideLoading()
    if App.Settings.AvoidScaling then
        UI.Main.Visible=false
        App.MenuOpen=false; App.MenuAnimating=false
    else
        tween(UI.Main, {Size=UDim2.new(0,36,0,36)}, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.delay(0.2, function()
            UI.Main.Visible=false
            applyLayout()
            App.MenuOpen=false; App.MenuAnimating=false
        end)
    end
end

local function toggleMenu()
    if App.MenuAnimating then return end
    if App.MenuOpen then closeMenu() else openMenu() end
end

---------------------------------------------------------------------
-- CREATE GUI
---------------------------------------------------------------------
local function createGui()
    local pg, how = getParentGui()
    print("[FE12] parent=", how)
    if not pg then return false end

    pcall(function()
        for _, n in ipairs({"FE_BUNDLE_V12","FE_BUNDLE_V10_FIXED","FE_BUNDLE_V10","TEST_GUI_ONLY","FE_BUNDLE_MARKER"}) do
            local o = pg:FindFirstChild(n); if o then o:Destroy() end
        end
    end)

    local root = Instance.new("ScreenGui")
    root.Name = "FE_BUNDLE_V12"
    root.ResetOnSpawn = false
    root.IgnoreGuiInset = true
    root.DisplayOrder = 999999
    root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(root) end end)
    root.Parent = pg

    UI = { Root = root, NavButtons = {} }

    -- Icon
    local icon = Instance.new("TextButton")
    icon.Name = "Icon"
    icon.Parent = root
    icon.Position = UDim2.new(
        App.Settings.IconPosX or 0,
        App.Settings.IconPosXO or 14,
        App.Settings.IconPosY or 0.38,
        App.Settings.IconPosYO or 0
    )
    icon.Size = UDim2.new(0, 58, 0, 58)
    icon.BackgroundColor3 = Theme.Accent
    icon.Text = "FE"
    icon.TextColor3 = Theme.Black
    icon.TextSize = 18
    icon.Font = Enum.Font.GothamBold
    icon.AutoButtonColor = true
    icon.ZIndex = 100
    corner(icon, 14); stroke(icon, Theme.Black, 2, 0)
    UI.Icon = icon

    local tag = Instance.new("TextLabel")
    tag.Parent = root
    tag.Position = UDim2.new(
        App.Settings.IconPosX or 0,
        (App.Settings.IconPosXO or 14) - 8,
        App.Settings.IconPosY or 0.38,
        (App.Settings.IconPosYO or 0) + 60
    )
    tag.Size = UDim2.new(0, 74, 0, 14)
    tag.BackgroundTransparency = 1
    tag.Text = "FE BUNDLE"
    tag.TextColor3 = Theme.Accent
    tag.TextSize = 10
    tag.Font = Enum.Font.GothamBold
    tag.ZIndex = 101
    UI.IconTag = tag

    -- Main
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Parent = root
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.Size = UDim2.new(0, 560, 0, 520)
    main.BackgroundColor3 = Theme.Page
    main.BackgroundTransparency = App.Settings.UITransparency
    main.BorderSizePixel = 0
    main.Visible = false
    main.Active = true
    main.ZIndex = 20
    corner(main, 14); stroke(main, Theme.Accent, 1.5, 0.35)
    UI.Main = main

    -- Header
    local header = new("Frame", {Parent=main, Size=UDim2.new(1,0,0,48), BackgroundColor3=Theme.Surface, BorderSizePixel=0, ZIndex=21})
    corner(header, 14)
    new("Frame", {Parent=header, Position=UDim2.new(0,0,1,-12), Size=UDim2.new(1,0,0,12), BackgroundColor3=Theme.Surface, BorderSizePixel=0, ZIndex=21})
    UI.HeaderTitle = new("TextLabel", {
        Parent=main, Position=UDim2.new(0,14,0,6), Size=UDim2.new(1,-90,0,22),
        BackgroundTransparency=1, Text="FE_BUNDLE", TextColor3=Theme.Text, TextSize=16,
        Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=22
    })
    new("TextLabel", {
        Parent=main, Position=UDim2.new(0,14,0,28), Size=UDim2.new(1,-90,0,14),
        BackgroundTransparency=1, Text="v"..App.Version.." · rebuild", TextColor3=Theme.Muted, TextSize=11,
        Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=22
    })
    local closeBtn = new("TextButton", {
        Parent=main, Position=UDim2.new(1,-42,0,8), Size=UDim2.new(0,30,0,28),
        BackgroundColor3=Theme.Red, Text="X", TextColor3=Theme.Text, TextSize=14,
        Font=Enum.Font.GothamBold, ZIndex=30
    })
    corner(closeBtn, 8)
    connAdd("Global", closeBtn.MouseButton1Click:Connect(closeMenu))

    -- Nav
    local nav = new("Frame", {
        Parent=main, Position=UDim2.new(0,8,0,52), Size=UDim2.new(1,-16,0,34),
        BackgroundTransparency=1, ZIndex=22
    })
    local navLay = Instance.new("UIListLayout")
    navLay.FillDirection=Enum.FillDirection.Horizontal
    navLay.Padding=UDim.new(0,4)
    navLay.Parent=nav
    local pages = {
        {"Emotes","Emotes"},{"Bundles","Bundles"},{"CTRL","Controller"},
        {"Custom","Custom"},{"Favs","Favorites"},{"Save","Save"},{"Set","Settings"}
    }
    for _, p in ipairs(pages) do
        local b = makeBtn(nav, p[1], function() navigate(p[2]) end, Theme.Card, {bucket="Global", size=UDim2.new(0, isCompact() and 52 or 68, 0, 28)})
        UI.NavButtons[p[2]] = b
    end

    -- Content
    UI.Content = new("Frame", {
        Parent=main, Position=UDim2.new(0,0,0,90), Size=UDim2.new(1,0,1,-120),
        BackgroundTransparency=1, ZIndex=22
    })

    UI.StatusLabel = new("TextLabel", {
        Parent=main, Position=UDim2.new(0,12,1,-26), Size=UDim2.new(1,-24,0,18),
        BackgroundTransparency=1, Text="Ready", TextColor3=Theme.Muted, TextSize=12,
        Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=22
    })

    -- Floating layer
    UI.FloatingLayer = new("Frame", {
        Parent=root, BackgroundTransparency=1, BorderSizePixel=0, ZIndex=40, Size=UDim2.new(1,0,1,0)
    })

    -- Quick bar
    UI.QuickBar = new("Frame", {
        Parent=root, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,8),
        Size=UDim2.new(0.9,0,0,72), BackgroundColor3=Theme.Surface, BackgroundTransparency=0.15,
        BorderSizePixel=0, Visible=false, ZIndex=45
    })
    corner(UI.QuickBar, 12); stroke(UI.QuickBar, Theme.Accent, 1, 0.4)

    -- Header drag
    local headerDrag = new("TextButton", {
        Parent=main, Size=UDim2.new(1,-50,0,48), BackgroundTransparency=1, Text="", ZIndex=25
    })
    local mainDragging, mainInput, mainStart, mainPos
    connAdd("Global", headerDrag.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            mainDragging=true; mainInput=input; mainStart=input.Position; mainPos=main.Position
            local c; c=input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then mainDragging=false; if c then c:Disconnect() end end
            end)
        end
    end))
    connAdd("Global", UserInputService.InputChanged:Connect(function(input)
        if mainDragging and input==mainInput then
            local d=input.Position-mainStart
            main.Position=UDim2.new(mainPos.X.Scale, mainPos.X.Offset+d.X, mainPos.Y.Scale, mainPos.Y.Offset+d.Y)
        end
    end))

    -- Icon drag/tap
    local iconDragging, iconMoved, iconInput, iconStart, iconPos
    local THRESH=10
    connAdd("Global", icon.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            iconDragging=true; iconMoved=false; iconInput=input; iconStart=input.Position; iconPos=icon.Position
            local c; c=input.Changed:Connect(function()
                if input.UserInputState==Enum.UserInputState.End then
                    iconDragging=false
                    if not iconMoved then toggleMenu() end
                    if c then c:Disconnect() end
                end
            end)
        end
    end))
    connAdd("Global", UserInputService.InputChanged:Connect(function(input)
        if iconDragging and input==iconInput then
            local d=input.Position-iconStart
            if math.abs(d.X)>THRESH or math.abs(d.Y)>THRESH then iconMoved=true end
            if iconMoved then
                local np = UDim2.new(iconPos.X.Scale, iconPos.X.Offset+d.X, iconPos.Y.Scale, iconPos.Y.Offset+d.Y)
                icon.Position = np
                -- clamp absolute
                local vs = viewportSize()
                local ap = icon.AbsolutePosition
                local asz = icon.AbsoluteSize
                local cx = math.clamp(ap.X, 4, math.max(4, vs.X - asz.X - 4))
                local cy = math.clamp(ap.Y, 4, math.max(4, vs.Y - asz.Y - 24))
                icon.Position = UDim2.new(0, cx, 0, cy)
                tag.Position = UDim2.new(0, cx - 8, 0, cy + 60)
            end
        end
    end))

    applyLayout()
    print("[FE12] createGui OK")
    return true
end

---------------------------------------------------------------------
-- CHARACTER LIFECYCLE
---------------------------------------------------------------------
local function onCharacter(char)
    pcall(function() stopEmote("respawn") end)
    task.delay(1.0, function()
        pcall(captureOriginals)
        stopReverse()
        refreshControllerTracks()
        if not App.Controller.Docked then showControllerFloat() end
        updateEmoteRuntimeUI()
        -- Auto re-apply saved animation pack / custom mix after death
        local hasPack = false
        for _, st in ipairs(States) do
            if normalizeId(App.CurrentForm[st]) ~= "" then hasPack = true; break end
        end
        if hasPack and App.Settings.AutoLoad ~= false then
            status("Re-applying pack...", true)
            pcall(function()
                applyCurrentForm(App.LastAppliedName ~= "" and App.LastAppliedName or "Auto")
            end)
            notify("FE_BUNDLE", "Pack re-applied")
        end
        reflowFloating()
    end)
end

---------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------
print("[FE12] loading data...")
pcall(loadData)

local ok, err = pcall(createGui)
if not ok then
    print("[FE12] createGui ERROR:", err)
    notify("FE_BUNDLE", "Boot error")
elseif err == false then
    print("[FE12] createGui returned false")
else
    print("[FE12] SUCCESS")
    applyRuntimeSettings()
    reflowFloating()
    rebuildQuickPanel()

    if not App.Settings.StartClosed then
        task.delay(0.45, function()
            openMenu()
            navigate("Emotes")
        end)
    end

    -- autoload
    task.spawn(function()
        task.wait(1.2)
        local hasAny=false
        for _, st in ipairs(States) do
            if normalizeId(App.CurrentForm[st])~="" then hasAny=true break end
        end
        if App.Settings.AutoLoad and hasAny then
            pcall(function() applyCurrentForm(App.LastAppliedName~="" and App.LastAppliedName or "Saved") end)
        end
        -- Always prefetch recommendations
        pcall(function()
            searchCatalog("Emote", "dance", false)
            searchCatalog("Bundle", "animation", false)
            status("Ready", true)
            if App.Page == "Emotes" then navigate("Emotes") end
        end)
    end)
end

pcall(function()
    connAdd("Character", LocalPlayer.CharacterAdded:Connect(onCharacter))
    if LocalPlayer.Character then onCharacter(LocalPlayer.Character) end
end)

-- viewport resize
pcall(function()
    local cam = workspace.CurrentCamera
    if cam then
        connAdd("Global", cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            applyLayout(); reflowFloating()
        end))
    end
end)


-- B shortcut: open/toggle Quick Selector (or floating picker)
pcall(function()
    connAdd("Global", UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        -- ignore when typing in TextBox
        local focused = UserInputService:GetFocusedTextBox()
        if focused then return end
        local keyName = App.Settings.EmoteShortcutKey or "B"
        local keyEnum = Enum.KeyCode[keyName]
        if not keyEnum then keyEnum = Enum.KeyCode.B end
        if input.KeyCode == keyEnum then
            if App.Settings.PickerProvider == "Quick" then
                if UI and UI.QuickBar then
                    UI.QuickBar.Visible = not UI.QuickBar.Visible
                    if UI.QuickBar.Visible then rebuildQuickPanel() end
                end
            else
                -- open menu on Emotes if closed
                if not App.MenuOpen then openMenu() end
                navigate("Emotes")
            end
        end
        -- Escape stops emote
        if input.KeyCode == Enum.KeyCode.Escape then
            if App.EmoteState == "PLAYING" or App.EmoteState == "PAUSED" then
                stopEmote("escape")
            end
        end
    end))
end)

print("[FE12] end")
