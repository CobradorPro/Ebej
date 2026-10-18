-- Invicible Flight 4.2 - versão MOBILE (Delta Executor)
-- Controles na tela: FLY (liga/desliga), BOOST, SOBE, DESCE
-- Analógico do Roblox = direção (relativa à câmera)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

-- evita duplicar ao executar de novo
if env.XVMobile then
	pcall(function() env.XVMobile.Destroy() end)
end

local conns = {}
local function track(c) table.insert(conns, c) return c end

-- ===== configurações (iguais ao original) =====
local NORMAL_SPEED = 69
local BOOST_SPEED = 345
local SMOOTH = 8            -- suavização da velocidade
local TURN_SMOOTH = 3
local MAX_TURN = 30         -- graus (curva no boost)
local BOOST_COOLDOWN = 7
local BOOST_TIME = 4.5

local ANIM_IDS = {
	Idle = "91070209987449",
	Forward = "71022035423223",
	Back = "100937015689535",
	Boost = "71147904131761",
	Start = "88638764356174",
	Loop = "125475313956714",
	TurnLeft = "125312551762145",
	TurnRight = "98729594690961",
}

local SOUND_IDS = {
	Boost = "rbxassetid://134766751892656",
	Lift = "rbxassetid://73797069547045",
}
local PARTICLE_TEX = "rbxassetid://123331711329790"

-- ===== estado =====
local character, humanoid, root
local anims = {}
local flying, boosting, stunned = false, false, false
local lastBoost = 0
local holdUp, holdDown = false, false
local velocity = Vector3.zero
local turnAngle = 0

local gyro = Instance.new("BodyGyro")
gyro.Name = "FlightGyro"
gyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
gyro.P = 2e5
gyro.D = 500

local bv = Instance.new("BodyVelocity")
bv.Name = "FlightVelocity"
bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
bv.P = 1e4
bv.Velocity = Vector3.zero

-- ===== animações =====
local function loadAnims()
	anims = {}
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
	for name, id in pairs(ANIM_IDS) do
		pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			anims[name] = animator:LoadAnimation(a)
		end)
	end
end

local function playAnim(name)
	local a = anims[name]
	if a and not a.IsPlaying then
		for _, o in pairs(anims) do
			if o.IsPlaying then o:Stop() end
		end
		pcall(function() a:Play() end)
	end
end

local function stopAnims()
	for _, o in pairs(anims) do
		if o.IsPlaying then o:Stop() end
	end
end

-- ===== efeitos =====
local function playSound(id)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 1
	s.Parent = workspace
	s:Play()
	Debris:AddItem(s, 6)
end

local function makeRing(cf)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 235, 255)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.45, 2, 2)
	ring.CFrame = cf * CFrame.Angles(math.rad(30), math.rad(90), 0)
	ring.Parent = workspace
	Debris:AddItem(ring, 1)

	TweenService:Create(
		ring,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(0.45, 30, 30) }
	):Play()
end

local function burstParticles()
	if not root then return end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = PARTICLE_TEX
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Speed = NumberRange.new(20, 40)
	pe.SpreadAngle = Vector2.new(360, 360)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = root
	pe:Emit(40)
	Debris:AddItem(pe, 2)
end

local shakeEnd, shakeMag = 0, 0
local function shake(duration, magnitude)
	shakeEnd = tick() + duration
	shakeMag = magnitude
end

track(RunService.RenderStepped:Connect(function()
	if tick() < shakeEnd then
		local cam = workspace.CurrentCamera
		local m = shakeMag * math.clamp((shakeEnd - tick()), 0, 1)
		cam.CFrame = cam.CFrame * CFrame.Angles(
			math.rad((math.random() - 0.5) * m),
			math.rad((math.random() - 0.5) * m),
			0
		)
	end
end))

-- ===== lógica de voo =====
local function toggleFly()
	if stunned or not root then return end

	if not flying then
		flying = true
		gyro.Parent = root
		bv.Parent = root
		playSound(SOUND_IDS.Lift)
		playAnim("Idle")

		-- sobe um pouco ao ligar
		task.spawn(function()
			local target = root.Position + Vector3.new(0, 5, 0)
			local t = 0
			while t < 0.4 and flying and root do
				t += RunService.RenderStepped:Wait()
				root.CFrame = root.CFrame:Lerp(CFrame.new(target), math.clamp(t / 0.4, 0, 1))
			end
		end)
	else
		flying = false
		boosting = false
		gyro.Parent = nil
		bv.Parent = nil
		velocity = Vector3.zero
		turnAngle = 0
		stopAnims()
	end
end

local function doBoost()
	if not flying or boosting or not root then return end
	if tick() - lastBoost < BOOST_COOLDOWN then return end

	boosting = true
	lastBoost = tick()
	playSound(SOUND_IDS.Boost)
	shake(1.5, 6)
	makeRing(root.CFrame)
	stopAnims()
	playAnim("Boost")

	task.delay(0.7, function()
		if flying and boosting and root then
			makeRing(root.CFrame)
			playAnim("Loop")
		end
	end)

	task.delay(1.8, function()
		if flying and boosting and root then
			makeRing(root.CFrame)
			burstParticles()
		end
	end)

	task.delay(BOOST_TIME, function()
		if boosting then
			boosting = false
			turnAngle = 0
			if flying then playAnim("Idle") end
		end
	end)
