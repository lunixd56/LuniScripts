local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

-- ============================================================
-- CONSTANTS & COLORS
-- ============================================================
local LINE_HEIGHT    = 20
local CROSS_COOLDOWN = 2
local HEADER_H       = 28
local SCAN_INTERVAL  = 0.25

local GATE_COLORS = {
	start   = Color3.fromRGB(255, 255, 255),
	s2      = Color3.fromRGB(80,  200, 255),
	s3      = Color3.fromRGB(255, 140, 30),
	pit     = Color3.fromRGB(60,  220, 100),
	pitExit = Color3.fromRGB(220, 80,  60),
	cc      = Color3.fromRGB(255,  60, 200),
}
local GATE_LABELS = {
	start   = "🏁  START / FINISH",
	s2      = "〔S2〕 SECTOR 2",
	s3      = "〔S3〕 SECTOR 3",
	pit     = "🔧  PIT ENTRY",
	pitExit = "🚪  PIT EXIT",
	cc      = "✂️   CUT CORNER",
}

local PURPLE = Color3.fromRGB(200, 80, 255)
local GREEN  = Color3.fromRGB(80, 220, 120)
local YELLOW = Color3.fromRGB(255, 220, 60)

-- ============================================================
-- STATE
-- ============================================================
local gates = {
	start = { part=nil, p1=nil, p2=nil, preview=nil },
	s2    = { part=nil, p1=nil, p2=nil, preview=nil },
	s3    = { part=nil, p1=nil, p2=nil, preview=nil },
	pit   = { part=nil, p1=nil, p2=nil, preview=nil },
	pitExit = { part=nil, p1=nil, p2=nil, preview=nil },
}
-- Multiple CC gates: list of { part, p1, p2, preview }
local ccGates = {}
local activeCCGate = nil    -- FIX #2: tracks the CC gate currently being placed
local pitSpeedOffset = -30   -- speed REDUCTION inside pitlane (negative = slower)
local playerNicknames = {}   -- [uidStr] = "nickname string"

local placingGate = nil
local placingStep = 0
local clickConn   = nil

local lapCount   = 0
local targetLaps = 3
local isFinished = false

local playerData     = {}
local latestSnapshot = playerData

local lastScan      = 0
local lastLBRefresh = 0

local sessionBests = { s1=math.huge, s2=math.huge, s3=math.huge, lap=math.huge }

local spectatingPlayer = nil

local qualiActive  = false
local qualiEndTime = 0

-- Overheads & Limits
local showOverheads = true
local maxSpeedLimit = 250
local maxDriftLimit = 1.0
local playerLimits  = {}   -- [uidStr] = { speed=N, drift=N }

-- Pit box target (global default)
local targetBoxes = 3

-- Infraction log
local infractionLog = {}
local MAX_LOG = 200
local rebuildLogs  -- forward declare so addLog can call it
local function addLog(plrName, kind, value)
	table.insert(infractionLog, 1, { timestamp=os.date("%H:%M:%S"), name=plrName, kind=kind, value=value })
	if #infractionLog > MAX_LOG then table.remove(infractionLog) end
	if rebuildLogs then rebuildLogs() end   -- live-update if popup is open
end

-- Per-player notify cooldowns
local notifyCooldowns = {}
local function notify(msg, uid)
	local key = uid or "global"
	if time() - (notifyCooldowns[key] or 0) < 3 then return end
	notifyCooldowns[key] = time()
	StarterGui:SetCore("SendNotification", { Title="🚨 INFRACTION", Text=msg, Duration=5 })
end

-- ============================================================
-- GUI ROOT
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name, screenGui.ResetOnSpawn, screenGui.ZIndexBehavior =
	"RaceLineGUI", false, Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ============================================================
-- STYLE HELPERS
-- ============================================================
local function applyCorner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0,8)
	c.Parent = inst
end
local function applyStroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = color, thickness or 1, transparency or 0.65
	s.Parent = inst
end
local function makeLabel(parent, text, size, pos, fontSize, color, bold, zIndex)
	local l = Instance.new("TextLabel")
	l.Text, l.Size, l.Position = text, size, pos
	l.BackgroundTransparency = 1
	l.TextColor3  = color or Color3.fromRGB(230,230,230)
	l.TextSize    = fontSize or 14
	l.Font        = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Center
	if zIndex then l.ZIndex = zIndex end
	l.Parent = parent
	return l
end
local function makeButton(parent, text, size, pos, bgColor, textColor, zIndex)
	local b = Instance.new("TextButton")
	b.Text, b.Size, b.Position = text, size, pos
	b.BackgroundColor3 = bgColor or Color3.fromRGB(60,120,255)
	b.TextColor3       = textColor or Color3.fromRGB(255,255,255)
	b.TextSize, b.Font, b.BorderSizePixel, b.AutoButtonColor = 12, Enum.Font.GothamBold, 0, true
	if zIndex then b.ZIndex = zIndex end
	b.Parent = parent
	applyCorner(b, UDim.new(0,6))
	return b
end
local function formatTime(seconds)
	if seconds == math.huge or not seconds then return "—" end
	return string.format("%02d:%06.3f", math.floor(seconds/60), seconds%60)
end

-- ============================================================
-- PANEL FACTORY  (draggable + minimizable)
-- ============================================================
local function makePanel(startPos, w, h, accentColor, title, autoY)
	local outer = Instance.new("Frame")
	outer.Size, outer.Position = UDim2.new(0,w,0,h), startPos
	outer.BackgroundColor3, outer.BackgroundTransparency = Color3.fromRGB(14,14,20), 0.08
	outer.BorderSizePixel, outer.ClipsDescendants = 0, true
	outer.Parent = screenGui
	applyCorner(outer); applyStroke(outer, accentColor, 1, 0.65)

	local bar = Instance.new("Frame")
	bar.Size, bar.BackgroundColor3, bar.BorderSizePixel, bar.ZIndex = UDim2.new(1,0,0,HEADER_H), accentColor, 0, 2
	bar.Parent = outer; applyCorner(bar, UDim.new(0,8))

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size, titleLbl.Position = UDim2.new(1,-34,1,0), UDim2.new(0,8,0,0)
	titleLbl.BackgroundTransparency, titleLbl.Text = 1, title
	titleLbl.TextColor3 = Color3.fromRGB(10,10,18)
	titleLbl.TextSize, titleLbl.Font = 12, Enum.Font.GothamBold
	titleLbl.TextXAlignment, titleLbl.ZIndex = Enum.TextXAlignment.Left, 3
	titleLbl.Parent = bar

	local minBtn = Instance.new("TextButton")
	minBtn.Size, minBtn.Position = UDim2.new(0,22,0,22), UDim2.new(1,-25,0.5,-11)
	minBtn.BackgroundTransparency, minBtn.Text = 1, "▼"
	minBtn.TextColor3, minBtn.TextSize = Color3.fromRGB(10,10,18), 13
	minBtn.Font, minBtn.BorderSizePixel, minBtn.ZIndex = Enum.Font.GothamBold, 0, 4
	minBtn.Parent = bar

	local body = Instance.new("Frame")
	body.Size, body.Position = UDim2.new(1,0,1,-HEADER_H), UDim2.new(0,0,0,HEADER_H)
	body.BackgroundTransparency, body.BorderSizePixel = 1, 0
	body.Parent = outer

	if autoY then outer.AutomaticSize, body.AutomaticSize = Enum.AutomaticSize.Y, Enum.AutomaticSize.Y end

	local minimized = false
	local fixedSize, collapsedSz = UDim2.new(0,w,0,h), UDim2.new(0,w,0,HEADER_H)

	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		if minimized then
			if autoY then
				fixedSize = UDim2.new(0,w,0,outer.AbsoluteSize.Y)
				outer.AutomaticSize, body.AutomaticSize = Enum.AutomaticSize.None, Enum.AutomaticSize.None
			end
			outer.Size, body.Visible = collapsedSz, false
		else
			body.Visible = true
			if autoY then outer.AutomaticSize, body.AutomaticSize = Enum.AutomaticSize.Y, Enum.AutomaticSize.Y
			else outer.Size = fixedSize end
		end
		minBtn.Text = minimized and "▲" or "▼"
	end)

	local dragging, dragStart, origPos
	bar.InputBegan:Connect(function(inp)
		-- FIX #7: support both mouse and touch drag
		if inp.UserInputType == Enum.UserInputType.MouseButton1
		or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = Vector2.new(inp.Position.X, inp.Position.Y)
			origPos   = Vector2.new(outer.Position.X.Offset, outer.Position.Y.Offset)
		end
	end)
	bar.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
		or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
		or inp.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStart
			outer.Position = UDim2.new(0, origPos.X+d.X, 0, origPos.Y+d.Y)
		end
	end)
	return outer, body
end

-- ============================================================
-- TOP CENTER QUALIFYING TIMER
-- ============================================================
local qualiUI = Instance.new("Frame")
qualiUI.Size, qualiUI.Position = UDim2.new(0,300,0,40), UDim2.new(0.5,-150,0,20)
qualiUI.BackgroundColor3, qualiUI.BackgroundTransparency = Color3.fromRGB(0,0,0), 0.7
qualiUI.BorderSizePixel, qualiUI.Visible = 0, false
qualiUI.Parent = screenGui; applyCorner(qualiUI, UDim.new(0,6))
local qualiLabel = makeLabel(qualiUI, "QUALIFYING - 00:00.000", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), 18, Color3.fromRGB(255,255,255), true)

-- ============================================================
-- SPECTATE STOP BUTTON
-- ============================================================
local spectateUI = Instance.new("TextButton")
spectateUI.Size, spectateUI.Position = UDim2.new(0,220,0,30), UDim2.new(0.5,-110,0,65)
spectateUI.BackgroundColor3 = Color3.fromRGB(200,40,40)
spectateUI.Text, spectateUI.TextColor3 = "Stop Spectating", Color3.fromRGB(255,255,255)
spectateUI.Font, spectateUI.Visible = Enum.Font.GothamBold, false
spectateUI.Parent = screenGui; applyCorner(spectateUI)
spectateUI.MouseButton1Click:Connect(function()
	workspace.CurrentCamera.CameraSubject = player.Character:WaitForChild("Humanoid")
	spectatingPlayer, spectateUI.Visible = nil, false
end)

-- ============================================================
-- FRAME 1 – GATE PLACER
-- ============================================================
local setStatus
local _, f1Body = makePanel(UDim2.new(0,16,0,16), 234, 226, Color3.fromRGB(255,200,0), "🏁  GATE PLACER", false)
local statusLabel = makeLabel(f1Body, "Place gates.", UDim2.new(1,-16,0,34), UDim2.new(0,8,0,4), 12, Color3.fromRGB(180,180,200))
statusLabel.TextWrapped = true
setStatus = function(text, color)
	statusLabel.Text, statusLabel.TextColor3 = text, color or Color3.fromRGB(180,180,200)
