
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

-- ===============================
-- 1. Criação da Interface Base
-- ===============================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdvancedCollisionGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===============================
-- 2. Sistema de Notificação
-- ===============================
local notifFrame = Instance.new("Frame")
notifFrame.Name = "Notification"
notifFrame.Size = UDim2.new(0, 300, 0, 50)
notifFrame.Position = UDim2.new(0.5, -150, -0.2, 0)
notifFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
notifFrame.BorderSizePixel = 0
notifFrame.Parent = screenGui

local UICornerNotif = Instance.new("UICorner")
UICornerNotif.CornerRadius = UDim.new(0, 8)
UICornerNotif.Parent = notifFrame

local notifText = Instance.new("TextLabel")
notifText.Size = UDim2.new(1, 0, 1, 0)
notifText.BackgroundTransparency = 1
notifText.Font = Enum.Font.GothamBold
notifText.TextSize = 18
notifText.TextColor3 = Color3.fromRGB(255, 255, 255)
notifText.Text = ""
notifText.Parent = notifFrame

local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tweenInfoBack = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local tweenIn = TweenService:Create(notifFrame, tweenInfo, {Position = UDim2.new(0.5, -150, 0, 20)})
local tweenOut = TweenService:Create(notifFrame, tweenInfoBack, {Position = UDim2.new(0.5, -150, -0.2, 0)})

local currentNotifTask = nil
local function ShowNotification(text, color)
	if currentNotifTask then
		task.cancel(currentNotifTask)
	end
	
	notifText.Text = text
	notifText.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	
	tweenOut:Cancel()
	tweenIn:Play()
	
	currentNotifTask = task.spawn(function()
		task.wait(2.5)
		tweenIn:Cancel()
		tweenOut:Play()
		task.wait(0.5)
		currentNotifTask = nil
	end)
end

-- ===============================
-- 3. HUD Inferior
-- ===============================
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusHUD"
statusLabel.Size = UDim2.new(0, 450, 0, 30)
statusLabel.AnchorPoint = Vector2.new(0, 1)
statusLabel.Position = UDim2.new(0, 10, 1, -10)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamSemibold
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.RichText = true
statusLabel.TextStrokeTransparency = 0.2
statusLabel.Parent = screenGui

local isCollisionRemoved = false

-- ===============================
-- 4. Janela Principal (Painel)
-- ===============================
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 180, 0, 170)
mainFrame.Position = UDim2.new(0.5, -90, 0.7, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local UICornerMain = Instance.new("UICorner")
UICornerMain.CornerRadius = UDim.new(0, 8)
UICornerMain.Parent = mainFrame

local actionContainer = Instance.new("Frame")
actionContainer.Size = UDim2.new(1, -25, 1, 0)
actionContainer.BackgroundTransparency = 1
actionContainer.Parent = mainFrame

local toggleColBtn = Instance.new("TextButton")
toggleColBtn.Size = UDim2.new(1, -5, 0.2, -4)
toggleColBtn.Position = UDim2.new(0, 5, 0, 2)
toggleColBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
toggleColBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleColBtn.Font = Enum.Font.SourceSansBold
toggleColBtn.TextSize = 16
toggleColBtn.Text = "Remover Colisão"
toggleColBtn.Parent = actionContainer
Instance.new("UICorner", toggleColBtn).CornerRadius = UDim.new(0, 4)

local updateBtn = Instance.new("TextButton")
updateBtn.Size = UDim2.new(1, -5, 0.2, -4)
updateBtn.Position = UDim2.new(0, 5, 0.2, 2)
updateBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 200)
updateBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
updateBtn.Font = Enum.Font.SourceSansBold
updateBtn.TextSize = 16
updateBtn.Text = "Atualizar"
updateBtn.Parent = actionContainer
Instance.new("UICorner", updateBtn).CornerRadius = UDim.new(0, 4)