end

-- movimento a cada frame
track(RunService.RenderStepped:Connect(function(dt)
	if not flying or not root or not humanoid then return end

	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then return end
	flatLook = flatLook.Unit
	local flatRight = flatLook:Cross(Vector3.yAxis)

	local md = humanoid.MoveDirection
	local fwd = md:Dot(flatLook)      -- -1..1 (frente/trás)
	local strafe = md:Dot(flatRight)  -- -1..1 (esquerda/direita)

	local vertical = 0
	if holdUp then vertical += 1 end
	if holdDown then vertical -= 1 end

	local dir
	local speed

	if boosting then
		speed = BOOST_SPEED
		local target = strafe * MAX_TURN
		turnAngle = math.clamp(turnAngle + (target - turnAngle) * TURN_SMOOTH * dt, -MAX_TURN, MAX_TURN)
		local rotated = CFrame.fromAxisAngle(Vector3.yAxis, -math.rad(turnAngle)) * flatLook
		dir = rotated + Vector3.new(0, vertical, 0)
		if dir.Magnitude > 0 then dir = dir.Unit end
	else
		speed = NORMAL_SPEED
		turnAngle = 0
		dir = look * fwd + cam.CFrame.RightVector * strafe + Vector3.new(0, vertical, 0)
		if dir.Magnitude > 0 then dir = dir.Unit end

		-- animações de acordo com o movimento
		if strafe < -0.5 and math.abs(strafe) > math.abs(fwd) then
			playAnim("TurnLeft")
		elseif strafe > 0.5 and math.abs(strafe) > math.abs(fwd) then
			playAnim("TurnRight")
		elseif fwd < -0.3 then
			playAnim("Back")
		elseif fwd > 0.3 then
			playAnim("Forward")
		else
			playAnim("Idle")
		end
	end

	velocity = velocity:Lerp(dir * speed, math.clamp(SMOOTH * dt, 0, 1))
	bv.Velocity = velocity

	local faceDir = boosting
		and (CFrame.fromAxisAngle(Vector3.yAxis, -math.rad(turnAngle)) * flatLook)
		or flatLook
	gyro.CFrame = CFrame.new(root.Position, root.Position + faceDir)
end))

-- ===== personagem / respawn =====
local function setupCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")

	flying, boosting = false, false
	velocity = Vector3.zero
	turnAngle = 0
	gyro.Parent = nil
	bv.Parent = nil

	loadAnims()
end

track(player.CharacterAdded:Connect(setupCharacter))
setupCharacter(player.Character or player.CharacterAdded:Wait())

-- ===== teclado (opcional, caso use no PC) =====
track(UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.X then
		toggleFly()
	elseif input.KeyCode == Enum.KeyCode.R then
		doBoost()
	end
end))

-- ===== botões na tela =====
local gui = Instance.new("ScreenGui")
gui.Name = "InvicibleFlightMobile"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999

local okParent = pcall(function()
	gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not okParent or not gui.Parent then
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function makeButton(text, pos, size, color)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = UDim2.fromOffset(size, size)
	b.Position = pos
	b.AnchorPoint = Vector2.new(1, 0)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.25
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = true
	b.Parent = gui

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b

	local s = Instance.new("UIStroke")
	s.Color = Color3.new(1, 1, 1)
	s.Transparency = 0.5
	s.Thickness = 2
	s.Parent = b

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.25, 0)
	pad.PaddingBottom = UDim.new(0.25, 0)
	pad.PaddingLeft = UDim.new(0.15, 0)
	pad.PaddingRight = UDim.new(0.15, 0)
	pad.Parent = b

	return b
end

-- posição: lado direito, acima do botão de pulo
local flyBtn   = makeButton("FLY",    UDim2.new(1, -20, 0.18, 0),  70, Color3.fromRGB(40, 120, 255))
local boostBtn = makeButton("BOOST",  UDim2.new(1, -20, 0.18, 80), 70, Color3.fromRGB(255, 110, 40))
local upBtn    = makeButton("SOBE",   UDim2.new(1, -100, 0.18, 0), 70, Color3.fromRGB(60, 180, 90))
local downBtn  = makeButton("DESCE",  UDim2.new(1, -100, 0.18, 80), 70, Color3.fromRGB(180, 60, 60))

flyBtn.Activated:Connect(toggleFly)
boostBtn.Activated:Connect(doBoost)

local function bindHold(btn, setter)
	btn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then
			setter(true)
		end
	end)
	btn.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then
			setter(false)
		end
	end)
end

bindHold(upBtn, function(v) holdUp = v end)
bindHold(downBtn, function(v) holdDown = v end)

-- feedback visual do estado
track(RunService.Heartbeat:Connect(function()
	flyBtn.BackgroundColor3 = flying and Color3.fromRGB(40, 200, 120) or Color3.fromRGB(40, 120, 255)
	local left = math.max(0, BOOST_COOLDOWN - (tick() - lastBoost))
	boostBtn.Text = (left > 0 and not boosting) and string.format("%.0f", left) or "BOOST"
	boostBtn.BackgroundColor3 = boosting and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 110, 40)
end))

-- ===== limpeza =====
env.XVMobile = {
	Destroy = function()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		flying, boosting = false, false
		gyro:Destroy()
		bv:Destroy()
		gui:Destroy()
	end,
}

print("Invicible Flight Mobile carregado!")