end

local ROW_Y = { start=44, s2=90, s3=136 }
local addBtns, removeBtns = {}, {}
for _, key in ipairs({"start","s2","s3"}) do
	local lbl = makeLabel(f1Body, ({start="START/FINISH",s2="SECTOR 2",s3="SECTOR 3"})[key],
		UDim2.new(1,-16,0,14), UDim2.new(0,8,0,ROW_Y[key]-2), 10, GATE_COLORS[key], true)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	addBtns[key]    = makeButton(f1Body, "➕ ADD", UDim2.new(0.5,-6,0,26), UDim2.new(0,6,0,ROW_Y[key]+14), Color3.fromRGB(30,160,70))
	removeBtns[key] = makeButton(f1Body, "🗑",     UDim2.new(0.5,-6,0,26), UDim2.new(0.5,0,0,ROW_Y[key]+14), Color3.fromRGB(180,40,40))
end
local removeAllBtn = makeButton(f1Body, "🗑  REMOVE ALL", UDim2.new(1,-16,0,26), UDim2.new(0,8,0,186), Color3.fromRGB(120,30,30))

-- ============================================================
-- FRAME 2 – LAP COUNTER
-- ============================================================
local _, f2Body     = makePanel(UDim2.new(0,16,0,176), 234, 180, Color3.fromRGB(80,160,255), "🚗  LAP COUNTER", false)
local lapLabel      = makeLabel(f2Body, "Laps: 0 / 3",   UDim2.new(1,-16,0,28), UDim2.new(0,8,0,4),  22, Color3.fromRGB(255,255,255), true)
local sectorLabel   = makeLabel(f2Body, "Sector: —",     UDim2.new(1,-16,0,18), UDim2.new(0,8,0,36), 12, Color3.fromRGB(160,220,255))
local deltaLabel    = makeLabel(f2Body, "Delta: —",      UDim2.new(1,-16,0,18), UDim2.new(0,8,0,54), 14, Color3.fromRGB(200,200,200), true)
local finishedLabel = makeLabel(f2Body, "",              UDim2.new(1,-16,0,18), UDim2.new(0,8,0,76), 12, Color3.fromRGB(255,220,60), true)
local changeLapsBtn = makeButton(f2Body, "⚙ Laps Target", UDim2.new(0.5,-6,0,26), UDim2.new(0,8,0,106), Color3.fromRGB(50,80,160))
local redoBtn       = makeButton(f2Body, "🔄 Reset",       UDim2.new(0.5,-6,0,26), UDim2.new(0.5,2,0,106), Color3.fromRGB(160,100,20))

-- Lap Target Popup
local lapPopup = Instance.new("Frame")
lapPopup.Size, lapPopup.Position = UDim2.new(0,210,0,120), UDim2.new(0.5,-105,0.5,-60)
lapPopup.BackgroundColor3, lapPopup.BackgroundTransparency = Color3.fromRGB(10,10,18), 0
lapPopup.BorderSizePixel, lapPopup.Visible, lapPopup.ZIndex = 0, false, 30
lapPopup.Parent = screenGui; applyCorner(lapPopup); applyStroke(lapPopup, Color3.fromRGB(80,160,255), 1.5, 0)
makeLabel(lapPopup, "Set Lap Target", UDim2.new(1,0,0,28), UDim2.new(0,0,0,4), 14, Color3.fromRGB(255,255,255), true, 31)
local lapInputBox = Instance.new("TextBox")
lapInputBox.Size, lapInputBox.Position = UDim2.new(1,-24,0,32), UDim2.new(0,12,0,36)
lapInputBox.BackgroundColor3, lapInputBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
lapInputBox.PlaceholderText, lapInputBox.Text = "Enter laps (1–99)", tostring(targetLaps)
lapInputBox.TextSize, lapInputBox.Font, lapInputBox.BorderSizePixel, lapInputBox.ZIndex = 14, Enum.Font.GothamBold, 0, 31
lapInputBox.Parent = lapPopup; applyCorner(lapInputBox, UDim.new(0,6))
local lapConfirmBtn = makeButton(lapPopup, "✔ Confirm", UDim2.new(0.5,-6,0,28), UDim2.new(0,6,0,80), Color3.fromRGB(30,180,80), nil, 31)
local lapCancelBtn  = makeButton(lapPopup, "✖ Cancel",  UDim2.new(0.5,-6,0,28), UDim2.new(0.5,0,0,80), Color3.fromRGB(180,50,50), nil, 31)
changeLapsBtn.MouseButton1Click:Connect(function() lapInputBox.Text=tostring(targetLaps); lapPopup.Visible=true end)
lapConfirmBtn.MouseButton1Click:Connect(function()
	local val = tonumber(lapInputBox.Text)
	if val and val>=1 and val<=99 then targetLaps=math.floor(val); lapPopup.Visible=false
	else lapInputBox.Text="1–99 only!" end
end)
lapCancelBtn.MouseButton1Click:Connect(function() lapPopup.Visible=false end)

-- ============================================================
-- ADD LAPS POPUP
-- ============================================================
local addLapsPopup = Instance.new("Frame")
addLapsPopup.Size, addLapsPopup.Position = UDim2.new(0,220,0,130), UDim2.new(0.5,-110,0.5,-65)
addLapsPopup.BackgroundColor3, addLapsPopup.BackgroundTransparency = Color3.fromRGB(10,10,18), 0
addLapsPopup.BorderSizePixel, addLapsPopup.Visible, addLapsPopup.ZIndex = 0, false, 30
addLapsPopup.Parent = screenGui; applyCorner(addLapsPopup); applyStroke(addLapsPopup, Color3.fromRGB(80,220,120), 1.5, 0)
local addLapsTitleLbl  = makeLabel(addLapsPopup, "Add Laps to Player", UDim2.new(1,0,0,28), UDim2.new(0,0,0,4), 13, Color3.fromRGB(255,255,255), true, 31)
local addLapsPlayerLbl = makeLabel(addLapsPopup, "", UDim2.new(1,-24,0,16), UDim2.new(0,12,0,30), 11, Color3.fromRGB(180,220,255), false, 31)
local addLapsInputBox = Instance.new("TextBox")
addLapsInputBox.Size, addLapsInputBox.Position = UDim2.new(1,-24,0,30), UDim2.new(0,12,0,50)
addLapsInputBox.BackgroundColor3, addLapsInputBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
addLapsInputBox.PlaceholderText, addLapsInputBox.Text = "Laps to add (e.g. 1)", "1"
addLapsInputBox.TextSize, addLapsInputBox.Font, addLapsInputBox.BorderSizePixel, addLapsInputBox.ZIndex = 14, Enum.Font.GothamBold, 0, 31
addLapsInputBox.Parent = addLapsPopup; applyCorner(addLapsInputBox, UDim.new(0,6))
local addLapsConfirmBtn = makeButton(addLapsPopup, "✔ Add",    UDim2.new(0.5,-6,0,28), UDim2.new(0,6,0,92), Color3.fromRGB(30,180,80), nil, 31)
local addLapsCancelBtn  = makeButton(addLapsPopup, "✖ Cancel", UDim2.new(0.5,-6,0,28), UDim2.new(0.5,0,0,92), Color3.fromRGB(180,50,50), nil, 31)
local addLapsTargetUid = nil
addLapsCancelBtn.MouseButton1Click:Connect(function() addLapsPopup.Visible=false; addLapsTargetUid=nil end)
addLapsConfirmBtn.MouseButton1Click:Connect(function()
	local val = tonumber(addLapsInputBox.Text)
	if val and addLapsTargetUid and playerData[addLapsTargetUid] then
		playerData[addLapsTargetUid].lap = math.max(0, playerData[addLapsTargetUid].lap + math.floor(val))
	else addLapsInputBox.Text="Enter a number!"; return end
	addLapsPopup.Visible=false; addLapsTargetUid=nil
end)

-- ============================================================
-- RIGHT-CLICK PLAYER CONTEXT POPUP
-- Opens when right-clicking any leaderboard row
-- Replaces the ⚙ inline button (which was overlapping gap text)
-- ============================================================
local ctxPopup = Instance.new("Frame")
ctxPopup.Size, ctxPopup.Position = UDim2.new(0,260,0,340), UDim2.new(0.5,-130,0.5,-170)
ctxPopup.BackgroundColor3, ctxPopup.BackgroundTransparency = Color3.fromRGB(10,10,18), 0
ctxPopup.BorderSizePixel, ctxPopup.Visible, ctxPopup.ZIndex = 0, false, 35
ctxPopup.Parent = screenGui; applyCorner(ctxPopup); applyStroke(ctxPopup, Color3.fromRGB(255,200,0), 1.5, 0)

local ctxTitle   = makeLabel(ctxPopup, "Player Settings", UDim2.new(1,-40,0,26), UDim2.new(0,0,0,2), 13, Color3.fromRGB(255,255,255), true, 36)
local ctxNameLbl = makeLabel(ctxPopup, "", UDim2.new(1,-16,0,16), UDim2.new(0,8,0,28), 11, Color3.fromRGB(180,220,255), false, 36)
local ctxCloseBtn = makeButton(ctxPopup, "✖", UDim2.new(0,26,0,22), UDim2.new(1,-30,0,3), Color3.fromRGB(180,40,40), nil, 36)

-- Nickname
makeLabel(ctxPopup, "Nickname (blank = real name)", UDim2.new(1,-16,0,14), UDim2.new(0,8,0,48), 10, Color3.fromRGB(160,160,180), false, 36).TextXAlignment = Enum.TextXAlignment.Left
local ctxNickBox = Instance.new("TextBox")
ctxNickBox.Size, ctxNickBox.Position = UDim2.new(1,-16,0,26), UDim2.new(0,8,0,64)
ctxNickBox.BackgroundColor3, ctxNickBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
ctxNickBox.PlaceholderText, ctxNickBox.Text = "e.g. Fulano - Williams", ""
ctxNickBox.TextSize, ctxNickBox.Font, ctxNickBox.BorderSizePixel, ctxNickBox.ZIndex = 12, Enum.Font.GothamBold, 0, 36
ctxNickBox.Parent = ctxPopup; applyCorner(ctxNickBox, UDim.new(0,5))

