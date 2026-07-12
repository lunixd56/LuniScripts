--[[
    Car Controller para Mobile - FAB (V19)
    - Exclusivo Client-Side (LocalScript).
    - [Correção] Bug do Gás/W e AutoDrive pararem do nada (Inputs persistentes).
    - [Correção] Bug do Pit Limiter travar a velocidade do carro permanentemente.
    - [Adição] Botão de Boost (Left Shift) estilo segurar/soltar + maior que os outros.
    - [Adição] Integração do Boost com o Webhook do Discord (com anti-spam).
]]

-- ========================================================
-- CONFIGURAÇÃO DA WEBHOOK
-- ========================================================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1518611856758018175/hRhZwn6ihQmG3OzB_Rm5q45-4mGt9OCptgELnTh3lExcHwqE1f0kymg8-9DYznCysvg8" 

local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local pGui = player:WaitForChild("PlayerGui")

local savedPositions = {}
local keysPressed = {}
local originalCarSpeed = nil
local lastBoostLogTime = 0

if pGui:FindFirstChild("CarControls_FAB") then pGui.CarControls_FAB:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarControls_FAB"
ScreenGui.Parent = pGui
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999

-- ========================================================
-- TEXTOS ESTÁTICOS (CRÉDITOS E TELEMETRIA)
-- ========================================================
local creditsText = Instance.new("TextLabel", ScreenGui)
creditsText.Size = UDim2.new(0, 200, 0, 15)
creditsText.Position = UDim2.new(0.5, 0, 1, -10)
creditsText.AnchorPoint = Vector2.new(0.5, 1)
creditsText.BackgroundTransparency = 1
creditsText.Text = "Feito por luni56, qualquer bug me avisar"
creditsText.TextColor3 = Color3.fromRGB(150, 150, 150)
creditsText.TextSize = 10
creditsText.Font = Enum.Font.Gotham
creditsText.ZIndex = 1000

local telemetryText = Instance.new("TextLabel", ScreenGui)
telemetryText.Size = UDim2.new(0, 150, 0, 30)
telemetryText.Position = UDim2.new(0, 10, 1, -10)
telemetryText.AnchorPoint = Vector2.new(0, 1)
telemetryText.BackgroundTransparency = 1
telemetryText.Text = "Gravidade: --\nVelocidade: --"
telemetryText.TextColor3 = Color3.fromRGB(200, 200, 200)
telemetryText.TextSize = 10
telemetryText.TextXAlignment = Enum.TextXAlignment.Left
telemetryText.TextYAlignment = Enum.TextYAlignment.Bottom
telemetryText.Font = Enum.Font.GothamBold
telemetryText.ZIndex = 1000
telemetryText.Visible = false

-- ========================================================
-- FUNÇÃO CORE DO WEBHOOK
-- ========================================================
local function enviarLogDiscord(mensagem)
    if WEBHOOK_URL == "SUA_WEBHOOK_AQUI" or WEBHOOK_URL == "" then return end
    
    task.spawn(function()
        local dados = {
            ["content"] = "",
            ["embeds"] = {{
                ["title"] = "🚗 Notificação de Uso do Script",
                ["description"] = mensagem,
                ["color"] = 16753920, 
                ["footer"] = {
                    ["text"] = "Mobile Car Controller - FAB • " .. os.date("%X")
                }
            }}
        }
        
        local json = HttpService:JSONEncode(dados)
        local funcaoRequest = (request or http_request or syn and syn.request)
        
        if funcaoRequest then
            funcaoRequest({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = json
            })
        else
            pcall(function() HttpService:PostAsync(WEBHOOK_URL, json) end)
        end
    end)
end

enviarLogDiscord("👤 **" .. player.Name .. "** abriu o Script.")

