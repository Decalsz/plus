--[[
    Irenk Bundle + Emote Hub v8.4 - SAWERIA ULTRA
    One-file LocalScript for Delta/mobile

    FIXES v8.4:
    - ICON TOGGLE FIXED: Hanya pakai satu event (Activated/Touch),
      tidak ada konflik MouseButton1Down + Click + Activated + InputBegan sekaligus.
    - DRAG FIXED: Drag icon dan drag main window dipisah bersih dengan
      threshold jarak supaya tap = toggle, geser = drag. Tidak konflik.
    - ANIMASI POP-IN / POP-OUT: Open/Close pakai scale + transparency tween
      Saweria-style (spring bounce in, shrink out).
    - INFO MODAL: Preview animasi 3D avatar bisa dilihat sebelum dipakai.
    - VISUAL UPGRADE: Tema Saweria lengkap, gradient header, glow, badge,
      animasi loading shimmer, tombol press effect, info modal premium.
    - STATUS BAR: Animasi masuk dari bawah.
    - Semua fungsi lama tetap berjalan normal.
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local HttpService    = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local SaveFile  = "Irenk_BundleEmoteHub_v84_Save.json"
local CAN_FILES = type(writefile)=="function" and type(readfile)=="function" and type(isfile)=="function"

local Alive               = true
local CurrentPage         = "Bundles"
local ChoosingState       = nil
local ApplyMethod         = "Animate"
local AutoLoad            = true
local ModalDimTransparency = 0.5

local EmoteSpeed     = 1
local EmoteLoop      = true
local MoveWhileEmote = true
local CurrentEmoteTrack = nil

local BundleResults   = {}
local EmoteResults    = {}
local FavoriteBundles = {}
local FavoriteEmotes  = {}
local SavedPacks      = {}
local AutoLoadName    = ""
local LastAppliedName = ""
local NextBundleCursor = nil
local NextEmoteCursor  = nil
local LastBundleKeyword = "animation"
local LastEmoteKeyword  = "dance"
local AnimationObjectCache = {}
local OriginalIds = {}

local States      = {"Idle","Walk","Run","Jump","Fall","Climb","Swim"}
local CurrentForm = {Idle="",Walk="",Run="",Jump="",Fall="",Climb="",Swim=""}
local SlotMeta    = {Idle=nil,Walk=nil,Run=nil,Jump=nil,Fall=nil,Climb=nil,Swim=nil}

local Connections     = {}
local PageConnections = {}
local LoadingActive   = false
local AutoLoadingMore = false

local ScreenGui, IconButton, Main, Body, HeaderTitle, StatusLabel
local ModalDim, ModalCard, LoadingDim, LoadingCard, LoadingBar
local SearchBox

-- SAWERIA ULTRA THEME
local Theme = {
    -- Base
    Page        = Color3.fromRGB(16, 18, 28),        -- deep navy bg
    Paper       = Color3.fromRGB(22, 26, 40),         -- panel bg
    Card        = Color3.fromRGB(30, 35, 56),         -- card
    Field       = Color3.fromRGB(20, 24, 38),         -- input field
    -- Saweria signature orange/yellow
    Orange      = Color3.fromRGB(255, 168, 0),
    OrangeDark  = Color3.fromRGB(200, 120, 0),
    OrangeGlow  = Color3.fromRGB(255, 200, 80),
    -- Accents
    Cyan        = Color3.fromRGB(0, 220, 200),
    CyanDark    = Color3.fromRGB(0, 160, 148),
    Green       = Color3.fromRGB(60, 220, 140),
    GreenDark   = Color3.fromRGB(30, 160, 100),
    Yellow      = Color3.fromRGB(255, 220, 60),
    Red         = Color3.fromRGB(255, 75, 100),
    RedDark     = Color3.fromRGB(200, 40, 70),
    Purple      = Color3.fromRGB(140, 80, 255),
    -- Text
    Text        = Color3.fromRGB(240, 242, 255),
    TextSub     = Color3.fromRGB(160, 170, 200),
    Muted       = Color3.fromRGB(100, 110, 145),
    LightMuted  = Color3.fromRGB(70, 80, 110),
    -- Misc
    Black       = Color3.fromRGB(8, 10, 18),
    White       = Color3.fromRGB(255, 255, 255),
    Border      = Color3.fromRGB(50, 60, 90),
    Shimmer     = Color3.fromRGB(255, 200, 80),
}

local AnimateNames = {
    Idle={"idle"}, Walk={"walk"}, Run={"run"}, Jump={"jump"},
    Fall={"fall"}, Climb={"climb"}, Swim={"swim","swimidle"}
}

---------------------------------------------------------------------
-- BASIC HELPERS
---------------------------------------------------------------------

local function add(list, conn)
    table.insert(list or Connections, conn)
    return conn
end

local function disconnectList(list)
    for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
    for i = #list, 1, -1 do table.remove(list, i) end
end

local function new(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do pcall(function() obj[k] = v end) end
    return obj
end

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thick, trans)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Border
    s.Thickness = thick or 1
    s.Transparency = trans or 0
    s.Parent = obj
    return s
end

-- Tween helper: style + dir customizable
local function tween(obj, props, time, style, dir)
    pcall(function()
        TweenService:Create(obj,
            TweenInfo.new(time or 0.18,
                style or Enum.EasingStyle.Quart,
                dir   or Enum.EasingDirection.Out),
            props):Play()
    end)
end

-- Spring-style bounce tween
local function tweenBounce(obj, props, time)
    pcall(function()
        TweenService:Create(obj,
            TweenInfo.new(time or 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            props):Play()
    end)
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
        else out[k] = v end
    end
    return out
end

local function getParentGui()
    local pg = nil
    pcall(function() if gethui then pg = gethui() end end)
    if not pg then pcall(function() pg = game:GetService("CoreGui") end) end
    if not pg then pg = LocalPlayer:WaitForChild("PlayerGui") end
    return pg
end

local function status(text, good)
    if not StatusLabel then return end
    StatusLabel.Text = tostring(text or "")
    if good == true then
        StatusLabel.TextColor3 = Theme.Green
    elseif good == false then
        StatusLabel.TextColor3 = Theme.Red
    else
        StatusLabel.TextColor3 = Theme.Muted
    end
    -- animate in from right
    pcall(function()
        StatusLabel.Position = UDim2.new(0, 32, 1, -38)
        tween(StatusLabel, {Position=UDim2.new(0, 16, 1, -38)}, 0.18)
    end)
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
        AutoLoad=AutoLoad, AutoLoadName=AutoLoadName, LastAppliedName=LastAppliedName,
        ApplyMethod=ApplyMethod, ModalDimTransparency=ModalDimTransparency,
        EmoteSpeed=EmoteSpeed, EmoteLoop=EmoteLoop, MoveWhileEmote=MoveWhileEmote,
        CurrentForm=CurrentForm, SlotMeta=SlotMeta,
        FavoriteBundles=FavoriteBundles, FavoriteEmotes=FavoriteEmotes, SavedPacks=SavedPacks
    }
    pcall(function() writefile(SaveFile, HttpService:JSONEncode(data)) end)
end

local function loadData()
    if not CAN_FILES then return false end
    local exists = false
    pcall(function() exists = isfile(SaveFile) end)
    if not exists then return false end
    local raw; pcall(function() raw = readfile(SaveFile) end)
    if not raw then return false end
    local data; pcall(function() data = HttpService:JSONDecode(raw) end)
    if type(data) ~= "table" then return false end
    if type(data.AutoLoad)=="boolean" then AutoLoad=data.AutoLoad end
    if type(data.AutoLoadName)=="string" then AutoLoadName=data.AutoLoadName end
    if type(data.LastAppliedName)=="string" then LastAppliedName=data.LastAppliedName end
    if type(data.ApplyMethod)=="string" then ApplyMethod=data.ApplyMethod end
    if type(data.ModalDimTransparency)=="number" then ModalDimTransparency=math.clamp(data.ModalDimTransparency,0.05,0.9) end
    if type(data.EmoteSpeed)=="number" then EmoteSpeed=data.EmoteSpeed end
    if type(data.EmoteLoop)=="boolean" then EmoteLoop=data.EmoteLoop end
    if type(data.MoveWhileEmote)=="boolean" then MoveWhileEmote=data.MoveWhileEmote end
    if type(data.CurrentForm)=="table" then CurrentForm=data.CurrentForm end
    if type(data.SlotMeta)=="table" then SlotMeta=data.SlotMeta end
    if type(data.FavoriteBundles)=="table" then FavoriteBundles=data.FavoriteBundles end
    if type(data.FavoriteEmotes)=="table" then FavoriteEmotes=data.FavoriteEmotes end
    if type(data.SavedPacks)=="table" then SavedPacks=data.SavedPacks end
    return true
end

---------------------------------------------------------------------
-- HTTP / CATALOG
---------------------------------------------------------------------

local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res)=="string" then return res end
    return nil
end

local function decodeJson(raw)
    if not raw then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok then return data end
    return nil
end

local function searchCatalog(kind, keyword, append)
    keyword = tostring(keyword or "")
    if keyword=="" then keyword = kind=="Emote" and "dance" or "animation" end
    local encoded = HttpService:UrlEncode(keyword)
    local cursor = kind=="Emote" and NextEmoteCursor or NextBundleCursor
    if not append then
        if kind=="Emote" then EmoteResults={}; NextEmoteCursor=nil
        else BundleResults={}; NextBundleCursor=nil end
        cursor=nil
    end
    local cursorParam = cursor and ("&Cursor="..HttpService:UrlEncode(cursor)) or ""
    local subcategory = kind=="Emote" and "39" or "38"
    local url = "https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory="..subcategory.."&Keyword="..encoded.."&Limit=30&SortType=0"..cursorParam
    local data = decodeJson(httpGet(url))
    if not data or type(data.data)~="table" then
        if kind=="Bundle" then
            local url2="https://catalog.roblox.com/v1/search/items/details?Category=12&Subcategory=27&Keyword="..encoded.."&Limit=30&SortType=0"..cursorParam
            data=decodeJson(httpGet(url2))
        end
    end
    if not data or type(data.data)~="table" then return false, 0 end
    if kind=="Emote" then
        for _, item in ipairs(data.data) do table.insert(EmoteResults, item) end
        NextEmoteCursor=data.nextPageCursor; LastEmoteKeyword=keyword
        return true, #EmoteResults
    else
        for _, item in ipairs(data.data) do table.insert(BundleResults, item) end
        NextBundleCursor=data.nextPageCursor; LastBundleKeyword=keyword
        return true, #BundleResults
    end
end

local function fetchBundleDetails(bundleId)
    bundleId=normalizeId(bundleId)
    if bundleId=="" then return nil end
    return decodeJson(httpGet("https://catalog.roblox.com/v1/bundles/"..bundleId.."/details"))
end

---------------------------------------------------------------------
-- BUNDLE RESOLVER
---------------------------------------------------------------------

local function categorizeAnimation(pathText)
    pathText=string.lower(tostring(pathText or ""))
    if string.find(pathText,"idle",1,true) then return "Idle" end
    if string.find(pathText,"walk",1,true) then return "Walk" end
    if string.find(pathText,"run",1,true)  then return "Run" end
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
            local id=normalizeId(child.AnimationId)
            local state=categorizeAnimation(p)
            if id~="" and state and not output[state] then output[state]=id end
        end
        if #child:GetChildren()>0 then scanAnimationTree(child,p,output) end
    end
end

local function resolveAnimationsFromAsset(assetId)
    assetId=normalizeId(assetId)
    if assetId=="" then return {} end
    if AnimationObjectCache[assetId] then return AnimationObjectCache[assetId] end
    local found={}
    local ok,objects=pcall(function() return game:GetObjects("rbxassetid://"..assetId) end)
    if ok and objects then
        for _, obj in ipairs(objects) do
            scanAnimationTree(obj,obj.Name,found)
            pcall(function() obj:Destroy() end)
        end
    end
    AnimationObjectCache[assetId]=found
    return found
end

local function extractAnimationsFromBundle(details)
    local form={}
    if not details then return form end
    local items=details.items or details.Items or {}
    for _, item in ipairs(items) do
        local itemId=tostring(item.id or item.Id or "")
        local resolved=resolveAnimationsFromAsset(itemId)
        for state,id in pairs(resolved) do if not form[state] then form[state]=id end end
    end
    local assetTypeToState={[48]="Climb",[50]="Fall",[51]="Idle",[52]="Jump",[53]="Run",[54]="Swim",[55]="Walk"}
    for _, item in ipairs(items) do
        local itemId=tostring(item.id or item.Id or "")
        local assetType=tonumber(item.assetType or item.AssetType or item.assetTypeId or item.AssetTypeId)
        local state=assetTypeToState[assetType] or categorizeAnimation(item.name or item.Name)
        if state and not form[state] then form[state]=itemId end
    end
    return form
end

---------------------------------------------------------------------
-- APPLY ANIMATION
---------------------------------------------------------------------

local function getAnimationsForState(state)
    local _,_,animate=getCharHum()
    if not animate then return {} end
    local result={}
    for _, child in ipairs(animate:GetChildren()) do
        local lowerName=string.lower(child.Name)
        for _, expected in ipairs(AnimateNames[state] or {}) do
            if lowerName==expected then
                if child:IsA("Animation") then table.insert(result,child) end
                for _, d in ipairs(child:GetDescendants()) do if d:IsA("Animation") then table.insert(result,d) end end
            end
        end
    end
    return result
end

local function captureOriginals()
    OriginalIds={}
    for _, state in ipairs(States) do
        OriginalIds[state]={}
        for _, anim in ipairs(getAnimationsForState(state)) do table.insert(OriginalIds[state],anim.AnimationId) end
    end
end

local function restartAnimate()
    local _,_,animate=getCharHum()
    if animate then pcall(function() animate.Disabled=true; task.wait(0.1); animate.Disabled=false end) end
end

local function setStateAnimation(state,id)
    id=normalizeId(id)
    if id=="" then return false end
    local anims=getAnimationsForState(state)
    if #anims<=0 then return false end
    for _, anim in ipairs(anims) do anim.AnimationId=toAnimUrl(id) end
    return true
end

local function applyDescriptionAnimations()
    local _,hum=getCharHum()
    if not hum then return 0 end
    local props={Idle="IdleAnimation",Walk="WalkAnimation",Run="RunAnimation",Jump="JumpAnimation",Fall="FallAnimation",Climb="ClimbAnimation",Swim="SwimAnimation"}
    local changed=0
    pcall(function()
        local desc=hum:GetAppliedDescription()
        for state,prop in pairs(props) do
            local id=normalizeId(CurrentForm[state])
            if id~="" then desc[prop]=tonumber(id) or 0; changed=changed+1 end
        end
        hum:ApplyDescription(desc)
    end)
    return changed
end

local function applyCurrentForm(name)
    local changed=0; local descChanged=0
    if ApplyMethod=="Animate" or ApplyMethod=="Both" then
        for _, state in ipairs(States) do
            if normalizeId(CurrentForm[state])~="" and setStateAnimation(state,CurrentForm[state]) then changed=changed+1 end
        end
    end
    if ApplyMethod=="Description" or ApplyMethod=="Both" then descChanged=applyDescriptionAnimations() end
    restartAnimate()
    if name then LastAppliedName=name end
    saveData()
    status("Applied "..(name or LastAppliedName or "pack").." | "..changed.." states", changed>0 or descChanged>0)
end

local function applyBundleFull(bundleId, bundleName)
    showLoading("Resolving bundle...")
    task.spawn(function()
        local details=fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Bundle details failed",false); return end
        local form=extractAnimationsFromBundle(details)
        local count=0
        for _, state in ipairs(States) do
            CurrentForm[state]=form[state] or ""
            SlotMeta[state]=CurrentForm[state]~="" and {Bundle=bundleName or details.name or "Bundle",BundleId=normalizeId(bundleId),Id=CurrentForm[state]} or nil
            if CurrentForm[state]~="" then count=count+1 end
        end
        hideLoading()
        if count<=0 then status("No animations found",false); return end
        LastAppliedName=bundleName or details.name or "Bundle"
        applyCurrentForm(LastAppliedName)
    end)
end

local function setCustomSlotFromBundle(state,bundleId,bundleName)
    showLoading("Setting "..state.."...")
    task.spawn(function()
        local details=fetchBundleDetails(bundleId)
        if not details then hideLoading(); status("Bundle details failed",false); return end
        local form=extractAnimationsFromBundle(details)
        hideLoading()
        local id=form[state]
        if normalizeId(id)==="" then status("No "..state.." anim in bundle",false); return end
        CurrentForm[state]=id
        SlotMeta[state]={Bundle=bundleName or details.name or "Bundle",BundleId=normalizeId(bundleId),Id=id}
        ChoosingState=nil; saveData()
        status("Set "..state.." from "..(bundleName or details.name),true)
        renderCustom()
    end)
end

local function restoreOriginal()
    for _, state in ipairs(States) do
        local originals=OriginalIds[state]; local anims=getAnimationsForState(state)
        if originals and #originals>0 then
            for i,anim in ipairs(anims) do anim.AnimationId=originals[i] or originals[1] end
        end
    end
    restartAnimate(); status("Original animations restored",true)
end

---------------------------------------------------------------------
-- EMOTE
---------------------------------------------------------------------

local function stopEmote()
    if CurrentEmoteTrack then
        pcall(function() CurrentEmoteTrack:Stop(0.15); CurrentEmoteTrack:Destroy() end)
        CurrentEmoteTrack=nil
    end
end

local function playEmote(assetId, name)
    local _,hum=getCharHum()
    if not hum then status("Humanoid not found",false); return end
    stopEmote()
    local anim=Instance.new("Animation")
    anim.AnimationId=toAnimUrl(assetId)
    local ok,track=pcall(function() return hum:LoadAnimation(anim) end)
    if not ok or not track then status("Emote failed. May be private.",false); return end
    CurrentEmoteTrack=track
    pcall(function()
        track.Priority=MoveWhileEmote and Enum.AnimationPriority.Action or Enum.AnimationPriority.Action4
        track.Looped=EmoteLoop
        track:Play(0.15,1,EmoteSpeed)
    end)
    status("Playing: "..(name or assetId),true)
end

---------------------------------------------------------------------
-- LOADING OVERLAY  (shimmer bar, Saweria style)
---------------------------------------------------------------------

function showLoading(text)
    hideLoading()
    LoadingActive=true
    -- dim
    LoadingDim=new("Frame",{Parent=ScreenGui,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,0,1,0),BackgroundColor3=Theme.Black,BackgroundTransparency=0.3,BorderSizePixel=0,ZIndex=250})
    -- card: pop in
    LoadingCard=new("Frame",{Parent=ScreenGui,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,10,0,10),BackgroundColor3=Theme.Paper,BorderSizePixel=0,ZIndex=251,BackgroundTransparency=1})
    corner(LoadingCard,18); stroke(LoadingCard,Theme.Orange,2,0)
    tweenBounce(LoadingCard,{Size=UDim2.new(0,340,0,120),BackgroundTransparency=0},0.38)
    -- icon area (saweria logo placeholder circle)
    task.delay(0.12, function()
        if not LoadingCard then return end
        local iconCircle=new("Frame",{Parent=LoadingCard,AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,0,0,-22),Size=UDim2.new(0,44,0,44),BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=254})
        corner(iconCircle,22); stroke(iconCircle,Theme.OrangeDark,2,0)
        new("TextLabel",{Parent=iconCircle,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="⚡",TextColor3=Theme.Black,TextSize=22,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=255})

        makeLabel(LoadingCard,text or "Loading...",UDim2.new(0,20,0,26),UDim2.new(1,-40,0,28),15,Theme.Text)
        -- progress track
        local bg=new("Frame",{Parent=LoadingCard,Position=UDim2.new(0,20,0,68),Size=UDim2.new(1,-40,0,14),BackgroundColor3=Theme.Card,BorderSizePixel=0,ZIndex=252})
        corner(bg,7); stroke(bg,Theme.Border,1,0)
        LoadingBar=new("Frame",{Parent=bg,Position=UDim2.new(-0.4,0,0,0),Size=UDim2.new(0.4,0,1,0),BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=253})
        corner(LoadingBar,7)
        -- shimmer overlay on bar
        local shimmer=new("Frame",{Parent=LoadingBar,Position=UDim2.new(-1,0,0,0),Size=UDim2.new(0.5,0,1,0),BackgroundColor3=Theme.OrangeGlow,BackgroundTransparency=0.55,BorderSizePixel=0,ZIndex=254})
        corner(shimmer,7)
        task.spawn(function()
            while LoadingActive and LoadingBar and LoadingBar.Parent do
                LoadingBar.Position=UDim2.new(-0.4,0,0,0)
                tween(LoadingBar,{Position=UDim2.new(1,0,0,0)},0.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
                task.wait(0.9)
            end
        end)
    end)