-- Speed limit
makeLabel(ctxPopup, "Speed Limit", UDim2.new(1,-16,0,14), UDim2.new(0,8,0,94), 10, Color3.fromRGB(160,160,180), false, 36).TextXAlignment = Enum.TextXAlignment.Left
local ctxSpeedBox = Instance.new("TextBox")
ctxSpeedBox.Size, ctxSpeedBox.Position = UDim2.new(1,-16,0,26), UDim2.new(0,8,0,110)
ctxSpeedBox.BackgroundColor3, ctxSpeedBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
ctxSpeedBox.PlaceholderText, ctxSpeedBox.Text = "Max Speed (global default)", ""
ctxSpeedBox.TextSize, ctxSpeedBox.Font, ctxSpeedBox.BorderSizePixel, ctxSpeedBox.ZIndex = 12, Enum.Font.GothamBold, 0, 36
ctxSpeedBox.Parent = ctxPopup; applyCorner(ctxSpeedBox, UDim.new(0,5))

-- Friction limit
makeLabel(ctxPopup, "Friction Limit", UDim2.new(1,-16,0,14), UDim2.new(0,8,0,140), 10, Color3.fromRGB(160,160,180), false, 36).TextXAlignment = Enum.TextXAlignment.Left
local ctxDriftBox = Instance.new("TextBox")
ctxDriftBox.Size, ctxDriftBox.Position = UDim2.new(1,-16,0,26), UDim2.new(0,8,0,156)
ctxDriftBox.BackgroundColor3, ctxDriftBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
ctxDriftBox.PlaceholderText, ctxDriftBox.Text = "Friction limit (global default)", ""
ctxDriftBox.TextSize, ctxDriftBox.Font, ctxDriftBox.BorderSizePixel, ctxDriftBox.ZIndex = 12, Enum.Font.GothamBold, 0, 36
ctxDriftBox.Parent = ctxPopup; applyCorner(ctxDriftBox, UDim.new(0,5))

-- Target boxes
makeLabel(ctxPopup, "Target Boxes", UDim2.new(1,-16,0,14), UDim2.new(0,8,0,186), 10, Color3.fromRGB(160,160,180), false, 36).TextXAlignment = Enum.TextXAlignment.Left
local ctxBoxesBox = Instance.new("TextBox")
ctxBoxesBox.Size, ctxBoxesBox.Position = UDim2.new(1,-16,0,26), UDim2.new(0,8,0,202)
ctxBoxesBox.BackgroundColor3, ctxBoxesBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
ctxBoxesBox.PlaceholderText, ctxBoxesBox.Text = "Target pit stops (global default)", ""
ctxBoxesBox.TextSize, ctxBoxesBox.Font, ctxBoxesBox.BorderSizePixel, ctxBoxesBox.ZIndex = 12, Enum.Font.GothamBold, 0, 36
ctxBoxesBox.Parent = ctxPopup; applyCorner(ctxBoxesBox, UDim.new(0,5))

local ctxApplyBtn    = makeButton(ctxPopup, "✔ Apply",         UDim2.new(1,-16,0,26), UDim2.new(0,8,0,234), Color3.fromRGB(30,180,80),  nil, 36)
local ctxResetBoxBtn = makeButton(ctxPopup, "🔄 Boxes",        UDim2.new(0.33,-4,0,24), UDim2.new(0,8,0,266), Color3.fromRGB(60,110,60), nil, 36)
local ctxResetCCBtn  = makeButton(ctxPopup, "🔄 CC",           UDim2.new(0.33,-4,0,24), UDim2.new(0.33,-2,0,266), Color3.fromRGB(110,40,110), nil, 36)
local ctxClearLimBtn = makeButton(ctxPopup, "↩ Global",        UDim2.new(0.34,-4,0,24), UDim2.new(0.66,-2,0,266), Color3.fromRGB(50,50,70), nil, 36)

local ctxTargetUid = nil

ctxCloseBtn.MouseButton1Click:Connect(function() ctxPopup.Visible=false end)
ctxApplyBtn.MouseButton1Click:Connect(function()
	if not ctxTargetUid then ctxPopup.Visible=false; return end
	-- Save nickname (blank = clear)
	local nick = ctxNickBox.Text:match("^%s*(.-)%s*$")
	if nick and nick ~= "" then
		playerNicknames[ctxTargetUid] = nick
	else
		playerNicknames[ctxTargetUid] = nil
	end
	-- Save limits
	local s, d, b = tonumber(ctxSpeedBox.Text), tonumber(ctxDriftBox.Text), tonumber(ctxBoxesBox.Text)
	if s or d then
		playerLimits[ctxTargetUid] = playerLimits[ctxTargetUid] or {}
		if s then playerLimits[ctxTargetUid].speed = s end
		if d then playerLimits[ctxTargetUid].drift = d end
	end
	if b and playerData[ctxTargetUid] then playerData[ctxTargetUid].targetBoxes = math.floor(b) end
	ctxPopup.Visible=false
end)
ctxClearLimBtn.MouseButton1Click:Connect(function()
	if ctxTargetUid then
		playerLimits[ctxTargetUid] = nil
		if playerData[ctxTargetUid] then playerData[ctxTargetUid].targetBoxes = nil end
	end
	ctxPopup.Visible=false
end)
ctxResetBoxBtn.MouseButton1Click:Connect(function()
	if ctxTargetUid and playerData[ctxTargetUid] then
		playerData[ctxTargetUid].boxes=0; playerData[ctxTargetUid].lastBoxSide=nil; playerData[ctxTargetUid].lastBoxCross=0
	end; ctxPopup.Visible=false
end)
ctxResetCCBtn.MouseButton1Click:Connect(function()
	if ctxTargetUid and playerData[ctxTargetUid] then
		playerData[ctxTargetUid].ccs=0; playerData[ctxTargetUid].ccLastSide={}; playerData[ctxTargetUid].ccLastCross={}
	end; ctxPopup.Visible=false
end)

-- ============================================================
-- FRAME 3 – STANDINGS
-- ============================================================
local _, f3Body = makePanel(UDim2.new(0,16,0,16), 260, 38, Color3.fromRGB(220,80,80), "🏆  STANDINGS  (L-click: Spectate | R-click: Settings)", true)

local f3layout = Instance.new("UIListLayout")
f3layout.Padding, f3layout.SortOrder, f3layout.Parent = UDim.new(0,2), Enum.SortOrder.LayoutOrder, f3Body

local gapMode = "leader"
local gapToggleRow = Instance.new("Frame")
gapToggleRow.Size, gapToggleRow.BackgroundTransparency = UDim2.new(1,0,0,28), 1
gapToggleRow.LayoutOrder, gapToggleRow.Parent = 0, f3Body

local gapToLeaderBtn = makeButton(gapToggleRow,"▶ Gap to P1",  UDim2.new(0.5,-3,1,-24), UDim2.new(0,6,0,2), Color3.fromRGB(40,100,200))
local gapToAheadBtn  = makeButton(gapToggleRow,"Gap to Ahead", UDim2.new(0.5,-3,1,-24), UDim2.new(0.5,-3,0,2), Color3.fromRGB(50,50,70))

local function updateGapToggle()
	if gapMode == "leader" then
		gapToLeaderBtn.BackgroundColor3, gapToLeaderBtn.Text = Color3.fromRGB(40,100,220), "▶ Gap to P1"
		gapToAheadBtn.BackgroundColor3,  gapToAheadBtn.Text  = Color3.fromRGB(50,50,70),  "Gap to Ahead"
	else
		gapToLeaderBtn.BackgroundColor3, gapToLeaderBtn.Text = Color3.fromRGB(50,50,70),  "Gap to P1"
		gapToAheadBtn.BackgroundColor3,  gapToAheadBtn.Text  = Color3.fromRGB(40,100,220),"▶ Gap to Ahead"
	end
end
gapToLeaderBtn.MouseButton1Click:Connect(function() gapMode="leader"; updateGapToggle() end)
gapToAheadBtn.MouseButton1Click:Connect(function()  gapMode="ahead";  updateGapToggle() end)
updateGapToggle()

local leaderContainer = Instance.new("Frame")
leaderContainer.Name, leaderContainer.Size = "LeaderContainer", UDim2.new(1,0,0,0)
leaderContainer.BackgroundTransparency, leaderContainer.AutomaticSize = 1, Enum.AutomaticSize.Y
leaderContainer.LayoutOrder, leaderContainer.Parent = 1, f3Body
local llayout = Instance.new("UIListLayout")
llayout.Padding, llayout.SortOrder, llayout.Parent = UDim.new(0,2), Enum.SortOrder.LayoutOrder, leaderContainer
local lpad = Instance.new("UIPadding")
lpad.PaddingTop, lpad.PaddingBottom = UDim.new(0,4), UDim.new(0,2)
lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0,6), UDim.new(0,6)
lpad.Parent = leaderContainer

local resetStandingsBtn = makeButton(f3Body, "🗑 RESET ALL", UDim2.new(1,-12,0,26), UDim2.new(0,6,0,0), Color3.fromRGB(180,40,40))
resetStandingsBtn.LayoutOrder = 2
local rsPad = Instance.new("UIPadding")
rsPad.PaddingLeft, rsPad.PaddingRight, rsPad.PaddingBottom = UDim.new(0,6), UDim.new(0,6), UDim.new(0,4)
rsPad.Parent = resetStandingsBtn

-- ============================================================
-- FRAME 4 – FASTEST LAPS & QUALI
-- ============================================================
local _, f4Body = makePanel(UDim2.new(0,16,0,64), 234, 38, Color3.fromRGB(180,60,220), "⏱  FASTEST LAPS & QUALI", true)
local qualiInputBox = Instance.new("TextBox")
qualiInputBox.Size, qualiInputBox.Position = UDim2.new(0.5,-6,0,26), UDim2.new(0,6,0,6)
qualiInputBox.BackgroundColor3, qualiInputBox.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
qualiInputBox.PlaceholderText, qualiInputBox.Text = "Mins (e.g. 15)", ""
qualiInputBox.Font, qualiInputBox.Parent = Enum.Font.Gotham, f4Body; applyCorner(qualiInputBox, UDim.new(0,4))
local startQualiBtn = makeButton(f4Body, "▶ Start Quali", UDim2.new(0.5,-8,0,26), UDim2.new(0.5,2,0,6), Color3.fromRGB(100,30,160))
local fastestContainer = Instance.new("Frame")
fastestContainer.Size, fastestContainer.Position = UDim2.new(1,0,1,-34), UDim2.new(0,0,0,36)
fastestContainer.BackgroundTransparency, fastestContainer.AutomaticSize = 1, Enum.AutomaticSize.Y
fastestContainer.Parent = f4Body
local flayout = Instance.new("UIListLayout")
flayout.Padding, flayout.SortOrder, flayout.Parent = UDim.new(0,2), Enum.SortOrder.LayoutOrder, fastestContainer
local fpad = Instance.new("UIPadding")
fpad.PaddingTop, fpad.PaddingBottom = UDim.new(0,4), UDim.new(0,4)
fpad.PaddingLeft, fpad.PaddingRight = UDim.new(0,6), UDim.new(0,6); fpad.Parent = fastestContainer

