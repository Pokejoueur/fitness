local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local Events = ReplicatedStorage:WaitForChild("Events")

local Signal = require(Assets.Modules.Signal)
local Spring = require(Assets.Modules.Spring)
local Spring2 = require(Assets.Modules.Spring2)
local Network = require(Assets.Modules.Network)
local Raycast = require(Assets.Modules.Raycast)
Raycast.VisualizeCasts = false

local mouseMovement = Spring2.new(Vector3.new())
mouseMovement.Speed = 15
mouseMovement.Damper = 0.65

local desiredXOffset, desiredYOffset = 0, 0

local maxCameraOffset = 2.5
local swayMultiplier = 3.5

local function loadAnim(animator, id)
	if (id ~= 0 and id ~= nil) then
		local track = Instance.new("Animation")
		track.AnimationId = "rbxassetid://" .. id
		return animator:LoadAnimation(track)
	end
	
	return nil
end

local function IsInFirstPerson()
	local camera = workspace.CurrentCamera

	if camera then
		if camera.CameraType.Name == "Scriptable" then
			return false
		end

		local focus = camera.Focus.Position
		local origin = camera.CFrame.Position

		return (focus - origin).Magnitude <= 1
	end

	return false
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local limbs = {
	"Head",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
	"HumanoidRootPart",
}