-- ========================================================
-- 1. SISTEMA DE LOADING (5 SEGUNDOS COM FADE)
-- ========================================================
local function launchLoadingScreen()
    local loadingFrame = Instance.new("Frame", ScreenGui)
    loadingFrame.Name = "LoadingScreen"
    loadingFrame.Size = UDim2.new(0, 320, 0, 75)
    loadingFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    loadingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    loadingFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    loadingFrame.BackgroundTransparency = 1 
    loadingFrame.ZIndex = 5000

    local uiCorner = Instance.new("UICorner", loadingFrame)
    uiCorner.CornerRadius = UDim.new(0.2, 0)

    local loadingText = Instance.new("TextLabel", loadingFrame)
    loadingText.Size = UDim2.new(1, -20, 1, -20)
    loadingText.Position = UDim2.new(0.5, 0, 0.5, 0)
    loadingText.AnchorPoint = Vector2.new(0.5, 0.5)
    loadingText.BackgroundTransparency = 1
    loadingText.Text = "Mobile Car Controller - FAB"
    loadingText.TextColor3 = Color3.new(1, 1, 1)
    loadingText.TextTransparency = 1 
    loadingText.Font = Enum.Font.GothamBold
    loadingText.TextScaled = true
    loadingText.ZIndex = 5001

    task.spawn(function()
        local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local fadeInBg = TweenService:Create(loadingFrame, tweenInfo, {BackgroundTransparency = 0.2})
        local fadeInText = TweenService:Create(loadingText, tweenInfo, {TextTransparency = 0})
        
        fadeInBg:Play()
        fadeInText:Play()
        
        task.wait(4) 
        
        local fadeOutBg = TweenService:Create(loadingFrame, tweenInfo, {BackgroundTransparency = 1})
        local fadeOutText = TweenService:Create(loadingText, tweenInfo, {TextTransparency = 1})
        
        fadeOutBg:Play()
        fadeOutText:Play()
        
        fadeOutBg.Completed:Connect(function() loadingFrame:Destroy() end)
    end)
end

launchLoadingScreen()

-- ========================================================
-- 2. SISTEMA DE NOTIFICAÇÃO LOCAL
-- ========================================================
local function showNotification(message)
    local notifFrame = Instance.new("Frame", ScreenGui)
    notifFrame.Size = UDim2.new(0, 320, 0, 50)
    notifFrame.Position = UDim2.new(0.5, -160, -0.2, 0) 
    notifFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    notifFrame.BackgroundTransparency = 0.1
    notifFrame.ZIndex = 2000
    
    Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0.2, 0)
    Instance.new("UIStroke", notifFrame).Color = Color3.fromRGB(100, 100, 255)

    local notifText = Instance.new("TextLabel", notifFrame)
    notifText.Size = UDim2.new(1, -20, 1, 0)
    notifText.Position = UDim2.new(0, 10, 0, 0)
    notifText.BackgroundTransparency = 1
    notifText.Text = message
    notifText.TextColor3 = Color3.new(1, 1, 1)
    notifText.Font = Enum.Font.GothamBold
    notifText.TextScaled = true
    notifText.ZIndex = 2001

    local tweenIn = TweenService:Create(notifFrame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, -160, 0.1, 0)})
    local tweenOut = TweenService:Create(notifFrame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0.5, -160, -0.2, 0)})

    tweenIn:Play()
    task.delay(4, function()
        tweenOut:Play()
        tweenOut.Completed:Connect(function() notifFrame:Destroy() end)
    end)
end

-- ========================================================
-- 3. VARIÁVEIS DE ESTADO E SISTEMA DRAG
-- ========================================================
local isEditMode = false
local systemEnabled = true
local isInCar = false
local controlButtons = {} 

local autoDriveEnabled = false
local pitLimiterEnabled = false

local carBaseSpeed = 0
local lastSeat = nil
local lastActiveState = false 

local function makeDraggable(hitbox, frameToMove)
    local dragging = false
    local dragInput, dragStart, startPos

    hitbox.InputBegan:Connect(function(input)
        if not isEditMode then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frameToMove.Position
            
            local connection
            connection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then 
                    dragging = false 
                    savedPositions[frameToMove.Name] = frameToMove.Position
                    connection:Disconnect()
                end
            end)
        end
    end)

    hitbox.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging and isEditMode then
            local delta = input.Position - dragStart
            frameToMove.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ========================================================