end

function hideLoading()
    LoadingActive=false
    if LoadingCard then
        local c=LoadingCard; LoadingCard=nil
        tween(c,{Size=UDim2.new(0,10,0,10),BackgroundTransparency=1},0.18)
        task.delay(0.2,function() pcall(function() c:Destroy() end) end)
    end
    if LoadingDim then
        local d=LoadingDim; LoadingDim=nil
        tween(d,{BackgroundTransparency=1},0.18)
        task.delay(0.2,function() pcall(function() d:Destroy() end) end)
    end
    LoadingBar=nil
end

---------------------------------------------------------------------
-- GUI HELPERS  (upgraded)
---------------------------------------------------------------------

function makeLabel(parent, text, pos, size, textSize, color)
    return new("TextLabel",{
        Parent=parent, Position=pos, Size=size, BackgroundTransparency=1,
        Text=text, TextColor3=color or Theme.Text, TextStrokeTransparency=1,
        TextSize=textSize or 13, Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        TextWrapped=true, ZIndex=20
    })
end

local function makeSubLabel(parent, text, pos, size, textSize, color)
    return new("TextLabel",{
        Parent=parent, Position=pos, Size=size, BackgroundTransparency=1,
        Text=text, TextColor3=color or Theme.TextSub, TextStrokeTransparency=1,
        TextSize=textSize or 12, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        TextWrapped=true, ZIndex=20
    })