-- ============================================================
-- FRAME 5 – SPEED AND DRIFT CONTROL
-- ============================================================
local _, f5Body = makePanel(UDim2.new(0,260,0,16), 234, 210, Color3.fromRGB(220,120,20), "🛡️  SPEED AND DRIFT CONTROL", false)
local speedLimInput = Instance.new("TextBox")
speedLimInput.Size, speedLimInput.Position = UDim2.new(1,-12,0,26), UDim2.new(0,6,0,6)
speedLimInput.BackgroundColor3, speedLimInput.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
speedLimInput.PlaceholderText, speedLimInput.Text = "Max Speed Limit", tostring(maxSpeedLimit)
speedLimInput.Parent = f5Body; applyCorner(speedLimInput)
local driftLimInput = Instance.new("TextBox")
driftLimInput.Size, driftLimInput.Position = UDim2.new(1,-12,0,26), UDim2.new(0,6,0,36)
driftLimInput.BackgroundColor3, driftLimInput.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
driftLimInput.PlaceholderText, driftLimInput.Text = "Max Friction Limit", tostring(maxDriftLimit)
driftLimInput.Parent = f5Body; applyCorner(driftLimInput)
local toggleOverheadsBtn = makeButton(f5Body, "Toggle Overheads: ON", UDim2.new(1,-12,0,26), UDim2.new(0,6,0,70), Color3.fromRGB(40,160,100))
local showLogsBtn        = makeButton(f5Body, "📋 View Logs",         UDim2.new(1,-12,0,26), UDim2.new(0,6,0,100), Color3.fromRGB(40,80,160))
speedLimInput.FocusLost:Connect(function() maxSpeedLimit=tonumber(speedLimInput.Text) or maxSpeedLimit; speedLimInput.Text=tostring(maxSpeedLimit) end)
driftLimInput.FocusLost:Connect(function() maxDriftLimit=tonumber(driftLimInput.Text) or maxDriftLimit; driftLimInput.Text=tostring(maxDriftLimit) end)
toggleOverheadsBtn.MouseButton1Click:Connect(function()
	showOverheads = not showOverheads
	toggleOverheadsBtn.Text = "Toggle Overheads: "..(showOverheads and "ON" or "OFF")
	toggleOverheadsBtn.BackgroundColor3 = showOverheads and Color3.fromRGB(40,160,100) or Color3.fromRGB(160,40,40)
end)

-- ============================================================
-- LOGS POPUP
-- ============================================================
local logsPopup = Instance.new("Frame")
logsPopup.Size, logsPopup.Position = UDim2.new(0,320,0,340), UDim2.new(0.5,-160,0.5,-170)
logsPopup.BackgroundColor3, logsPopup.BackgroundTransparency = Color3.fromRGB(10,10,18), 0
logsPopup.BorderSizePixel, logsPopup.Visible, logsPopup.ZIndex = 0, false, 40
logsPopup.Parent = screenGui; applyCorner(logsPopup); applyStroke(logsPopup, Color3.fromRGB(255,140,30), 1.5, 0)
makeLabel(logsPopup, "📋  INFRACTION LOGS", UDim2.new(1,-80,0,28), UDim2.new(0,0,0,0), 13, Color3.fromRGB(255,200,80), true, 41)
local logsCloseBtn = makeButton(logsPopup, "✖",       UDim2.new(0,26,0,22), UDim2.new(1,-30,0,3), Color3.fromRGB(180,40,40), nil, 41)
local logsClearBtn = makeButton(logsPopup, "🗑 Clear", UDim2.new(0,70,0,22), UDim2.new(1,-104,0,3), Color3.fromRGB(80,30,30), nil, 41)
local logsScroll = Instance.new("ScrollingFrame")
logsScroll.Size, logsScroll.Position = UDim2.new(1,-12,0,290), UDim2.new(0,6,0,32)
logsScroll.BackgroundTransparency, logsScroll.BorderSizePixel = 1, 0
logsScroll.ScrollBarThickness, logsScroll.ScrollBarImageColor3 = 4, Color3.fromRGB(255,140,30)
logsScroll.CanvasSize, logsScroll.AutomaticCanvasSize, logsScroll.ZIndex = UDim2.new(0,0,0,0), Enum.AutomaticSize.Y, 41
logsScroll.Parent = logsPopup
local logsLayout = Instance.new("UIListLayout")
logsLayout.Padding, logsLayout.SortOrder, logsLayout.Parent = UDim.new(0,2), Enum.SortOrder.LayoutOrder, logsScroll

local function buildLogsUI()
	for _, c in ipairs(logsScroll:GetChildren()) do if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end end
	if #infractionLog == 0 then
		local e = makeLabel(logsScroll,"No infractions logged.",UDim2.new(1,0,0,28),UDim2.new(0,0,0,0),11,Color3.fromRGB(120,120,140),false,42)
		e.LayoutOrder=1; return
	end
	for i, entry in ipairs(infractionLog) do
		local kindColor
		if entry.kind == "Speed" then kindColor = Color3.fromRGB(255,100,100)
		elseif entry.kind == "Drift" then kindColor = Color3.fromRGB(255,220,60)
		elseif entry.kind == "PitSpeed" then kindColor = Color3.fromRGB(255,160,30)
		else kindColor = Color3.fromRGB(180,180,255) end
		local row = Instance.new("Frame")
		row.Size, row.BackgroundColor3 = UDim2.new(1,0,0,28), i%2==0 and Color3.fromRGB(20,20,28) or Color3.fromRGB(16,16,22)
		row.BackgroundTransparency, row.BorderSizePixel, row.LayoutOrder, row.ZIndex = 0.3, 0, i, 42
		row.Parent = logsScroll; applyCorner(row, UDim.new(0,4))
		local t = makeLabel(row,entry.timestamp,UDim2.new(0,52,1,0),UDim2.new(0,4,0,0),10,Color3.fromRGB(140,140,160),false,43); t.TextXAlignment=Enum.TextXAlignment.Left
		local n = makeLabel(row,entry.name,UDim2.new(1,-160,1,0),UDim2.new(0,58,0,0),10,Color3.fromRGB(210,210,210),true,43); n.TextXAlignment=Enum.TextXAlignment.Left
		local v = makeLabel(row,entry.kind..": "..tostring(entry.value),UDim2.new(0,84,1,0),UDim2.new(1,-88,0,0),10,kindColor,true,43); v.TextXAlignment=Enum.TextXAlignment.Right
	end
end
-- wire up forward declare so addLog can update the popup live
rebuildLogs = function()
	if logsPopup.Visible then buildLogsUI() end
end
showLogsBtn.MouseButton1Click:Connect(function() buildLogsUI(); logsPopup.Visible=true end)
logsCloseBtn.MouseButton1Click:Connect(function() logsPopup.Visible=false end)
logsClearBtn.MouseButton1Click:Connect(function() infractionLog={}; buildLogsUI() end)

-- ============================================================
-- FRAME 6 – PIT LANE & CC
-- ============================================================
local _, f6Body = makePanel(UDim2.new(0,260,0,244), 234, 270, Color3.fromRGB(60,220,100), "📦  PIT LANE & CC", false)

-- Global box target
makeLabel(f6Body,"Global Box Target:",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,4),10,Color3.fromRGB(160,255,160),true).TextXAlignment=Enum.TextXAlignment.Left
local boxTargetInput = Instance.new("TextBox")
boxTargetInput.Size, boxTargetInput.Position = UDim2.new(0.5,-6,0,24), UDim2.new(0,6,0,20)
boxTargetInput.BackgroundColor3, boxTargetInput.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
boxTargetInput.PlaceholderText, boxTargetInput.Text = "Pit stops target", tostring(targetBoxes)
boxTargetInput.TextSize, boxTargetInput.Font, boxTargetInput.BorderSizePixel = 12, Enum.Font.GothamBold, 0
boxTargetInput.Parent = f6Body; applyCorner(boxTargetInput, UDim.new(0,4))
boxTargetInput.FocusLost:Connect(function() targetBoxes=tonumber(boxTargetInput.Text) or targetBoxes; boxTargetInput.Text=tostring(targetBoxes) end)

-- Pit speed offset
makeLabel(f6Body,"Pit Speed Offset (e.g. -30):",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,50),10,Color3.fromRGB(255,200,100),true).TextXAlignment=Enum.TextXAlignment.Left
local pitSpeedInput = Instance.new("TextBox")
pitSpeedInput.Size, pitSpeedInput.Position = UDim2.new(0.5,-6,0,24), UDim2.new(0,6,0,66)
pitSpeedInput.BackgroundColor3, pitSpeedInput.TextColor3 = Color3.fromRGB(30,30,40), Color3.fromRGB(255,255,255)
pitSpeedInput.PlaceholderText, pitSpeedInput.Text = "-30", tostring(pitSpeedOffset)
pitSpeedInput.TextSize, pitSpeedInput.Font, pitSpeedInput.BorderSizePixel = 12, Enum.Font.GothamBold, 0
pitSpeedInput.Parent = f6Body; applyCorner(pitSpeedInput, UDim.new(0,4))
pitSpeedInput.FocusLost:Connect(function() pitSpeedOffset=tonumber(pitSpeedInput.Text) or pitSpeedOffset; pitSpeedInput.Text=tostring(pitSpeedOffset) end)

-- Pit entry gate
makeLabel(f6Body,"PIT ENTRY:",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,96),10,GATE_COLORS.pit,true).TextXAlignment=Enum.TextXAlignment.Left
local pitAddBtn = makeButton(f6Body,"➕ ADD",    UDim2.new(0.5,-3,0,24),UDim2.new(0,6,0,112),Color3.fromRGB(30,160,70))
local pitRemBtn = makeButton(f6Body,"🗑 REMOVE", UDim2.new(0.5,-3,0,24),UDim2.new(0.5,1,0,112),Color3.fromRGB(180,40,40))

-- Pit exit gate
makeLabel(f6Body,"PIT EXIT:",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,140),10,GATE_COLORS.pitExit,true).TextXAlignment=Enum.TextXAlignment.Left
local pitExitAddBtn = makeButton(f6Body,"➕ ADD",    UDim2.new(0.5,-3,0,24),UDim2.new(0,6,0,156),Color3.fromRGB(160,80,20))
local pitExitRemBtn = makeButton(f6Body,"🗑 REMOVE", UDim2.new(0.5,-3,0,24),UDim2.new(0.5,1,0,156),Color3.fromRGB(180,40,40))