-- 4. CRIADORES DE INTERFACE (COM UIGRADIENT)
-- ========================================================
local function createButtonWithKeybind(name, text, pos, size, keyCode)
    local frame = Instance.new("Frame", ScreenGui)
    frame.Name = name
    frame.Size = size
    frame.Position = savedPositions[name] or pos
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0.2
    frame.ZIndex = 100
    frame.Visible = false 
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.25, 0)
    
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(150, 150, 150)
    stroke.Thickness = 2
    
    local gradient = Instance.new("UIGradient", frame)
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 40, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 15))
    }
    gradient.Rotation = 90

    local txt = Instance.new("TextLabel", frame)
    txt.Size = UDim2.new(1, -10, 1, -10)
    txt.Position = UDim2.new(0.5, 0, 0.5, 0)
    txt.AnchorPoint = Vector2.new(0.5, 0.5)
    txt.Text = text
    txt.TextColor3 = Color3.new(1, 1, 1)
    txt.BackgroundTransparency = 1
    txt.Font = Enum.Font.GothamBold
    txt.TextScaled = true 
    txt.ZIndex = 101

    local hitbox = Instance.new("TextButton", frame)
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 105 

    local resizeBtn = Instance.new("TextButton", frame)
    resizeBtn.Name = "ResizeBtn"
    resizeBtn.Size = UDim2.new(0, 30, 0, 30)
    resizeBtn.Position = UDim2.new(1, -32, 0, 2)
    resizeBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    resizeBtn.Text = "➕"
    resizeBtn.TextColor3 = Color3.new(1, 1, 1)
    resizeBtn.Visible = false
    resizeBtn.ZIndex = 110
    Instance.new("UICorner", resizeBtn).CornerRadius = UDim.new(0.3, 0)

    resizeBtn.MouseButton1Click:Connect(function()
        local currentX = frame.Size.X.Offset
        local nextX = currentX + 15
        local nextY = (frame.Name == "Gas_Key") and (nextX * 1.2) or nextX
        if nextX > 170 then nextX = 85; nextY = (frame.Name == "Gas_Key") and (85 * 1.2) or 85 end
        frame.Size = UDim2.new(0, nextX, 0, nextY)
    end)

    hitbox.InputBegan:Connect(function(input)
        if isEditMode then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            gradient.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 40))
            }
            keysPressed[keyCode] = true
            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
            
            -- Webhook exclusivo para o uso do Boost (com cooldown de 10 segundos)
            if name == "Boost_Key" then
                local tempoAtual = os.clock()
                if tempoAtual - lastBoostLogTime > 10 then
                    lastBoostLogTime = tempoAtual
                    enviarLogDiscord("🚀 **" .. player.Name .. "** usou o Boost (Left Shift).")
                end
            end
        end
    end)

    hitbox.InputEnded:Connect(function(input)
        if isEditMode then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            gradient.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 40, 40)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 15))
            }
            keysPressed[keyCode] = nil
            if keyCode == Enum.KeyCode.W and autoDriveEnabled then return end
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end
    end)

    table.insert(controlButtons, frame)
    makeDraggable(hitbox, frame)
    return frame
end

local function createSmallToggle(name, text, pos)
    local frame = Instance.new("Frame", ScreenGui)
    frame.Name = name
    frame.Size = UDim2.new(0, 60, 0, 40)
    frame.Position = savedPositions[name] or pos
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0.1
    frame.ZIndex = 100
    frame.Visible = false
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.2, 0)
    Instance.new("UIStroke", frame).Color = Color3.new(1, 1, 1)

    local gradient = Instance.new("UIGradient", frame)
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))
    }
    gradient.Rotation = 90

    local txt = Instance.new("TextLabel", frame)
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.Text = text
    txt.TextColor3 = Color3.new(1, 1, 1)
    txt.BackgroundTransparency = 1
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 10
    txt.ZIndex = 101

    local hitbox = Instance.new("TextButton", frame)
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 102

    table.insert(controlButtons, frame)
    makeDraggable(hitbox, frame)
    return frame, txt, hitbox, gradient
end

-- ========================================================
-- 5. LAYOUT DE CONTROLES PRINCIPAIS
-- ========================================================
local yPos = 0.65
local baseSize = 95

createButtonWithKeybind("Left_Key", "<", UDim2.new(0.08, 0, yPos, 0), UDim2.new(0, baseSize, 0, baseSize), Enum.KeyCode.A)
createButtonWithKeybind("Right_Key", ">", UDim2.new(0.26, 0, yPos, 0), UDim2.new(0, baseSize, 0, baseSize), Enum.KeyCode.D)
createButtonWithKeybind("Gas_Key", "▲", UDim2.new(0.82, 0, yPos - 0.08, 0), UDim2.new(0, baseSize, 0, baseSize * 1.2), Enum.KeyCode.W)
createButtonWithKeybind("Brake_Key", "▼", UDim2.new(0.66, 0, yPos, 0), UDim2.new(0, baseSize, 0, baseSize), Enum.KeyCode.S)
createButtonWithKeybind("Jump_Key", "PULO", UDim2.new(0.47, 0, yPos + 0.12, 0), UDim2.new(0, baseSize * 0.7, 0, baseSize * 0.7), Enum.KeyCode.Space)