end

local function makeButton(parent, text, pos, size, callback, color, textColor)
    -- subtle drop shadow
    local shadow=new("Frame",{
        Parent=parent,
        Position=UDim2.new(pos.X.Scale,pos.X.Offset+2,pos.Y.Scale,pos.Y.Offset+4),
        Size=size, BackgroundColor3=Theme.Black, BackgroundTransparency=0.6, BorderSizePixel=0, ZIndex=18
    }); corner(shadow,9)

    local b=new("TextButton",{
        Parent=parent, Position=pos, Size=size,
        BackgroundColor3=color or Theme.Card, BorderSizePixel=0,
        Text=text, TextColor3=textColor or Theme.Text, TextStrokeTransparency=1,
        TextSize=12, Font=Enum.Font.GothamBold, AutoButtonColor=false, ZIndex=21
    }); corner(b,9); stroke(b,Theme.Border,1,0)

    -- press animation
    add(PageConnections, b.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            tween(b,{Position=UDim2.new(pos.X.Scale,pos.X.Offset+1,pos.Y.Scale,pos.Y.Offset+2),BackgroundTransparency=0.12},0.06)
        end
    end))
    add(PageConnections, b.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            tween(b,{Position=pos,BackgroundTransparency=0},0.10)
            if callback then task.spawn(callback) end
        end
    end))
    -- mouse fallback
    add(PageConnections, b.MouseButton1Click:Connect(function()
        if callback then task.spawn(callback) end
    end))
    return b
end

local function makeBox(parent, placeholder, pos, size)
    local box=new("TextBox",{
        Parent=parent, Position=pos, Size=size,
        BackgroundColor3=Theme.Field, BorderSizePixel=0,
        Text="", PlaceholderText=placeholder, PlaceholderColor3=Theme.Muted,
        TextColor3=Theme.Text, TextStrokeTransparency=1,
        TextSize=13, Font=Enum.Font.Gotham, ClearTextOnFocus=false,
        TextXAlignment=Enum.TextXAlignment.Left, ZIndex=21
    }); corner(box,9); stroke(box,Theme.Orange,1,0.55)
    local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=box
    -- focus glow
    add(PageConnections, box.Focused:Connect(function() tween(box,{},0.12); pcall(function()
        for _,s in ipairs(box:GetChildren()) do if s:IsA("UIStroke") then tween(s,{Transparency=0},0.12) end end
    end) end))
    add(PageConnections, box.FocusLost:Connect(function() pcall(function()
        for _,s in ipairs(box:GetChildren()) do if s:IsA("UIStroke") then tween(s,{Transparency=0.55},0.12) end end
    end) end))
    return box
end

local function makePanel(parent, pos, size, color)
    local panel=new("Frame",{Parent=parent,Position=pos,Size=size,BackgroundColor3=color or Theme.Card,BorderSizePixel=0,ZIndex=19})
    corner(panel,12); stroke(panel,Theme.Border,1,0)
    return panel
end

-- Badge label (pill shaped)
local function makeBadge(parent, text, pos, color, textColor)
    local b=new("TextLabel",{
        Parent=parent, Position=pos, Size=UDim2.new(0,0,0,20),
        AutomaticSize=Enum.AutomaticSize.X, BackgroundColor3=color or Theme.Orange,
        BorderSizePixel=0, Text=" "..text.." ", TextColor3=textColor or Theme.Black,
        TextSize=10, Font=Enum.Font.GothamBold, ZIndex=25
    }); corner(b,10)
    return b
end

---------------------------------------------------------------------
-- AVATAR PREVIEW (viewport with live animation)
---------------------------------------------------------------------