local autoContainer = Instance.new("Frame")
autoContainer.Size = UDim2.new(1, -5, 0.2, -4)
autoContainer.Position = UDim2.new(0, 5, 0.4, 2)
autoContainer.BackgroundTransparency = 1
autoContainer.Parent = actionContainer

local autoLabel = Instance.new("TextLabel")
autoLabel.Size = UDim2.new(0.65, 0, 1, 0)
autoLabel.BackgroundTransparency = 1
autoLabel.Text = "Auto Update:"
autoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
autoLabel.Font = Enum.Font.SourceSansBold
autoLabel.TextSize = 15
autoLabel.TextXAlignment = Enum.TextXAlignment.Left
autoLabel.Parent = autoContainer

local switchBg = Instance.new("TextButton")
switchBg.Text = ""
switchBg.Size = UDim2.new(0, 40, 0, 20)
switchBg.AnchorPoint = Vector2.new(0, 0.5)
switchBg.Position = UDim2.new(0.65, 0, 0.5, 0)
switchBg.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
switchBg.Parent = autoContainer
Instance.new("UICorner", switchBg).CornerRadius = UDim.new(1, 0)

local switchKnob = Instance.new("Frame")
switchKnob.Size = UDim2.new(0, 16, 0, 16)
switchKnob.AnchorPoint = Vector2.new(0, 0.5)
switchKnob.Position = UDim2.new(0, 2, 0.5, 0)
switchKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
switchKnob.Parent = switchBg
Instance.new("UICorner", switchKnob).CornerRadius = UDim.new(1, 0)

local broadcastBtn = Instance.new("TextButton")
broadcastBtn.Size = UDim2.new(1, -5, 0.2, -4)
broadcastBtn.Position = UDim2.new(0, 5, 0.6, 2)
broadcastBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
broadcastBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
broadcastBtn.Font = Enum.Font.SourceSansBold
broadcastBtn.TextSize = 16
broadcastBtn.Text = "Falar Status"
broadcastBtn.Parent = actionContainer
Instance.new("UICorner", broadcastBtn).CornerRadius = UDim.new(0, 4)

local logsBtn = Instance.new("TextButton")
logsBtn.Size = UDim2.new(1, -5, 0.2, -4)
logsBtn.Position = UDim2.new(0, 5, 0.8, 2)
logsBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 200)
logsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
logsBtn.Font = Enum.Font.SourceSansBold
logsBtn.TextSize = 16
logsBtn.Text = "Abrir Chat Logs"
logsBtn.Parent = actionContainer
Instance.new("UICorner", logsBtn).CornerRadius = UDim.new(0, 4)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 20, 1, 0)
toggleBtn.Position = UDim2.new(1, -20, 0, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.TextSize = 14
toggleBtn.Text = ">"
toggleBtn.Parent = mainFrame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

local isExpanded = true
toggleBtn.MouseButton1Click:Connect(function()
	isExpanded = not isExpanded
	if isExpanded then
		actionContainer.Visible = true
		mainFrame:TweenSize(UDim2.new(0, 180, 0, 170), "Out", "Quint", 0.3, true)
		toggleBtn.Text = ">"
	else
		actionContainer.Visible = false
		mainFrame:TweenSize(UDim2.new(0, 25, 0, 170), "Out", "Quint", 0.3, true)
		toggleBtn.Text = "<"
	end
end)

-- ===============================
-- 5. Lógica de Arrastar (Drag)
-- ===============================
local function MakeDraggable(guiObject)
	local dragging, dragInput, dragStart, startPos

	guiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = guiObject.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)

	guiObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then 
			local delta = input.Position - dragStart
			guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

MakeDraggable(mainFrame)