-- Toggles Superiores Direitos e o Novo Botão de Boost (Maior e posicionado perfeitamente)
local autoFrame, autoTxt, autoHitbox, autoGrad = createSmallToggle("AutoDrive", "AUTO:\nOFF", UDim2.new(0.85, 0, yPos - 0.18, 0))
local pitFrame, pitTxt, pitHitbox, pitGrad = createSmallToggle("PitLimiter", "PIT:\nOFF", UDim2.new(0.76, 0, yPos - 0.18, 0))
createButtonWithKeybind("Boost_Key", "BOOST", UDim2.new(0.66, 0, yPos - 0.18, 0), UDim2.new(0, 75, 0, 45), Enum.KeyCode.LeftShift)

-- ========================================================
-- 6. INTERAÇÕES DOS TOGGLES (COM NOTIFICAÇÕES)
-- ========================================================
local function getCurrentSeat()
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
            return hum.SeatPart
        end
    end
    return nil
end

autoHitbox.MouseButton1Click:Connect(function()
    if isEditMode then return end
    autoDriveEnabled = not autoDriveEnabled
    
    if autoDriveEnabled then
        autoGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 80, 0))}
        autoTxt.Text = "AUTO:\nON"
        showNotification("🚗 Auto Drive Ativado!")
        enviarLogDiscord("🤖 **" .. player.Name .. "** ativou o Auto Drive.")
    else
        autoGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))}
        autoTxt.Text = "AUTO:\nOFF"
        showNotification("🛑 Auto Drive Desativado.")
    end
    
    VirtualInputManager:SendKeyEvent(autoDriveEnabled, Enum.KeyCode.W, false, game)
end)

pitHitbox.MouseButton1Click:Connect(function()
    if isEditMode then return end
    local seat = getCurrentSeat()
    if not seat then return end
    
    local maxSpeedValue = seat:FindFirstChild("MaxSpeed")
    
    if pitLimiterEnabled then
        pitLimiterEnabled = false
        pitGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))}
        pitTxt.Text = "PIT:\nOFF"
        showNotification("💨 Pit Limiter Desligado!")
        if maxSpeedValue and originalCarSpeed then
            pcall(function() maxSpeedValue.Value = originalCarSpeed end)
        end
    else
        local currentMax = maxSpeedValue and maxSpeedValue.Value or 100
        if currentMax <= 30 then
            showNotification("⚠️ Velocidade muito baixa para usar o PIT!")
            return
        end
        originalCarSpeed = currentMax -- Trava o valor original correto de forma imutável
        pitLimiterEnabled = true
        pitGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 120, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 60, 0))}
        pitTxt.Text = "PIT:\nON"
        showNotification("🏁 Pit Limiter Ligado!")
        enviarLogDiscord("🏁 **" .. player.Name .. "** ativou o Pit Limiter.")
    end
end)

-- ========================================================
-- 7. BOTÕES DO TOPO
-- ========================================================
local function createTopButton(name, text, pos, color1, color2)
    local frame = Instance.new("Frame", ScreenGui)
    frame.Size = UDim2.new(0, 150, 0, 42)
    frame.Position = savedPositions[name] or pos
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.ZIndex = 100
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.2, 0)
    
    local gradient = Instance.new("UIGradient", frame)
    gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, color1), ColorSequenceKeypoint.new(1, color2)}
    gradient.Rotation = 90
    
    local txt = Instance.new("TextLabel", frame)
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.Text = text
    txt.TextColor3 = Color3.new(1, 1, 1)
    txt.BackgroundTransparency = 1
    txt.Font = Enum.Font.GothamBold
    txt.TextSize = 13
    txt.ZIndex = 101

    local hitbox = Instance.new("TextButton", frame)
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 102

    makeDraggable(hitbox, frame)
    return frame, txt, hitbox, gradient
end

local toggleFrame, toggleTxt, toggleHitbox, toggleGrad = createTopButton("SystemToggle", "Controles: ON", UDim2.new(0.80, 0, 0.15, 0), Color3.fromRGB(0, 150, 0), Color3.fromRGB(0, 80, 0))
toggleHitbox.MouseButton1Click:Connect(function()
    systemEnabled = not systemEnabled
    toggleTxt.Text = systemEnabled and "Controles: ON" or "Controles: OFF"
    if systemEnabled then
        toggleGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 150, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 80, 0))}
        showNotification("✅ Controles do HUD Ligados.")
    else
        toggleGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 0, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 0, 0))}
        showNotification("❌ Controles do HUD Desligados.")
    end