local function createAvatarPreview(parent, animId, px, py, pw, ph)
    local viewport=new("ViewportFrame",{
        Parent=parent,
        Position=UDim2.new(0,px or 18,0,py or 18),
        Size=UDim2.new(0,pw or 148,0,ph or 128),
        BackgroundColor3=Theme.Field, BorderSizePixel=0,
        Ambient=Color3.fromRGB(160,160,200),
        LightColor=Color3.fromRGB(255,240,200),
        ZIndex=202
    }); corner(viewport,12); stroke(viewport,Theme.Orange,2,0)

    local world=Instance.new("WorldModel"); world.Parent=viewport
    local char=LocalPlayer.Character
    if not char then return viewport end

    local oldArch=char.Archivable; pcall(function() char.Archivable=true end)
    local clone; pcall(function() clone=char:Clone() end)
    pcall(function() char.Archivable=oldArch end)
    if not clone then return viewport end

    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
    end
    clone.Parent=world

    local root=clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if root then
        clone.PrimaryPart=root
        pcall(function()
            root.Anchored=true
            clone:SetPrimaryPartCFrame(CFrame.new(0,0,0)*CFrame.Angles(0,math.rad(180),0))
        end)
    end

    local cam=Instance.new("Camera"); cam.Parent=viewport; viewport.CurrentCamera=cam
    cam.CFrame=CFrame.new(Vector3.new(0,2.4,5.5),Vector3.new(0,1.8,0))

    local hum=clone:FindFirstChildOfClass("Humanoid")
    if hum and normalizeId(animId)~="" then
        local anim=Instance.new("Animation"); anim.AnimationId=toAnimUrl(animId)
        local ok,track=pcall(function() return hum:LoadAnimation(anim) end)
        if ok and track then
            pcall(function() track.Looped=true; track:Play(0.1,1,EmoteSpeed) end)
        end
    end
    return viewport
end

---------------------------------------------------------------------
-- INFO MODAL  (pop-in / pop-out, Saweria premium style)
---------------------------------------------------------------------

function closeInfoModal()
    if not ModalCard then return end
    local card=ModalCard; local dim=ModalDim
    ModalCard=nil; ModalDim=nil
    -- POP OUT: shrink + fade
    tween(card,{Size=UDim2.new(0,40,0,40),BackgroundTransparency=1},0.22,Enum.EasingStyle.Back,Enum.EasingDirection.In)
    if dim then tween(dim,{BackgroundTransparency=1},0.22) end
    task.delay(0.25,function()
        pcall(function() card:Destroy() end)
        pcall(function() if dim then dim:Destroy() end end)
    end)
end

local function showInfoModal(titleText, bodyText, imageId, actions, previewAnimId)
    closeInfoModal()
    -- dim layer
    ModalDim=new("Frame",{Parent=ScreenGui,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,0,1,0),BackgroundColor3=Theme.Black,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=200})
    tween(ModalDim,{BackgroundTransparency=ModalDimTransparency},0.22)

    -- card: starts tiny, pops in
    local cardH = previewAnimId and 390 or 340
    ModalCard=new("Frame",{
        Parent=ScreenGui, AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.new(0.5,0,0.5,0),
        Size=UDim2.new(0,40,0,40),
        BackgroundColor3=Theme.Paper, BorderSizePixel=0,
        ZIndex=201, BackgroundTransparency=1
    }); corner(ModalCard,20); stroke(ModalCard,Theme.Orange,2,0)

    -- POP IN: spring bounce
    tweenBounce(ModalCard,{Size=UDim2.new(0,460,0,cardH),BackgroundTransparency=0},0.48)

    task.delay(0.10, function()
        if not ModalCard then return end

        -- Orange header strip
        local headerStrip=new("Frame",{Parent=ModalCard,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,0,0,52),BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=202})
        corner(headerStrip,20)
        new("Frame",{Parent=headerStrip,Position=UDim2.new(0,0,1,-20),Size=UDim2.new(1,0,0,20),BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=202})

        -- Title in header
        new("TextLabel",{
            Parent=headerStrip,Position=UDim2.new(0,18,0,0),Size=UDim2.new(1,-60,1,0),
            BackgroundTransparency=1,Text=titleText or "Info",
            TextColor3=Theme.Black,TextSize=16,Font=Enum.Font.GothamBold,
            TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
            TextWrapped=true,ZIndex=205
        })

        -- Close X button on header
        local closeBtn=new("TextButton",{
            Parent=ModalCard,Position=UDim2.new(1,-44,0,10),Size=UDim2.new(0,32,0,32),
            BackgroundColor3=Theme.RedDark,BorderSizePixel=0,Text="✕",
            TextColor3=Theme.White,TextSize=14,Font=Enum.Font.GothamBold,
            AutoButtonColor=false,ZIndex=220
        }); corner(closeBtn,16)
        closeBtn.MouseButton1Click:Connect(closeInfoModal)
        closeBtn.InputEnded:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Touch then closeInfoModal() end
        end)

        -- PREVIEW area
        local contentY = 62
        if previewAnimId then
            -- 3D animated preview (large)
            createAvatarPreview(ModalCard,previewAnimId,16,contentY,200,178)
            -- Info text alongside preview
            new("TextLabel",{
                Parent=ModalCard,Position=UDim2.new(0,228,0,contentY),
                Size=UDim2.new(1,-244,0,178),
                BackgroundTransparency=1,Text=bodyText or "No info.",
                TextColor3=Theme.TextSub,TextSize=12,Font=Enum.Font.Gotham,
                TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
                TextWrapped=true,ZIndex=210
            })
            contentY = contentY + 190
            -- animated label below viewport
            makeBadge(ModalCard,"▶ LIVE PREVIEW",UDim2.new(0,18,0,contentY-18),Theme.Green,Theme.Black)
        else
            -- Image thumbnail
            local img=new("ImageLabel",{
                Parent=ModalCard,Position=UDim2.new(0,16,0,contentY),
                Size=UDim2.new(0,152,0,128),BackgroundColor3=Theme.Card,
                BorderSizePixel=0,Image=imageId or "",ScaleType=Enum.ScaleType.Fit,ZIndex=210
            }); corner(img,12); stroke(img,Theme.Border,1,0)
            -- info text
            new("TextLabel",{
                Parent=ModalCard,Position=UDim2.new(0,182,0,contentY),
                Size=UDim2.new(1,-198,0,128),
                BackgroundTransparency=1,Text=bodyText or "No info.",
                TextColor3=Theme.TextSub,TextSize=12,Font=Enum.Font.Gotham,
                TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
                TextWrapped=true,ZIndex=210
            })
            contentY = contentY + 142
        end

        -- Divider
        new("Frame",{Parent=ModalCard,Position=UDim2.new(0,16,0,contentY+4),Size=UDim2.new(1,-32,0,1),BackgroundColor3=Theme.Border,BorderSizePixel=0,ZIndex=210})
        contentY = contentY + 14

        -- Action buttons
        local btnX = 16
        local closeColor = Theme.Red
        local cbtn=new("TextButton",{
            Parent=ModalCard,Position=UDim2.new(0,btnX,0,contentY),Size=UDim2.new(0,90,0,34),
            BackgroundColor3=closeColor,BorderSizePixel=0,Text="✕ CLOSE",
            TextColor3=Theme.White,TextSize=12,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=215
        }); corner(cbtn,10)
        cbtn.MouseButton1Click:Connect(closeInfoModal)
        cbtn.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.Touch then closeInfoModal() end end)
        btnX = btnX + 100

        for _, act in ipairs(actions or {}) do
            local ab=new("TextButton",{
                Parent=ModalCard,Position=UDim2.new(0,btnX,0,contentY),Size=UDim2.new(0,98,0,34),
                BackgroundColor3=act.Color or Theme.Cyan,BorderSizePixel=0,
                Text=act.Text or "OK",TextColor3=Theme.Black,TextSize=12,
                Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=215
            }); corner(ab,10)
            ab.MouseButton1Click:Connect(function()
                if act.Callback then task.spawn(act.Callback) end
                if act.Close~=false then closeInfoModal() end
            end)
            ab.InputEnded:Connect(function(inp)
                if inp.UserInputType==Enum.UserInputType.Touch then
                    if act.Callback then task.spawn(act.Callback) end
                    if act.Close~=false then closeInfoModal() end
                end
            end)
            btnX = btnX + 106
        end
    end)
end

---------------------------------------------------------------------
-- PAGES
---------------------------------------------------------------------

local renderHome, renderCustom, renderFavorites, renderSave, renderSettings

local function setPage(page)
    CurrentPage=page
    disconnectList(PageConnections)
    clear(Body)
    if HeaderTitle then
        HeaderTitle.Text = page=="Bundles" and "Bundle Hub" or
                           page=="Emotes"  and "Emote Hub" or page
    end
end