return function(tool, script)
	local gunSettings, gunModel
	local settingsSignal = Signal.new()
	tool["__listener"].OnClientEvent:Connect(function(module, model)
		gunSettings = require(module)
		gunModel = model
		task.wait(1 / 30)
		settingsSignal:Fire()
	end)
	
	-- // wait for settings data
	settingsSignal:Wait()
	
	local player = game.Players.LocalPlayer
	if (not player) then
		tool:Destroy()
	end
	local mouse = player:GetMouse()
	repeat task.wait() until typeof(player.Character) == "Instance"
	local character = player.Character
	local humanoid = character:WaitForChild("Humanoid")
	if (character:FindFirstChild(tool)) then
		humanoid:UnequipTools()
	end
	
	local settings = player:WaitForChild("Settings")
	
	local anims = {}
	for index,id in pairs(gunSettings.anims) do
		anims[index] = loadAnim(humanoid, id)
	end
	
	local clipCurrent = gunSettings.ammo.infAmmo and math.huge or gunSettings.ammo.clipSize
	local clipSize = gunSettings.ammo.infAmmo and math.huge or gunSettings.ammo.clipSize
	local maxAmmo = gunSettings.ammo.maxAmmo
	
	local reloading = false
	local equipped = false
	local active = false
	local firing = false
	local altReload = false
	local aiming = false
	local switching = false
	local scoping = false
	local reloadCancelled = false
	local fired = false
	
	local equipTime = 0
	local fireDelay = 0
	local deltaTime = 0
	local modeSwitch = 1
	local defaultMouseDeltaSens = UserInputService.MouseDeltaSensitivity
	
	local fireMode = gunSettings.ammo.mode
	
	local defaultspeed = humanoid.WalkSpeed
	
	local recoil = Spring.spring.new(Vector3.new())
	recoil.d = gunSettings.fire.recoil.damper
	recoil.s = gunSettings.fire.recoil.speed
	
	local corePart = gunModel[gunSettings.corePart]
	local corePartString = Instance.new("StringValue")
	corePartString.Name = "corePart"
	corePartString.Value = gunSettings.corePart
	corePartString.Parent = gunModel
	
	local compressor = Instance.new("CompressorSoundEffect")
	compressor.Attack = 0.5
	compressor.GainMakeup = 0
	compressor.Ratio = 1
	compressor.Release = 0.8
	compressor.Threshold = -50
	compressor.Name = " "
	compressor.Parent = script
	
	local gunUI = Assets.Misc.gunUI:Clone()
	gunUI.Name = tool.Name
	gunUI.Parent = script
	local progressFrame = gunUI.Crosshair.Main.b.under.progress
	progressFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	local gunDataFrame = gunUI.Data
	gunDataFrame.Position = UDim2.new(1, 0, 0.883, 0)
	
	local gyro = nil
	
	local connections = {}
	local visibleParts = {}
	
	local firemodeTable = {
		"[ SEMI ]",
		"[ BURST ]",
		"[ AUTO ]"
	}
	
	local function shallowCopy(original)
		local copy = {}
		for key, value in pairs(original) do
			copy[key] = value
		end
		return copy
	end
	
	local crosshairs = {
		t = UDim2.new(0, 0, 0, -gunSettings.crosshair.idle +- 7),
		l = UDim2.new(0, -gunSettings.crosshair.idle +- 7, 0, 0),
		r = UDim2.new(0, gunSettings.crosshair.idle, 0, 0),
		b = UDim2.new(0, 0, 0, gunSettings.crosshair.idle),
	}
	local defaultCrosshair = shallowCopy(crosshairs)
	
	local function shoveCrosshairs(number)
		gunUI.Crosshair.Main.t.Position = UDim2.new(0, 0, 0, -gunSettings.crosshair.idle - 7 - number)
		gunUI.Crosshair.Main.l.Position = UDim2.new(0, -gunSettings.crosshair.idle - 7 - number, 0, 0)
		gunUI.Crosshair.Main.r.Position = UDim2.new(0, gunSettings.crosshair.idle + number, 0, 0)
		gunUI.Crosshair.Main.b.Position = UDim2.new(0, 0, 0, gunSettings.crosshair.idle + number)
		
		for index,position in pairs(crosshairs) do
			TweenService:Create(gunUI.Crosshair.Main[index], TweenInfo.new(gunSettings.crosshair.lerp, gunSettings.crosshair.easingStyle, gunSettings.crosshair.easingDirection), {Position = position}):Play()
		end
	end
	
	local function setCrosshairs(number, animate, lerp, easingStyle, easingDirection)
		crosshairs.t = UDim2.new(0, 0, 0, -number - 7)
		crosshairs.l = UDim2.new(0, -number - 7, 0, 0)
		crosshairs.r = UDim2.new(0, number, 0, 0)
		crosshairs.b = UDim2.new(0, 0, 0, number)
		
		for index,position in pairs(crosshairs) do
			if (animate) then
				TweenService:Create(gunUI.Crosshair.Main[index], TweenInfo.new(lerp or gunSettings.crosshair.lerp, easingStyle or gunSettings.crosshair.easingStyle, easingDirection or gunSettings.crosshair.easingDirection), {Position = position}):Play()
			else
				gunUI.Crosshair.Main[index].Position = position
			end
		end
	end
	
	local function randomChildren(parent)
		return parent:GetChildren()[math.random(1, #parent:GetChildren())]
	end
	
	local function getDistance(p1, p2)
		return ((typeof(p1) == "Instance" and p1.Position or p1) - (typeof(p2) == "Instance" and p2.Position or p2)).magnitude
	end
	
	local function isPartThin(part, increment)
		increment = increment or 0.75
		return part.Size.x <= increment or part.Size.y <= increment or part.Size.z <= increment
	end
	
	local function playSound(sound, parent, pitch, volume, silencer)
		local destroyParent = false
		if (typeof(parent) == "Vector3") then
			local pos = parent
			parent = Instance.new("Attachment")
			parent.WorldPosition = pos
			parent.Parent = workspace.Terrain
			destroyParent = true
		end
		
		local distance = parent:IsDescendantOf(workspace) and getDistance(workspace.CurrentCamera.CFrame.Position, parent:IsA("Attachment") and parent.WorldPosition or parent.Position) or nil
		local newsound = sound:Clone()
		newsound.PlaybackSpeed = pitch and newsound.PlaybackSpeed + math.random() * pitch or newsound.PlaybackSpeed
		newsound.Volume = volume or newsound.Volume
		newsound.SoundGroup = SoundService.Main
		newsound.Parent = parent
		if (silencer) then
			local newcompressor = compressor:Clone()
			newcompressor.Parent = newsound
		end
		newsound.PlaybackSpeed = silencer and newsound.PlaybackSpeed + 0.5 or newsound.PlaybackSpeed
		if (distance) then
			local equalizer = Instance.new("EqualizerSoundEffect")
			equalizer.HighGain = -(distance / 10)
			equalizer.MidGain = -(distance / 20)
			equalizer.LowGain = -(distance / 40)
			equalizer.Parent = newsound
		end
		task.delay(newsound.TimeLength + 0.5, function()
			newsound:Destroy()
			if (destroyParent) then
				parent:Destroy()
			end
		end)
		
		return newsound
	end
	
	local function playNormalSound(sound, parent, pitch, volume, dontDestroy)
		local destroyParent = false
		if (typeof(parent) == "Vector3") then
			local pos = parent
			parent = Instance.new("Attachment")
			parent.WorldPosition = pos
			parent.Parent = workspace.Terrain
			destroyParent = true
		end

		local newsound = sound:Clone()
		newsound.PlaybackSpeed = pitch or newsound.PlaybackSpeed
		newsound.Volume = volume or newsound.Volume
		newsound.SoundGroup = SoundService.Main
		newsound.Parent = parent
		local toDestroy = destroyParent and parent or newsound
		if (not dontDestroy) then
			task.delay(newsound.TimeLength + 0.5, function()
				toDestroy:Destroy()
			end)
		end

		return newsound, toDestroy
	end
	
	local function canProcess()
		return tick() - equipTime > gunSettings.equipDelay
	end
	
	local function findHumanoid(part)
		local foundhumanoid = part:FindFirstChildWhichIsA("Humanoid") or part.Parent:FindFirstChildWhichIsA("Humanoid")
		if (part.Parent ~= workspace and foundhumanoid) then
			return foundhumanoid
		end
		
		if (part.Parent ~= workspace) then
			return findHumanoid(part.Parent)
		end
		
		return nil
	end
	
	local function onscreen(pos)
		local _,screen = workspace.CurrentCamera:WorldToScreenPoint(pos)
		return screen
	end
	
	local function findCharInString(String, CharacterToFind, Start, End)
		if not String or not CharacterToFind or not Start then return end
		if not End then End = string.len(String) end
		local CharacterPos
		for i = Start, End do
			if string.sub(String, i, i) == CharacterToFind then
				CharacterPos = i
				break
			end
		end
		return CharacterPos
	end

	local function getMaterialString(Part)
		if not Part then return end
		local EnumAsString = tostring(Part.Material)
		local FirstDotPos = findCharInString(EnumAsString, ".", 1)
		if FirstDotPos then
			local SecondDotPos = findCharInString(EnumAsString, ".", FirstDotPos + 1)
			if SecondDotPos then
				local MaterialOfPart = string.sub(EnumAsString, SecondDotPos + 1)
				return MaterialOfPart
			end
		end
	end
	
	local function dryFire()
		if (not reloading and humanoid.Health > 0) then
			playSound(randomChildren(Assets.Sounds.Guns[tool.Name].DryFire), corePart.FirePoint):Play()
			anims.fire:Play()
			anims.fire:AdjustWeight(gunSettings.fire.dryFireWeight)
		end
	end
	
	local function unaim()
		if (aiming) then
			playSound(randomChildren(Assets.Sounds.aim), player.PlayerGui):Play()
			Network:FireServer("aim", tool, false)
		end
		aiming = false
		if (scoping and #visibleParts > 0) then
			for _,part in pairs(visibleParts) do
				part.instance.Transparency = part.transparent
			end
		end
		scoping = false
		gunUI.Scope.Visible = false
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(gunSettings.aim.aimLerp, gunSettings.aim.aimEasingStyle, gunSettings.aim.aimEasingDirection), {FieldOfView = 70}):Play()
		Events.client:Fire("aim-up")
		UserInputService.MouseDeltaSensitivity = defaultMouseDeltaSens
		
		for _,line in pairs(gunUI.Crosshair.Main:GetChildren()) do
			local ui = line:FindFirstChildWhichIsA("UIBase")
			if (ui) then
				ui.Enabled = true
			end
			TweenService:Create(line, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {BackgroundTransparency = 0}):Play()
		end
		
		anims.idle:AdjustSpeed(1)
		if (not reloading) then
			setCrosshairs(gunSettings.crosshair.idle, true)
		end
	end
	
	local function canShoot()
		local can = true
		local region3 = Region3.new(corePart.FirePoint.WorldPosition, corePart.FirePoint.WorldPosition)
		local parts = workspace:FindPartsInRegion3WithIgnoreList(region3, {character, workspace.Terrain.Ignore}, math.huge)
		if (#parts > 0) then
			for _,part in pairs(parts) do
				if (part:IsA("Part") and part.CanCollide == true and not part:IsDescendantOf(workspace.Characters)) then
					can = false
					break
				end
			end
		end
		if (can) then
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = {character, workspace.Terrain.Ignore}
			params.IgnoreWater = true
			
			local cast = workspace:Raycast(corePart.FirePoint.WorldPosition, (humanoid.RootPart.Position - corePart.FirePoint.WorldPosition), params)
			if (cast) then
				local part = cast.Instance
				if (part:IsA("Part") and part.CanCollide == true and not part:IsDescendantOf(workspace.Characters)) then
					can = false
				end
			end
		end
		
		return can
	end
	
	if (gunSettings.crosshair.enable == false) then
		for _,frame in pairs(gunUI.Crosshair.Main:GetChildren()) do
			if (frame.Name ~= "b") then
				frame.Visible = false
			else
				frame.Size = UDim2.new(0, 0, 0, 0)
				frame.BorderSizePixel = 0
			end
		end
	end
	
	local boltclicked = false
	mouse.Button1Down:Connect(function()
		active = true
		local fireRound = 0
		local boltIdle, boltIdleInstance = nil
		if (gunSettings.fire.boltDelay > 0) then
			boltIdle, boltIdleInstance = playNormalSound(randomChildren(Assets.Sounds.Guns[tool.Name].BoltIdle), corePart, nil, nil, true)
		end
		while active and equipped do
			if (clipCurrent < 1) then
				dryFire()
				
				break
			end
			
			if (not reloading and not reloadCancelled and settings.ragdoll.Value == false and humanoid:GetAttribute("run") == false and not altReload and canShoot() and canProcess() and tick() - fireDelay > (fireMode == 2 and gunSettings.fire.fireDelay * 2 or gunSettings.fire.fireDelay) and clipCurrent > 0 and humanoid.Health > 0) then
				local function fire()
					if (gunSettings.fire.boltDelay > 0 and (not boltclicked or gunSettings.fire.boltPerRound)) then
						local boltStartSound
						if (anims.boltStart) then
							anims.boltStart:Play()
							boltStartSound = playNormalSound(randomChildren(Assets.Sounds.Guns[tool.Name].BoltStart), corePart)
							boltStartSound:Play()
							task.defer(function()
								while humanoid:IsDescendantOf(workspace) do
									if (boltclicked) then
										break
									end
									
									if (anims.boltStart.TimePosition >= anims.boltStart.Length - 0.01) then
										anims.boltStart:AdjustSpeed(0)
										break
									end
									task.wait()
								end
							end)
						end
						if (anims.boltclick) then
							anims.boltclick:Play(gunSettings.fire.boltDelay)
						end
						
						local click = tick()
						while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
							if (tick() - click >= gunSettings.fire.boltDelay) then
								break
							end
							task.wait()
						end
						if (boltStartSound) then
							boltStartSound:Stop()
						end
						if (anims.boltStart) then
							anims.boltStart:Stop()
						end
						if (anims.boltclick and not anims.boltclick.Looped) then
							anims.boltclick:Stop(0.5)
						end
						if (tick() - click < gunSettings.fire.boltDelay) then
							return
						end
					end
					boltclicked = true
					shoveCrosshairs(gunSettings.crosshair.fire)
					local db = false
					firing = true
					fireDelay = tick()
					if (anims.reload) then
						anims.reload:Stop()
					end
					if (anims.altReload) then
						anims.altReload:Stop()
					end
					if (anims.preReload) then
						anims.preReload:Stop()
					end
					if (anims.holster) then
						anims.holster:Stop()
					end
					anims.equip:Stop()
					anims.fire:Play()
					if (boltclicked and boltIdle and not boltIdle.IsPlaying) then
						boltIdle:Play()
					end
					if (aiming) then
						anims.fire:AdjustWeight(gunSettings.fire.aimFireWeight)
					end
					fireRound += 1
					
					local recoilX = math.random(gunSettings.fire.recoil.x[1], gunSettings.fire.recoil.x[2]) / 20
					local recoilY = math.random(gunSettings.fire.recoil.y[1], gunSettings.fire.recoil.y[2]) / 20
					local recoilZ = math.random(gunSettings.fire.recoil.z[1], gunSettings.fire.recoil.z[2]) / 25
					if (aiming) then
						recoilX = recoilX / gunSettings.fire.recoilAim
						recoilY = recoilY / gunSettings.fire.recoilAim
						recoilZ = recoilZ / gunSettings.fire.recoilAim
					end
					recoil:Accelerate(Vector3.new(recoilX, recoilY, recoilZ))
					task.delay(1 / 30, function()
						recoil:Accelerate(Vector3.new(-recoilX / gunSettings.fire.recoil.recoilBackSize, -recoilY / gunSettings.fire.recoil.recoilBackSize, 0))
					end)
					playSound(randomChildren(Assets.Sounds.Guns[tool.Name].Fire), corePart.FirePoint, nil, nil, tool:GetAttribute("Silencer")):Play()
					if (clipCurrent < clipSize / 2) then
						playNormalSound(randomChildren(Assets.Sounds.Guns[tool.Name].LowAmmo), corePart.FirePoint, math.min((2.5 / (clipSize * 2)) * (clipSize - clipCurrent), 1.25)):Play()
					end
					
					task.spawn(function()
						for _,muzzle in pairs(corePart.FirePoint:GetChildren()) do
							if (muzzle:IsA("ParticleEmitter")) then
								muzzle:Emit(muzzle.Rate)
							elseif (muzzle:IsA("Light") and muzzle.Name == "Light") then
								local light = muzzle:Clone()
								light.Name = "__light"
								light.Enabled = true
								light.Parent = corePart.FirePoint
								task.delay(0.01, function()
									light:Destroy()
								end)
							end
						end
						
						if (not gunSettings.fire.altReloadPerRound) then
							Events.create:Fire("shell", Assets.Bullets[gunSettings.ammo.bulletType], corePart.ShellPoint.WorldCFrame, humanoid.RootPart.CFrame.RightVector * math.random(gunSettings.ammo.ejectVelocity.range[1], gunSettings.ammo.ejectVelocity.range[2]) + Vector3.new(0, math.random(gunSettings.ammo.ejectVelocity.up[1], gunSettings.ammo.ejectVelocity.up[2]), 0), character)
						end
					end)
					
					Network:FireServer("fire", tool, gunSettings, mouse.UnitRay.Direction)
					
					for k = 1, gunSettings.fire.bulletPerRound do
						local caster = Raycast.new()
						caster.SimulateBeforePhysics = false
						local params = RaycastParams.new()
						params.FilterDescendantsInstances = {workspace.Terrain.Ignore, character}
						params.IgnoreWater = true

						local behavior = Raycast.newBehavior()
						behavior.RaycastParams = params
						behavior.Acceleration = gunSettings.fire.acceleration
						behavior.MaxDistance = 3500

						local tracers = {current = nil, last = nil, beam = nil}
						tracers.trail = Assets.Misc.bulletTrail:Clone()
						tracers.last = Assets.Misc.tracers["0"]:Clone()
						tracers.current = Assets.Misc.tracers["1"]:Clone()
						tracers.beam = Assets.Misc.tracers.beam:Clone()
						tracers.beam.Color = ColorSequence.new(gunSettings.ammo.bulletTrailColor)
						for _,instance in pairs(tracers) do
							instance.Parent = workspace.Terrain
						end
						tracers.beam.Attachment0 = tracers.last
						tracers.beam.Attachment1 = tracers.current

						tracers.last.WorldCFrame = corePart.FirePoint.WorldCFrame
						tracers.current.WorldCFrame = corePart.FirePoint.WorldCFrame
						
						tracers.trail.CFrame = corePart.FirePoint.WorldCFrame
						tracers.trail.Trail.Enabled = true
						
						local origin = corePart.FirePoint.WorldCFrame.Position
						local direction = mouse.UnitRay.Direction + (Vector3.new(
							math.random(gunSettings.fire.spread.x[1], gunSettings.fire.spread.x[2]),
							math.random(gunSettings.fire.spread.y[1], gunSettings.fire.spread.y[2]),
							math.random(gunSettings.fire.spread.z[1], gunSettings.fire.spread.z[2])
							) / 1000)
						caster:Fire(corePart.FirePoint.WorldCFrame.Position, direction, gunSettings.fire.fireSpeed, behavior)
						
						local lastPoint
						caster.LengthChanged:Connect(function(caster, currentPoint, direction)
							local distanceFromCamera = getDistance(workspace.CurrentCamera.CFrame.Position, currentPoint)
							local tracerWidth = math.max(math.min(distanceFromCamera / (5000 / distanceFromCamera) * 0.05, 30), 0.05)
							tracers.beam.Width0 = math.max(tracerWidth / 2, 0.05)
							tracers.beam.Width1 = tracerWidth
							
							tracers.trail.CFrame = CFrame.new(currentPoint)
							
							if (lastPoint) then
								tracers.last.WorldCFrame = tracers.last.WorldCFrame:lerp(CFrame.new(lastPoint), (180 / distanceFromCamera) * deltaTime)
							end
							--[[if (lastPoint) then
								tracers.last.WorldCFrame = CFrame.new(lastPoint)
							end]]
							--tracers.current.WorldCFrame = CFrame.new(currentPoint)
							tracers.current.WorldCFrame = tracers.current.WorldCFrame:lerp(CFrame.new(currentPoint), 0.15 * deltaTime)
							lastPoint = currentPoint
							
							if (distanceFromCamera > 300 and not onscreen(currentPoint)) then
								--caster:Terminate()
							end
						end)

						caster.RayHit:Connect(function(caster, result, velocity)
							task.spawn(function()
								tracers.current.WorldCFrame = CFrame.new(result.Position)
								tracers.trail.CFrame = CFrame.new(origin)
								task.delay((1 / 60) * deltaTime, function()
									tracers.trail.CFrame = CFrame.new(result.Position)
								end)
								while tracers.last:IsDescendantOf(workspace.Terrain) do
									local distanceFromCamera = getDistance(workspace.CurrentCamera.CFrame.Position, result.Position)
									local tracerWidth = math.max(math.min(distanceFromCamera / 10 * 0.05, 1e8), 0.05)
									tracers.beam.Width0 = math.max(tracerWidth / 2, 0.05)
									tracers.beam.Width1 = tracerWidth
									tracers.last.WorldCFrame = tracers.last.WorldCFrame:lerp(CFrame.new(result.Position), 0.65)
									task.wait(1 / 144)
								end
							end)
							
							local targetHumanoid = findHumanoid(result.Instance)
							if (targetHumanoid and not result.Instance:FindFirstAncestorWhichIsA("Tool")) then
								if (not table.find(limbs, result.Instance.Name)) then
									Events.create:Fire("gunDebris", result.Instance, result.Position, result.Normal, velocity, math.random(gunSettings.ammo.bulletsize[1], gunSettings.ammo.bulletsize[2]) / 10)
								end
								
								local hitPosition = CFrame.new(result.Position, result.Position - (result.Normal * 1.5))
								local args = {
									targetHumanoid,
									result.Instance,
									result.Position,
									result.Normal,
									origin,
									velocity,
									targetHumanoid.RootPart.CFrame:toObjectSpace(hitPosition)
								}
								local lastHealth = targetHumanoid.Health
								local damaged = lastHealth - gunSettings.damage
								Events.create:Fire("particle", Assets.Particles.blood, math.min((lastHealth - damaged) / 2, 5), args[3], 5)
								local hitState, critical = Network:InvokeServer("hit", tool, gunSettings, args)
								if (hitState) then
									if (not db) then
										db = true
										playSound(Assets.Sounds.hitmark, player.PlayerGui):Play()
										
										local hitmark = gunUI.Crosshair.Hitmark:Clone()
										hitmark.Name = "__hitmark"
										hitmark.ImageTransparency = 0
										hitmark.ImageColor3 = critical and Color3.fromRGB(170, 0, 0) or Color3.fromRGB(255, 255, 255)
										hitmark.Parent = gunUI.Crosshair
										Debris:AddItem(hitmark, 3)
										TweenService:Create(hitmark, TweenInfo.new(1.5, Enum.EasingStyle.Quint), {ImageTransparency = 1, Size = UDim2.new(0, 0, 0, 0)}):Play()
									end
								end
							else
								Events.create:Fire("gunDebris", result.Instance, result.Position, result.Normal, velocity, math.random(gunSettings.ammo.bulletsize[1], gunSettings.ammo.bulletsize[2]) / 10)
								if (isPartThin(result.Instance) and result.Instance.Material == Enum.Material.Glass and not findHumanoid(result.Instance) and not result.Instance:FindFirstChild("__break") and not result.Instance.Parent:FindFirstChild("__break")) then
									local broke = Instance.new("StringValue")
									broke.Name = "__break"
									broke.Parent = result.Instance
									
									local args = {
										result.Instance,
										result.Position,
										result.Normal,
										origin,
										velocity
									}
									
									Network:FireServer("glass", tool, gunSettings, args)
								end
							end
						end)

						caster.CastTerminating:Connect(function()
							--tracers.beam.Enabled = false
							tracers.current.light.Enabled = false
							task.wait(0.15)
							for _,instance in pairs(tracers) do
								if (instance:IsA("Part")) then
									Debris:AddItem(instance, 1.5)
								else
									instance:Destroy()
								end
							end
						end)
					end
					
					clipCurrent = math.max(clipCurrent - 1, 0)
					
					fired = true
					if (not gunSettings.fire.altReloadPerRound) then
						fired = false
					end
					
					firing = false
				end
				
				if (gunSettings.fire.altReloadPerRound and fired) then
					fired = false
					--unaim()
					altReload = true
					--task.wait(gunSettings.fire.altReloadDelay)
					if (equipped) then
						Events.create:Fire("shell", Assets.Bullets[gunSettings.ammo.bulletType], corePart.ShellPoint.WorldCFrame, humanoid.RootPart.CFrame.RightVector * math.random(gunSettings.ammo.ejectVelocity.range[1], gunSettings.ammo.ejectVelocity.range[2]) + Vector3.new(0, math.random(gunSettings.ammo.ejectVelocity.up[1], gunSettings.ammo.ejectVelocity.up[2]), 0), character)
						playSound(randomChildren(Assets.Sounds.Guns[tool.Name].AltReload), corePart):Play()
						anims.altReload:Play()

						local stoppedConnection
						stoppedConnection = anims.altReload.Stopped:Connect(function()
							altReload = false
							stoppedConnection:Disconnect()
						end)
					end
					
					return
				end
				
				if (fireMode == 2) then
					for k = 1, gunSettings.fire.burstPerRound do
						if (not equipped or not canShoot()) then
							break
						end
						if (clipCurrent < 1) then
							dryFire()
							break
						end
						fire()
						task.wait(gunSettings.fire.burstDelay)
					end
					
					break
				else
					fire()
				end
				
				if (fireMode == 1) then
					break
				end
			end
			
			task.wait()
		end
		
		if (boltIdleInstance) then
			boltIdleInstance:Destroy()
		end
		if (anims.boltclick) then
			anims.boltclick:Stop(0.5)
		end
		if (anims.boltEnd and boltclicked) then
			if (not reloading) then
				anims.boltEnd:Play()
			end
			playNormalSound(randomChildren(Assets.Sounds.Guns[tool.Name].BoltEnd), corePart):Play()
		end
		boltclicked = false
	end)
	
	tool.Deactivated:Connect(function()
		active = false
		
		reloadCancelled = false
	end)
	
	tool.Equipped:Connect(function()
		equipped = true
		equipTime = tick()
		
		fired = false
		
		anims.equip:Play()
		anims.idle:Play()
		
		gunUI.Parent = player.PlayerGui
		
		setCrosshairs(1, false)
		setCrosshairs(gunSettings.crosshair.idle, true, 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.InOut)
		
		TweenService:Create(gunDataFrame, TweenInfo.new(1, Enum.EasingStyle.Quint), {Position = UDim2.new(0.787, 0, 0.883, 0)}):Play()
		
		table.insert(connections, UserInputService.InputBegan:Connect(function(key, typing)
			if ((key.UserInputType == Enum.UserInputType.MouseButton2 or (key.KeyCode == Enum.KeyCode.Q and not typing)) and gunSettings.aim.canAim and not reloading and IsInFirstPerson() and humanoid.Health > 0) then
				if (not aiming and humanoid:GetAttribute("run") == false) then
					TweenService:Create(workspace.CurrentCamera, TweenInfo.new(gunSettings.aim.aimLerp, gunSettings.aim.aimEasingStyle, gunSettings.aim.aimEasingDirection), {FieldOfView = gunSettings.aim.aimFOV}):Play()
					aiming = true
					Network:FireServer("aim", tool, true)
					Events.client:Fire("aim-down")
					defaultMouseDeltaSens = UserInputService.MouseDeltaSensitivity
					playSound(randomChildren(Assets.Sounds.aim), player.PlayerGui):Play()

					for _,line in pairs(gunUI.Crosshair.Main:GetChildren()) do
						local ui = line:FindFirstChildWhichIsA("UIBase")
						if (ui) then
							ui.Enabled = false
						end
						TweenService:Create(line, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {BackgroundTransparency = 1}):Play()
					end

					anims.idle.TimePosition = 0
					anims.idle:AdjustSpeed(0)
					setCrosshairs(1, true)
				else
					unaim()
				end
			end
			
			if (not typing) then
				if (key.KeyCode == Enum.KeyCode.R and canProcess() and not reloading and clipCurrent < clipSize and maxAmmo > 0) then
					reloading = true
					setCrosshairs(gunSettings.crosshair.reload, true)
					TweenService:Create(gunUI.Crosshair.Main.Center, TweenInfo.new(1, Enum.EasingStyle.Quint), {BackgroundColor3 = Color3.fromRGB(70, 70, 70)}):Play()
					TweenService:Create(progressFrame, TweenInfo.new(1, Enum.EasingStyle.Back), {Position = UDim2.new(0.5, 0, 0.35, 0)}):Play()
					
					progressFrame.bar.Size = UDim2.new(0, 0, 0, 1)
					if (anims.reload) then
						playSound(randomChildren(Assets.Sounds.Guns[tool.Name].Reload), corePart):Play()
						anims.reload:Play()
						Network:FireServer("reload", tool, gunSettings, "register")

						while anims.reload.TimePosition < anims.reload.Length do
							if (not anims.reload.IsPlaying) then
								break
							end
							if (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)) then
								reloadCancelled = true
								anims.reload:Stop()
								Network:FireServer("reload", tool, gunSettings, "cancel")
								break
							end
							--humanoid.WalkSpeed = 6
							progressFrame.bar.Size = UDim2.new((anims.reload.TimePosition / anims.reload.Length) * 1, 0, 1)
							task.wait()
						end 
						
					--	humanoid.WalkSpeed = defaultspeed
						if (anims.reload.TimePosition >= anims.reload.Length and not reloadCancelled) then
							Network:FireServer("reload", tool, gunSettings, "reloaded")
							local lastAmmo = clipSize - clipCurrent
							clipCurrent = math.min(clipCurrent + maxAmmo, clipSize)
							maxAmmo = math.max(maxAmmo - lastAmmo, 0)
						end
						TweenService:Create(progressFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, -0.5, 0)}):Play()
					elseif (anims.preReload) then
						anims.fire:Stop()
						anims.preReload:Play(0.15)
						Network:FireServer("reload", tool, gunSettings, "register")
						
						task.wait(0.45)
						for k = clipCurrent, clipSize - 1 do
							if (maxAmmo < 1 or not equipped or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)) then
								break
							end
							playSound(randomChildren(Assets.Sounds.Guns[tool.Name].InsertBullet), corePart):Play()
							Network:FireServer("reload", tool, gunSettings, "inserted")
							anims.insertBullet:Play()
							while anims.insertBullet.TimePosition < anims.insertBullet.Length do
								if (not anims.insertBullet.IsPlaying or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)) then
									break
								end
								--humanoid.WalkSpeed = 6
								progressFrame.bar.Size = UDim2.new((anims.insertBullet.TimePosition / anims.insertBullet.Length) * 1, 0, 1)
								task.wait()
							end
							anims.insertBullet:Stop(0.25)
							clipCurrent = math.min(clipCurrent + 1, clipSize)
							maxAmmo = math.max(maxAmmo - 1, 0)
						end
						
						--humanoid.WalkSpeed = defaultspeed
						TweenService:Create(progressFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, -0.5, 0)}):Play()
						if (equipped) then
							task.wait(gunSettings.fire.altReloadDelay)
							playSound(randomChildren(Assets.Sounds.Guns[tool.Name].AltReload), corePart):Play()
							anims.altReload:Play()
						end
						
						Network:FireServer("reload", tool, gunSettings, "finished")
					end
					
					TweenService:Create(gunUI.Crosshair.Main.Center, TweenInfo.new(1, Enum.EasingStyle.Quint), {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play()
					setCrosshairs(gunSettings.crosshair.idle, true)
					--shoveCrosshairs(gunSettings.crosshair.idle)
					fired = false
					reloading = false
				elseif (key.KeyCode == Enum.KeyCode.V and not switching and not reloading and not altReload) then
					local mode = gunSettings.ammo.modeAvailable
					if (#mode > 1) then
						switching = true
						modeSwitch += 1
						if (modeSwitch > #mode) then
							modeSwitch = 1
						end
						fireMode = mode[modeSwitch]
						playSound(randomChildren(Assets.Sounds.Guns[tool.Name].Switch), corePart):Play()
						if (anims.switch) then
							anims.switch:Play()
						end
						task.wait(0.5)
						switching = false
					end
				end
			end
		end))
		
		table.insert(connections, UserInputService.InputEnded:Connect(function(key)
			if (key.UserInputType == Enum.UserInputType.MouseButton2) then
				unaim()
			end
		end))
		
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if (input.UserInputType == Enum.UserInputType.MouseMovement) then
				desiredXOffset = math.min(math.max(input.Delta.x * swayMultiplier, -maxCameraOffset), maxCameraOffset)
				desiredYOffset = math.min(math.max(input.Delta.y * swayMultiplier, -maxCameraOffset), maxCameraOffset)
			end
		end))
		
		local movespeed = 0
		table.insert(connections, RunService.RenderStepped:Connect(function(dt)
			deltaTime = dt * 60
			
			mouseMovement:Impulse(Vector3.new(desiredXOffset * dt, (desiredYOffset) * dt))
			gunUI.Scope.Position = UDim2.new(0.5 + mouseMovement.Position.x, 0, 0.5 + mouseMovement.Position.y, 0)
			gunUI.Scope.frame.Position = UDim2.new(-0.75 + mouseMovement.Position.x * 10, 0, -0.75 + mouseMovement.Position.y * 10, 0)
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.Angles(recoil.p.y * deltaTime, recoil.p.x * deltaTime, recoil.p.z)
			
			movespeed = Vector3.new(humanoid.RootPart.Velocity.x, 0, humanoid.RootPart.Velocity.z).magnitude
			if (humanoid:GetAttribute("run") == true and not reloading and movespeed > 1) then
				if (anims.holster and not anims.holster.IsPlaying) then
					anims.idle:AdjustWeight(0.2, 0.25)
					anims.holster:Play(0.45)
				end
			else
				if (anims.holster and anims.holster.IsPlaying) then
					anims.idle:AdjustWeight(1, 0.5)
					anims.holster:Stop(0.45)
				end
			end
			
			if ((reloading or not IsInFirstPerson() or humanoid.Health < 1) and aiming) then
				unaim()
			end
			
			if (aiming) then
				UserInputService.MouseDeltaSensitivity = defaultMouseDeltaSens / (100 / camera.FieldOfView)
				
				if (gunSettings.aim.allowScope) then
					local distance = getDistance(workspace.CurrentCamera.CFrame.Position, gunModel.AimPart)
					if (distance < 0.25 and not scoping) then
						scoping = true
						
						gunUI.Scope.Visible = true
						gunUI.Scope.frame.Position = UDim2.new(0, 0, -0.75, 0)
						TweenService:Create(gunUI.Scope.frame, TweenInfo.new(1.5, Enum.EasingStyle.Quint), {Position = UDim2.new(-0.75, 0, -0.75, 0)}):Play()
						
						gunUI.Scope.zoom:Play()
						
						if (#visibleParts < 1) then
							for _,part in pairs(gunModel:GetDescendants()) do
								if (part:IsA("BasePart") and part.Transparency < 1) then
									visibleParts[#visibleParts + 1] = {
										["instance"] = part,
										["transparent"] = part.Transparency
									}
								end
							end
						end
						
						for _,part in pairs(visibleParts) do
							part.instance.Transparency = 1
						end
					end
				end
			end
			
			if (aiming and humanoid:GetAttribute("run") == true) then
				unaim()
			end
			
			if (tick() - fireDelay < 10 and not IsInFirstPerson() and humanoid.Health > 0 and settings.ragdoll.Value == false) then
				humanoid.AutoRotate = false
				if (not gyro) then
					gyro = Instance.new("BodyGyro")
					gyro.D = 50
					gyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
					gyro.Parent = humanoid.RootPart
				end
				
				gyro.CFrame = CFrame.new(humanoid.RootPart.Position, Vector3.new(mouse.UnitRay.Direction.x, 0, mouse.UnitRay.Direction.z) * 1000)
			elseif (gyro) then
				gyro:Destroy()
				gyro = nil
				if (humanoid.Health > 0) then
					humanoid.AutoRotate = true
				end
			end
			
			gunDataFrame.ammo.Text = maxAmmo
			gunDataFrame.clip.Text = reloading and "--" or clipCurrent
			gunDataFrame.gunName.Text = tool.Name
			gunDataFrame.mode.Text = firemodeTable[fireMode]
			
			TweenService:Create(gunDataFrame.clip, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {TextColor3 = fired and Color3.fromRGB(143, 143, 143) or Color3.fromRGB(255, 255, 255)}):Play()
			
			gunUI.Crosshair.Position = UDim2.new(0, mouse.x, 0, mouse.y)
		end))
		
		UserInputService.MouseIconEnabled = false
	end)
	
	tool.Unequipped:Connect(function()
		unaim()
		
		TweenService:Create(gunDataFrame, TweenInfo.new(1, Enum.EasingStyle.Quint), {Position = UDim2.new(1, 0, 0.883, 0)}):Play()
		gunUI.Parent = script
		if (gyro) then
			gyro:Destroy()
			gyro = nil
		end
		humanoid.AutoRotate = true
		
		UserInputService.MouseIconEnabled = true
		equipped = false
		altReload = false
		
		for _,anim in pairs(anims) do
			anim:Stop()
		end
		
		for _,con in pairs(connections) do
			con:Disconnect()
		end
	end)
	
	if (anims.reload) then
		anims.reload:GetMarkerReachedSignal("magout"):Connect(function()
			Events.create:Fire("magout", humanoid, tool, gunSettings)
			Network:FireServer("magout", tool, gunSettings)
		end)
	end
end