end)

local editFrame, editTxt, editHitbox, editGrad = createTopButton("EditToggle", "Modo Edição: OFF", UDim2.new(0.80, 0, 0.25, 0), Color3.fromRGB(70, 70, 70), Color3.fromRGB(30, 30, 30))
editHitbox.MouseButton1Click:Connect(function()
    isEditMode = not isEditMode
    editTxt.Text = isEditMode and "Modo Edição: ON" or "Modo Edição: OFF"
    
    if isEditMode then
        editGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 120, 180)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 60, 100))}
        showNotification("✏️ Modo de Edição Ativo. Arraste os botões!")
    else
        editGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 70, 70)), ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))}
        showNotification("🔒 Posições Salvas.")
    end
    
    for _, btn in pairs(controlButtons) do
        local stroke = btn:FindFirstChild("UIStroke")
        local resize = btn:FindFirstChild("ResizeBtn")
        if stroke then stroke.Color = isEditMode and Color3.new(0, 0.8, 1) or Color3.fromRGB(150, 150, 150) end
        if resize then resize.Visible = isEditMode end
    end
end)

-- ========================================================
-- 8. LOOP HEARTBEAT CORE E TELEMETRIA (ANTI-BUG DE INPUTS)
-- ========================================================
RunService.Heartbeat:Connect(function()
    local seat = getCurrentSeat()
    local currentlyInCar = (seat ~= nil)

    if currentlyInCar then
        if seat ~= lastSeat then
            lastSeat = seat
            local maxSpeedValue = seat:FindFirstChild("MaxSpeed")
            if maxSpeedValue and maxSpeedValue:IsA("ValueBase") then
                carBaseSpeed = maxSpeedValue.Value
            else
                carBaseSpeed = 100
            end
            pitLimiterEnabled = false
            lastActiveState = false
        end

        -- Repetição forçada de Inputs para impedir que soltem sozinhos "do nada"
        if systemEnabled then
            for key, _ in pairs(keysPressed) do
                VirtualInputManager:SendKeyEvent(true, key, false, game)
            end
            if autoDriveEnabled then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
            end
        end

        local maxSpeedValue = seat:FindFirstChild("MaxSpeed")
        if maxSpeedValue and maxSpeedValue:IsA("ValueBase") then
            if pitLimiterEnabled then
                local targetSpeed = (originalCarSpeed or 100) - 30
                if targetSpeed < 10 then targetSpeed = 10 end
                
                pcall(function()
                    if maxSpeedValue.Value ~= targetSpeed then
                        maxSpeedValue.Value = targetSpeed
                    end
                end)
            else
                carBaseSpeed = maxSpeedValue.Value
            end
        end
    end

    if isInCar and not currentlyInCar then
        local keysToRelease = {Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.LeftShift}
        for _, key in ipairs(keysToRelease) do
            VirtualInputManager:SendKeyEvent(false, key, false, game)
            keysPressed[key] = nil
        end
        
        autoDriveEnabled = false
        autoGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))}
        autoTxt.Text = "AUTO:\nOFF"
        
        pitLimiterEnabled = false
        pitGrad.Color = ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))}
        pitTxt.Text = "PIT:\nOFF"
        
        carBaseSpeed = 0
        originalCarSpeed = nil
        lastSeat = nil
        lastActiveState = false
    end

    isInCar = currentlyInCar
    local shouldShowCustom = systemEnabled and (isInCar or isEditMode)
    
    for _, btn in pairs(controlButtons) do
        btn.Visible = shouldShowCustom
    end
    
    -- Telemetria do Painel
    if shouldShowCustom then
        local gravidadeAtual = math.floor(workspace.Gravity)
        local velocidadeExibida = math.floor(carBaseSpeed)
        telemetryText.Text = "Gravidade: " .. gravidadeAtual .. "\nVelocidade: " .. velocidadeExibida
        telemetryText.Visible = true
    else
        telemetryText.Visible = false
    end

    local touchGui = pGui:FindFirstChild("TouchGui")
    if touchGui then
        local frame = touchGui:FindFirstChild("TouchControlFrame")
        if systemEnabled and isInCar then
            touchGui.Enabled = false
            if frame then frame.Position = UDim2.new(2, 0, 2, 0) end
        else
            touchGui.Enabled = true
            if frame then frame.Position = UDim2.new(0, 0, 0, 0) end
        end
    end
end)