-- Tabs: pill-style, active = orange glow
local function tabs()
    local tabDefs={
        {"BUNDLES","Bundle"},{"EMOTES","Emote"},{"CUSTOM","Custom"},
        {"FAVS","Favorites"},{"SAVE","Save"},{"SETTINGS","Settings"}
    }
    local xOff=10
    for i,def in ipairs(tabDefs) do
        local label=def[1]; local pageName=def[2]
        local active=(CurrentPage==pageName or (pageName=="Bundle" and CurrentPage=="Bundles") or (pageName=="Emote" and CurrentPage=="Emotes"))
        local btn=new("TextButton",{
            Parent=Body,Position=UDim2.new(0,xOff,0,6),
            Size=UDim2.new(0,0,0,30),AutomaticSize=Enum.AutomaticSize.X,
            BackgroundColor3=active and Theme.Orange or Theme.Card,BorderSizePixel=0,
            Text="  "..label.."  ",TextColor3=active and Theme.Black or Theme.TextSub,
            TextSize=11,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=21
        }); corner(btn,15)
        if active then stroke(btn,Theme.OrangeDark,1,0) else stroke(btn,Theme.Border,1,0) end
        add(PageConnections,btn.MouseButton1Click:Connect(function()
            if pageName=="Bundle" then renderHome("Bundle")
            elseif pageName=="Emote" then renderHome("Emote")
            elseif pageName=="Custom" then renderCustom()
            elseif pageName=="Favorites" then renderFavorites()
            elseif pageName=="Save" then renderSave()
            elseif pageName=="Settings" then renderSettings() end
        end))
        add(PageConnections,btn.InputEnded:Connect(function(inp)
            if inp.UserInputType~=Enum.UserInputType.Touch then return end
            if pageName=="Bundle" then renderHome("Bundle")
            elseif pageName=="Emote" then renderHome("Emote")
            elseif pageName=="Custom" then renderCustom()
            elseif pageName=="Favorites" then renderFavorites()
            elseif pageName=="Save" then renderSave()
            elseif pageName=="Settings" then renderSettings() end
        end))
        xOff = xOff + 68 + (i<=2 and 4 or 0)
    end
end

local function isFavorite(list,id)
    id=tostring(id)
    for _,item in ipairs(list) do if tostring(item.id)==id then return true end end
    return false
end

local function toggleFavorite(kind,item)
    local list=kind=="Emote" and FavoriteEmotes or FavoriteBundles
    local id=tostring(item.id or item.Id or "")
    for i,fav in ipairs(list) do
        if tostring(fav.id)==id then table.remove(list,i); saveData(); status("Removed ★",true); return end
    end
    table.insert(list,{id=id,name=tostring(item.name or item.Name or (kind.." "..id)),kind=kind})
    saveData(); status("Added ★",true)
end

-- Item card: upgraded dark card with image, glow on hover
local function renderItemCard(parent, item, index, kind)
    local id=tostring(item.id or item.Id or "")
    local name=tostring(item.name or item.Name or (kind.." "..id))
    local col=(index-1)%2; local row=math.floor((index-1)/2)
    local x=12+col*252; local y=12+row*146
    local card=new("Frame",{
        Parent=parent,Position=UDim2.new(0,x,0,y),Size=UDim2.new(0,242,0,134),
        BackgroundColor3=Theme.Card,BorderSizePixel=0,ZIndex=19
    }); corner(card,14); stroke(card,Theme.Border,1,0)

    local imgId=kind=="Emote" and assetThumbnail(id) or bundleThumbnail(id)
    local img=new("ImageLabel",{
        Parent=card,Position=UDim2.new(0,10,0,10),Size=UDim2.new(0,78,0,72),
        BackgroundColor3=Theme.Field,BorderSizePixel=0,Image=imgId,ScaleType=Enum.ScaleType.Fit,ZIndex=20
    }); corner(img,10); stroke(img,Theme.Border,1,0)

    -- kind badge
    makeBadge(card,kind,UDim2.new(0,10,0,84),kind=="Emote" and Theme.Purple or Theme.Cyan,Theme.Black)

    -- name
    new("TextLabel",{
        Parent=card,Position=UDim2.new(0,96,0,10),Size=UDim2.new(1,-102,0,44),
        BackgroundTransparency=1,Text=name,TextColor3=Theme.Text,
        TextSize=12,Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        TextWrapped=true,ZIndex=20
    })
    new("TextLabel",{
        Parent=card,Position=UDim2.new(0,96,0,56),Size=UDim2.new(1,-102,0,18),
        BackgroundTransparency=1,Text="ID: "..id,TextColor3=Theme.Muted,
        TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=20
    })

    -- PLAY/APPLY button
    local applyLabel = kind=="Emote" and "▶ PLAY" or (ChoosingState and "✔ SET "..string.upper(ChoosingState) or "✔ APPLY")
    local applyColor = kind=="Emote" and Theme.Green or Theme.Orange
    makeButton(card, applyLabel, UDim2.new(0,10,1,-36), UDim2.new(0,88,0,26),
        function()
            if kind=="Emote" then playEmote(id,name)
            else if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name)
                 else applyBundleFull(id,name) end end
        end, applyColor, Theme.Black)

    -- INFO button
    makeButton(card,"ℹ INFO",UDim2.new(0,104,1,-36),UDim2.new(0,60,0,26),function()
        local body=kind..": "..name.."\nID: "..id.."\n\n"..
            (kind=="Emote" and "Lihat preview animasi 3D sebelum dipakai.\nSpeed & loop bisa diubah di Settings."
             or (ChoosingState and ("Akan di-set ke slot: "..ChoosingState) or "Apply full bundle atau Custom Mix."))
        local actions={}
        if kind=="Emote" then
            table.insert(actions,{Text="▶ PREVIEW",Color=Theme.Green,Callback=function() playEmote(id,name) end,Close=false})
        else
            table.insert(actions,{Text="✔ ".. (ChoosingState and "SET" or "APPLY"),Color=Theme.Orange,
                Callback=function() if ChoosingState then setCustomSlotFromBundle(ChoosingState,id,name) else applyBundleFull(id,name) end end})
        end
        table.insert(actions,{Text="★ FAV",Color=Theme.Yellow,Callback=function() toggleFavorite(kind,item) end,Close=false})
        showInfoModal(name,body,imgId,actions,kind=="Emote" and id or nil)
    end,Theme.Cyan,Theme.Black)

    -- FAV button
    local isFav=isFavorite(kind=="Emote" and FavoriteEmotes or FavoriteBundles,id)
    makeButton(card,isFav and "★" or "☆",UDim2.new(0,170,1,-36),UDim2.new(0,32,0,26),function()
        toggleFavorite(kind,item)
        if CurrentPage=="Bundles" then renderHome("Bundle") elseif CurrentPage=="Emotes" then renderHome("Emote") end
    end,isFav and Theme.Yellow or Theme.Card)
end

renderHome = function(kind)
    kind=kind or (CurrentPage=="Emotes" and "Emote" or "Bundle")
    setPage(kind=="Emote" and "Emotes" or "Bundles"); tabs()
    local placeholder=kind=="Emote" and "Cari emote: dance, pose, laugh..." or "Cari bundle: ninja, robot, zombie..."
    SearchBox=makeBox(Body,placeholder,UDim2.new(0,10,0,50),UDim2.new(1,-118,0,36))
    SearchBox.Text=kind=="Emote" and (LastEmoteKeyword~="dance" and LastEmoteKeyword or "") or (LastBundleKeyword~="animation" and LastBundleKeyword or "")

    -- Search button
    makeButton(Body,"🔍 CARI",UDim2.new(1,-104,0,50),UDim2.new(0,94,0,36),function()
        showLoading("Mencari "..string.lower(kind).."...")
        task.spawn(function()
            local ok,count=searchCatalog(kind,SearchBox.Text,false)
            hideLoading()
            if ok then renderHome(kind); status("Ditemukan "..count.." "..string.lower(kind),true)
            else status("Gagal. Cek HTTP.",false) end
        end)
    end,Theme.Orange,Theme.Black)

    -- hint
    local hintText=kind=="Emote" and "Tekan INFO untuk preview 3D animasi." or
        (ChoosingState and ("🎯 Pilih bundle untuk slot: "..ChoosingState) or "Apply bundle penuh atau Custom Mix.")
    makeSubLabel(Body,hintText,UDim2.new(0,10,0,94),UDim2.new(1,-20,0,20),11,ChoosingState and Theme.Orange or Theme.Muted)

    local scroll=new("ScrollingFrame",{
        Parent=Body,Position=UDim2.new(0,0,0,118),Size=UDim2.new(1,0,1,-156),
        BackgroundColor3=Theme.Page,BorderSizePixel=0,
        ScrollBarThickness=4,ScrollBarImageColor3=Theme.Orange,
        CanvasSize=UDim2.new(0,0,0,380),ZIndex=19
    }); corner(scroll,12); stroke(scroll,Theme.Border,1,0)

    local list=kind=="Emote" and EmoteResults or BundleResults
    if #list==0 then
        makeSubLabel(scroll,"Memuat "..string.lower(kind).."...",UDim2.new(0,16,0,20),UDim2.new(0,300,0,30),14,Theme.Muted)
    else
        for i,item in ipairs(list) do renderItemCard(scroll,item,i,kind) end
        local rows=math.ceil(#list/2)
        scroll.CanvasSize=UDim2.new(0,0,0,math.max(360,rows*146+62))
        local hasNext=kind=="Emote" and NextEmoteCursor or NextBundleCursor
        if hasNext then
            makeSubLabel(scroll,"Scroll ke bawah untuk load lebih...",UDim2.new(0,16,0,rows*146+18),UDim2.new(0,300,0,30),12,Theme.Muted)
            add(PageConnections,scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if AutoLoadingMore then return end
                local bottom=scroll.CanvasPosition.Y+scroll.AbsoluteWindowSize.Y
                local limit=scroll.CanvasSize.Y.Offset-45
                if bottom>=limit then
                    AutoLoadingMore=true
                    showLoading("Load lebih "..string.lower(kind).."...")
                    task.spawn(function()
                        local ok=searchCatalog(kind,kind=="Emote" and LastEmoteKeyword or LastBundleKeyword,true)
                        hideLoading(); AutoLoadingMore=false
                        if ok then renderHome(kind) end
                    end)
                end
            end))
        end
    end
