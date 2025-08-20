return function(script)
	local character = script.Parent
	local humanoid = character:WaitForChild("Humanoid")
	
	local clone = character:Clone()
	
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerStorage = game:GetService("ServerStorage")
	local ChatService = game:GetService("Chat")
	local Players = game:GetService("Players")
	local PhysicsService = game:GetService("PhysicsService")
	
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local ServerAssets = ServerStorage:WaitForChild("Assets")
	local Events = ReplicatedStorage:WaitForChild("Events")
	
	local network = require(Assets.Modules.Network)
	local raycast = require(Assets.Modules.Raycast)
	local ragdoll = require(ServerAssets.Framework.Ragdoll)
	local combat = require(Assets.Framework.Combat)
	
	local simplePath = require(script["__path"])
	local path = simplePath.new(character)

	local goal = nil

	local wanderTargetRadius = 100;
	local wanderRadius = 50;
	
	local respawnTime = 20;
	
	local minMeleeRadius = 2.5;
	
	local meleeActiveRadius = 20;
	local gunActiveRadius = 120;

	local wanderTargetDetectDistance = 10000;
	local minDetectDistance = 5;
	local maxDetectDistance = 1000;
	local abortChasingDistance = 100;
	
	local sideMoveDelayTime = {1, 10};
	local sideMoveLength = 7;

	local stuckTime = 0.25;

	local wanderDelayTime = {0, 5};
	
	local lookDirectionMaxDistance = 1000;
	local lookRoughness = 50;
	local lookAngleInterval = 10;
	local minLookDistance = 15;
	
	local attackDelay = 0.75;
	local attackDamage = 15;

	local losingSightMax = 50;
	local characterFieldOfView = 165;
	
	local aiSettings = script:WaitForChild("settings")
	local playersHostile = aiSettings.playerHostile.Value;
	local VoiceLineType = aiSettings.voiceLine.Value;
	local teamName = aiSettings.teamName.Value;
	local aiActive = aiSettings.active.Value;
	local chatBubble = false;
	local voiceline = true;
	--aiActive = false
	
	local jumpOnDamageTaken = true;
	local avoidDamageJumpAmount = {3, 5};
	local avoidDamageRandomPositionRadius = 15;
	local avoidDamageLength = {2, 10};
	local avoidDamageAmount = {3, 5};
	
	local debugging = false;
	
	local chatlineModule = Assets.Modules.chatline:FindFirstChild(teamName)
	if (not chatlineModule) then
		chatlineModule = Assets.Modules.chatline.Default
	end
	local chatline = require(chatlineModule)
	
	local doNotKillSCPs = {
		"173"
	}
	
	local callBackupOnSCPs = {
		"173"
	}
	
	local chargeSCPs = {
		"173"
	}
	
	local hideDelay = 0
	local hurtDelay = 0
	local spottedDelay = math.random(5, 10)

	local globalRate = 1 / 15;

	local ignoreTable = {character}

	local chasing = false
	local backupRequested = false
	local backupping = false
	
	local defaultspeed = 16
	local runspeed = 30
	
	local speed = defaultspeed
	
	local defaultFOV = characterFieldOfView
	
	local lastTargetName = ""
	local seenEnemy = false
	local isLastTargetSCP = false
	
	local entityVoicePitch = math.random(10, 15) / 100
	
	local guid = game.HttpService:GenerateGUID(false)
	
	local backpack = Instance.new("Folder")
	backpack.Name = "Backpack"
	backpack.Parent = character

	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = workspace.Terrain, workspace.Terrain
	local beam = script.Beam
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	
	local teamValue = Instance.new("StringValue")
	teamValue.Name = "CharacterTeam"
	teamValue.Value = teamName
	teamValue.Parent = character
	
	if (humanoid.RootPart:CanSetNetworkOwnership()) then
		humanoid.RootPart:SetNetworkOwner(nil)
	end
	path.Visualize = debugging
	beam.Enabled = debugging
	
	local settings = ServerAssets.Settings:Clone()
	settings.Parent = humanoid
	local settingsObject = Instance.new("ObjectValue")
	settingsObject.Name = "settingsObject"
	settingsObject.Value = settings
	settingsObject.Parent = humanoid
	ragdoll:Init(settings, character, true)
	
	for _,corescript in pairs(script:GetChildren()) do
		if (corescript:IsA("Script")) then
			corescript.Parent = character
			corescript.Disabled = false
		end
	end

	local function getDistance(p1, p2)
		if (p1 == nil or p2 == nil) then
			return 0
		end
		
		return ((typeof(p1) == "Instance" and p1.Position or p1) - (typeof(p2) == "Instance" and p2.Position or p2)).magnitude
	end

	local function angleBetween(vectorA, vectorB)
		return math.acos(math.clamp(vectorA:Dot(vectorB), -1, 1))
	end

	local function inFieldOfView(model, fov)
		if (not character:FindFirstChild("Head")) then
			return false
		end
		
		local lookForward = character.Head.CFrame.LookVector
		local lookToPoint = ((typeof(model) == "Instance" and model.PrimaryPart.Position or model) - character.Head.Position).unit

		local angle = angleBetween(lookForward, lookToPoint)
		return math.abs(angle) <= math.rad(fov) / 2
	end

	local function canSee(model)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = ignoreTable
		params.IgnoreWater = true

		local cast = workspace:Raycast(character.Head.Position, (model.PrimaryPart.Position - character.Head.Position).unit * 10000, params)
		if (cast) then
			if (cast.Instance.Transparency >= 0.5) then
				ignoreTable[#ignoreTable + 1] = cast.Instance
				return canSee(model)
			elseif (cast.Instance:IsDescendantOf(model)) then
				return true
			end
		elseif (not cast) then
			return true
		end

		return false
	end
	
	local function stringMatchInTable(string, table)
		for _,k in pairs(table) do
			if (k == string) then
				return true
			end
		end
		
		return false
	end
	
	local function sortPositionTable(t, ascend)
		for k = 1, #t do
			if (ascend) then
				if (k > 1 and t[k].magnitude > t[k - 1].magnitude) then
					local l = t[k - 1]
					t[k - 1] = t[k]
					t[k] = l
					return sortPositionTable(t, ascend)
				end
			else
				if (k > 1 and t[k].magnitude < t[k - 1].magnitude) then
					local l = t[k - 1]
					t[k - 1] = t[k]
					t[k] = l
					return sortPositionTable(t, ascend)
				end
			end
		end

		return t
	end
	
	local function randomChildren(parent)
		if (#parent:GetChildren() < 1) then
			return false
		end
		return parent:GetChildren()[math.random(1, #parent:GetChildren())]
	end

	local function isTargetTeam(targetCharacter)
		local team = targetCharacter:FindFirstChild("CharacterTeam")
		if (team and string.lower(team.Value) == string.lower(teamValue.Value)) then
			return true
		elseif (team == "Noob" and team.Value == "Phoenix" or team == "Phoenix" and team.Value == "Noob") then
			return true
		elseif (team == "Bulldozer" and team.Value == "MTF" or team == "MTF" and team.Value == "Bulldozer") then
			return true
		end

		return false
	end
	
	local function getHumanoid(part)
		local foundhumanoid = part:FindFirstChildWhichIsA("Humanoid") or part.Parent:FindFirstChildWhichIsA("Humanoid")
		if (part.Parent ~= workspace and foundhumanoid) then
			return foundhumanoid
		end

		if (part.Parent ~= workspace) then
			return getHumanoid(part.Parent)
		end

		return nil
	end
	

	local function attackPlayers(model)
		local isPlayer = Players:GetPlayerFromCharacter(model)
		if (not isPlayer or (isPlayer and playersHostile)) then
			return true
		end
		return false
	end
	
	local function isTargetSCP(targetCharacter)
		local isSCP = targetCharacter:FindFirstChild("isSCP")
		if (isSCP) then
			return isSCP.Value
		end

		return false
	end
	
	local function attackTeamMate(t)
		local isNPC = t:FindFirstChild("CharacterTeam")
		if (not isNPC or (isNPC and not playersHostile)) then
			return false
		end
		
		return true
	end
	
	local function findHumanoid(parent)
		local maxDistance, foundCharacter = maxDetectDistance, nil
		for _,targetCharacter in pairs(parent:GetChildren()) do
			local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
			local distance = targetHumanoid and targetHumanoid.RootPart and getDistance(targetHumanoid.RootPart, humanoid.RootPart)
			if (targetHumanoid and attackPlayers(targetCharacter) and not targetCharacter:FindFirstChild("__ignore") and distance and distance < maxDistance and targetHumanoid.RootPart.Anchored == false and targetHumanoid.Health > 0 and targetHumanoid ~= humanoid and (inFieldOfView(targetCharacter, characterFieldOfView) and canSee(targetCharacter) and not isTargetTeam(targetCharacter) or (distance <= minDetectDistance and not isTargetTeam(targetCharacter)))) then
					maxDistance = distance
					foundCharacter = targetCharacter
				end
			end


		return foundCharacter
	end
	
	local function findTeammate(parent)
		local maxDistance, foundCharacter = maxDetectDistance, nil
		for _,targetCharacter in pairs(parent:GetChildren()) do
			local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
			local distance = targetHumanoid and targetHumanoid.RootPart and getDistance(targetHumanoid.RootPart, humanoid.RootPart)
			if (targetHumanoid and not targetCharacter:FindFirstChild("__ignore") and distance and distance < maxDistance and targetHumanoid.RootPart.Anchored == false and targetHumanoid.Health > 0 and targetHumanoid ~= humanoid and (canSee(targetCharacter) and isTargetTeam(targetCharacter) or (distance <= minDetectDistance and isTargetTeam(targetCharacter)))) then
				maxDistance = distance
				foundCharacter = targetCharacter
			end
		end

		return foundCharacter
	end

	local function findWanderHumanoid(parent, distance)
		local maxDistance, foundCharacter = maxDetectDistance, nil
		for _,targetCharacter in pairs(parent:GetChildren()) do
			local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
			local distance = targetHumanoid and targetHumanoid.RootPart and getDistance(targetHumanoid.RootPart, humanoid.RootPart)
			if (targetHumanoid and attackPlayers(targetCharacter) and distance and distance < maxDistance and targetHumanoid.RootPart.Anchored == false and targetHumanoid.Health > 0 and targetHumanoid ~= humanoid and not isTargetTeam(targetCharacter)) then
				maxDistance = distance
				foundCharacter = targetCharacter
			end
		end

		return foundCharacter
	end

	local function clampDistanceBetweenVectors(v1, v2, max)
		return v1 + ((v2 - v1).Unit * math.min((v2 - v1).Magnitude,  max))
	end
	
	local function getDirection(p1, p2, distance)
		return (p2 - p1).unit * (distance or 1)
	end
	
	local function findLookDirection()
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {character, workspace.Terrain.Ignore}
		params.IgnoreWater = true
		
		local direction = nil
		local h, k = humanoid.RootPart.Position.x, humanoid.RootPart.Position.z
		local radius = 1.5
		local distances = {}
		for i = 1, 360, lookAngleInterval do
			raycast.VisualizeCasts = false
			local x, z = h + radius * math.cos(math.rad(i)), k + radius * math.sin(math.rad(i))
			local origin = Vector3.new(x, humanoid.RootPart.Position.y + 1.5, z)
			local direction = getDirection(humanoid.RootPart.Position, origin)
			
			local cast = workspace:Raycast(origin, direction * lookDirectionMaxDistance, params)
			if (cast and inFieldOfView(origin, characterFieldOfView)) then
				distances[#distances + 1] = cast.Position
			end
		end
		local minDistance, indexDistance = 0, nil
		for index,position in pairs(distances) do
			local distance = getDistance(humanoid.RootPart.Position, position)
			if (distance > minDistance) then
				minDistance = distance
				indexDistance = index
			end
		end
		if (indexDistance) then
			--direction = distances[indexDistance]
			direction = sortPositionTable(distances)
		end
		
		return direction
	end
	
	local function playSound(sound, parent, pitch, volume)
		local destroyParent = false
		if (typeof(parent) == "Vector3") then
			local pos = parent
			parent = Instance.new("Attachment")
			parent.WorldPosition = pos
			parent.Parent = workspace.Terrain
			destroyParent = true
		end

		local newsound = sound:Clone()
		newsound.PlaybackSpeed = pitch and newsound.PlaybackSpeed + math.random() * pitch or newsound.PlaybackSpeed
		newsound.Volume = volume or newsound.Volume
		newsound.SoundGroup = game.SoundService.Main
		newsound.Parent = parent
		task.delay(newsound.TimeLength + 0.5, function()
			newsound:Destroy()
			if (destroyParent) then
				parent:Destroy()
			end
		end)

		return newsound
	end

	path.WaypointReached:Connect(function(agent, lastWaypoint, nextWaypoint)
		if (humanoid.RootPart) then
			if ((humanoid.RootPart.Position.y - 2.5) - nextWaypoint.Position.y > 1) then
				humanoid.Jump = true
			end
			if (goal and (typeof(goal) == "Instance" or typeof(goal) == "Vector3")) then
				path:Run(goal)
			end
		end
	end)
	
	local function generateNewRandomPosition(origin, radius, flag)
		local pos = origin + Vector3.new(math.random(-radius, radius), 0, math.random(-radius, radius))
		local state = path:Run(pos)
		if (not state) then
			flag += 1
			if (flag >= 5) then
				pos = humanoid.RootPart.Position + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
				humanoid:MoveTo(pos)
				return pos
			end
			return generateNewRandomPosition(origin, radius, flag)
		end
		return pos
	end
	
	local function getGunFromInventory(ammo)
		local guns = {}
		
		for _,tool in pairs(backpack:GetChildren()) do
			if (tool:IsA("Tool") and tool:GetAttribute("IsGun") == true) then
				repeat task.wait() until tool:GetAttribute("ClipCurrent") ~= nil
				if (ammo) then
					if (tool:GetAttribute("ClipCurrent") > 0) then
						guns[#guns + 1] = tool
					end
				else
					if (tool:GetAttribute("ClipCurrent") < 1) then
						guns[#guns + 1] = tool
					end
				end
			end
		end
		
		if (#guns > 0) then
			return guns[math.random(1, #guns)]
		end
		
		return false
	end
	
	local function unequipTools()
		for _,tool in pairs(character:GetChildren()) do
			if (tool:IsA("Tool")) then
				tool.Parent = backpack
			end
		end
	end
	
	local function equipTool(tool)
		if (tool) then
			unequipTools()
			if (typeof(tool) == "string") then
				backpack[tool].Parent = character
			else
				tool.Parent = character
			end
		end
	end
	unequipTools()
	equipTool(getGunFromInventory(true))
	
	local function fireGun(targetPosition)
		local direction = getDirection(character.Head.Position, targetPosition)
		local aimX, aimY, aimZ = 135, 60, 135
		direction = direction + Vector3.new(math.random(-aimX, aimX), math.random(-aimY, aimY), math.random(-aimZ, aimZ)) / 1000
		local gun = character:FindFirstChildWhichIsA("Tool")
		if (gun and gun:GetAttribute("IsGun") == true) then
			if (gun:GetAttribute("ClipCurrent") < 1 and gun:GetAttribute("Reloading") == false) then
				local otherFullAmmoGun = getGunFromInventory(true)
				if (otherFullAmmoGun) then
					equipTool(otherFullAmmoGun)
				else
					gun["__bind"]["__reload"]:Fire()
				end
			else
				gun["__bind"]:Fire(true, direction)
			end
		end
	end
	
	local function talk(textGoal, chat)
		if (humanoid.Health < 1) then
			return
		end
	
		
		local voicelineType = Assets.Sounds.voicelines:FindFirstChild(VoiceLineType) or Assets.Sounds.voicelines.Default
		local header = chatline.convertHeaderToText(textGoal)
		if (chatBubble or chat or not header) then
			local text = typeof(textGoal) == "table" and textGoal[math.random(1, #textGoal)] or textGoal
			ChatService:Chat(character.Head, text, "White")
			network:FireAllClients("create", "botChat", character.Name, text)
		elseif (voiceline and voicelineType and character:FindFirstChild("Head")) then
			local pitch = math.random(10, 15) / 100
			if (math.random(2) == 1) then
				pitch = -pitch
			end
			network:FireAllClients("create", "sound", randomChildren(voicelineType[header]), character.Head, pitch, nil, nil, {5, 10, 25}, true, "__talking")
		end
	end
	
	local function callBackup()
		if (not backupRequested) then
			backupRequested = true
			talk(chatline.backupText)
			Events.ai:Fire("backup", humanoid.RootPart.Position, guid, teamValue.Value)
		end
	end
	
	--[[local sphereCollision = Assets.Misc.sphereCollision:Clone()
	sphereCollision.Name = "__collision"
	sphereCollision.Parent = character

	local weld = Instance.new("Weld")
	weld.Part0 = humanoid.RootPart
	weld.Part1 = sphereCollision
	weld.C0 = CFrame.new(0, -0.450004578, -0.0999984741, 0, 0, 1, -0.999999762, 0, 0, 0, -0.999999762, 0)
	weld.Parent = sphereCollision]]

	task.spawn(function()
		while humanoid:IsDescendantOf(workspace) do
			if (humanoid.Health < 1) then
				break
			end
			
			--PhysicsService:SetPartCollisionGroup(sphereCollision, "EntityCollision")
			
			local targetCharacter = findHumanoid(workspace.Characters)
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildWhichIsA("Humanoid")

			if (aiActive) then
				if (targetCharacter) then
					chasing = true

					local isSCP = isTargetSCP(targetCharacter)
					local scpType = isSCP and string.gsub(targetCharacter.Name, "%D", "") or ""
					local scpChatline = isSCP and require(Assets.Modules.chat[scpType])

					local losingSight = 0
					local damageTime = 0
					local updatedTargetPosition = targetHumanoid.RootPart.Position

					local gyro = Instance.new("BodyGyro")
					gyro.MaxTorque = Vector3.new(1e3, 1e3, 1e3)
					gyro.D = 50
					gyro.Parent = humanoid.RootPart
					
					local teammateSpotted = findTeammate(workspace.Characters)
					if (not seenEnemy and tick() - spottedDelay >= 10 and (teammateSpotted and teammateSpotted.AI.vars.spotted.Value == false or not teammateSpotted)) then
						spottedDelay = tick()
						--local isSCP = isTargetSCP(targetCharacter)
						if (lastTargetName == targetCharacter.Name) then
							if (not isSCP) then
								talk(chatline.foundText)
							else
								isLastTargetSCP = true
								talk(targetCharacter.Name .. " Spotted!", true)
							end
						else
							if (not isSCP) then
								talk(chatline.spottedClassDText)
							else
								isLastTargetSCP = true
								talk(targetCharacter.Name .. " Spotted!", true)
							end
						end
						
						lastTargetName = targetCharacter.Name
					end
					script.vars.spotted.Value = true
					seenEnemy = true
					
					-- // call backup
					task.delay(1, function()
						if (stringMatchInTable(scpType, callBackupOnSCPs)) then
							callBackup()
						end
					end)

					local sideMoveDelay = tick()
					while targetCharacter:IsDescendantOf(workspace.Characters) and humanoid.Health > 0 and not backupping do
						local otherTargetHumanoid = findHumanoid(workspace.Characters)
						if (otherTargetHumanoid and otherTargetHumanoid ~= targetCharacter or getDistance(targetCharacter.PrimaryPart, humanoid.RootPart) > abortChasingDistance or targetHumanoid.Health <= 0) then
							if (not isSCP or (scpType == "173" and targetCharacter.viewers.Value > 3)) then
								break
							end
						end

						--[[if (not character:FindFirstChildWhichIsA("Tool")) then
							for _,tool in pairs(backpack:GetChildren()) do
								if (tool:IsA("Tool") and tool:GetAttribute("IsGun") == true) then
									tool.Parent = character
									break
								end
							end
						end]]

						local cansee = canSee(targetCharacter)
						if (not cansee) then
							losingSight += 1
						else
							losingSight = 0
							updatedTargetPosition = targetHumanoid.RootPart.Position
						end
						if (losingSight > losingSightMax) then
							talk(chatline.lostTrackText)
							break
						end
						local distance = getDistance(targetHumanoid.RootPart, humanoid.RootPart)
						if (distance <= 5 and tick() - damageTime >= attackDelay and humanoid.Health > 0) then
							damageTime = tick()
							targetHumanoid:TakeDamage(attackDamage)
						end

						goal = clampDistanceBetweenVectors(updatedTargetPosition, humanoid.RootPart.Position, minMeleeRadius)
						if (distance <= meleeActiveRadius or not cansee or (distance > meleeActiveRadius and distance > gunActiveRadius)) then
							path:Run(goal)
							speed = runspeed

							if (distance <= meleeActiveRadius and not stringMatchInTable(scpType, doNotKillSCPs)) then
								fireGun(targetHumanoid.RootPart.Position + Vector3.new(0, math.random(1, 15) / 10, 0))
							end

							if (scpType == "173" and targetCharacter.caged.Value == false and distance < 5 and humanoid.Health > 0) then
								targetCharacter.caged.Value = true

								talk(scpChatline.action)
								task.wait(5)
								if (humanoid.Health < 1) then
									targetCharacter.caged.Value = false
									return
								end

								local cage = Assets.Models["173-Cage"]:Clone()
								cage.CFrame = targetHumanoid.RootPart.CFrame
								cage.Parent = workspace.Debris

								local weld = Instance.new("Weld")
								weld.Part0 = targetHumanoid.RootPart
								weld.Part1 = cage
								weld.Parent = cage

								local ignore = Instance.new("StringValue")
								ignore.Name = "__ignore"
								ignore.Parent = targetCharacter

								talk(scpChatline.recontain)

								local offsetHeight = Vector3.new(0, 3.5, 0)
								local goalCFrame = cage.CFrame + offsetHeight
								for k = 1, 100 do
									cage.CFrame = cage.CFrame:lerp(goalCFrame, 0.08)
									task.wait()
								end

								task.spawn(function()
									while cage do
										if (humanoid.Health < 1) then
											break
										end
										cage.CFrame = cage.CFrame:lerp(humanoid.RootPart.CFrame + humanoid.RootPart.CFrame.LookVector * 8 + offsetHeight, 0.15)
										task.wait()
									end

									task.wait(5)
									if (targetCharacter and targetCharacter:FindFirstChild("caged")) then
										targetCharacter.caged.Value = false
									end
									cage:Destroy()
									ignore:Destroy()
								end)

								break
							end
						elseif (path.Status == simplePath.StatusType.Active) then
							path:Stop()
						end

						if (distance > meleeActiveRadius and distance <= gunActiveRadius) then
							-- // move random side
							if (tick() - sideMoveDelay >= math.random(sideMoveDelayTime[1], sideMoveDelayTime[2]) / 10) then
								sideMoveDelay = tick()
								humanoid:MoveTo(humanoid.RootPart.Position + humanoid.RootPart.CFrame.RightVector * math.random(-sideMoveLength, sideMoveLength))
							end

							if (isSCP and stringMatchInTable(scpType, chargeSCPs)) then
								if (math.random(20) == 1) then
									path:Run(goal)
								end
							end

							if ((canSee(targetCharacter) or math.random(60) == 1) and math.random(5) == 1 and not stringMatchInTable(scpType, doNotKillSCPs)) then
								fireGun(targetHumanoid.RootPart.Position + Vector3.new(0, math.random(1, 15) / 10, 0))
							elseif (not canSee(targetCharacter) and tick() - hideDelay > math.random(5, 10) and math.random(20) == 1 and not stringMatchInTable(scpType, doNotKillSCPs)) then
								if (not isLastTargetSCP) then
									hideDelay = tick()
									talk(chatline.hideText)
								else
									isLastTargetSCP = false
								end
							end

							speed = defaultspeed / 1.5
						end

						humanoid.AutoRotate = false
						gyro.CFrame = CFrame.new(Vector3.new(humanoid.RootPart.Position.x, 0, humanoid.RootPart.Position.z), Vector3.new(goal.x, 0, goal.z))
						a1.WorldPosition = targetHumanoid.RootPart.Position + Vector3.new(0, 1.5, 0)

						task.wait(globalRate)
					end
					
					if (targetHumanoid.Health < 1 and combat:getKiller(targetHumanoid) ~= humanoid) then
						talk(chatline.thanksText)
					end

					local gun = character:FindFirstChildWhichIsA("Tool")
					if (gun and gun:GetAttribute("IsGun") == true) then
						gun["__bind"]:Fire(false)
					end
					speed = defaultspeed
					gyro:Destroy()
					humanoid.AutoRotate = true
					if (typeof(goal) == "Vector3" or typeof(goal) == "Instance") then
						path:Run(goal)
					end
				else
					if (not chasing and not backupping) then
						script.vars.spotted.Value = false

						local gun = character:FindFirstChildWhichIsA("Tool")
						if (gun and gun:GetAttribute("IsGun") == true) then
							if (gun:GetAttribute("ClipCurrent") < gun:GetAttribute("ClipSize")) then
								gun["__bind"]["__reload"]:Fire()
							else
								local otherLowAmmoGun = getGunFromInventory(false)
								if (otherLowAmmoGun) then
									equipTool(otherLowAmmoGun)
								end
							end
						end

						local foundTarget = false
						local wanderTarget = findWanderHumanoid(workspace.Characters, wanderTargetDetectDistance)
						local wanderTargetChance = math.random(1, 3)
						if (wanderTarget and wanderTargetChance < 2) then
							local wanderTargetHumanoid = wanderTarget:FindFirstChildWhichIsA("Humanoid")
							goal = generateNewRandomPosition(wanderTargetHumanoid.RootPart.Position, wanderTargetRadius, 0)
						else
							goal = generateNewRandomPosition(humanoid.RootPart.Position, wanderRadius, 0)
						end
						local idle = tick()
						local gyro = Instance.new("BodyGyro")
						gyro.MaxTorque = Vector3.new(1e3, 1e3, 1e3)
						gyro.D = lookRoughness
						gyro.Parent = humanoid.RootPart
						while humanoid.RootPart and goal and getDistance(goal, humanoid.RootPart) > 10 and not backupping do
							if (findHumanoid(workspace.Characters)) then
								foundTarget = true
								break
							end

							if (humanoid.RootPart.Velocity.magnitude > 1) then
								idle = tick()
							else
								if (tick() - idle > stuckTime) then
									goal = humanoid.RootPart.Position + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
									humanoid:MoveTo(goal)
									break
								end
							end

							local lookDirection = false -- findLookDirection()
							if (lookDirection and not humanoid.Jump and getDistance(humanoid.RootPart, lookDirection[#lookDirection]) > minLookDistance) then
								local lookPosition = lookDirection[math.random(1, #lookDirection)]
								lookPosition = Vector3.new(lookPosition.x, humanoid.RootPart.Position.y, lookPosition.z)
								local lookCFrame = CFrame.new(humanoid.RootPart.Position + Vector3.new(0, 1.5, 0), lookPosition)
								network:FireAllClients("cam/mouse", character, lookCFrame, {humanoid.RootPart.Position + Vector3.new(0, 1.5, 0), lookPosition})
								for _,position in pairs(lookDirection) do
									gyro.CFrame = CFrame.new(Vector3.new(humanoid.RootPart.Position.x, 0, humanoid.RootPart.Position.z), Vector3.new(position.x, 0, position.z))
								end

								humanoid.AutoRotate = false
							else
								gyro:Destroy()
								humanoid.AutoRotate = true
							end
							task.wait()
						end

						gyro:Destroy()
						humanoid.AutoRotate = true

						if (not foundTarget) then
							local time = tick()
							local timeTowait = math.random(wanderDelayTime[1], wanderDelayTime[2]) / 10
							while tick() - time < timeTowait do
								if (findHumanoid(workspace.Characters) or backupping) then
									break
								end
								task.wait()
							end
						end
					end

					chasing = false
				end
			end

			task.wait(globalRate)
		end
	end)
	
	local connections = {}
	local connected = true
	local reload = false
	task.defer(function()
		while connected and humanoid:IsDescendantOf(workspace) do
			if (character:FindFirstChild("Head")) then
				a0.WorldPosition = character.Head.Position
			end

			local gun = character:FindFirstChildWhichIsA("Tool")
			if (gun and gun:GetAttribute("IsGun") == true and gun:GetAttribute("Reloading") == true) then
				reload = true
				speed = 6
			else
				if (reload) then
					reload = false
					speed = defaultspeed
				end
			end

			local targetCharacter = findHumanoid(workspace.Characters)
			if (not targetCharacter and character:FindFirstChild("Head")) then
				seenEnemy = false
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {character, workspace.Terrain.Ignore}
				params.IgnoreWater = true

				local cast = workspace:Raycast(character.Head.Position, humanoid.RootPart.CFrame.LookVector * 1000, params)
				if (cast and cast.Instance.CanCollide == true) then
					a1.WorldPosition = cast.Position
				else
					a1.WorldPosition = character.Head.Position + humanoid.RootPart.CFrame.LookVector * 10
				end

				local cast = workspace:Raycast(humanoid.RootPart.Position, humanoid.RootPart.CFrame.LookVector * 5, params)
				if (cast and cast.Instance.CanCollide == true and not cast.Instance:IsDescendantOf(workspace.Debris) and not cast.Instance:IsDescendantOf(workspace.Characters)) then
					local topY = cast.Instance.Position.y + (cast.Instance.Size.y / 2)
					local movespeed = Vector3.new(humanoid.RootPart.Velocity.x, 0, humanoid.RootPart.Velocity.z).magnitude
					if ((humanoid.RootPart.Position.y + 1.5) >= topY and movespeed > 0) then
						humanoid.Jump = true
					end
				end
			else
				local targetHumanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid")
				if (targetHumanoid and targetHumanoid.RootPart) then
					local lookCFrame = CFrame.new(humanoid.RootPart.Position + Vector3.new(0, 1.5, 0), targetHumanoid.RootPart.Position + Vector3.new(0, 1.5, 0))
					network:FireAllClients("cam/mouse", character, lookCFrame, {humanoid.RootPart.Position + Vector3.new(0, 1.5, 0), targetHumanoid.RootPart.Position + Vector3.new(0, 1.5, 0)})
				end
			end

			humanoid.WalkSpeed = speed
			task.wait(globalRate)
		end
	end)
	
	local diedDebounce = false
	local hurtSoundDelay = 0
	local lastHealth = humanoid.Health
	table.insert(connections, humanoid.HealthChanged:Connect(function(health)
		local damageTaken = lastHealth - health
		if (damageTaken > 0 and humanoid.Health > 0) then
			task.defer(function()
				if (damageTaken > 10 and tick() - hurtDelay >= math.random(5, 10)) then
					hurtDelay = tick()
					talk(chatline.hurtText)
				end

				if (damageTaken > 5 and damageTaken < 30 and tick() - hurtSoundDelay >= math.random(1, 3) / 10 and humanoid.Health > 0) then
					hurtSoundDelay = tick()
					local hurtSound = Assets.Sounds.Hurt:FindFirstChild(teamName)
					if (not hurtSound) then
						hurtSound = Assets.Sounds.Hurt.Default
					end
					if (character:FindFirstChild("Head")) then
						playSound(randomChildren(hurtSound), character.Head):Play()
					end
				end

				if (damageTaken > 10 and humanoid.Health < 30) then
					callBackup()
				end

				characterFieldOfView = 360
				if (jumpOnDamageTaken) then
					task.spawn(function()
						for k = 1, math.random(avoidDamageJumpAmount[1], avoidDamageJumpAmount[2]) do
							if (findHumanoid(workspace.Characters)) then
								break
							end
							humanoid.Jump = true
							task.wait(math.random() * 1)
						end
					end)
				end

				for i = 1, math.random(avoidDamageAmount[1], avoidDamageAmount[2]) do
					if (findHumanoid(workspace.Characters)) then
						break
					end
					if (path.Status == simplePath.StatusType.Active) then
						path:Stop()
					end
					goal = humanoid.RootPart.Position + Vector3.new(math.random(-avoidDamageRandomPositionRadius, avoidDamageRandomPositionRadius), 0, math.random(-avoidDamageRandomPositionRadius, avoidDamageRandomPositionRadius))
					path:Run(goal)

					local time = tick()
					local timeWait = math.random(avoidDamageLength[1], avoidDamageLength[2]) / 10
					while goal and getDistance(goal, humanoid.RootPart) > 0.5 do
						if (tick() - time > timeWait or findHumanoid(workspace.Characters)) then
							break
						end
						task.wait()
					end
					if (path.Status == simplePath.StatusType.Active and not findHumanoid(workspace.Characters)) then
						path:Stop()
					end
				end

				characterFieldOfView = defaultFOV
			end)
		elseif (humanoid.Health < 1 and damageTaken > 0 and damageTaken < 30 and not diedDebounce) then
			diedDebounce = true
			
			local deathSound = Assets.Sounds.Death:FindFirstChild(teamName)
			if (not deathSound) then
				deathSound = Assets.Sounds.Death.Default
			end
			
			if (character:FindFirstChild("Head")) then
				talk(chatline.diedText)
				playSound(randomChildren(deathSound), character.Head):Play()
			end
			
			task.wait(1 / 2)
			ragdoll:DeathAnimation(character, "normal", respawnTime / 2, humanoid, settings)
		end
		
		lastHealth = health
	end))
	
	table.insert(connections, Events.ai.Event:Connect(function(type, ...)
		if (not aiActive) then
			return
		end
		
		if (type == "backup") then
			local pos, id, team = unpack({...})
			if (id ~= guid and team == teamValue.Value) then
				task.wait(math.random(1, 3))
				if (humanoid.Health > 0) then
					playSound(randomChildren(Assets.Sounds.radio), humanoid.RootPart):Play()
					if (not findHumanoid(workspace.Characters) and not backupping) then
						backupping = true
						talk(chatline.yesText)

						local backupFailedFlag = 0
						local stuck = tick()
						while true do
							if (findHumanoid(workspace.Characters) or getDistance(humanoid.RootPart, pos) < 10 or backupFailedFlag > 15) then
								break
							end
							local state = path:Run(pos)
							if (not state) then
								backupFailedFlag += 1
							end
							if (humanoid.RootPart.Velocity.magnitude > 0) then
								stuck = tick()
							else
								if (tick() - stuck > 3) then
									break
								end
							end

							task.wait(globalRate)
						end
						backupping = false
					else
						if (getDistance(humanoid.RootPart, pos) < 20) then
							talk(chatline.inPositionText)
						else
							talk(chatline.noText)
						end
					end
				end
			end
		end
	end))
	
	table.insert(connections, humanoid.Died:Connect(function()
		connected = false
		for _,con in pairs(connections) do
			con:Disconnect()
		end
		
		for _,part in pairs(character:GetDescendants()) do
			if (part:IsA("BasePart")) then
				PhysicsService:SetPartCollisionGroup(part, "Death")
			end
		end
		
		local toolToDrop = character:FindFirstChildWhichIsA("Tool")
		if (toolToDrop and toolToDrop:GetAttribute("IsGun") == true) then
			local gunModel = toolToDrop:FindFirstChildWhichIsA("Model")
			local serverScript = toolToDrop:FindFirstChildWhichIsA("Script")
			local motor = serverScript and serverScript:FindFirstChildWhichIsA("Motor6D")
			if (gunModel and serverScript and motor) then
				local model = Assets.GunModels[toolToDrop.Name]:Clone()
				model.Parent = workspace.Terrain.Ignore

				for _,part in pairs(model:GetDescendants()) do
					if (part:IsA("BasePart")) then
						part.CanCollide = true
						PhysicsService:SetPartCollisionGroup(part, "NoCollisions")
					end
				end

				model.Handle.CFrame = gunModel.Handle.CFrame
				model.Handle.RotVelocity = (humanoid.RootPart and humanoid.RootPart.Velocity or model.Handle.Velocity) + Vector3.new(0, 30, 0)
				game.Debris:AddItem(model, 10)
				
				motor:Destroy()
				gunModel:Destroy()
			end
		end
		
		task.wait(respawnTime)
		pcall(function()
			path:Destroy()
		end)
		backpack:Destroy()
		clone.Parent = workspace.Characters
		character:Destroy()
	end))
end
