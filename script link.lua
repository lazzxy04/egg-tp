if _G.EggStop then _G.EggStop() end

-- Localize crucial Roblox globals at the absolute top so Matcha never loses them
local CF_new = CFrame.new
local V3_new = Vector3.new
local V2_new = Vector2.new
local UD2_new = UDim2.new
local C3_rgb = Color3.fromRGB

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
local GLASS_BG = C3_rgb(10, 10, 15)
local GLASS_ALPHA = 0.45 
local RIM_COLOR = C3_rgb(255, 255, 255)
local RIM_ALPHA = 0.15 
local HEAD_OVERLAY = C3_rgb(255, 255, 255)
local HEAD_ALPHA = 0.03 
local BTN_COLOR = C3_rgb(255, 255, 255)
local BTN_ALPHA = 0.1 
local BTN_HOVER_ALPHA = 0.25 

local GOLD = C3_rgb(255, 215, 0)
local GREEN = C3_rgb(50, 255, 100)
local RED = C3_rgb(255, 100, 100)

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
        for _, f in ipairs({
            function() playsound(SND) end,
            function() PlaySound(SND) end,
            function()
                local s = Instance.new("Sound")
                s.SoundId = SND
                s.Volume = 2
                s.Parent = WS
                s:Play()
            end,
        }) do
            if pcall(f) then break end
        end
    end
    pcall(function() notify("100B+ Egg Spawned!", t.name .. " | " .. fmt(t.luck), 5) end)
end

-- ====================================================
-- BULLETPROOF EGG TELEPORT 
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
    local targetCFrame = CF_new(pos.X, pos.Y + 5, pos.Z)
    
    local success = pcall(function() char:PivotTo(targetCFrame) end)
    
    if not success then
        local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        if hrp and hrp:IsA("BasePart") then
            if not pcall(function() hrp.CFrame = targetCFrame end) then
                pcall(function() hrp.Position = V3_new(pos.X, pos.Y + 5, pos.Z) end)
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
            wpMarker.Size = V3_new(3, 3, 3)
            wpMarker.Color = GREEN
            wpMarker.Material = Enum.Material.Neon
            wpMarker.Anchored = true
            wpMarker.CanCollide = false
            wpMarker.Parent = workspace
            
            local bgui = Instance.new("BillboardGui", wpMarker)
            bgui.Size = UD2_new(0, 100, 0, 30)
            bgui.AlwaysOnTop = true
            local txt = Instance.new("TextLabel", bgui)
            txt.Size = UD2_new(1, 0, 1, 0)
            txt.BackgroundTransparency = 1
            txt.Text = "WAYPOINT"
            txt.TextColor3 = GREEN
            txt.TextStrokeTransparency = 0
            txt.Font = Enum.Font.GothamBold
            txt.TextScaled = true
        end
        pcall(function() wpMarker.Position = savedWaypoint.Position end)
        
        pcall(function() notify("Waypoint", "Position Saved & Visualized!", 2) end)
    else
        pcall(function() notify("Waypoint", "Error: Character body not found!", 2) end)
    end
end

local function stopFly()
    isTweening = false
    if flyLoop then flyLoop:Disconnect() flyLoop = nil end
    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        local hum = char:FindFirstChild("Humanoid")
        
        if hrp and hrp:IsA("BasePart") then pcall(function() hrp.Anchored = false end) end
        if hum and hum:IsA("Humanoid") then pcall(function() hum.PlatformStand = false end) end
    end
end