-- ===============================
-- 7. Função de Chat Universal
-- ===============================
local function forceChatMessage(message)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channel = TextChatService:FindFirstChild("TextChannels") and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
		if channel then
			channel:SendAsync(message)
		end
	else
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local sayMsg = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents") and ReplicatedStorage.DefaultChatSystemChatEvents:FindFirstChild("SayMessageRequest")
		if sayMsg then
			sayMsg:FireServer(message, "All")
		end
	end
end

-- Função Auxiliar para pegar o MaxSpeed atual
local function GetCurrentMaxSpeed()
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid.SeatPart then
			local maxSpeedObj = humanoid.SeatPart:FindFirstChild("MaxSpeed")
			if maxSpeedObj and maxSpeedObj:IsA("NumberValue") then
				return math.floor(maxSpeedObj.Value)
			end
		end
	end
	return 0
end

-- Botões Novos (Status & Logs)
broadcastBtn.MouseButton1Click:Connect(function()
	local roundedGrav = math.floor(Workspace.Gravity + 0.5)
	local currentMaxSpeed = GetCurrentMaxSpeed()
	local statusColisao = isCollisionRemoved and "OFF" or "ON"
	
	forceChatMessage("MAXSPEED: " .. tostring(currentMaxSpeed) .. " | GRAVITY: " .. tostring(roundedGrav) .. " | COLLISION: " .. statusColisao)
end)

-- Sistema de 10 minutos
task.spawn(function()
	while true do
		task.wait(600) -- 10 minutos
		local roundedGrav = math.floor(Workspace.Gravity + 0.5)
		local currentMaxSpeed = GetCurrentMaxSpeed()
		
		forceChatMessage("MY CURRENT MAXSPEED IS: " .. tostring(currentMaxSpeed))
		task.wait(1.5)
		forceChatMessage("CURRENT GRAVITY IS: " .. tostring(roundedGrav))
	end
end)

-- UI do Chat Logs
local logsWindow = Instance.new("Frame")
logsWindow.Size = UDim2.new(0, 350, 0, 250)
logsWindow.Position = UDim2.new(0.5, 100, 0.5, -125)
logsWindow.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
logsWindow.Visible = false
logsWindow.Parent = screenGui
Instance.new("UICorner", logsWindow).CornerRadius = UDim.new(0, 8)
MakeDraggable(logsWindow)

local logsTitle = Instance.new("TextLabel")
logsTitle.Size = UDim2.new(1, 0, 0, 30)
logsTitle.BackgroundTransparency = 1
logsTitle.Text = " Chat Logs"
logsTitle.TextColor3 = Color3.fromRGB(255,255,255)
logsTitle.Font = Enum.Font.GothamBold
logsTitle.TextSize = 16
logsTitle.TextXAlignment = Enum.TextXAlignment.Left
logsTitle.Parent = logsWindow

local logsClose = Instance.new("TextButton")
logsClose.Size = UDim2.new(0, 30, 0, 30)
logsClose.Position = UDim2.new(1, -30, 0, 0)
logsClose.BackgroundTransparency = 1
logsClose.Text = "X"
logsClose.TextColor3 = Color3.fromRGB(255, 50, 50)
logsClose.Font = Enum.Font.GothamBold
logsClose.TextSize = 16
logsClose.Parent = logsWindow
logsClose.MouseButton1Click:Connect(function() logsWindow.Visible = false end)

local logsScroll = Instance.new("ScrollingFrame")
logsScroll.Size = UDim2.new(1, -10, 1, -40)
logsScroll.Position = UDim2.new(0, 5, 0, 35)
logsScroll.BackgroundTransparency = 1
logsScroll.ScrollBarThickness = 6
logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logsScroll.Parent = logsWindow

local logsLayout = Instance.new("UIListLayout")
logsLayout.SortOrder = Enum.SortOrder.LayoutOrder
logsLayout.Padding = UDim.new(0, 2)
logsLayout.Parent = logsScroll

logsBtn.MouseButton1Click:Connect(function()
	logsWindow.Visible = not logsWindow.Visible
end)

