if _G.EggStop then _G.EggStop() end

local WS = game:GetService("Workspace")
local RS = game:GetService("RunService")
local LP = game:GetService("Players").LocalPlayer

local MIN, NOTIFY_MIN, TAB, SND, ROWS = 0, 1e11, "Egg Overlay", "rbxassetid://4590662766", 8
local st = { run = true, lbl = true, tp = false, snd = true, panel = true }
local targets, first, sel, notified = {}, true, nil, {}
local pool, labels, conn = {}, {}, nil
local px, py, PW, RH = 20, 200, 260, 26
local dragging, dx, dy, was = false, 0, 0, false

-- Waypoint & Custom Fly State
local savedWaypoint = nil
local flyLoop = nil
local wpMarker = nil
local isTweening = false

-- Clean Glassy Colors
local GLASS_BG = Color3.fromRGB(10, 10, 15)
local GLASS_ALPHA = 0.45 
local RIM_COLOR = Color3.fromRGB(255, 255, 255)
local RIM_ALPHA = 0.15 
local HEAD_OVERLAY = Color3.fromRGB(255, 255, 255)
local HEAD_ALPHA = 0.03 
local BTN_COLOR = Color3.fromRGB(255, 255, 255)
local BTN_ALPHA = 0.1 
local BTN_HOVER_ALPHA = 0.25 

local GOLD = Color3.fromRGB(255, 215, 0)
local GREEN = Color3.fromRGB(50, 255, 100)
local RED = Color3.fromRGB(255, 100, 100)

local function now() return (os.time and os.time()) or 0 end

-- Number formatting
local function fmt(n)
    if not n then return "0" end
    if n >= 1e21 then return string.format("%.1fSx", n / 1e21) end
    if n >= 1e18 then return string.format("%.1fQi", n / 1e18) end
    if n >= 1e15 then return string.format("%.1fQa", n / 1e15) end
    if n >= 1e12 then return string.format("%.1fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

local function parse(t)
    if not t then return nil end
    local s = tostring(t):upper():gsub("[,%s]", "")
    local n, x = s:match("([%d%.]+)([A-Z]*)")
    n = tonumber(n)
    if not n then return nil end
    local mults = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18, SX = 1e21 }
    return n * (mults[x] or 1)
end

local function readEgg(e)
    local r = e:FindFirstChild("Handle") or e:FindFirstChild("RootPart") or e:FindFirstChild("EggBase")
    local bb = r and r:FindFirstChild("EggLuck")
    local l = bb and bb:FindFirstChild("Luck")
    local luck = l and parse(l.Text)
    if not luck then return nil end
    return { model = e, root = r, name = e.Name, luck = luck }
end

local function keyOf(t)
    local ok, p = pcall(function() return t.root.Position end)
    if not ok or not p then return t.name .. "|" .. t.luck end
    return t.name .. "|" .. t.luck .. "|" .. math.floor(p.X / 20) .. "|" .. math.floor(p.Z / 20)
end

local function alert(t)
    if st.snd then
        pcall(function()
            local s = Instance.new("Sound")
            s.SoundId = SND
            s.Volume = 2
            s.Parent = WS
            s:Play()
        end)
    end
    pcall(function() notify("100B+ Egg Spawned!", t.name .. " | " .. fmt(t.luck), 5) end)
end

-- ====================================================
-- BULLETPROOF EGG TELEPORT (Direct Global CFrame)
-- ====================================================
local function tp(t)
    local char = LP.Character
    if not char then return end
    
    local ok, pos = pcall(function() return t.root.Position end)
    if not (ok and pos) then
        pcall(function() notify("Egg Overlay", "Egg has despawned!", 3) end)
        return
    end
    
    sel = t.model
    local targetCFrame = CFrame.new(pos.X, pos.Y + 5, pos.Z)
    
    local success = pcall(function() 
        char:PivotTo(targetCFrame) 
    end)
    
    if not success then
        local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        if hrp and hrp:IsA("BasePart") then
            if not pcall(function() hrp.CFrame = targetCFrame end) then
                pcall(function() hrp.Position = Vector3.new(pos.X, pos.Y + 5, pos.Z) end)
            end
        end
    end