-- CC gates
makeLabel(f6Body,"CUT CORNERS:",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,186),10,GATE_COLORS.cc,true).TextXAlignment=Enum.TextXAlignment.Left
local ccAddBtn    = makeButton(f6Body,"➕ ADD CC",    UDim2.new(0.34,-3,0,24),UDim2.new(0,6,0,202),Color3.fromRGB(160,30,140))
local ccRemLastBtn= makeButton(f6Body,"🗑 LAST",      UDim2.new(0.33,-3,0,24),UDim2.new(0.34,1,0,202),Color3.fromRGB(130,30,30))
local ccRemAllBtn = makeButton(f6Body,"🗑 ALL",       UDim2.new(0.33,-3,0,24),UDim2.new(0.67,1,0,202),Color3.fromRGB(100,20,20))
local ccCountLbl  = makeLabel(f6Body,"CCs placed: 0",UDim2.new(1,-12,0,14),UDim2.new(0,6,0,230),10,Color3.fromRGB(220,120,220),false)

-- CC Leaderboard popup
local ccLBPopup = Instance.new("Frame")
ccLBPopup.Size, ccLBPopup.Position = UDim2.new(0,240,0,320), UDim2.new(0.5,-120,0.5,-160)
ccLBPopup.BackgroundColor3, ccLBPopup.BackgroundTransparency = Color3.fromRGB(10,10,18), 0
ccLBPopup.BorderSizePixel, ccLBPopup.Visible, ccLBPopup.ZIndex = 0, false, 40
ccLBPopup.Parent = screenGui; applyCorner(ccLBPopup); applyStroke(ccLBPopup, GATE_COLORS.cc, 1.5, 0)
makeLabel(ccLBPopup,"✂️  CUT CORNER BOARD",UDim2.new(1,-40,0,28),UDim2.new(0,0,0,0),13,GATE_COLORS.cc,true,41)
local ccLBCloseBtn = makeButton(ccLBPopup,"✖",UDim2.new(0,26,0,22),UDim2.new(1,-30,0,3),Color3.fromRGB(180,40,40),nil,41)
local ccLBScroll = Instance.new("ScrollingFrame")
ccLBScroll.Size, ccLBScroll.Position = UDim2.new(1,-12,0,278), UDim2.new(0,6,0,32)
ccLBScroll.BackgroundTransparency, ccLBScroll.BorderSizePixel = 1, 0
ccLBScroll.ScrollBarThickness, ccLBScroll.ScrollBarImageColor3 = 4, GATE_COLORS.cc
ccLBScroll.CanvasSize, ccLBScroll.AutomaticCanvasSize, ccLBScroll.ZIndex = UDim2.new(0,0,0,0), Enum.AutomaticSize.Y, 41
ccLBScroll.Parent = ccLBPopup
local ccLBLayout = Instance.new("UIListLayout")
ccLBLayout.Padding, ccLBLayout.SortOrder, ccLBLayout.Parent = UDim.new(0,2), Enum.SortOrder.LayoutOrder, ccLBScroll
ccLBCloseBtn.MouseButton1Click:Connect(function() ccLBPopup.Visible=false end)

local function rebuildCCLeaderboard()
	for _, c in ipairs(ccLBScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local list = {}
	for uid, data in pairs(playerData) do table.insert(list, {uid=uid, data=data}) end
	table.sort(list, function(a,b) return a.data.ccs > b.data.ccs end)
	for i, entry in ipairs(list) do
		local data = entry.data
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,28)
		row.BackgroundColor3 = i%2==0 and Color3.fromRGB(22,22,30) or Color3.fromRGB(18,18,24)
		row.BackgroundTransparency, row.BorderSizePixel, row.LayoutOrder, row.ZIndex = 0.3, 0, i, 42
		row.Parent = ccLBScroll; applyCorner(row, UDim.new(0,4))
		local rankLbl = makeLabel(row,({"🥇","🥈","🥉"})[i] or ("#"..i),UDim2.new(0,24,1,0),UDim2.new(0,0,0,0),i<=3 and 13 or 10,Color3.fromRGB(220,220,220),true,43)
		local nick = playerNicknames[entry.uid] or data.displayName
		local nLbl = makeLabel(row,nick,UDim2.new(1,-70,1,0),UDim2.new(0,26,0,0),11,Color3.fromRGB(210,210,210),false,43); nLbl.TextXAlignment=Enum.TextXAlignment.Left
		local cLbl = makeLabel(row,"✂ "..data.ccs,UDim2.new(0,42,1,0),UDim2.new(1,-44,0,0),12,data.ccs>0 and Color3.fromRGB(255,80,80) or Color3.fromRGB(140,140,160),true,43); cLbl.TextXAlignment=Enum.TextXAlignment.Right
	end
end

local ccLBBtn = makeButton(f6Body,"📊 CC Leaderboard",UDim2.new(1,-12,0,24),UDim2.new(0,6,0,248),Color3.fromRGB(140,30,120))
ccLBBtn.MouseButton1Click:Connect(function() rebuildCCLeaderboard(); ccLBPopup.Visible=true end)

-- ============================================================
-- GATE BUILDING
-- ============================================================
local function makePreview(color)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CastShadow = "GatePreview", true, false, false
	p.Material, p.Color, p.Transparency = Enum.Material.Neon, color, 0.55
	p.Size, p.Parent = Vector3.new(0.1, LINE_HEIGHT, 0.3), workspace
	return p
end
local function updatePreview(preview, p1, p2)
	if not preview or not p1 or not p2 then return end
	local dist = (p2-p1).Magnitude
	if dist < 0.1 then return end
	local mid = Vector3.new((p1.X+p2.X)/2,(p1.Y+p2.Y)/2+LINE_HEIGHT/2,(p1.Z+p2.Z)/2)
	preview.Size  = Vector3.new(dist, LINE_HEIGHT, 0.3)
	preview.CFrame = CFrame.lookAt(mid, mid+(p2-p1).Unit) * CFrame.Angles(0, math.pi/2, 0)
end
local function buildGatePart(key, a, b)
	local g = gates[key]
	if g.part then g.part:Destroy() end
	local part = Instance.new("Part")
	part.Name, part.Anchored, part.CanCollide, part.CastShadow = "Gate_"..key, true, false, false
	part.Size = Vector3.new((b-a).Magnitude, LINE_HEIGHT, 0.3)
	part.Material, part.Color = Enum.Material.SmoothPlastic, GATE_COLORS[key]
	local mid = Vector3.new((a.X+b.X)/2,(a.Y+b.Y)/2+LINE_HEIGHT/2,(a.Z+b.Z)/2)
	part.CFrame = CFrame.lookAt(mid, mid+(b-a).Unit) * CFrame.Angles(0, math.pi/2, 0)
	local bb = Instance.new("BillboardGui")
	bb.Size, bb.StudsOffset, bb.AlwaysOnTop, bb.Parent = UDim2.new(0,180,0,36), Vector3.new(0,LINE_HEIGHT/2+3,0), true, part
	local bbl = Instance.new("TextLabel")
	bbl.Size, bbl.BackgroundTransparency = UDim2.new(1,0,1,0), 1
	bbl.Text, bbl.TextColor3, bbl.TextSize, bbl.Font = GATE_LABELS[key], GATE_COLORS[key], 16, Enum.Font.GothamBold
	bbl.Parent = bb
	part.Parent = workspace
	g.part = part
end
local function removeGate(key)
	local g = gates[key]
	if g.part    then g.part:Destroy();    g.part    = nil end
	if g.preview then g.preview:Destroy(); g.preview = nil end
	g.p1, g.p2 = nil, nil
end
local function cancelPlacement()
	if placingGate and gates[placingGate] and gates[placingGate].preview then
		gates[placingGate].preview:Destroy(); gates[placingGate].preview = nil
	elseif placingGate == "cc_new" and activeCCGate and activeCCGate.preview then
		-- FIX #2: clean up CC preview on cancel
		activeCCGate.preview:Destroy(); activeCCGate.preview = nil
	end
	if clickConn then clickConn:Disconnect(); clickConn = nil end
	placingGate, placingStep = nil, 0
	activeCCGate = nil   -- FIX #2: clear active CC gate
end
local function startGatePlacement(key)
	cancelPlacement(); placingGate, placingStep = key, 1
	setStatus("Click to place P1", Color3.fromRGB(255,200,0))
	clickConn = mouse.Button1Down:Connect(function()
		local hit = mouse.Hit
		if not hit or (mouse.Target and mouse.Target:IsDescendantOf(screenGui)) then return end
		local g = gates[placingGate]
		if placingStep == 1 then
			g.p1, placingStep = hit.Position, 2
			g.preview = makePreview(GATE_COLORS[placingGate])
			setStatus("Click to place P2", Color3.fromRGB(255,200,0))
		elseif placingStep == 2 then
			g.p2 = hit.Position
			if g.preview then g.preview:Destroy(); g.preview = nil end
			buildGatePart(placingGate, g.p1, g.p2)
			cancelPlacement(); setStatus("✅ Placed!", Color3.fromRGB(80,220,120))
		end
	end)
end

-- ============================================================
-- PLAYER DATA
-- ============================================================
local function ensurePlayerData(plr)
	local uid = tostring(plr.UserId)
	if not playerData[uid] then
		playerData[uid] = {
			displayName   = plr.DisplayName, username = plr.Name,
			lap=0, sector=0, sectorTime=math.huge, lastGateTime=0, lapStartTime=0,
			fastestLap    = math.huge,
			lastSide={}, lastCross={},
			finishedRace  = false,
			personalBests = { s1=math.huge, s2=math.huge, s3=math.huge, lap=math.huge },
			lastDelta     = nil, lastDeltaColor = Color3.new(1,1,1),
			currentRank   = 0,
			lastSpeedSetting = nil,
			lastDriftSetting = nil,
			lastSpeedNotify  = 0,   -- FIX #6: repeat speed notification cooldown
			lastDriftNotify  = 0,   -- FIX #6: repeat drift notification cooldown
			-- Pit box system
			boxes         = 0,
			targetBoxes   = nil,
			lastBoxSide   = nil,
			lastBoxCross  = 0,
			-- Pitlane speed
			inPit         = false,
			lastPitSpeedNotify = 0,
			-- Cut corner system (per-CC gate tracking)
			ccs           = 0,
			ccLastSide    = {},   -- [index] = side
			ccLastCross   = {},   -- [index] = timestamp
		}
	end
	return playerData[uid]
end