local function executeFly()
    if not savedWaypoint then
        pcall(function() notify("Waypoint", "Set a waypoint first!", 3) end)
        return
    end
    
    stopFly() 
    
    local char = LP.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local hum = char:FindFirstChild("Humanoid")
    if not (hrp and hrp:IsA("BasePart")) then return end
    
    local startCF = hrp.CFrame
    local targetCF = savedWaypoint
    local dist = (startCF.Position - targetCF.Position).Magnitude
    local duration = math.max(0.1, dist / 500) 
    local startTime = tick()
    
    isTweening = true
    pcall(function() hrp.Anchored = true end)
    if hum and hum:IsA("Humanoid") then pcall(function() hum.PlatformStand = true end) end 
    pcall(function() notify("Waypoint", "Flying to Waypoint (Noclip Active)...", 2) end)
    
    flyLoop = RS.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        local alpha = math.clamp(elapsed / duration, 0, 1)
        
        if char then
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
            end
        end
        
        if hrp and hrp:IsA("BasePart") then
            pcall(function() hrp.CFrame = startCF:Lerp(targetCF, alpha) end)
        end
        
        if alpha >= 1 then
            stopFly()
            pcall(function() notify("Waypoint", "Arrived!", 2) end)
        end
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
    d.Color = C3_rgb(255, 255, 255)
    pool[#pool + 1] = d
    return d
end

local shadow = sq(C3_rgb(0, 0, 0), 0.5) 
local rim = sq(RIM_COLOR, RIM_ALPHA) 
local bg = sq(GLASS_BG, GLASS_ALPHA) 
local head = sq(HEAD_OVERLAY, HEAD_ALPHA) 
local accent = sq(C3_rgb(255, 255, 255), 1) 

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
local lastFindTick = 0
RS.Heartbeat:Connect(function()
    if not st.run then return end
    if tick() - lastFindTick < 0.4 then return end
    lastFindTick = tick()
    
    local nt, new, t0 = {}, {}, now()
    local f = WS:FindFirstChild("RenderedEggs")
    for _, e in ipairs(f and f:GetChildren() or {}) do
        local ok, t = pcall(readEgg, e)
        if ok and t and t.luck >= MIN then
            nt[#nt + 1] = t
            local k = keyOf(t)
            local prev = notified[k]
            notified[k] = t0
            if not first and (not prev or t0 - prev > 600) then new[#new + 1] = t end
        end
    end
    table.sort(nt, function(a, b) return a.luck > b.luck end)
    targets, first = nt, false
    if #new > 0 then
        table.sort(new, function(a, b) return a.luck > b.luck end)
        if new[1].luck >= NOTIFY_MIN then
            alert(new[1])
        end
    end
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

    local tickTime = os.clock()
    local rainbowColor = Color3.fromHSV(tickTime % 4 / 4, 1, 1)
    local pastelRainbow = Color3.fromHSV(tickTime % 4 / 4, 0.4, 1)

    shadow.Visible, rim.Visible, bg.Visible, head.Visible, accent.Visible, headTx.Visible = show, show, show, show, show, show
    
    shadow.Position = V2_new(px + 4, py + 4)
    shadow.Size = V2_new(PW, totalHeight)
    
    rim.Position = V2_new(px - 1, py - 1)
    rim.Size = V2_new(PW + 2, totalHeight + 2)
    
    bg.Position, bg.Size = V2_new(px, py), V2_new(PW, totalHeight)
    
    accent.Position, accent.Size = V2_new(px, py), V2_new(PW, 2)
    accent.Color = rainbowColor
    
    head.Position, head.Size = V2_new(px, py + 2), V2_new(PW, 26)
    
    headTx.Position = V2_new(px + 8, py + 7)
    headTx.Text = "Made by R:6_cozy  |  Eggs: " .. #list
    headTx.Color = pastelRainbow
    
    emptyTx.Visible = show and #list == 0
    emptyTx.Position = V2_new(px + 8, py + 34)
    emptyTx.Text = "Waiting for eggs to spawn..."
    emptyTx.Color = C3_rgb(150, 150, 150)

    for i = 1, ROWS do
        local r, t = rows[i], list[i]
        if show and t then
            local ry = py + 28 + (i - 1) * RH + 4
            local bw = 48
            local bh = RH - 6
            local tp_bx = px + PW - 54
            
            local hovTP = not dragging and mx >= tp_bx and mx <= tp_bx + bw and my >= ry + 2 and my <= ry + 2 + bh
            
            r.txt.Text = string.format("%s  -  %s", t.name, fmt(t.luck))
            r.txt.Color = (t.model == sel) and GREEN or ((t.luck >= NOTIFY_MIN) and GOLD or C3_rgb(220, 220, 230))
            r.txt.Position = V2_new(px + 8, ry + 4)
            
            r.tpBtn.Color = BTN_COLOR
            r.tpBtn.Transparency = hovTP and BTN_HOVER_ALPHA or BTN_ALPHA
            r.tpBtn.Position, r.tpBtn.Size = V2_new(tp_bx, ry + 2), V2_new(bw, bh)
            r.tpTxt.Text = "TP"
            r.tpTxt.Color = C3_rgb(255, 255, 255)
            r.tpTxt.Position = V2_new(tp_bx + bw / 2, ry + 5)
            
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
        
        wpSetBtn.Position, wpSetBtn.Size = V2_new(b1x, by), V2_new(wbw, bh)
        wpSetBtn.Transparency = hov1 and BTN_HOVER_ALPHA or BTN_ALPHA
        wpSetTxt.Position = V2_new(b1x + wbw/2, by + 4)
        
        wpGoBtn.Position, wpGoBtn.Size = V2_new(b2x, by), V2_new(wbw, bh)
        wpGoBtn.Transparency = hov2 and BTN_HOVER_ALPHA or BTN_ALPHA
        
        wpGoTxt.Text = flyLoop and "Stop Fly" or "Tween WP"
        wpGoTxt.Color = flyLoop and RED or (savedWaypoint and GREEN or C3_rgb(255, 255, 255))
        wpGoTxt.Position = V2_new(b2x + wbw/2, by + 4)
        
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

    local c = 0
    if st.lbl then
        for _, t in ipairs(list) do
            if c >= #labels then break end
            local ok, pos = pcall(function() return t.root.Position end)
            if ok and pos then
                local targetPos = V3_new(pos.X, pos.Y + 2.8, pos.Z)
                local sc, vis = nil, false
                
                local success = pcall(function()
                    if type(WorldToScreen) == "function" then
                        sc, vis = WorldToScreen(targetPos)
                    else
                        sc, vis = workspace.CurrentCamera:WorldToViewportPoint(targetPos)
                    end
                end)
                
                if success and sc then
                    if typeof(sc) == "Vector3" then 
                        vis = sc.Z > 0 
                        sc = V2_new(sc.X, sc.Y) 
                    end 
                    
                    if vis then
                        c = c + 1
                        labels[c].Text = t.name .. " | " .. fmt(t.luck)
                        labels[c].Color = (t.luck >= NOTIFY_MIN) and GOLD or C3_rgb(255, 255, 255)
                        labels[c].Position = sc
                        labels[c].Visible = true
                    end
                end
            end
        end
    end
    for i = c + 1, #labels do labels[i].Visible = false end
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

notify("R:6_cozy", "Auto feature removed successfully!", 5)