end

-- ====================================================
-- CUSTOM LERP FLY & NOCLIP WAYPOINT SYSTEM
-- ====================================================
local function setWaypoint()
    local char = LP.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if hrp and hrp:IsA("BasePart") then
        savedWaypoint = hrp.CFrame
        
        if not wpMarker or not wpMarker.Parent then
            pcall(function() if wpMarker then wpMarker:Destroy() end end)
            wpMarker = Instance.new("Part")
            wpMarker.Name = "R6_WaypointMarker"
            wpMarker.Shape = Enum.PartType.Ball
            wpMarker.Size = Vector3.new(3, 3, 3)
            wpMarker.Color = GREEN
            wpMarker.Material = Enum.Material.Neon
            wpMarker.Anchored = true
            wpMarker.CanCollide = false
            wpMarker.Parent = workspace
            
            local bgui = Instance.new("BillboardGui", wpMarker)
            bgui.Size = UDim2.new(0, 100, 0, 30)
            bgui.AlwaysOnTop = true
            local txt = Instance.new("TextLabel", bgui)
            txt.Size = UDim2.new(1, 0, 1, 0)
            txt.BackgroundTransparency = 1
            txt.Text = "WAYPOINT"
            txt.TextColor3 = GREEN
            txt.TextStrokeTransparency = 0
            txt.Font = Enum.Font.GothamBold
            txt.TextScaled = true
        end
        pcall(function() wpMarker.Position = savedWaypoint.Position end)
        pcall(function() notify("Waypoint", "Position Saved & Visualized!", 2) end)
    end
end

local function stopFly()
    isTweening = false
    if flyLoop then flyLoop:Disconnect() flyLoop = nil end
    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        local hum = char:FindFirstChild("Humanoid")
        if hrp then pcall(function() hrp.Anchored = false end) end
        if hum then pcall(function() hum.PlatformStand = false end) end
    end
end

local function executeFly()
    if not savedWaypoint then return end
    stopFly()
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local hum = char:FindFirstChild("Humanoid")
    if not hrp then return end
    
    local startCF = hrp.CFrame
    local targetCF = savedWaypoint
    local dist = (startCF.Position - targetCF.Position).Magnitude
    local duration = math.max(0.1, dist / 500)
    local startTime = tick()
    
    isTweening = true
    pcall(function() hrp.Anchored = true end)
    if hum then pcall(function() hum.PlatformStand = true end) end
    
    flyLoop = RS.RenderStepped:Connect(function()
        local alpha = math.clamp((tick() - startTime) / duration, 0, 1)
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
        end
        pcall(function() hrp.CFrame = startCF:Lerp(targetCF, alpha) end)
        if alpha >= 1 then stopFly() end
    end)
end

-- ====================================================
-- GUI DRAWING
-- ====================================================
local function mousePos()
    local ok, x, y = pcall(function()
        local v = game:GetService("UserInputService"):GetMouseLocation()
        return v.X, v.Y
    end)
    if ok and x then return x, y end
    ok, x, y = pcall(function()
        local m = LP:GetMouse()
        return m.X, m.Y
    end)
    if ok and x then return x, y end
    return -1, -1
end

local function isDown()
    local ok, v = pcall(function() return ismouse1pressed() end)
    return ok and v == true
end