-- ============================================================
-- OVERHEAD HELPERS
-- ============================================================
local function getOverhead(plr)
	local char = plr.Character
	if not char then return nil end
	local head = char:FindFirstChild("Head")
	if not head then return nil end
	local oh = head:FindFirstChild("RaceOverhead")
	if not oh then
		oh = Instance.new("BillboardGui")
		oh.Name, oh.Size = "RaceOverhead", UDim2.new(0,200,0,100)
		oh.StudsOffset, oh.AlwaysOnTop, oh.Parent = Vector3.new(0,4,0), true, head
		local lay = Instance.new("UIListLayout")
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment   = Enum.VerticalAlignment.Bottom
		lay.Parent = oh
		for _, info in ipairs({{"NameLabel",20,16},{"SpeedLabel",18,14},{"DriftLabel",18,14}}) do
			local l = Instance.new("TextLabel")
			l.Name, l.Size = info[1], UDim2.new(1,0,0,info[2])
			l.BackgroundTransparency, l.Font, l.TextSize = 1, Enum.Font.GothamBold, info[3]
			l.Parent = oh
		end
	end
	return oh
end

-- ============================================================
-- LEADERBOARD
-- ============================================================
local function rebuildLeaderboard()
	for _, c in ipairs(leaderContainer:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local list = {}
	for uid, data in pairs(latestSnapshot) do table.insert(list, {uid=uid, data=data}) end
	table.sort(list, function(a,b)
		if a.data.lap    ~= b.data.lap    then return a.data.lap    > b.data.lap    end
		if a.data.sector ~= b.data.sector then return a.data.sector > b.data.sector end
		if a.data.sectorTime ~= b.data.sectorTime then return a.data.sectorTime < b.data.sectorTime end
		return tonumber(a.uid) < tonumber(b.uid)
	end)
	for i, entry in ipairs(list) do playerData[entry.uid].currentRank = i end

	local leaderTime = list[1] and list[1].data.sectorTime or math.huge

	for i, entry in ipairs(list) do
		local data  = entry.data
		local isMe  = entry.uid == tostring(player.UserId)
		local isLead= i == 1

		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1,0,0,34)
		row.BackgroundColor3 = i%2==0 and Color3.fromRGB(22,22,30) or Color3.fromRGB(18,18,24)
		row.BackgroundTransparency, row.BorderSizePixel = 0.3, 0
		row.LayoutOrder, row.Text, row.Parent = i, "", leaderContainer
		applyCorner(row, UDim.new(0,5))

		-- Left-click → spectate
		row.MouseButton1Click:Connect(function()
			local target = Players:GetPlayerByUserId(tonumber(entry.uid))
			if target and target.Character then
				workspace.CurrentCamera.CameraSubject = target.Character:FindFirstChild("Humanoid")
				spectatingPlayer = target
				spectateUI.Text  = "Stop Spectating "..target.DisplayName
				spectateUI.Visible = true
			end
		end)

		-- Right-click → context popup (per-player settings)
		row.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton2 then
				ctxTargetUid      = entry.uid
				ctxTitle.Text     = "Settings: "..data.displayName
				ctxNameLbl.Text   = "("..data.username..")"
				ctxNickBox.Text   = playerNicknames[entry.uid] or ""
				local lim = playerLimits[entry.uid]
				ctxSpeedBox.Text  = lim and lim.speed and tostring(lim.speed) or ""
				ctxDriftBox.Text  = lim and lim.drift and tostring(lim.drift) or ""
				ctxBoxesBox.Text  = data.targetBoxes and tostring(data.targetBoxes) or ""
				ctxPopup.Visible  = true
			end
		end)

		-- Rank medal
		makeLabel(row, ({"🥇","🥈","🥉"})[i] or ("#"..i),
			UDim2.new(0,24,1,0), UDim2.new(0,0,0,0),
			i<=3 and 13 or 10, Color3.fromRGB(220,220,220), true)

		-- Name (show nickname if set)
		local displayedName = playerNicknames[entry.uid] and (playerNicknames[entry.uid]) or data.displayName
		local nLbl = makeLabel(row, displayedName..(data.finishedRace and " 🏁" or ""),
			UDim2.new(1,-176,1,0), UDim2.new(0,26,0,0),
			10, isMe and YELLOW or Color3.fromRGB(210,210,210), isMe)
		nLbl.TextXAlignment = Enum.TextXAlignment.Left

		-- L# S#
		local secStr = data.sector==0 and "—" or ("S"..data.sector)
		local iLbl = makeLabel(row, "L"..data.lap.." "..secStr,
			UDim2.new(0,40,1,0), UDim2.new(1,-150,0,0), 9, Color3.fromRGB(100,220,255), true)
		iLbl.TextXAlignment = Enum.TextXAlignment.Right

		-- Gap
		local gapStr, gapColor
		if isLead then gapStr, gapColor = "LEAD", GREEN
		else
			local refTime = gapMode=="leader" and leaderTime or (list[i-1] and list[i-1].data.sectorTime or leaderTime)
			gapStr  = string.format("+%.3f", math.abs(refTime - data.sectorTime))
			gapColor = Color3.fromRGB(255,120,120)
		end
		local gLbl = makeLabel(row, gapStr, UDim2.new(0,36,1,0), UDim2.new(1,-108,0,0), 8, gapColor, true)
		gLbl.TextXAlignment = Enum.TextXAlignment.Right

		-- Box counter 📦 X/Y
		local bTarget = data.targetBoxes or targetBoxes
		local bDone   = data.boxes >= bTarget
		local bColor  = bDone and Color3.fromRGB(80,220,120) or Color3.fromRGB(200,160,60)
		local bLbl = makeLabel(row, "📦"..data.boxes.."/"..bTarget,
			UDim2.new(0,36,0.5,0), UDim2.new(1,-72,0,-8), 8, bColor, true)
		bLbl.TextXAlignment = Enum.TextXAlignment.Right

		-- CC counter ✂️ X
		local cColor = data.ccs > 0 and Color3.fromRGB(255,80,80) or Color3.fromRGB(140,140,160)
		local cLbl = makeLabel(row, "✂"..data.ccs,
			UDim2.new(0,28,0.5,0), UDim2.new(1,-72,0.5,2), 8, cColor, true)
		cLbl.TextXAlignment = Enum.TextXAlignment.Right

		-- + Laps button
		local addLapBtn = makeButton(row, "+", UDim2.new(0,20,0,20), UDim2.new(1,-44,0.5,-10), Color3.fromRGB(30,160,70))
		addLapBtn.TextSize = 14
		addLapBtn.MouseButton1Click:Connect(function()
			addLapsTargetUid, addLapsPlayerLbl.Text, addLapsInputBox.Text = entry.uid, "Player: "..data.displayName, "1"
			addLapsPopup.Visible = true
		end)

		-- X Remove
		local xBtn = makeButton(row, "X", UDim2.new(0,20,0,20), UDim2.new(1,-20,0.5,-10), Color3.fromRGB(180,40,40))
		xBtn.MouseButton1Click:Connect(function() playerData[entry.uid] = nil end)
	end
end

-- ============================================================
-- FASTEST LAPS
-- ============================================================
local function rebuildFastestLaps()
	for _, c in ipairs(fastestContainer:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local list = {}
	for uid, data in pairs(latestSnapshot) do table.insert(list, {uid=uid, data=data}) end
	table.sort(list, function(a,b) return a.data.fastestLap < b.data.fastestLap end)
	for i, entry in ipairs(list) do
		local data = entry.data
		if data.fastestLap == math.huge then continue end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,30)
		row.BackgroundColor3 = i%2==0 and Color3.fromRGB(22,22,30) or Color3.fromRGB(18,18,24)
		row.BackgroundTransparency, row.BorderSizePixel, row.LayoutOrder = 0.3, 0, i
		row.Parent = fastestContainer; applyCorner(row, UDim.new(0,5))
		makeLabel(row,({"🥇","🥈","🥉"})[i] or ("#"..i),UDim2.new(0,26,1,0),UDim2.new(0,0,0,0),i<=3 and 14 or 11,Color3.fromRGB(220,220,220),true)
		local nl = makeLabel(row,data.displayName,UDim2.new(1,-80,1,0),UDim2.new(0,28,0,0),11,entry.uid==tostring(player.UserId) and YELLOW or Color3.fromRGB(210,210,210),entry.uid==tostring(player.UserId))
		nl.TextXAlignment=Enum.TextXAlignment.Left
		local tl = makeLabel(row,formatTime(data.fastestLap),UDim2.new(0,60,1,0),UDim2.new(1,-65,0,0),11,Color3.fromRGB(200,100,220),true)
		tl.TextXAlignment=Enum.TextXAlignment.Right
	end
end

-- ============================================================
-- RACE LOGIC
-- ============================================================
local function resetRaceLocal()
	lapCount, isFinished = 0, false
	finishedLabel.Text, deltaLabel.Text = "", "Delta: —"
	sessionBests = { s1=math.huge, s2=math.huge, s3=math.huge, lap=math.huge }
	for _, data in pairs(playerData) do
		data.lap, data.sector, data.sectorTime = 0, 0, math.huge
		data.lapStartTime, data.lastGateTime   = 0, 0
		data.fastestLap                        = math.huge
		data.lastSide, data.lastCross          = {}, {}
		data.finishedRace                      = false
		data.personalBests = { s1=math.huge, s2=math.huge, s3=math.huge, lap=math.huge }
		data.lastDelta     = nil
		-- Reset pit/cc
		data.boxes, data.ccs          = 0, 0
		data.lastBoxSide, data.lastCcSide = nil, nil
		data.lastBoxCross, data.lastCcCross = 0, 0
	end
	rebuildLeaderboard(); rebuildFastestLaps()
end

local function processCrossing(plr, key, now)
	local data = ensurePlayerData(plr)
	if data.finishedRace then return end
	local prevTime    = data.lastGateTime
	data.lastGateTime = now
	local sectorTime  = prevTime > 0 and (now - prevTime) or 0
	local colorCode   = YELLOW

	local function checkSector(secKey, timeVal)
		if timeVal > 0 then
			if timeVal < sessionBests[secKey] then
				sessionBests[secKey], colorCode = timeVal, PURPLE
				data.lastDelta = string.format("%s%.3f", timeVal-data.personalBests[secKey]<0 and "-" or "+", math.abs(timeVal-data.personalBests[secKey]))
				data.personalBests[secKey] = timeVal
			elseif timeVal < data.personalBests[secKey] then
				data.lastDelta = string.format("-%0.3f", data.personalBests[secKey]-timeVal)
				data.personalBests[secKey] = timeVal
				colorCode = GREEN
			else
				data.lastDelta = string.format("+%.3f", timeVal - data.personalBests[secKey])
			end
			data.lastDeltaColor = colorCode
		end
	end

	if key == "start" then
		checkSector("s3", sectorTime)
		if data.lapStartTime > 0 then
			local lapTime = now - data.lapStartTime
			if lapTime > 2 then
				if lapTime < sessionBests.lap       then sessionBests.lap         = lapTime end
				if lapTime < data.personalBests.lap then data.personalBests.lap   = lapTime end
				if lapTime < data.fastestLap        then data.fastestLap          = lapTime end
				data.lap += 1
				if not qualiActive and data.lap >= targetLaps then data.finishedRace = true end
			end
		end
		data.lapStartTime, data.sector, data.sectorTime = now, 1, now
	elseif key == "s2" then
		checkSector("s1", sectorTime); data.sector, data.sectorTime = 2, now
	elseif key == "s3" then
		checkSector("s2", sectorTime); data.sector, data.sectorTime = 3, now
	end