end

renderCustom = function()
    setPage("Custom"); tabs()
    makeLabel(Body,"Custom Mix Animasi",UDim2.new(0,10,0,50),UDim2.new(1,-20,0,24),15,Theme.Text)
    local scroll=new("ScrollingFrame",{
        Parent=Body,Position=UDim2.new(0,0,0,82),Size=UDim2.new(1,0,1,-120),
        BackgroundColor3=Theme.Page,BorderSizePixel=0,
        ScrollBarThickness=4,ScrollBarImageColor3=Theme.Orange,
        CanvasSize=UDim2.new(0,0,0,430),ZIndex=19
    }); corner(scroll,12); stroke(scroll,Theme.Border,1,0)
    local y=12
    for _,state in ipairs(States) do
        local panel=makePanel(scroll,UDim2.new(0,10,0,y),UDim2.new(1,-24,0,52),Theme.Card)
        makeLabel(panel,state,UDim2.new(0,10,0,4),UDim2.new(0,66,0,44),13,Theme.Orange)
        local meta=SlotMeta[state]
        local text=meta and ((meta.Bundle or "Bundle").." · ID "..tostring(meta.Id or "")) or "belum diset"
        makeSubLabel(panel,text,UDim2.new(0,82,0,4),UDim2.new(1,-254,0,44),11,meta and Theme.TextSub or Theme.LightMuted)
        makeButton(panel,"SET",UDim2.new(1,-164,0,10),UDim2.new(0,46,0,30),function() ChoosingState=state; renderHome("Bundle") end,Theme.Green,Theme.Black)
        makeButton(panel,"INFO",UDim2.new(1,-112,0,10),UDim2.new(0,60,0,30),function()
            local body=meta and ("Slot: "..state.."\nBundle: "..tostring(meta.Bundle).."\nBundle ID: "..tostring(meta.BundleId).."\nAnim ID: "..tostring(meta.Id)) or ("Slot: "..state.."\nBelum ada animasi.")
            showInfoModal("Slot: "..state,body,meta and bundleThumbnail(meta.BundleId) or "",{})
        end,Theme.Cyan,Theme.Black)
        makeButton(panel,"✕",UDim2.new(1,-44,0,10),UDim2.new(0,30,0,30),function() CurrentForm[state]=""; SlotMeta[state]=nil; saveData(); renderCustom() end,Theme.Red,Theme.White)
        y=y+60
    end
    makeButton(scroll,"✔ APPLY CUSTOM PACK",UDim2.new(0,10,0,y+8),UDim2.new(0,190,0,36),function() LastAppliedName="Custom Mix"; applyCurrentForm("Custom Mix") end,Theme.Orange,Theme.Black)
    makeButton(scroll,"✕ CLEAR MIX",UDim2.new(0,212,0,y+8),UDim2.new(0,120,0,36),function() for _,st in ipairs(States) do CurrentForm[st]=""; SlotMeta[st]=nil end; saveData(); renderCustom() end,Theme.Red,Theme.White)
    scroll.CanvasSize=UDim2.new(0,0,0,y+62)
end

renderFavorites = function()
    setPage("Favorites"); tabs()
    makeLabel(Body,"Favorit Bundle & Emote",UDim2.new(0,10,0,50),UDim2.new(1,-20,0,24),15,Theme.Text)
    local scroll=new("ScrollingFrame",{
        Parent=Body,Position=UDim2.new(0,0,0,82),Size=UDim2.new(1,0,1,-120),
        BackgroundColor3=Theme.Page,BorderSizePixel=0,
        ScrollBarThickness=4,ScrollBarImageColor3=Theme.Orange,
        CanvasSize=UDim2.new(0,0,0,380),ZIndex=19
    }); corner(scroll,12); stroke(scroll,Theme.Border,1,0)
    local idx=1
    for _,fav in ipairs(FavoriteBundles) do renderItemCard(scroll,fav,idx,"Bundle"); idx=idx+1 end
    for _,fav in ipairs(FavoriteEmotes) do renderItemCard(scroll,fav,idx,"Emote"); idx=idx+1 end
    if idx==1 then makeSubLabel(scroll,"Belum ada favorit. Tap ★ di card.",UDim2.new(0,16,0,20),UDim2.new(0,300,0,30),13,Theme.Muted) end
    scroll.CanvasSize=UDim2.new(0,0,0,math.max(360,math.ceil((idx-1)/2)*146+62))
end