local function addLogMessage(sender, msg)
	local msgLabel = Instance.new("TextLabel")
	msgLabel.Size = UDim2.new(1, -10, 0, 20)
	msgLabel.BackgroundTransparency = 1
	msgLabel.Text = "["..sender.."]: "..msg
	msgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	msgLabel.Font = Enum.Font.SourceSansSemibold
	msgLabel.TextSize = 15
	msgLabel.TextXAlignment = Enum.TextXAlignment.Left
	msgLabel.TextWrapped = true
	msgLabel.AutomaticSize = Enum.AutomaticSize.Y
	msgLabel.Parent = logsScroll
	
	logsScroll.CanvasPosition = Vector2.new(0, logsScroll.AbsoluteCanvasSize.Y)
end

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.MessageReceived:Connect(function(textChatMessage)
		if textChatMessage.TextSource then
			local plr = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
			local name = plr and plr.Name or "Sistema"
			addLogMessage(name, textChatMessage.Text)
		end
	end)
else
	for _, p in pairs(Players:GetPlayers()) do
		p.Chatted:Connect(function(msg) addLogMessage(p.Name, msg) end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.Chatted:Connect(function(msg) addLogMessage(p.Name, msg) end)
	end)
end

-- ===============================
-- 6. Lógica de Colisão & Restauração
-- ===============================
local autoUpdateEnabled = false
local autoUpdateConnection = nil
local originalCollisionStates = {}

local function turnOffAutoUpdate()
	if autoUpdateEnabled then
		autoUpdateEnabled = false
		TweenService:Create(switchBg, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(200, 50, 50)}):Play()
		TweenService:Create(switchKnob, TweenInfo.new(0.3), {Position = UDim2.new(0, 2, 0.5, 0)}):Play()
		if autoUpdateConnection then
			autoUpdateConnection:Disconnect()
			autoUpdateConnection = nil
		end
	end
end

local function manageCollisions(actionType)
	local count = 0
	
	if actionType == "Remove" or actionType == "AutoUpdate" then
		for _, obj in pairs(Workspace:GetDescendants()) do
			if obj:IsA("Model") and obj.Name == "Body" then
				for _, part in pairs(obj:GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then
						originalCollisionStates[part] = true
						part.CanCollide = false
						count = count + 1
					end
				end
			end
		end
		
		if count > 0 then
			isCollisionRemoved = true
			toggleColBtn.Text = "Restaurar Colisão"
			toggleColBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
			
			if actionType == "AutoUpdate" then
				task.spawn(ShowNotification, "Auto Update: "..count.." partes removidas!", Color3.fromRGB(200, 150, 255))
			else
				task.spawn(ShowNotification, "Colisão Removida!", Color3.fromRGB(100, 255, 100))
			end
			
			forceChatMessage("I DISABLED MY COLLISIONS!")
		elseif actionType == "Remove" then
			task.spawn(ShowNotification, "Nenhuma colisão encontrada.", Color3.fromRGB(200, 200, 200))
		end
		
	elseif actionType == "Restore" then
		for part, _ in pairs(originalCollisionStates) do
			if part and part.Parent then
				part.CanCollide = true
				count = count + 1
			end
		end
		originalCollisionStates = {}
		
		isCollisionRemoved = false
		toggleColBtn.Text = "Remover Colisão"
		toggleColBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		
		turnOffAutoUpdate()
		task.spawn(ShowNotification, "Colisão Restaurada!", Color3.fromRGB(255, 200, 50))
		forceChatMessage("I ENABLED MY COLLISIONS!")
	end
end

toggleColBtn.MouseButton1Click:Connect(function() 
	if isCollisionRemoved then
		manageCollisions("Restore")
	else
		manageCollisions("Remove")
	end
end)

updateBtn.MouseButton1Click:Connect(function() 
	if isCollisionRemoved then
		manageCollisions("Remove")
	else
		task.spawn(ShowNotification, "Remova a colisão primeiro!", Color3.fromRGB(255, 100, 100))
	end
end)

switchBg.MouseButton1Click:Connect(function()
	if not isCollisionRemoved then
		task.spawn(ShowNotification, "Remova a colisão primeiro!", Color3.fromRGB(255, 100, 100))
		return
	end
	
	autoUpdateEnabled = not autoUpdateEnabled
	
	if autoUpdateEnabled then
		TweenService:Create(switchBg, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(50, 200, 50)}):Play()
		TweenService:Create(switchKnob, TweenInfo.new(0.3), {Position = UDim2.new(0, 22, 0.5, 0)}):Play()
		
		manageCollisions("AutoUpdate")
		
		autoUpdateConnection = Workspace.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				local parent = descendant.Parent
				while parent and parent ~= Workspace do
					if parent.Name == "Body" and parent:IsA("Model") then
						if descendant.CanCollide then
							originalCollisionStates[descendant] = true
							descendant.CanCollide = false
						end
						break
					end
					parent = parent.Parent
				end
			end
		end)
	else
		turnOffAutoUpdate()
	end