end

-- ============================================================
-- GATE / PIT / CC CROSSING CHECK
-- ============================================================
local function checkGatesForPlayer(plr, pos, now)
	local data    = ensurePlayerData(plr)
	local isLocal = plr == player

	-- Race gates (start, s2, s3)
	for _, key in ipairs({"start","s2","s3"}) do
		local g = gates[key]
		if not g.part then continue end
		local l3   = g.part.CFrame:PointToObjectSpace(pos)
		local sz   = g.part.Size
		local side = l3.Z >= 0 and 1 or -1
		local inBnd = math.abs(l3.X) <= sz.X/2+4 and l3.Y >= -sz.Y/2-4 and l3.Y <= sz.Y/2+4
		data.lastSide[key]  = data.lastSide[key]  or side
		data.lastCross[key] = data.lastCross[key] or 0
		if side ~= data.lastSide[key] then
			if inBnd and (now - data.lastCross[key]) >= CROSS_COOLDOWN then
				data.lastCross[key], data.lastSide[key] = now, side
				processCrossing(plr, key, now)
				if isLocal and data.finishedRace then
					finishedLabel.Text, finishedLabel.TextColor3 = "🏁 RACE FINISHED", Color3.fromRGB(255,220,60)
				end
			else data.lastSide[key] = side end
		end
	end

	-- Pit entry gate → count box + mark inPit
	do
		local g = gates.pit
		if g.part then
			local l3   = g.part.CFrame:PointToObjectSpace(pos)
			local sz   = g.part.Size
			local side = l3.Z >= 0 and 1 or -1
			local inBnd = math.abs(l3.X) <= sz.X/2+4 and l3.Y >= -sz.Y/2-4 and l3.Y <= sz.Y/2+4
			data.lastBoxSide  = data.lastBoxSide  or side
			data.lastBoxCross = data.lastBoxCross or 0
			if side ~= data.lastBoxSide then
				if inBnd and (now - data.lastBoxCross) >= CROSS_COOLDOWN then
					data.lastBoxCross, data.lastBoxSide = now, side
					data.boxes += 1
					data.inPit = true
					-- FIX #1: check speed AT the moment of pit entry crossing
					local uidStrPit  = tostring(plr.UserId)
					local pLimPit    = (playerLimits[uidStrPit] and playerLimits[uidStrPit].speed) or maxSpeedLimit
					local pitLimitAt = pLimPit + pitSpeedOffset
					if pitLimitAt < 0 then pitLimitAt = 30 end
					local pChar   = plr.Character
					local pRoot   = pChar and pChar:FindFirstChild("HumanoidRootPart")
					local entrySpd = (pRoot and pRoot.AssemblyLinearVelocity.Magnitude) or 0
					if entrySpd > pitLimitAt then
						local dNamePit = playerNicknames[uidStrPit] or plr.Name
						notify("⚠️ "..dNamePit.." entered pit SPEEDING! ("..math.floor(entrySpd).." / "..math.floor(pitLimitAt)..")", uidStrPit.."_pit")
						addLog(dNamePit, "PitSpeed", math.floor(entrySpd).."/"..math.floor(pitLimitAt))
						data.lastPitSpeedNotify = now
					end
				else data.lastBoxSide = side end
			end
		end
	end

	-- Pit exit gate → mark not in pit
	do
		local g = gates.pitExit
		if g.part then
			local l3   = g.part.CFrame:PointToObjectSpace(pos)
			local sz   = g.part.Size
			local side = l3.Z >= 0 and 1 or -1
			local inBnd = math.abs(l3.X) <= sz.X/2+4 and l3.Y >= -sz.Y/2-4 and l3.Y <= sz.Y/2+4
			data.lastSide["pitExit"]  = data.lastSide["pitExit"]  or side
			data.lastCross["pitExit"] = data.lastCross["pitExit"] or 0
			if side ~= data.lastSide["pitExit"] then
				if inBnd and (now - data.lastCross["pitExit"]) >= CROSS_COOLDOWN then
					data.lastCross["pitExit"], data.lastSide["pitExit"] = now, side
					data.inPit = false
				else data.lastSide["pitExit"] = side end
			end
		end
	end

	-- Multiple CC gates
	for idx, g in ipairs(ccGates) do
		if not g.part then continue end
		local l3   = g.part.CFrame:PointToObjectSpace(pos)
		local sz   = g.part.Size
		local side = l3.Z >= 0 and 1 or -1
		local inBnd = math.abs(l3.X) <= sz.X/2+4 and l3.Y >= -sz.Y/2-4 and l3.Y <= sz.Y/2+4
		data.ccLastSide[idx]  = data.ccLastSide[idx]  or side
		data.ccLastCross[idx] = data.ccLastCross[idx] or 0
		if side ~= data.ccLastSide[idx] then
			if inBnd and (now - data.ccLastCross[idx]) >= CROSS_COOLDOWN then
				data.ccLastCross[idx], data.ccLastSide[idx] = now, side
				data.ccs += 1
				local displayedName = playerNicknames[tostring(plr.UserId)] or plr.Name
				notify(displayedName.." cut a corner! (CC #"..data.ccs..")", tostring(plr.UserId).."_cc")
				addLog(displayedName, "CC", "Cut #"..data.ccs.." at CC"..idx)
			else data.ccLastSide[idx] = side end
		end
	end
end

-- ============================================================
-- BUTTON WIRING
-- ============================================================
for _, k in ipairs({"start","s2","s3"}) do
	addBtns[k].MouseButton1Click:Connect(function()    startGatePlacement(k) end)
	removeBtns[k].MouseButton1Click:Connect(function() removeGate(k)         end)
end
removeAllBtn.MouseButton1Click:Connect(function()
	for _, k in ipairs({"start","s2","s3"}) do removeGate(k) end
end)
pitAddBtn.MouseButton1Click:Connect(function()     startGatePlacement("pit")     end)
pitRemBtn.MouseButton1Click:Connect(function()     removeGate("pit")             end)
pitExitAddBtn.MouseButton1Click:Connect(function() startGatePlacement("pitExit") end)
pitExitRemBtn.MouseButton1Click:Connect(function() removeGate("pitExit")         end)

-- Multi-CC buttons
ccAddBtn.MouseButton1Click:Connect(function()
	-- Place a new CC gate using a generic key "cc_N"
	local idx = #ccGates + 1
	local g = { part=nil, p1=nil, p2=nil, preview=nil }
	ccGates[idx] = g
	-- Hijack the placement system by temporarily using a unique key
	-- We handle CC placement manually
	cancelPlacement()
	placingGate = "cc_new"
	placingStep = 1
	activeCCGate = g   -- FIX #2: store reference so Heartbeat preview works
	-- store index in a closure
	local myIdx = idx
	setStatus("CC #"..myIdx.." — Click P1", GATE_COLORS.cc)
	if clickConn then clickConn:Disconnect() end
	clickConn = mouse.Button1Down:Connect(function()
		local hit = mouse.Hit
		if not hit or (mouse.Target and mouse.Target:IsDescendantOf(screenGui)) then return end
		if placingStep == 1 then
			g.p1, placingStep = hit.Position, 2
			g.preview = makePreview(GATE_COLORS.cc)
			activeCCGate = g   -- FIX #2: update ref after preview created
			setStatus("CC #"..myIdx.." — Click P2", GATE_COLORS.cc)
		elseif placingStep == 2 then
			g.p2 = hit.Position
			if g.preview then g.preview:Destroy(); g.preview = nil end
			-- build the gate part
			if g.part then g.part:Destroy() end
			local a, b = g.p1, g.p2
			local part = Instance.new("Part")
			part.Name, part.Anchored, part.CanCollide, part.CastShadow = "Gate_cc"..myIdx, true, false, false
			part.Size = Vector3.new((b-a).Magnitude, LINE_HEIGHT, 0.3)
			part.Material, part.Color = Enum.Material.SmoothPlastic, GATE_COLORS.cc
			local mid = Vector3.new((a.X+b.X)/2,(a.Y+b.Y)/2+LINE_HEIGHT/2,(a.Z+b.Z)/2)
			part.CFrame = CFrame.lookAt(mid, mid+(b-a).Unit) * CFrame.Angles(0, math.pi/2, 0)
			local bb = Instance.new("BillboardGui")
			bb.Size, bb.StudsOffset, bb.AlwaysOnTop, bb.Parent = UDim2.new(0,180,0,36), Vector3.new(0,LINE_HEIGHT/2+3,0), true, part
			local bbl = Instance.new("TextLabel")
			bbl.Size, bbl.BackgroundTransparency = UDim2.new(1,0,1,0), 1
			bbl.Text, bbl.TextColor3, bbl.TextSize, bbl.Font = "✂️  CC #"..myIdx, GATE_COLORS.cc, 16, Enum.Font.GothamBold
			bbl.Parent = bb
			part.Parent = workspace
			g.part = part
			cancelPlacement()   -- FIX #2: this now also clears activeCCGate
			ccCountLbl.Text = "CCs placed: "..#ccGates
			setStatus("✅ CC #"..myIdx.." placed!", Color3.fromRGB(80,220,120))
		end
	end)
end)

ccRemLastBtn.MouseButton1Click:Connect(function()
	local idx = #ccGates
	if idx == 0 then return end
	local g = ccGates[idx]
	if g.part    then g.part:Destroy()    end
	if g.preview then g.preview:Destroy() end
	table.remove(ccGates, idx)
	ccCountLbl.Text = "CCs placed: "..#ccGates
end)

ccRemAllBtn.MouseButton1Click:Connect(function()
	for _, g in ipairs(ccGates) do
		if g.part    then g.part:Destroy()    end
		if g.preview then g.preview:Destroy() end
	end
	ccGates = {}
	ccCountLbl.Text = "CCs placed: 0"
end)
redoBtn.MouseButton1Click:Connect(resetRaceLocal)
resetStandingsBtn.MouseButton1Click:Connect(function() playerData = {}; latestSnapshot = playerData end)