renderSave = function()
    setPage("Save"); tabs()
    makeLabel(Body,"Simpan & Auto-load Pack",UDim2.new(0,10,0,50),UDim2.new(1,-20,0,24),15,Theme.Text)
    local nameBox=makeBox(Body,"Nama save...",UDim2.new(0,10,0,82),UDim2.new(0,214,0,36))
    makeButton(Body,"💾 SIMPAN",UDim2.new(0,234,0,82),UDim2.new(0,110,0,36),function()
        local name=tostring(nameBox.Text or ""); if name=="" then name="Pack "..tostring(#SavedPacks+1) end
        table.insert(SavedPacks,{Name=name,Form=tableCopy(CurrentForm),Meta=tableCopy(SlotMeta)})
        saveData(); renderSave(); status("Tersimpan: "..name,true)
    end,Theme.Green,Theme.Black)
    local scroll=new("ScrollingFrame",{
        Parent=Body,Position=UDim2.new(0,0,0,130),Size=UDim2.new(1,0,1,-168),
        BackgroundColor3=Theme.Page,BorderSizePixel=0,
        ScrollBarThickness=4,ScrollBarImageColor3=Theme.Orange,
        CanvasSize=UDim2.new(0,0,0,360),ZIndex=19
    }); corner(scroll,12); stroke(scroll,Theme.Border,1,0)
    local y=10
    for i,pack in ipairs(SavedPacks) do
        local panel=makePanel(scroll,UDim2.new(0,10,0,y),UDim2.new(1,-24,0,60),Theme.Card)
        local name=tostring(pack.Name or ("Pack "..i))
        local auto=AutoLoadName==name and " [AUTO]" or ""
        makeLabel(panel,name..auto,UDim2.new(0,10,0,6),UDim2.new(1,-252,0,22),13,Theme.Text)
        makeSubLabel(panel,"Gunakan, edit, hapus, atau auto-load.",UDim2.new(0,10,0,30),UDim2.new(1,-252,0,18),10,Theme.Muted)
        makeButton(panel,"AUTO",UDim2.new(1,-234,0,14),UDim2.new(0,52,0,32),function() AutoLoadName=name; AutoLoad=true; saveData(); renderSave() end,AutoLoadName==name and Theme.Orange or Theme.Card)
        makeButton(panel,"USE",UDim2.new(1,-174,0,14),UDim2.new(0,48,0,32),function() CurrentForm=tableCopy(pack.Form); SlotMeta=tableCopy(pack.Meta); LastAppliedName=name; applyCurrentForm(name) end,Theme.Green,Theme.Black)
        makeButton(panel,"EDIT",UDim2.new(1,-118,0,14),UDim2.new(0,48,0,32),function() CurrentForm=tableCopy(pack.Form); SlotMeta=tableCopy(pack.Meta); renderCustom() end,Theme.Cyan,Theme.Black)
        makeButton(panel,"DEL",UDim2.new(1,-62,0,14),UDim2.new(0,40,0,32),function() table.remove(SavedPacks,i); saveData(); renderSave() end,Theme.Red,Theme.White)
        y=y+68
    end
    scroll.CanvasSize=UDim2.new(0,0,0,math.max(360,y+20))
end

renderSettings = function()
    setPage("Settings"); tabs()
    makeLabel(Body,"Pengaturan",UDim2.new(0,10,0,50),UDim2.new(1,-20,0,24),15,Theme.Text)
    -- Speed
    makeSubLabel(Body,"Emote Speed",UDim2.new(0,10,0,86),UDim2.new(0,160,0,20),12,Theme.Muted)
    local speedBox=makeBox(Body,"Masukkan speed: 1, 1.5, 2...",UDim2.new(0,10,0,110),UDim2.new(0,222,0,34))
    speedBox.Text=tostring(EmoteSpeed)
    makeButton(Body,"APPLY",UDim2.new(0,244,0,110),UDim2.new(0,80,0,34),function()
        local n=tonumber(speedBox.Text)
        if not n then status("Speed tidak valid",false); return end
        EmoteSpeed=n
        if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end
        saveData(); status("Speed: "..EmoteSpeed.."x",true); renderSettings()
    end,Theme.Green,Theme.Black)
    makeButton(Body,"1x",UDim2.new(0,334,0,110),UDim2.new(0,40,0,34),function() EmoteSpeed=1; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(1) end) end; saveData(); renderSettings() end,EmoteSpeed==1 and Theme.Orange or Theme.Card)
    makeButton(Body,"-",UDim2.new(0,380,0,110),UDim2.new(0,36,0,34),function() EmoteSpeed=math.max(0.1,EmoteSpeed-0.5); if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end; saveData(); renderSettings() end,Theme.Card)
    makeButton(Body,"+",UDim2.new(0,422,0,110),UDim2.new(0,36,0,34),function() EmoteSpeed=EmoteSpeed+0.5; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack:AdjustSpeed(EmoteSpeed) end) end; saveData(); renderSettings() end,Theme.Card)
    makeSubLabel(Body,"Speed saat ini: "..EmoteSpeed.."x",UDim2.new(0,10,0,150),UDim2.new(1,-20,0,20),11,Theme.Muted)
    -- Loop / Move toggles
    makeButton(Body,EmoteLoop and "🔁 LOOP: ON" or "🔁 LOOP: OFF",UDim2.new(0,10,0,180),UDim2.new(0,140,0,34),function() EmoteLoop=not EmoteLoop; if CurrentEmoteTrack then pcall(function() CurrentEmoteTrack.Looped=EmoteLoop end) end; saveData(); renderSettings() end,EmoteLoop and Theme.Green or Theme.Card,EmoteLoop and Theme.Black or Theme.TextSub)
    makeButton(Body,MoveWhileEmote and "🚶 MOVE: ON" or "🚶 MOVE: OFF",UDim2.new(0,160,0,180),UDim2.new(0,140,0,34),function() MoveWhileEmote=not MoveWhileEmote; saveData(); renderSettings() end,MoveWhileEmote and Theme.Green or Theme.Card,MoveWhileEmote and Theme.Black or Theme.TextSub)
    -- Modal dim
    makeSubLabel(Body,"Transparansi modal background",UDim2.new(0,10,0,228),UDim2.new(1,-20,0,20),12,Theme.Muted)
    local dims={{"25%",0.25},{"45%",0.45},{"65%",0.65},{"80%",0.80}}
    local dx=10
    for _,d in ipairs(dims) do
        makeButton(Body,d[1],UDim2.new(0,dx,0,252),UDim2.new(0,72,0,32),function() ModalDimTransparency=d[2]; saveData(); renderSettings() end,math.abs(ModalDimTransparency-d[2])<0.01 and Theme.Orange or Theme.Card)
        dx=dx+80
    end
    -- Apply method
    makeSubLabel(Body,"Metode Apply",UDim2.new(0,10,0,300),UDim2.new(0,160,0,20),12,Theme.Muted)
    makeButton(Body,"ANIMATE",UDim2.new(0,10,0,322),UDim2.new(0,100,0,32),function() ApplyMethod="Animate"; saveData(); renderSettings() end,ApplyMethod=="Animate" and Theme.Orange or Theme.Card)
    makeButton(Body,"DESCRIPTION",UDim2.new(0,120,0,322),UDim2.new(0,128,0,32),function() ApplyMethod="Description"; saveData(); renderSettings() end,ApplyMethod=="Description" and Theme.Orange or Theme.Card)
    makeButton(Body,"BOTH",UDim2.new(0,258,0,322),UDim2.new(0,80,0,32),function() ApplyMethod="Both"; saveData(); renderSettings() end,ApplyMethod=="Both" and Theme.Orange or Theme.Card)
    -- Autoload / controls
    makeButton(Body,AutoLoad and "⚡ AUTOLOAD: ON" or "⚡ AUTOLOAD: OFF",UDim2.new(0,10,0,370),UDim2.new(0,160,0,34),function() AutoLoad=not AutoLoad; saveData(); renderSettings() end,AutoLoad and Theme.Green or Theme.Card,AutoLoad and Theme.Black or Theme.TextSub)
    makeButton(Body,"⏹ STOP EMOTE",UDim2.new(0,182,0,370),UDim2.new(0,140,0,34),stopEmote,Theme.Red,Theme.White)
    makeButton(Body,"↺ RESET ANIM",UDim2.new(0,332,0,370),UDim2.new(0,136,0,34),restoreOriginal,Theme.Yellow,Theme.Black)
end

---------------------------------------------------------------------
-- SAWERIA ICON (pixel art lightning bolt)
---------------------------------------------------------------------