end)

-- ===============================
-- 8. Sistema Anti-Cheat & HUD
-- ===============================
local lastGravity = Workspace.Gravity
local lastMaxSpeedValue = nil
local isBeingKicked = false

RunService.RenderStepped:Connect(function()
	if isBeingKicked then return end
	
	local currentGravity = Workspace.Gravity
	
	if currentGravity ~= lastGravity then
		forceChatMessage("I CHANGED MY GRAVITY TO: " .. tostring(currentGravity))
		if currentGravity > 196.25 then
			isBeingKicked = true
			task.wait(0.2)
			player:Kick("Anti cheat: gravity alterada de forma ilegal.")
			return
		end
		lastGravity = currentGravity
	end
	
	local colTextColor = isCollisionRemoved and "#32FF32" or "#FF3232"
	local colTextStatus = isCollisionRemoved and "Desativada" or "Ativada"
	
	local maxSpeedText = "A pé"
	local currentMaxSpeedValue = nil
	local character = player.Character
	
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid.SeatPart then
			local maxSpeedObj = humanoid.SeatPart:FindFirstChild("MaxSpeed")
			if maxSpeedObj and maxSpeedObj:IsA("NumberValue") then
				currentMaxSpeedValue = maxSpeedObj.Value
				maxSpeedText = tostring(math.floor(currentMaxSpeedValue))
			end
		end
	end
	
	if currentMaxSpeedValue ~= nil and lastMaxSpeedValue ~= nil then
		if currentMaxSpeedValue ~= lastMaxSpeedValue then
			forceChatMessage("I CHANGED MY SPEED TO: " .. tostring(currentMaxSpeedValue))
		end
	end
	lastMaxSpeedValue = currentMaxSpeedValue
	
	statusLabel.Text = string.format(
		"<font color='#E0E0E0'>Gravidade:</font> <b><font color='#FFFFFF'>%.1f</font></b> | <font color='#E0E0E0'>Colisão:</font> <b><font color='%s'>%s</font></b> | <font color='#E0E0E0'>MaxSpeed:</font> <b><font color='#FFFF55'>%s</font></b>", 
		currentGravity, 
		colTextColor, 
		colTextStatus,
		maxSpeedText
	)
end)

-- ===============================
-- 9. Sistema de Proximidade e Colisão (Lag Compensation Aprimorado)
-- ===============================
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "DamageFlashGui"
flashGui.IgnoreGuiInset = true 
flashGui.Parent = player:WaitForChild("PlayerGui")

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.new(1, 0, 1, 0)
flashFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
flashFrame.BackgroundTransparency = 1 
flashFrame.BorderSizePixel = 0
flashFrame.Parent = flashGui