startQualiBtn.MouseButton1Click:Connect(function()
	local mins = tonumber(qualiInputBox.Text)
	if mins and mins > 0 then
		resetRaceLocal(); qualiActive = true; qualiEndTime = time()+(mins*60)
		qualiUI.Visible = true; startQualiBtn.Text = "🛑 Stop Quali"
		startQualiBtn.BackgroundColor3 = Color3.fromRGB(180,40,40); qualiInputBox.Text = ""
	else
		if qualiActive then
			qualiActive = false; qualiUI.Visible = false
			startQualiBtn.Text = "▶ Start Quali"
			startQualiBtn.BackgroundColor3 = Color3.fromRGB(100,30,160)
		end
	end
end)

-- ============================================================
-- INIT
-- ============================================================
ensurePlayerData(player)

-- ============================================================
-- HEARTBEAT
-- ============================================================
RunService.Heartbeat:Connect(function()
	local now = time()

	for uid, data in pairs(playerData) do
		if not Players:GetPlayerByUserId(tonumber(uid)) and data.lap < 1 then
			playerData[uid] = nil
		end
	end

	if qualiActive then
		local rem = qualiEndTime - now
		if rem <= 0 then
			qualiActive = false; qualiLabel.Text = "QUALIFYING - FINISHED"
			startQualiBtn.Text = "▶ Start Quali"; startQualiBtn.BackgroundColor3 = Color3.fromRGB(100,30,160)
		else qualiLabel.Text = "QUALIFYING - "..formatTime(rem) end
	end

	-- FIX #2: guard against cc_new key which doesn't exist in gates table
	if placingGate and placingStep == 2 then
		if placingGate ~= "cc_new" and gates[placingGate] and gates[placingGate].preview then
			updatePreview(gates[placingGate].preview, gates[placingGate].p1, mouse.Hit and mouse.Hit.Position)
		elseif placingGate == "cc_new" and activeCCGate and activeCCGate.preview then
			updatePreview(activeCCGate.preview, activeCCGate.p1, mouse.Hit and mouse.Hit.Position)
		end
	end

	-- PLAYER PROCESSING
	for _, plr in ipairs(Players:GetPlayers()) do
		local data = ensurePlayerData(plr)
		local char = plr.Character
		if not char then continue end
		local hum  = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		-- FIX #5: always update overhead to "In Foot" when root is missing so it never stays stale
		if not root then
			local ohFoot = getOverhead(plr)
			if ohFoot then
				local slFoot = ohFoot:FindFirstChild("SpeedLabel")
				local dlFoot = ohFoot:FindFirstChild("DriftLabel")
				if slFoot then slFoot.Text = "In Foot" end
				if dlFoot then dlFoot.Text = "" end
			end
			continue
		end
		local seat = hum and hum.SeatPart

		-- Gate detection: local player uses HumanoidRootPart every frame
		if plr == player then
			checkGatesForPlayer(player, root.Position, now)
		elseif seat and seat:IsA("VehicleSeat") then
			checkGatesForPlayer(plr, seat.Position, now)
		end

		-- Overhead labels
		local oh = getOverhead(plr)
		if oh then
			oh.Enabled = showOverheads
			local nl = oh:FindFirstChild("NameLabel")
			local sl = oh:FindFirstChild("SpeedLabel")
			local dl = oh:FindFirstChild("DriftLabel")
			if nl then
				local ohNick = playerNicknames[tostring(plr.UserId)] or plr.DisplayName; nl.Text = string.format("%s (P%d)", ohNick, data.currentRank or 0)
				nl.TextColor3= plr==player and YELLOW or Color3.new(1,1,1)
			end

			if seat and seat:IsA("VehicleSeat") then
				local uidStr    = tostring(plr.UserId)
				local pLimSpeed = playerLimits[uidStr] and playerLimits[uidStr].speed or maxSpeedLimit
				local pLimDrift = playerLimits[uidStr] and playerLimits[uidStr].drift or maxDriftLimit

				-- Speed: read MaxSpeed value inside seat
				local speedVal = seat:FindFirstChild("MaxSpeed")
				local curSpeed = (speedVal and speedVal:IsA("ValueBase")) and speedVal.Value or seat.MaxSpeed
				if sl then
					sl.Text      = "MaxSpeed: "..math.floor(curSpeed)
					sl.TextColor3= curSpeed > pLimSpeed and Color3.new(1,0,0) or Color3.new(1,1,1)
				end
				-- FIX #3: log ALL speed changes (not just violations)
				if curSpeed ~= data.lastSpeedSetting then
					local displayedName = playerNicknames[uidStr] or plr.Name
					addLog(displayedName, "Speed", math.floor(curSpeed))
					-- Also notify immediately on change if already over limit
					if curSpeed > pLimSpeed then
						notify(displayedName.." over Speed limit: "..math.floor(curSpeed).." (max "..math.floor(pLimSpeed)..")", uidStr)
						data.lastSpeedNotify = now
					end
				end
				-- FIX #6: repeat notification every 5s while still over limit
				if curSpeed > pLimSpeed and curSpeed == data.lastSpeedSetting then
					if (now - (data.lastSpeedNotify or 0)) >= 5 then
						data.lastSpeedNotify = now
						local displayedName = playerNicknames[uidStr] or plr.Name
						notify(displayedName.." over Speed limit: "..math.floor(curSpeed).." (max "..math.floor(pLimSpeed)..")", uidStr)
					end
				end
				data.lastSpeedSetting = curSpeed

				-- Pitlane speed check: if inPit, use actual car velocity against (limit + pitSpeedOffset)
				if data.inPit and gates.pit.part then
					local char2 = plr.Character
					local root2 = char2 and char2:FindFirstChild("HumanoidRootPart")
					local actualSpeed = root2 and root2.AssemblyLinearVelocity.Magnitude or 0
					local pitLimit = pLimSpeed + pitSpeedOffset
					if pitLimit < 0 then pitLimit = 30 end   -- safety floor
					if actualSpeed > pitLimit and (now - data.lastPitSpeedNotify) > 4 then
						data.lastPitSpeedNotify = now
						local displayedName = playerNicknames[uidStr] or plr.Name
						notify("⚠️ "..displayedName.." is SPEEDING in the pit! ("..math.floor(actualSpeed).." / "..math.floor(pitLimit)..")", uidStr.."_pit")
						addLog(displayedName, "PitSpeed", math.floor(actualSpeed).."/"..math.floor(pitLimit))
					end
				end

				-- =========================================================
				-- Drift: walk UP from seat until we find a model whose
				-- parent is named "Vehicles". That model is nicknameCar.
				-- Then: nicknameCar → Chassis → Wheels → Wheel_BL → PhysicalWheel
				-- =========================================================
				local curDrift = nil
				local carModel = nil
				local ancestor = seat.Parent
				while ancestor and ancestor ~= workspace do
					if ancestor.Parent and ancestor.Parent.Name == "Vehicles" then
						carModel = ancestor
						break
					end
					ancestor = ancestor.Parent
				end
				if carModel then
					local chassis   = carModel:FindFirstChild("Chassis")
					local wheels    = chassis  and chassis:FindFirstChild("Wheels")
					local wBL       = wheels   and (wheels:FindFirstChild("WheelBL") or wheels:FindFirstChild("Wheel_BL"))
					local physWheel = wBL      and wBL:FindFirstChild("PhysicalWheel")
					if physWheel and physWheel:IsA("BasePart") then
						local props = physWheel.CustomPhysicalProperties
						if typeof(props) == "PhysicalProperties" then
							curDrift = props.Friction
						end
					end
				end

				if dl then
					if curDrift then
						dl.Text = string.format("Friction: %.2f", curDrift)
						-- FIX #4: changed < to > so limit is a MAXIMUM (flag when friction EXCEEDS limit)
						if curDrift > pLimDrift then
							dl.TextColor3 = Color3.new(1,1,0.4)
							-- FIX #3: log ALL drift changes (not just violations)
							if curDrift ~= data.lastDriftSetting then
								local dn2 = playerNicknames[uidStr] or plr.Name
								addLog(dn2, "Drift", string.format("%.2f",curDrift))
								notify(dn2.." Friction "..string.format("%.2f",curDrift).." > limit "..string.format("%.2f",pLimDrift), uidStr.."_drift")
								data.lastDriftNotify = now
							end
							-- FIX #6: repeat drift notification every 5s while still over limit
							if curDrift == data.lastDriftSetting and (now - (data.lastDriftNotify or 0)) >= 5 then
								data.lastDriftNotify = now
								local dn2 = playerNicknames[uidStr] or plr.Name
								notify(dn2.." Friction "..string.format("%.2f",curDrift).." > limit "..string.format("%.2f",pLimDrift), uidStr.."_drift")
							end
						else
							dl.TextColor3 = Color3.new(1,1,1)
							-- FIX #3: still log drift changes even when within limit
							if curDrift ~= data.lastDriftSetting then
								local dn2 = playerNicknames[uidStr] or plr.Name
								addLog(dn2, "Drift", string.format("%.2f",curDrift))
							end
						end
					else
						dl.Text, dl.TextColor3 = "Drift: N/A", Color3.new(0.5,0.5,0.5)
					end
				end
				data.lastDriftSetting = curDrift
			else
				-- FIX #5: player is not in a vehicle – show "In Foot"
				if sl then sl.Text = "In Foot" end
				if dl then dl.Text = "" end
			end
		end
	end

	-- Leader display
	do
		local leader = nil
		for _, data in pairs(playerData) do
			if not leader then leader = data
			elseif data.lap > leader.lap then leader = data
			elseif data.lap == leader.lap and data.sector > leader.sector then leader = data
			elseif data.lap == leader.lap and data.sector == leader.sector and data.sectorTime < leader.sectorTime then leader = data
			end
		end
		if leader then
			local secStr = leader.sector==0 and "—" or ("S"..leader.sector)
			lapLabel.Text   = qualiActive and ("Lap: "..leader.lap.."  "..secStr) or string.format("Lap: %d / %d  %s", leader.lap, targetLaps, secStr)
			sectorLabel.Text= "Leader: "..leader.displayName
		end
	end

	-- Delta (only when spectating)
	if spectatingPlayer then
		local tData = playerData[tostring(spectatingPlayer.UserId)]
		if tData and tData.lastDelta then
			deltaLabel.Text, deltaLabel.TextColor3, deltaLabel.Visible = "Delta: "..tData.lastDelta, tData.lastDeltaColor, true
		end
	else deltaLabel.Visible = false end

	-- Leaderboard refresh
	if now - lastLBRefresh >= 0.5 then
		lastLBRefresh  = now
		latestSnapshot = playerData
		rebuildLeaderboard(); rebuildFastestLaps()
	end
end)