local function drawSaweriaIcon(parent)
    -- Clean lightning bolt pixel art on orange bg
    local holder=new("Frame",{Parent=parent,Position=UDim2.new(0,8,0,8),Size=UDim2.new(1,-16,1,-16),BackgroundTransparency=1,Active=false,ZIndex=82})
    local grid={
        "00011100",
        "00111100",
        "01111000",
        "11110000",
        "01111111",
        "00011111",
        "00001110",
        "00000100",
    }
    local lit=Color3.fromRGB(18,18,18)
    local n=#grid[1]
    for yy,row in ipairs(grid) do
        for xx=1,n do
            if string.sub(row,xx,xx)=="1" then
                new("Frame",{
                    Parent=holder,
                    Position=UDim2.new((xx-1)/n,0,(yy-1)/#grid,0),
                    Size=UDim2.new(1/n,1,1/#grid,1),
                    BackgroundColor3=lit,BorderSizePixel=0,Active=false,ZIndex=83
                })
            end
        end
    end
end

---------------------------------------------------------------------
-- GUI CREATE
---------------------------------------------------------------------

local function createGui()
    local pg=getParentGui()
    -- cleanup old versions
    pcall(function()
        local names={"IrenkBundleAnimationHub","IrenkBundleAnimationHubV2","IrenkBundleAnimationHubV3",
            "IrenkBundleAnimationHubV4Saweria","IrenkBundleAnimationHubV5CleanSaweria",
            "IrenkBundleAnimationHubV6CleanSaweria","IrenkBundleAnimationHubV7OriginalSaweria",
            "IrenkBundleEmoteHubV8InfoSaweria","IrenkBundleEmoteHubV83InfoSaweria",
            "IrenkBundleEmoteHubV84SaweriaULTRA"}
        for _,name in ipairs(names) do
            local old=pg:FindFirstChild(name)
            if old then old:Destroy() end
        end
    end)

    ScreenGui=new("ScreenGui",{Name="IrenkBundleEmoteHubV84SaweriaULTRA",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=999999,ZIndexBehavior=Enum.ZIndexBehavior.Global})
    ScreenGui.Parent=pg

    -- ========== ICON BUTTON ==========
    IconButton=new("TextButton",{
        Parent=ScreenGui,Position=UDim2.new(0,18,0.5,-30),
        Size=UDim2.new(0,58,0,58),
        BackgroundColor3=Theme.Orange,BorderSizePixel=0,
        Text="",AutoButtonColor=false,ZIndex=80
    }); corner(IconButton,16); stroke(IconButton,Theme.OrangeDark,2,0)
    drawSaweriaIcon(IconButton)

    -- pulse ring
    local ring=new("Frame",{
        Parent=ScreenGui,AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.new(0,47,0.5,-1),
        Size=UDim2.new(0,58,0,58),
        BackgroundTransparency=1,BorderSizePixel=0,ZIndex=79
    }); corner(ring,30)
    stroke(ring,Theme.Orange,2,0.4)
    task.spawn(function()
        while Alive and ring and ring.Parent do
            tween(ring,{Size=UDim2.new(0,74,0,74),BackgroundTransparency=1},0.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
            pcall(function()
                for _,s in ipairs(ring:GetChildren()) do
                    if s:IsA("UIStroke") then tween(s,{Transparency=1},0.7) end
                end
            end)
            task.wait(0.75)
            ring.Size=UDim2.new(0,58,0,58)
            pcall(function()
                for _,s in ipairs(ring:GetChildren()) do
                    if s:IsA("UIStroke") then tween(s,{Transparency=0.4},0.05) end
                end
            end)
            task.wait(0.15)
        end
    end)

    -- ========== MAIN WINDOW ==========
    Main=new("Frame",{
        Parent=ScreenGui,AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.new(0.5,0,0.5,0),
        Size=UDim2.new(0,10,0,10),    -- starts tiny for pop-in
        BackgroundColor3=Theme.Page,BorderSizePixel=0,
        Visible=false,Active=true,ZIndex=10
    }); corner(Main,18); stroke(Main,Theme.Border,2,0)

    -- Header
    local header=new("Frame",{
        Parent=Main,Position=UDim2.new(0,0,0,0),
        Size=UDim2.new(1,0,0,58),
        BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=11
    }); corner(header,18)
    new("Frame",{Parent=header,Position=UDim2.new(0,0,1,-18),Size=UDim2.new(1,0,0,18),BackgroundColor3=Theme.Orange,BorderSizePixel=0,ZIndex=11})

    -- ⚡ icon in header
    local hIcon=new("Frame",{Parent=Main,Position=UDim2.new(0,14,0,11),Size=UDim2.new(0,36,0,36),BackgroundColor3=Theme.OrangeDark,BorderSizePixel=0,ZIndex=14}); corner(hIcon,18)
    new("TextLabel",{Parent=hIcon,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="⚡",TextColor3=Theme.Black,TextSize=18,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=15})

    HeaderTitle=new("TextLabel",{
        Parent=Main,Position=UDim2.new(0,58,0,8),Size=UDim2.new(1,-108,0,26),
        BackgroundTransparency=1,Text="Bundle Hub",TextColor3=Theme.Black,
        TextStrokeTransparency=1,TextSize=18,Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=14
    })
    new("TextLabel",{
        Parent=Main,Position=UDim2.new(0,58,0,32),Size=UDim2.new(1,-108,0,18),
        BackgroundTransparency=1,Text="by Irenk · Saweria Ultra v8.4",TextColor3=Color3.fromRGB(40,40,40),
        TextStrokeTransparency=1,TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=14
    })

    -- Close button
    local CloseButton=new("TextButton",{
        Parent=Main,Position=UDim2.new(1,-48,0,11),Size=UDim2.new(0,34,0,34),
        BackgroundColor3=Theme.RedDark,BorderSizePixel=0,
        Text="✕",TextColor3=Theme.White,TextStrokeTransparency=1,
        TextSize=15,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=120
    }); corner(CloseButton,17)

    local function doClose()
        -- POP OUT
        tween(Main,{Size=UDim2.new(0,10,0,10),BackgroundTransparency=1},0.22,Enum.EasingStyle.Back,Enum.EasingDirection.In)
        task.delay(0.25,function()
            if Main then Main.Visible=false; Main.BackgroundTransparency=0 end
        end)
    end
    add(Connections, CloseButton.MouseButton1Click:Connect(doClose))
    add(Connections, CloseButton.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch then doClose() end
    end))

    -- Body
    Body=new("Frame",{Parent=Main,Position=UDim2.new(0,12,0,64),Size=UDim2.new(1,-24,1,-100),BackgroundTransparency=1,ZIndex=18})

    -- Status label (bottom)
    StatusLabel=new("TextLabel",{
        Parent=Main,Position=UDim2.new(0,16,1,-36),Size=UDim2.new(1,-80,0,24),
        BackgroundTransparency=1,Text="Ready",TextColor3=Theme.Muted,
        TextStrokeTransparency=1,TextSize=11,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=20
    })

    -- Version badge bottom right
    makeBadge(Main,"v8.4 ULTRA",UDim2.new(1,-76,1,-32),Theme.Orange,Theme.Black)

    ----------------------------------------------------------------
    -- DRAG for main window (header only, clean threshold approach)
    ----------------------------------------------------------------
    local HeaderDrag=new("TextButton",{
        Parent=Main,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,-56,0,58),
        BackgroundTransparency=1,Text="",BorderSizePixel=0,Active=true,
        AutoButtonColor=false,ZIndex=115
    })
    local mainDragging=false; local mainDragInput, mainDragStart, mainDragPos
    local DRAG_THRESHOLD=6

    add(Connections, HeaderDrag.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            mainDragging=false
            mainDragInput=inp; mainDragStart=inp.Position; mainDragPos=Main.Position
            inp.Changed:Connect(function()
                if inp.UserInputState==Enum.UserInputState.End then mainDragging=false; mainDragInput=nil end
            end)
        end
    end))
    add(Connections, HeaderDrag.InputChanged:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseMovement then
            if mainDragInput and (inp.UserInputType==mainDragInput.UserInputType) then
                mainDragInput=inp
            end
        end
    end))
    add(Connections, UserInputService.InputChanged:Connect(function(inp)
        if not mainDragInput then return end
        if inp~=mainDragInput and inp.UserInputType~=mainDragInput.UserInputType then return end
        local d=inp.Position-mainDragStart
        if not mainDragging and (math.abs(d.X)>DRAG_THRESHOLD or math.abs(d.Y)>DRAG_THRESHOLD) then
            mainDragging=true
        end
        if mainDragging then
            Main.Position=UDim2.new(mainDragPos.X.Scale,mainDragPos.X.Offset+d.X,mainDragPos.Y.Scale,mainDragPos.Y.Offset+d.Y)
        end
    end))

    ----------------------------------------------------------------
    -- ICON BUTTON: toggle + drag  (FIXED — no event conflict)
    ----------------------------------------------------------------
    local iconDragging=false
    local iconDragInput, iconDragStart, iconDragPos
    local iconDragMoved=false
    local ICON_DRAG_THRESHOLD=8

    -- Single InputBegan handles both drag tracking and tap detection
    add(Connections, IconButton.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            iconDragMoved=false
            iconDragInput=inp; iconDragStart=inp.Position; iconDragPos=IconButton.Position
            inp.Changed:Connect(function()
                if inp.UserInputState==Enum.UserInputState.End then
                    -- If we didn't drag far: it's a TAP → toggle
                    if not iconDragMoved then
                        -- POP IN or POP OUT
                        if not Main.Visible then
                            -- Show + pop in
                            Main.Size=UDim2.new(0,10,0,10)
                            Main.BackgroundTransparency=1
                            Main.Visible=true
                            tweenBounce(Main,{Size=UDim2.new(0,580,0,545),BackgroundTransparency=0},0.48)
                            if not Body:FindFirstChildWhichIsA("GuiObject") then
                                task.delay(0.1,function()
                                    local ok,err=pcall(function() renderHome("Bundle") end)
                                    if not ok then status("Error: "..tostring(err),false) end
                                end)
                            end
                        else
                            -- Pop out then hide
                            tween(Main,{Size=UDim2.new(0,10,0,10),BackgroundTransparency=1},0.22,Enum.EasingStyle.Back,Enum.EasingDirection.In)
                            task.delay(0.25,function()
                                if Main then Main.Visible=false; Main.BackgroundTransparency=0 end
                            end)
                        end
                    end
                    iconDragging=false; iconDragMoved=false; iconDragInput=nil
                end
            end)
        end
    end))

    -- Track icon drag movement
    add(Connections, UserInputService.InputChanged:Connect(function(inp)
        if not iconDragInput then return end
        if inp.UserInputType~=iconDragInput.UserInputType then return end
        local d=inp.Position-iconDragStart
        local dist=math.sqrt(d.X*d.X+d.Y*d.Y)
        if dist>ICON_DRAG_THRESHOLD then
            iconDragMoved=true; iconDragging=true
        end
        if iconDragging then
            IconButton.Position=UDim2.new(iconDragPos.X.Scale,iconDragPos.X.Offset+d.X,iconDragPos.Y.Scale,iconDragPos.Y.Offset+d.Y)
        end
    end))

    -- Mouse click fallback (PC)
    add(Connections, IconButton.MouseButton1Click:Connect(function()
        if iconDragMoved then return end
        if not Main.Visible then
            Main.Size=UDim2.new(0,10,0,10); Main.BackgroundTransparency=1; Main.Visible=true
            tweenBounce(Main,{Size=UDim2.new(0,580,0,545),BackgroundTransparency=0},0.48)
            if not Body:FindFirstChildWhichIsA("GuiObject") then
                task.delay(0.1,function()
                    local ok,err=pcall(function() renderHome("Bundle") end)
                    if not ok then status("Error: "..tostring(err),false) end
                end)
            end
        else
            tween(Main,{Size=UDim2.new(0,10,0,10),BackgroundTransparency=1},0.22,Enum.EasingStyle.Back,Enum.EasingDirection.In)
            task.delay(0.25,function()
                if Main then Main.Visible=false; Main.BackgroundTransparency=0 end
            end)
        end
    end))
end

---------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------

loadData()
createGui()

LocalPlayer.CharacterAdded:Connect(function() task.wait(1); captureOriginals() end)
if LocalPlayer.Character then task.wait(0.5); captureOriginals() end

task.spawn(function()
    task.wait(1)
    local hasAny=false
    for _,st in ipairs(States) do if normalizeId(CurrentForm[st])~="" then hasAny=true; break end end
    if AutoLoad and hasAny then
        applyCurrentForm(LastAppliedName~="" and LastAppliedName or "Saved Pack")
        status("Auto-loaded: "..(LastAppliedName~="" and LastAppliedName or "Saved Pack"),true)
    else
        status("Memuat bundle populer...",nil)
        local ok=searchCatalog("Bundle","animation",false)
        if ok then
            status("Bundle populer dimuat ✓",true)
        else
            status("Cari bundle atau emote.",true)
        end
    end
end)