local function PulseRedScreen()
	local tweenFlashIn = TweenService:Create(flashFrame, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {BackgroundTransparency = 0.5})
	local tweenFlashOut = TweenService:Create(flashFrame, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {BackgroundTransparency = 1})
	
	tweenFlashIn:Play()
	tweenFlashIn.Completed:Wait()
	tweenFlashOut:Play()
end

local notifiedProximity = {}
local collisionCooldown = {}
local giveSpaceCooldown = {}
local previousCarStates = {}

Players.PlayerRemoving:Connect(function(plr)
	previousCarStates[plr] = nil
end)

RunService.Heartbeat:Connect(function()
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or not humanoid.SeatPart then return end
	
	local myCarPart = humanoid.SeatPart
	local myPos = myCarPart.Position
	local myVelocity = myCarPart.AssemblyLinearVelocity
	
	local ping = player:GetNetworkPing() 
	
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherHumanoid = otherPlayer.Character:FindFirstChild("Humanoid")
			
			if otherHumanoid and otherHumanoid.SeatPart then
				local otherCarPart = otherHumanoid.SeatPart
				local otherVelocity = otherCarPart.AssemblyLinearVelocity
				local otherPos = otherCarPart.Position
				
				local minDistance = 9999
				
				if myVelocity.Magnitude > 5 or otherVelocity.Magnitude > 5 then
					local distNormal = (myPos - otherPos).Magnitude
					local distPredThem = (myPos - (otherPos + (otherVelocity * ping))).Magnitude
					local distPredMe = (otherPos - (myPos + (myVelocity * ping))).Magnitude
					minDistance = math.min(distNormal, distPredThem, distPredMe)
				else
					minDistance = (myPos - otherPos).Magnitude
				end
				
				local abruptChange = false
				local prevState = previousCarStates[otherPlayer]
				if prevState then
					local accelDiff = (otherVelocity - prevState.Velocity).Magnitude
					local yJump = math.abs(otherPos.Y - prevState.Position.Y)
					
					if (accelDiff > 35 or yJump > 4) and minDistance < 45 then
						abruptChange = true
					end
				end
				previousCarStates[otherPlayer] = {Velocity = otherVelocity, Position = otherPos}
				
				local relativeSpeed = (myVelocity - otherVelocity).Magnitude
				local dynamicProximityDist = 150 + (relativeSpeed * ping * 2.5)
				local giveSpaceDist = 50 + (relativeSpeed * ping * 1.5)
				
				if minDistance < dynamicProximityDist then 
					if not notifiedProximity[otherPlayer] then
                        notifiedProximity[otherPlayer] = true
						task.spawn(ShowNotification, "Carro de " .. otherPlayer.Name .. " está próximo!", Color3.fromRGB(255, 200, 50))
					end
				else
					notifiedProximity[otherPlayer] = false
				end
				
				if minDistance < giveSpaceDist and minDistance > 25 then
					if not giveSpaceCooldown[otherPlayer] then
						giveSpaceCooldown[otherPlayer] = true
						forceChatMessage("I NEED TO GIVE SPACE TO " .. otherPlayer.Name)
						task.spawn(ShowNotification, "Dê espaço para " .. otherPlayer.Name .. "!", Color3.fromRGB(255, 150, 50))
						
						task.delay(4, function()
							giveSpaceCooldown[otherPlayer] = nil
						end)
					end
				end
				
				if minDistance < 22 or abruptChange then 
					if not collisionCooldown[otherPlayer] then
						collisionCooldown[otherPlayer] = true
						
						task.spawn(PulseRedScreen)
						task.spawn(ShowNotification, "Batida! " .. otherPlayer.Name .. " colidiu em você!", Color3.fromRGB(255, 50, 50))
						forceChatMessage("I CRASHED INTO " .. otherPlayer.Name)
						
						task.delay(3, function()
							collisionCooldown[otherPlayer] = nil
						end)
					end
				end
			end
		end
	end
end)