local function sq(color, alpha)
    local d = Drawing.new("Square")
    d.Filled, d.Color, d.Transparency, d.Visible, d.Thickness = true, color, alpha, false, 0
    pool[#pool + 1] = d
    return d
end

local function tx(size, center, bold)
    local d = Drawing.new("Text")
    d.Size, d.Center, d.Outline, d.Visible = size, center, true, false
    d.Font = bold and 3 or 2
    d.Color = Color3.fromRGB(255, 255, 255)
    pool[#pool + 1] = d
    return d
end

local shadow = sq(Color3.fromRGB(0, 0, 0), 0.5) 
local rim = sq(RIM_COLOR, RIM_ALPHA) 
local bg = sq(GLASS_BG, GLASS_ALPHA) 
local head = sq(HEAD_OVERLAY, HEAD_ALPHA) 
local accent = sq(Color3.fromRGB(255, 255, 255), 1) 

local headTx = tx(16, false, true)
local emptyTx = tx(14, false, false)

local rows = {}
for i = 1, ROWS do
    rows[i] = { 
        txt = tx(14, false, false), 
        tpBtn = sq(BTN_COLOR, BTN_ALPHA), 
        tpTxt = tx(13, true, true)
    }
end
for i = 1, 30 do
    local d = tx(14, true, true)
    d.Color = GOLD
    labels[i] = d
end

local wpSetBtn = sq(BTN_COLOR, BTN_ALPHA)
local wpSetTxt = tx(14, true, true)
wpSetTxt.Text = "Set WP"

local wpGoBtn = sq(BTN_COLOR, BTN_ALPHA)
local wpGoTxt = tx(14, true, true)

pcall(function() UI.RemoveTab(TAB) end)
UI.AddTab(TAB, function(tab)
    local o = tab:Section("Egg overlay", "Left")
    o:Toggle("egg_panel", "Show on-screen panel", st.panel, function(v) st.panel = v == true end)
    o:Toggle("egg_lbl", "Show labels on eggs", st.lbl, function(v) st.lbl = v == true end)
    o:Toggle("egg_snd", "Sound on 100B+ spawn", st.snd, function(v) st.snd = v == true end)
    o:Button("Unload", function() if _G.EggStop then _G.EggStop() end end)
end)

-- Find Eggs Loop
RS.Heartbeat:Connect(function()
    if not st.run then return end
    local nt, t0 = {}, now()
    local f = WS:FindFirstChild("RenderedEggs")
    for _, e in ipairs(f and f:GetChildren() or {}) do
        local ok, t = pcall(readEgg, e)
        if ok and t and t.luck >= MIN then
            nt[#nt + 1] = t
        end
    end
    table.sort(nt, function(a, b) return a.luck > b.luck end)
    targets = nt
end)

conn = RS.RenderStepped:Connect(function()
    local list = targets
    local mx, my = mousePos()
    local down = isDown()
    local clicked = down and not was
    was = down
    local show = st.panel
    local n = math.min(#list, ROWS)
    local listHeight = 28 + math.max(n, 1) * RH
    local totalHeight = listHeight + 36 

    if show and clicked and mx >= px and mx <= px + PW and my >= py and my <= py + 26 then
        dragging, dx, dy = true, mx - px, my - py
    end
    if dragging then
        if down then px, py = mx - dx, my - dy else dragging = false end
    end

    shadow.Visible, rim.Visible, bg.Visible, head.Visible, accent.Visible, headTx.Visible = show, show, show, show, show, show
    shadow.Position = Vector2.new(px + 4, py + 4)
    shadow.Size = Vector2.new(PW, totalHeight)
    
    rim.Position = Vector2.new(px - 1, py - 1)
    rim.Size = Vector2.new(PW + 2, totalHeight + 2)
    
    bg.Position, bg.Size = Vector2.new(px, py), Vector2.new(PW, totalHeight)
    
    accent.Position, accent.Size = Vector2.new(px, py), Vector2.new(PW, 2)
    accent.Color = Color3.fromHSV(os.clock() % 4 / 4, 1, 1)
    
    head.Position, head.Size = Vector2.new(px, py + 2), Vector2.new(PW, 26)
    
    headTx.Position = Vector2.new(px + 8, py + 7)
    headTx.Text = "Made by R:6_cozy  |  Eggs: " .. #list
    headTx.Color = Color3.fromHSV(os.clock() % 4 / 4, 0.4, 1)
    
    emptyTx.Visible = show and #list == 0
    emptyTx.Position = Vector2.new(px + 8, py + 34)
    emptyTx.Text = "Waiting for eggs to spawn..."
    emptyTx.Color = Color3.fromRGB(150, 150, 150)

    for i = 1, ROWS do
        local r, t = rows[i], list[i]
        if show and t then
            local ry = py + 28 + (i - 1) * RH + 4
            local bw = 48
            local bh = RH - 6
            local tp_bx = px + PW - 54
            
            local hovTP = not dragging and mx >= tp_bx and mx <= tp_bx + bw and my >= ry + 2 and my <= ry + 2 + bh
            
            r.txt.Text = string.format("%s  -  %s", t.name, fmt(t.luck))
            r.txt.Color = (t.model == sel) and GREEN or ((t.luck >= NOTIFY_MIN) and GOLD or Color3.fromRGB(220, 220, 230))
            r.txt.Position = Vector2.new(px + 8, ry + 4)
            
            r.tpBtn.Color = BTN_COLOR
            r.tpBtn.Transparency = hovTP and BTN_HOVER_ALPHA or BTN_ALPHA
            r.tpBtn.Position, r.tpBtn.Size = Vector2.new(tp_bx, ry + 2), Vector2.new(bw, bh)
            r.tpTxt.Text = "TP"
            r.tpTxt.Color = Color3.fromRGB(255, 255, 255)
            r.tpTxt.Position = Vector2.new(tp_bx + bw / 2, ry + 5)
            
            r.txt.Visible, r.tpBtn.Visible, r.tpTxt.Visible = true, true, true
            if clicked and hovTP then
                tp(t)
            end
        else
            r.txt.Visible, r.tpBtn.Visible, r.tpTxt.Visible = false, false, false
        end
    end

    wpSetBtn.Visible, wpGoBtn.Visible, wpSetTxt.Visible, wpGoTxt.Visible = show, show, show, show
    
    if show then
        local wbw = (PW - 20) / 2
        local b1x, by = px + 6, py + listHeight + 6
        local b2x, bh = px + 6 + wbw + 8, 24
        
        local hov1 = not dragging and mx >= b1x and mx <= b1x + wbw and my >= by and my <= by + bh
        local hov2 = not dragging and mx >= b2x and mx <= b2x + wbw and my >= by and my <= by + bh
        
        wpSetBtn.Position, wpSetBtn.Size = Vector2.new(b1x, by), Vector2.new(wbw, bh)
        wpSetBtn.Transparency = hov1 and BTN_HOVER_ALPHA or BTN_ALPHA
        wpSetTxt.Position = Vector2.new(b1x + wbw/2, by + 4)
        
        wpGoBtn.Position, wpGoBtn.Size = Vector2.new(b2x, by), Vector2.new(wbw, bh)
        wpGoBtn.Transparency = hov2 and BTN_HOVER_ALPHA or BTN_ALPHA
        
        wpGoTxt.Text = flyLoop and "Stop Fly" or "Tween WP"
        wpGoTxt.Color = flyLoop and RED or (savedWaypoint and GREEN or Color3.fromRGB(255, 255, 255))
        wpGoTxt.Position = Vector2.new(b2x + wbw/2, by + 4)
        
        if clicked then
            if hov1 then setWaypoint() end
            if hov2 then 
                if flyLoop then 
                    stopFly()
                    pcall(function() notify("Waypoint", "Flight Cancelled", 2) end)
                else
                    executeFly()
                end
            end
        end
    end
end)

_G.EggStop = function()
    if not st.run then return end
    st.run = false
    if conn then conn:Disconnect() end
    stopFly()
    pcall(function() if wpMarker then wpMarker:Destroy() end end)
    for _, d in ipairs(pool) do pcall(function() d:Remove() end) end
    for _, d in ipairs(labels) do pcall(function() d:Remove() end) end
    pcall(function() UI.RemoveTab(TAB) end)
    _G.EggStop = nil
    notify("Egg Overlay", "Unloaded", 3)
end

notify("R:6_cozy", "Egg TP Fixed & Loaded!", 5)
