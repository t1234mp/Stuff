local module = {}

--Services
local inputService = game:GetService("UserInputService")
local debrisService = game:GetService("Debris")
local collectService = game:GetService("CollectionService")

--Modules
local utils = require(script.Parent:WaitForChild("Utils"))	--Utility functions, general useful things.
local sfx = require(script.Parent:WaitForChild("SFX"))		--Shortcut sound effect player.

--Data
local types = require(script.Parent.Types)	--Basically just a bunch of enums. Makes things more readable.

--Creates a table containing named constants.
--You can change these in game, but they're generally not intended for that.
--Things will probably work better if you manually change them here.
function createControllerConstants()
	local physicsScale = 8					--How many units are in a stud.
	return {
		BaseFrameRate = 60,					--Base frame rate the game runs at. Variable framerate was abandoned, do not change.
		Physics = {
			Scale = physicsScale,				--Reference for physics scale. Set earlier as this is referenced a bunch.
			
			Gravity = 0.21875,						--Base gravitational acceleration.
			GravityDir = Vector3.new(0, -1, 0),		--Direction of gravity.
			GroundAccel = 0.046875,					--Player acceleration on ground while walking.
			GroundDecel = 0.5,						--Player deceleration on ground while walking.
			RollDecel = 0.125,						--Player deceleration on ground while rolling.
			Friction = 0.046875,					--Friction of ground while walking.
			RollFriction = 0.046875 / 2,			--Friction of ground while rolling.
			AirAccel = 0.09375,						--Player acceleration in the air.
			MaxSpeed = 6,							--Player top speed.
			
			Slope = 0.125,							--Strength of gravity while on a slope, while walking.
			SlopeUp = 0.078125,						--Strength of gravity while on a slope, while rolling uphill.
			SlopeDown = 0.3125,						--Strength of gravity while on a slope, while rolling downhill.
			
			WallStickMinSpeed = 2.5,				--Minimum speed to continue running on a wall.
			JumpPower = 6.5,						--Velocity when jumping.
			HurtGravity = 0.1875,					--Gravity during damage knockback.
			CliffTolerance = math.rad(45),			--Maximum angle before disabling ground snapping,
			
			StandingWidth = 9/physicsScale,			--Hitbox width when standing.
			StandingHeight = 19/physicsScale,		--Hitbox height when standing.
			RollingWidth = 7/physicsScale,			--Hitbox width when rolling.
			RollingHeight = 14/physicsScale,		--Hitbox height when rolling.
			PushRadius = 10/physicsScale,			--Horizontal collision width.
			
			WaterSkipAccelDown = 1,					--Upwards acceleration while water skipping, during the downwards part.
			WaterSkipAccelUp = 0.9,					--Upwards acceleration while water skipping, during the upwards part.
			WaterSkipDrag = 0.99,					--Drag while water skipping.
			
			SpeedShoes = {							--Physical constants with the speed shoes powerup.
				Accel = 0.09375,					
				Decel = 0.5,	--Unchanged
				Friction = 0.09375,
				MaxSpeed = 12,
				AirAccel = 0.1875,
				RollFric = 0.046875,
				RollDecel = 0.125	--Unchanged
			},
			
			Water = {								--Physical constants while under water.
				Jump = 3.5,
				JumpRelease = 2,
				Gravity = 0.0625,
				Accel = 0.0234375,
				Decel = 0.25,
				Friction = 0.0234375,
				MaxSpeed = 3,
				AirAccel = 0.1875,
				RollFric = 0.01171875,
				RollDecel = 0.125	--Unchanged
			}
		}
	}
end

local constRef = createControllerConstants()

--Creates a table containing all player state, named.
--All objects get a reference to this for processing, allowing easy manipulation of the player.
--For example, teleporting the player is as simple as setting their position.
function createControllerState()
	return {
		Camera = {		--State for the built in camera controller.
			Yaw = 0,							--Camera yaw (horizontal movement).
			Pitch = 0,							--Camera pitch (vertical movement).
			CFrame = CFrame.new(),				--Camera CFrame
			Normal = Vector3.new(0,1,0),		--Vertical axis the camera orbits around.
			Mode = types.CameraModes.Disabled,	--Current camera mode, if not using custom camera movement.
			SwitchMerge = 0						--Used to smooth the transition from 2D to 3D camera.
		},
		Char = {
			MovementMode = types.MovementModes.Free,	--Player movement, either freespace or plane locked.
			MovementLockPlaneCF = CFrame.new(),			--CFrame keeping track of plane lock.
			Position = Vector3.new(),					--Player position.
			Velocity = Vector3.new(),					--Player overall velocity, for calculations and air movement.
			PrevVelocity = Vector3.new(),				--Used to keep track of changes in velocity.
			GroundVelocity = Vector3.new(),				--Used for velocity on ground. 2D, although uses a Vec3 for simplicity.
			SurfaceNormal = Vector3.new(0,1,0),			--Normal of the surface the player is standing on.
			OnGround = true,							--If the player is currently on the ground.
			WasOnGround = true,							--If the player was on the ground during the previous frame.
			Rolling = false,							--If the player is currently rolling.
			WasRolling = false,							--If the player was rolling during the previous frame.
			CurrentHeight = createControllerConstants().Physics.StandingHeight,	--Current value for the player's width.
			CurrentWidth = createControllerConstants().Physics.StandingWidth,	--Current value for the player's height.
			HasJumped = false,							--If the player has jumped during this step.
			Skidding = false,							--If the player is braking hard (controls the skidding sound effect).
			ControlLock = 0,							--Locks the player's controls if greater than 0. Automatically counts down to 0.
			SpinRev = 0,								--Spindash charge, automatically goes to 0 if not actively charged.
			HasDashed = false,							--If the player has released a spindash during the current frame.
			DropCharge = 0,								--Drop dash timer. Counts up upon initiating the move.
			DropCharging = false,						--If the player is currently charging a drop dash.
			LastDir = Vector3.new(1,0,0),				--When stopped, stores the last direction the player was facing. Mainly for 2D operations.
			InWater = false,							--If the player is currently in water.
			WasInWater = false,							--If the player was in water during the last frame.
			CamInWater = false,							--If the camera is in water.
			TimeInWater = 0,							--How many frames the player has been in water.
			OnCliff = false,							--If the player is on a cliff.
			WasOnCliff = false,							--If the player was on a cliff during the last frame.
			Rings = 0,									--How many rings the player has.
			TimeSinceLastHit = 1024,					--Time since the player last took damage.
			HurtFlag = types.HurtFlags.None,			--Used to trigger damage.
			HurtState = types.HurtState.None,			--Used to keep track of damaged state (knockback, dead).
			HurtPosition = Vector3.new(),				--Used to determine the direction to knock the player back.
			InvTimer = 0,								--Invulnerability Timer (hurt specific, not the invincible effect).
			Score = 0,									--Player score.
			Timer = 0,									--Default timer, automatically resets on death.
			Lives = 3,									--Default life counter. Does not actually do anything, if you want game over, react to it yourself.
			RingLifeCount = 100,						--Used to keep track of how many rings contribute to a life.
			SpeedTimer = 0,								--Timer for speed powerup. Automatically decreases to 0.
			InvincTimer = 0,							--Timer for invincibility powerup. Automatically decreases to 0.
			ShieldType = types.Shields.None				--What shield the player currently has (only NONE and NORMAL are implemented).
		}
	}
end

--Creates a table containing settings.
--These are things to either help with using the engine or to expose to the player.
function createControllerSettings()
	return {
		Debug = {
			ShowRayCasts = false,			--Visualize raycasts.
			DisableGroundGravity = false,	--Disables gravity while on the ground (mainly for testing vertical surfaces).
			ShowDebugCasts = false,			--Show debug specific raycasts.
		},
		AutoUpdateCamera = true,			--If off, camera calculations will still be made, but won't be applied. Use to blend with external effects.
		InputMode = types.InputModes.KeyboardMouse,
		CameraDist3d = 16,					--Distance camera attempts to hold in free third person mode.
		CameraDist2d = 32,					--Distance camera attempts to hold in 2d mode.
		CameraHOff2d = 8					--Height offset applied to camera in 2d mode.
	}
end

--Creates a table containing a list of keys and what actions they represent.
--Can be modified.
function createKeyMap()
	local keyMap = {}
	keyMap[Enum.KeyCode.W] = types.KeyMapActions.Forward
	keyMap[Enum.KeyCode.Up] = types.KeyMapActions.Forward
	keyMap[Enum.KeyCode.S] = types.KeyMapActions.Back
	keyMap[Enum.KeyCode.Down] = types.KeyMapActions.Back
	keyMap[Enum.KeyCode.A] = types.KeyMapActions.Left
	keyMap[Enum.KeyCode.Left] = types.KeyMapActions.Left
	keyMap[Enum.KeyCode.D] = types.KeyMapActions.Right
	keyMap[Enum.KeyCode.Right] = types.KeyMapActions.Right
	keyMap[Enum.KeyCode.Space] = types.KeyMapActions.Jump
	keyMap[Enum.KeyCode.LeftShift] = types.KeyMapActions.Crouch
	keyMap[Enum.KeyCode.RightShift] = types.KeyMapActions.Crouch
	return keyMap
end

--Creates a new player controller. This is the object you interact with the engine through.
function module:NewPlayerController()
	--Create Controller
	local controller = {}
	
	--Controller Data
	controller.State = createControllerState()			--State table. See function definition.
	controller.Settings = createControllerSettings()	--Settings table.
	controller.Constants = createControllerConstants()	--Constant table.
	controller.Input = {								--Current input to the controller. (Handled by the controller.)
		Direction = Vector3.new(),
		Jump = 0,
		Crouch = 0,
	}
	controller.KeyMap = createKeyMap()	--Key mapping, can be changed as needed.
	controller.Enabled = false			--If the controller should process data.
	controller.InputEnabled = false		--If the controller should respond to user input.
	controller.Objects = {				--List of objects the controller needs to process. Updated automatically.
		Types = {}
	}
	
	--Create Events
	controller.Died = Instance.new("BindableEvent")		--Fires when the player dies.
	controller.Hurt = Instance.new("BindableEvent")		--Fires when the player is hurt.
	controller.LifeUp = Instance.new("BindableEvent")	--Fires when the player gains a life.
	
	--Shortcuts (Used internally, to avoid constantly referring to things).
	local consts = controller.Constants
	local char = controller.State.Char
	local cam = controller.State.Camera
	local phys = consts.Physics
	local set = controller.Settings
	local db = set.Debug
	local map = controller.KeyMap
	local input = controller.Input
	local objects = controller.Objects
	
	--Helper Functions
	--Local copy of Utils:debugCast(). Acts the same, unless debug casting is disabled in settings.
	--	origin - Starting point of cast.
	--	direction - Direction of cast.
	--	length - Length of the cast.
	--	color - Color of the visualization.
	local function debugCast(origin:Vector3, direction:Vector3, length:number, color:Color3)
		if not db.ShowDebugCasts then return end
		--Defaults for optionals
		if not length then length = direction.magnitude end
		if not color then color = Color3.new(0,0,1) end
		direction = direction.Unit
		
		--if showRayCasts then
		local en = origin+(direction*length)
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.1,0.1,(origin-en).Magnitude)
		part.CFrame = CFrame.new((origin+en)/2,origin)
		part.Color = color
		part.Anchored = true
		part.CanCollide = false
		part.Parent = workspace.RaycastDebugFolder
		--end
	end
	
	--Local copy of Utils:cast(). Acts the same, except visualizations are controlled by settings.
	--	origin - Origin of the raycast.
	--	direction - Direction of the raycast.
	--	length - Length of the raycast.
	--	detectNonCollidable - If noncollidable parts should be detected or ignored.
	--	transparentMode - How to deal with transparent objects.
	--		0 - Transparency is not taken into account.
	--		1 - If the object is more transparent than transparencyThreshold, it is ignored.
	--	transparencyThreshold - Threshold for ignoring transparent objects.
	local function cast(origin:Vector3, direction:Vector3, length:number, detectNonCollidable:boolean, transparentMode:number, transparencyThreshold:number)
		--Defaults for optionals
		if not length then length = 1 end
		if not detectNonCollidable then detectNonCollidable = false end
		if transparentMode == nil then transparentMode = 0 end
		if not transparencyThreshold then transparencyThreshold = 0.9 end
		
		direction = direction.Unit
		
		local parameters = RaycastParams.new()
		parameters.FilterType = Enum.RaycastFilterType.Blacklist
		parameters.FilterDescendantsInstances = {workspace.RaycastDebugFolder}
		
		local result
		
		local c = 0
		repeat
			c = c + 1
			result = workspace:Raycast(origin, direction*length, parameters)
			if not result then break end
			
			local isTransparent = result.Instance.Transparency >= transparencyThreshold
			
			if transparentMode == 0 then		--Transparency is not taken into account at all.
				if result.Instance.CanCollide or detectNonCollidable then break end
			elseif transparentMode == 1 then	--Transparent objects are ignored completely.
				if not isTransparent then
					if result.Instance.CanCollide or detectNonCollidable then break end
				end
			end
			
			local t = parameters.FilterDescendantsInstances
			table.insert(t,result.Instance)
			parameters.FilterDescendantsInstances = t
		until c > 64
		if c > 64 then warn("Took too long to finish! (Too many noncollidable parts.)") end
		
		if db.ShowRayCasts then
			local en = origin+(direction*length)
			local color = Color3.new(1,0,0)
			if result then
				color = Color3.new(0,1,0)
				local part = Instance.new("Part")
				part.Anchored = true
				part.CanCollide = false
				part.Shape = Enum.PartType.Ball
				part.Color = Color3.new(1,1,0)
				part.Size = Vector3.new(0.25,0.25,0.25)
				part.CFrame = CFrame.new(result.Position)
				part.Parent = workspace.RaycastDebugFolder
			end
			local part = Instance.new("Part")
			part.Size = Vector3.new(0.1,0.1,(origin-en).Magnitude)
			part.CFrame = CFrame.new((origin+en)/2,origin)
			part.Color = color
			part.Anchored = true
			part.CanCollide = false
			part.Parent = workspace.RaycastDebugFolder
		end
		if result then
			return result, (origin-result.Position).magnitude
		else
			return false, length
		end
	end
	
	--Processes the acquisition of user input.
	local function getUserInput()
		if
			controller.InputEnabled
			and char.ControlLock < 0.01
			and char.HurtState ~= types.HurtState.Knockback
			and char.HurtState ~= types.HurtState.Dead
		then
			--TODO: Other input methods.
			if set.InputMode == types.InputModes.KeyboardMouse then
				input.Direction = Vector3.new(0,0,0)
				local jump = 0
				local crouch = 0
				for keyCode, mapping in pairs(map) do
					local keyDown = inputService:IsKeyDown(keyCode)
					if mapping == types.KeyMapActions.Forward then
						if keyDown then input.Direction = input.Direction + Vector3.new(0,0,-1) end
					elseif mapping == types.KeyMapActions.Back then
						if keyDown then input.Direction = input.Direction + Vector3.new(0,0,1) end
					elseif mapping == types.KeyMapActions.Left then
						if keyDown then input.Direction = input.Direction + Vector3.new(-1,0,0) end
					elseif mapping == types.KeyMapActions.Right then
						if keyDown then input.Direction = input.Direction + Vector3.new(1,0,0) end
					elseif mapping == types.KeyMapActions.Jump then
						if keyDown then jump = jump + 1 end
					elseif mapping == types.KeyMapActions.Crouch then
						if keyDown then crouch = crouch + 1 end
					end
				end
				if jump > 0 then
					input.Jump = input.Jump + 1
				else
					input.Jump = 0
				end
				if crouch > 0 then
					input.Crouch = input.Crouch + 1
				else
					input.Crouch = 0
				end
				if input.Direction ~= Vector3.new(0,0,0) then
					input.Direction = input.Direction.Unit
				end
			end
		else
			input.Direction = Vector3.new()
			input.Jump = 0
			input.Crouch = 0
		end
	end
	
	--Processes objects that request collision checks.
	--If an object has a boolean attribute called "Collision", it will be set
	--	to true when the player collides with the object.
	--If it has a vector3 attribute called "CollisionNormal", it will be set
	--	to the normal of the collision (for checking which side the player hit from).
	local function checkCollision(castResult:RaycastResult)
		if castResult then
			if
				castResult.Instance:GetAttribute("Collision") == true		--For some reason, using typeof errors when the attribute does not exist.
				or castResult.Instance:GetAttribute("Collision") == false
			then
				castResult.Instance:SetAttribute("Collision", true)
			end
			if
				castResult.Instance:GetAttribute("CollisionNormal")
				and typeof(castResult.Instance:GetAttribute("CollisionNormal")) == typeof(Vector3.new())
			then
				castResult.Instance:SetAttribute("CollisionNormal", castResult.Normal)
			end
		end
	end
	
	--Primary collision detection function.
	local function detectGround()
		--Wall Detection
		do
			for y=-char.CurrentHeight/2,char.CurrentHeight/2,char.CurrentHeight/2 do
				for i=0,math.pi*2,math.pi/4 do
					local cf = utils:CFFromNormal(char.SurfaceNormal)*CFrame.Angles(0,i,0)
					local result, len = cast(char.Position+(char.SurfaceNormal*y),cf.lookVector,phys.PushRadius)
					if result then
						--table.insert(objectCollisionList,result)
						local pos = result.Position
						local norm = result.Normal
						char.Position = char.Position - (norm * len) + (norm * phys.PushRadius)
						local newVelocity = utils:projectOntoPlane(char.Velocity, norm)
						if math.deg(utils:angleBetween(char.Velocity.Unit, newVelocity.Unit)) < 23 then
							char.Velocity = newVelocity.Unit * char.Velocity.Magnitude
						else
							char.Velocity = newVelocity
						end
						checkCollision(result)
					end	
				end
			end
		end
		
		--Ground Detection
		do
			local groundDetected = false
			local groundNormals = {}	--All ground detections
			local filteredNormals = {}	--Only detections where the surface angle is close to the player angle.
			local h
			local castLen = char.CurrentHeight
			if char.OnGround then castLen = castLen + 2 end	-- +2 means the player will snap to surfaces up to two studs down rather than becoming airborn.
			local minLen = math.huge
			for _, p in pairs({{1,0},{-1,0},{0,1},{0,-1}}) do
				local normalCF = utils:CFFromNormal(char.SurfaceNormal)
				local newPos = char.Position + (normalCF * Vector3.new(
					char.CurrentWidth * p[1], 0, char.CurrentWidth * p[2]))
				local result, len = cast(
					newPos,
					-char.SurfaceNormal,
					castLen
				)
				if result then
					--table.insert(objectCollisionList,result)
					if utils:angleBetween(char.SurfaceNormal, result.Normal) < phys.CliffTolerance then
						table.insert(filteredNormals, result.Normal)
					end
					table.insert(groundNormals, result.Normal)
					groundDetected = true
					if len < minLen then
						minLen = len
					end
					checkCollision(result)
				end
			end
			--Ground Snapping
			char.OnGround = groundDetected
			if groundDetected then
				local avgNormal = Vector3.new()
				for _, normal in pairs(groundNormals) do
					avgNormal = avgNormal + normal
				end
				avgNormal = (avgNormal / #groundNormals).Unit
				
				local avgFNormal
				if #filteredNormals > 0 then
					avgFNormal = Vector3.new()
					for _, normal in pairs(filteredNormals) do
						avgFNormal = avgFNormal + normal
					end
					avgFNormal = (avgFNormal / #filteredNormals).Unit
				else
					avgFNormal = avgNormal
				end
				
				--Cliff Detection
				char.WasOnCliff = char.OnCliff
				char.OnCliff = #filteredNormals < #groundNormals
				
				--Actual Snapping
				local doSnap = true
				if char.WasOnGround then	--Already on ground
					if math.deg(utils:angleBetween(avgNormal, char.SurfaceNormal)) > 40 then	--If the angle change is too abrupt, do not snap.
						doSnap = false
					else
						if char.OnCliff then
							char.SurfaceNormal = avgFNormal
						else
							char.SurfaceNormal = avgNormal
						end
					end
				else	--If not already on ground, always stick to surface.
					char.SurfaceNormal = avgNormal
				end
				
				if doSnap then
					char.Position = char.Position - (char.SurfaceNormal * minLen) + (char.SurfaceNormal * char.CurrentHeight)
				end
			else
				char.SurfaceNormal = phys.GravityDir * -1
			end
		end
	
		--Ceiling Detection 
		do
			local ceilingDetected = false
			local normals = {}
			local minLen = math.huge
			for _, p in pairs({{1,0},{-1,0},{0,1},{0,-1}}) do
				--CFrame:PointToWorldSpace = cf*v3 (for shortening, thats a long function)
				local normalCF = utils:CFFromNormal(char.SurfaceNormal)
				local newPos = char.Position + (normalCF * Vector3.new(
					char.CurrentWidth * p[1], 0, char.CurrentWidth * p[2]))
				local result, len = cast(
					newPos,
					char.SurfaceNormal,
					char.CurrentHeight
				)
				if result then
					--table.insert(objectCollisionList,result)
					table.insert(normals, result.Normal)
					ceilingDetected = true
					if len < minLen then
						minLen = len
					end
					checkCollision(result)
				end
			end
			--Hit ceiling
			if ceilingDetected then
				local newSurfaceNormal = Vector3.new(0, 0, 0)
				for _, normal in pairs(normals) do
					newSurfaceNormal = newSurfaceNormal + normal
				end
				newSurfaceNormal = newSurfaceNormal / #normals
				--local newSurfaceNormal = normals[1]
				local ceilingAngle = utils:angleBetween(phys.GravityDir, newSurfaceNormal.Unit)
				if ceilingAngle < math.pi / 4 then
					char.Velocity = utils:projectOntoPlane(char.Velocity, newSurfaceNormal)
					char.Position = char.Position - (newSurfaceNormal * minLen) + (newSurfaceNormal * char.CurrentHeight)
				else
					char.Position = char.Position - (char.SurfaceNormal * minLen) + (char.SurfaceNormal * char.CurrentHeight)
					char.SurfaceNormal = newSurfaceNormal.Unit
				end
			end
		end
	end
	
	--Camera Input
	inputService.InputChanged:Connect(function(input, processed)
		if not processed then
			if controller.InputEnabled then
				if cam.Mode == types.CameraModes.FreeThirdPerson or cam.Mode == types.CameraModes.FreeFirstPerson then
					if set.InputMode == types.InputModes.KeyboardMouse then	--Mouse Camera
						if input.UserInputType == Enum.UserInputType.MouseMovement then
							inputService.MouseBehavior = Enum.MouseBehavior.LockCenter
							local delta = input.Delta
							cam.Yaw = (cam.Yaw - delta.X / 360) % (math.pi * 2)
							cam.Pitch = math.clamp(cam.Pitch - (delta.Y / 360), -math.pi / 2.1, math.pi / 2.1)
						end
					end
				end
			end
		end
	end)
	local localLook = Vector3.new(0, 0, 1)
	local fakeCamCF = CFrame.new()			--Used to remove issues with the 2D camera and using the actual camera's position.
	--Main camera update function.
	local function updateCamera()
		if not (localLook.Magnitude < 2) then	--It should always be 1. If it somehow ends up NaN, this fixes it. Still haven't ironed that out.
			localLook = Vector3.new(0, 0, 1)
		end
		--Processes the third person free look camera.
		local function ftp():CFrame
			local verticalAngle = math.deg(utils:angleBetween(phys.GravityDir * -1, char.SurfaceNormal.Unit))
			
			if verticalAngle < 40 then
				cam.Normal = cam.Normal:Lerp(phys.GravityDir * -1, 0.2).Unit
			else
				cam.Normal = cam.Normal:Lerp(char.SurfaceNormal, 0.2).Unit
			end
			
			localLook = utils:projectOntoPlane(localLook, cam.Normal).Unit
			local normCF = utils:CFFromNormal(cam.Normal,localLook)
			local camRotCF = CFrame.Angles(0, cam.Yaw ,0) * CFrame.Angles(cam.Pitch, 0, 0)
			
			local targetCF = CFrame.new(char.Position) * normCF * camRotCF
			local _, len = cast(char.Position, targetCF.LookVector * -1, set.CameraDist3d, false, 1)
			targetCF = targetCF * CFrame.new(0, 0, len - 0.1)
			
			return targetCF
		end
		--Processes the 2D locked camera.
		local function ls():CFrame
			local cf = CFrame.lookAt(
				(char.Position + (char.MovementLockPlaneCF.LookVector * set.CameraDist2d)) - (phys.GravityDir * set.CameraHOff2d),
				char.Position,
				phys.GravityDir * -1
			)
			
			local r = fakeCamCF - fakeCamCF.Position
			local t = cf - cf.Position
			
			local nr = r:Lerp(t, 0.1)
			
			fakeCamCF = CFrame.new((char.Position - (nr.LookVector * set.CameraDist2d))) * nr
			
			return fakeCamCF
		end
		if cam.Mode == types.CameraModes.FreeThirdPerson or cam.Mode == types.CameraModes.LockedSide then
			if cam.Mode == types.CameraModes.LockedSide then
				--cam.SwitchMerge = 1
				cam.SwitchMerge = math.min(cam.SwitchMerge + 1/20, 1)
			else
				--cam.SwitchMerge = 0
				cam.SwitchMerge = math.max(cam.SwitchMerge - 1/20, 0)
			end
				--cam.CFrame = ls()
			if cam.SwitchMerge <= 0.01 then
				ls()
				cam.CFrame = ftp()
			elseif cam.SwitchMerge >= 0.99 then
				cam.CFrame = ls()
				cam.Yaw = 0
				localLook = -char.MovementLockPlaneCF.LookVector
			else
				--Somrthinh
				if cam.Mode == types.CameraModes.FreeThirdPerson then
					cam.Yaw = 0
					localLook = -char.MovementLockPlaneCF.LookVector
				end
				
				--Fancy math because a plain linear interpolation looks bad.
				cam.SwitchMerge = math.clamp(cam.SwitchMerge, 0, 1)
				--local a = ls()
				--local b = ftp()
				--cam.CFrame = b:Lerp(a, (1 - math.cos(cam.SwitchMerge * math.pi)) / 2)
				--cam.CFrame = a
				cam.CFrame = ftp():Lerp(ls(), (1 - math.cos(cam.SwitchMerge * math.pi)) / 2)
			end
		end
	end
	
	--Main function for player movement.
	local function doMovement(controlDirGlobal, stepTime)
		local timeMod = (consts.BaseFrameRate * stepTime)	--Compensation for variable framerate
		
		--Set last direction moved (but only if still moving).
		if char.Velocity.Magnitude > 0.001 then
			char.LastDir = char.Velocity.Unit
		end
		
		--Make sure the character is in a state in which they use normal movement.
		if char.HurtState == types.HurtState.None or char.HurtState == types.HurtState.Knockback or char.HurtState == types.HurtState.Invulnerable then
			--Jumping
			if input.Jump == 1 and input.Crouch == 0 and char.OnGround then
				if char.InWater then
					char.Velocity = char.Velocity + (char.SurfaceNormal * phys.Water.Jump)
				else
					char.Velocity = char.Velocity + (char.SurfaceNormal * phys.JumpPower)
				end
				char.OnGround = false
				char.HasJumped = true
				char.Rolling = true
				script.Parent.Assets.JumpSFX:Play()
			end
			--Jump height reduction. When player lets go of jump, if they are moving up fast enough, cap their upwards velocity.
			if input.Jump == 0 and char.HasJumped and input.Crouch == 0 then
				char.HasJumped = false
				local v = utils:projectOntoVector(char.Velocity, phys.GravityDir)
				if char.InWater then
					if v.Magnitude > 2 and char.Velocity:Dot(phys.GravityDir) < 0 then
						local a = utils:projectOntoPlane(char.Velocity, phys.GravityDir)
						local b = utils:projectOntoVector(char.Velocity, phys.GravityDir)
						char.Velocity = a + (b.Unit * 2)
					end
				else
					if v.Magnitude > 4 and char.Velocity:Dot(phys.GravityDir) < 0 then
						local a = utils:projectOntoPlane(char.Velocity, phys.GravityDir)
						local b = utils:projectOntoVector(char.Velocity, phys.GravityDir)
						char.Velocity = a + (b.Unit * 4)
					end
				end
			end
			
			--Drop Dash
			if input.Jump == 1 and (not char.OnGround) and (not char.HasJumped) and char.Rolling then
				char.DropCharging = true
				char.DropCharge = 0
				utils:playSFX(char.Position,60+11.615,2.5)
			end
			if input.Jump == 0 and not char.OnGround then
				char.DropCharging = false
				char.DropCharge = 0
			end
			if input.Jump > 0 and (not char.OnGround) and char.DropCharging then
				char.DropCharge = char.DropCharge + 1
			end
			if char.OnGround and (not char.WasOnGround) and char.DropCharge >= 20 then
				local dropSpeed = 8
				local dropMax = 12
				local newVelocity = char.Velocity
				local newDir
				if char.MovementMode == types.MovementModes.Locked then
					newDir = utils:projectOntoPlane(char.LastDir, char.SurfaceNormal).Unit
				else
					newDir = utils:projectOntoPlane(workspace.CurrentCamera.CFrame.LookVector, cam.Normal).Unit
				end
				
				local newSpeed = ((newVelocity/4)+(dropSpeed*newDir)).Magnitude
				
				char.Velocity = newDir*math.clamp(newSpeed,0,dropMax)
				utils:playSFX(char.Position,66.815,2)
				
				char.DropCharge = -1
				char.DropCharging = 0
				char.Rolling = true
			end
			
			--Rolling/Spindash
			if script.Parent.Assets.SpindashSFX.TimePosition > 2 and script.Parent.Assets.SpindashSFX.TimePosition < 2.9 then
				script.Parent.Assets.SpindashSFX:Stop()
			end
			if input.Crouch > 0 then
				if char.Velocity.Magnitude > 1.1 then
					--Roll
					if not char.Rolling and char.OnGround then
						script.Parent.Assets.SpindashSFX.TimePosition = 0
						script.Parent.Assets.SpindashSFX:Play()
					end
					char.Rolling = true	--Not in the ground condition, allows entering a roll if airborn for other reasons than jumping.
				else
					--Spindash
					if input.Jump == 1 then
						script.Parent.Assets.SpindashSFX.PlaybackSpeed = 1+(char.SpinRev/16)
						script.Parent.Assets.SpindashSFX.TimePosition = 0
						script.Parent.Assets.SpindashSFX:Play()
						char.SpinRev = math.min(char.SpinRev + 2, 8)
					end
					if char.SpinRev > 0.05 then
						char.Rolling = true
					end
				end
			end
			char.HasDashed = false
			if input.Crouch == 0 and char.OnGround and char.SpinRev > 0.05 then
				--Release Spindash
				local groundSpeed = 8 + math.floor(char.SpinRev / 2)
				
				local flatVector
				if char.MovementMode == types.MovementModes.Locked then
					flatVector = utils:projectOntoPlane(char.LastDir, char.SurfaceNormal)
				else
					flatVector = utils:projectOntoPlane(cam.CFrame.LookVector, char.SurfaceNormal)--cam.Normal)
				end
				local dir = utils:projectOntoPlane(flatVector, char.SurfaceNormal).Unit
				
				char.Velocity = dir * groundSpeed
				char.HasDashed = true
				char.SpinRev = 0
				
				script.Parent.Assets.SpindashSFX.PlaybackSpeed = 1
				script.Parent.Assets.SpindashSFX.TimePosition = 3
				script.Parent.Assets.SpindashSFX:Play()
			end
			if char.SpinRev > 0.05 then
				char.SpinRev = char.SpinRev * 0.96875	--Not sure how to framerate compensate this
				char.Rolling = true
			end
					
			--Main Physics
			if char.OnGround then	--If player is on the ground.
				char.HasJumped = false
				local vertAngle = math.deg(utils:angleBetween(phys.GravityDir * -1, char.SurfaceNormal))
				local groundSpeed = char.Velocity.Magnitude
				
				if char.WasOnGround then	--Player is on ground as normal.
					if char.Velocity:FuzzyEq(Vector3.new(), 10 ^ -10) then
						char.Velocity = Vector3.new()
					else
						char.Velocity = utils:projectOntoPlane(char.Velocity, char.SurfaceNormal).Unit * char.Velocity.Magnitude
					end
				else	--If the player has just landed.
					if char.HurtState == types.HurtState.Knockback then
						char.Velocity = Vector3.new()
						char.HurtState = types.HurtState.Invulnerable
						char.InvTimer = 120
					else
						char.Velocity = utils:projectOntoPlane(char.Velocity, char.SurfaceNormal)
					end
				end
				
				if char.Rolling and (not char.WasOnGround) and (not char.HasDashed) and char.DropCharge ~= -1 then
					if input.Crouch == 0 then
						char.Rolling = false
					else
						script.Parent.Assets.SpindashSFX.TimePosition = 0
						script.Parent.Assets.SpindashSFX:Play()
					end
				end
				if char.DropCharge == -1 then char.DropCharge = 0 end
				
				--Movement Logic
				if char.Rolling then	--Rolling
					--Unrolling
					if char.Velocity.Magnitude < 1 and char.SpinRev < 0.05 then --and spinRev < 0.05 and not forcedRoll then
						char.Rolling = false
						return
					end
					
					--Braking
					if controlDirGlobal.Magnitude > 0.01 then
						char.Velocity = char.Velocity + ((controlDirGlobal - char.Velocity.Unit).Unit * phys.RollDecel * timeMod)
					end
					
					--Friction
					if char.Velocity.Magnitude > phys.RollFriction * 0.5 * timeMod then
						char.Velocity = char.Velocity - (char.Velocity.Unit * phys.RollFriction * 0.5 * timeMod)
					else
						char.Velocity = char.Velocity / 1.1
					end
					
					--Slope Acceleration (IE Gravity)
					if math.abs(char.SurfaceNormal:Dot(phys.GravityDir)) < 0.99 and not db.DisableGroundGravity then
						local gravCF = utils:CFFromNormal(char.SurfaceNormal, phys.GravityDir)
						local amount = utils:projectOntoVector(gravCF.LookVector, phys.GravityDir).Magnitude
						if char.Velocity:Dot(phys.GravityDir) < 0 then	--Player is moving upwards
							char.Velocity = char.Velocity + gravCF.LookVector * amount * phys.SlopeUp
						else
							char.Velocity = char.Velocity + gravCF.LookVector * amount * phys.SlopeDown
						end
					end
				else	--Running
					if controlDirGlobal.Magnitude > 0.01 then	--If the player is actively moving.
						if char.Velocity.Magnitude > 1 then
							local diff = char.Velocity.Unit:Dot(controlDirGlobal.Unit)
							local groundV = utils:projectOntoPlane(char.Velocity, char.SurfaceNormal)
							local groundSpeed = groundV.Magnitude
							local newSpeed = groundSpeed
							
							if diff > -0.25 and vertAngle < 45 then
								newSpeed = newSpeed + (phys.GroundAccel * diff * timeMod)
							elseif vertAngle >= 45 then
								newSpeed = newSpeed + (phys.GroundAccel * diff * timeMod)
							else
								newSpeed = newSpeed + (phys.GroundDecel * diff * timeMod)
							end
							
							if diff < -0.667 then
								if not char.Skidding then
									utils:playSFX(char.Position, 8.118, 1.5)	--Skid SFX
								end
								char.Skidding = true
							else
								char.Skidding = false
							end
							
							if newSpeed < phys.MaxSpeed or newSpeed < groundSpeed then
								groundSpeed = newSpeed
							end
							
							char.Velocity = (char.Velocity + (controlDirGlobal / ((groundSpeed / 2) + 2))).Unit * groundSpeed
						else	--Simplified motion rules when moving very slowly.
							char.Velocity = char.Velocity + (controlDirGlobal * phys.GroundAccel * timeMod)
						end
					else	--Player is not actively controlling Sonic.
						if char.Velocity.Magnitude > phys.Friction * timeMod then
							char.Velocity = char.Velocity - (char.Velocity.Unit * phys.Friction * timeMod)
						else
							char.Velocity = char.Velocity / 1.1
						end
					end
					
					--Slope Acceleration (IE Gravity)
					if math.abs(char.SurfaceNormal:Dot(phys.GravityDir)) < 0.99 and not db.DisableGroundGravity then
						local gravCF = utils:CFFromNormal(char.SurfaceNormal, phys.GravityDir)
						local amount = utils:projectOntoVector(gravCF.LookVector, phys.GravityDir).Magnitude
						char.Velocity = char.Velocity + gravCF.LookVector * amount * phys.Slope
					end
				end
				
				--Wall Disconnection
				if vertAngle > 45 and not db.DisableGroundGravity then
					if groundSpeed < phys.WallStickMinSpeed then
						if vertAngle > 89 then
							char.OnGround = false
						end
						char.ControlLock = 30
					end
				end
			else	--Air Movement
				local newVelocity = char.Velocity + (controlDirGlobal * phys.AirAccel)
				local oldGSP = utils:projectOntoPlane(char.Velocity, phys.GravityDir * -1)
				local newGSP = utils:projectOntoPlane(newVelocity, phys.GravityDir * -1)
				local newVSP = utils:projectOntoVector(newVelocity, phys.GravityDir * -1)
				if newGSP.Magnitude < phys.MaxSpeed then	--Player is within speed limits
					char.Velocity = newVelocity
				else	--Player is overspeed
					if newGSP.Magnitude < oldGSP.Magnitude then
						char.Velocity = newVelocity
					else
						char.Velocity = newVSP + (newGSP.Unit * oldGSP.Magnitude)
					end
				end
				
				--Gravity
				if char.HurtState == types.HurtState.Knockback then
					char.Velocity = char.Velocity + (phys.GravityDir * phys.HurtGravity * timeMod)
				else
					char.Velocity = char.Velocity + (phys.GravityDir * phys.Gravity * timeMod)
				end
			end
		elseif char.HurtState == types.HurtState.Dead then
			char.Velocity = char.Velocity + (phys.GravityDir * phys.Gravity * timeMod)
		end
		if char.MovementMode == types.MovementModes.Locked then
			char.Velocity = utils:projectOntoPlane(char.Velocity, char.MovementLockPlaneCF.LookVector)
		end
	end
	
	--Processes objects that have been registered to the controller.
	local function processObjects()
		for _, pointer in pairs(script.Objects:GetChildren()) do
			if pointer:IsA("ObjectValue") then
				local obj = pointer.Value
				if obj then
					if obj:IsDescendantOf(game) then
						local objId = obj.Name
						local scr = obj:FindFirstChild("Main", true)
						if scr then
							if scr:IsA("ModuleScript") then
								if scr:GetAttribute("ID") then
									objId = scr:GetAttribute("ID")
								end
								local mod = require(scr)
								--Check if any object of this type has been loaded. If not, run its init func.
								if not objects[objId] then
									mod:Init(controller)
									objects[objId] = true
								end
								--Check if this specific object has been loaded. If not, run its load func.
								if not collectService:HasTag(obj, "TSE_LOADED_OBJECT") then
									mod:Load(controller)
									collectService:AddTag(obj, "TSE_LOADED_OBJECT")
								end
								--Run this objects step func.
								mod:Step(controller)
							end
						end
					else
						pointer:Destroy()	--Cleanup for unloaded objects.
					end
				else
					pointer:Destroy()	--Cleanup for unloaded objects.
				end
			end
		end
	end
	
	--Applies automatic changes to the physics constants for things like water.
	local function handlePhysChanges()
		phys.Gravity = constRef.Physics.Gravity
		phys.GroundAccel = constRef.Physics.GroundAccel
		phys.GroundDecel = constRef.Physics.GroundDecel
		phys.Friction = constRef.Physics.Friction
		phys.MaxSpeed = constRef.Physics.MaxSpeed
		phys.AirAccel = constRef.Physics.AirAccel
		phys.RollFriction = constRef.Physics.RollFriction
		if char.InWater then
			phys.Gravity = phys.Water.Gravity
			phys.GroundAccel = phys.Water.Accel
			phys.GroundDecel = phys.Water.Decel
			phys.Friction = phys.Water.Friction
			phys.MaxSpeed = phys.Water.MaxSpeed
			phys.AirAccel = phys.Water.AirAccel
			phys.RollFriction = phys.Water.RollFric
		end
		if char.SpeedTimer > 0 then
			if char.InWater then
				phys.GroundAccel = phys.SpeedShoes.Accel * 0.5
				phys.GroundDecel = phys.SpeedShoes.Decel * 0.5
				--phys.Friction = phys.SpeedShoes.Friction * 0.5
				phys.MaxSpeed = phys.SpeedShoes.MaxSpeed * 0.5
				phys.AirAccel = phys.SpeedShoes.AirAccel * 0.5
				--phys.RollFriction = phys.SpeedShoes.RollFric * 0.5
			else
				phys.GroundAccel = phys.SpeedShoes.Accel
				phys.GroundDecel = phys.SpeedShoes.Decel
				phys.Friction = phys.SpeedShoes.Friction
				phys.MaxSpeed = phys.SpeedShoes.MaxSpeed
				phys.AirAccel = phys.SpeedShoes.AirAccel
				phys.RollFriction = phys.SpeedShoes.RollFric
			end
		end
	end
	
	--Primary update function.
	--Calls other update functions.
	controller.Step = function(_, stepTime:number)
		
		if not stepTime then
			stepTime = 1 / 60
		end
		
		if controller.Enabled then
			if db.ShowRayCasts or db.ShowDebugCasts then
				workspace.RaycastDebugFolder:ClearAllChildren()
			end
			
			--Some Things
			handlePhysChanges()
			
			char.PrevVelocity = char.Velocity
			char.WasRolling = char.Rolling
			
			if char.Rolling then
				char.CurrentHeight = phys.RollingHeight
				char.CurrentWidth = phys.RollingWidth
			else
				char.CurrentHeight = phys.StandingHeight
				char.CurrentWidth = phys.StandingWidth
			end
			
			char.Timer = char.Timer + stepTime
			
			if char.Rings >= char.RingLifeCount then
				char.RingLifeCount = char.RingLifeCount + 100
				char.Lives = char.Lives + 1
				controller.LifeUp:Fire()
			end
			
			if char.SpeedTimer > 0 then
				char.SpeedTimer = char.SpeedTimer - 1
			end
			if char.InvincTimer > 0 then
				char.InvincTimer = char.InvincTimer - 1
				if char.HurtFlag == types.HurtFlags.GenericHit then
					char.HurtFlag = types.HurtFlags.None
				end
			end
			
			--Input
			getUserInput()
			if char.ControlLock > 0 then
				char.ControlLock = char.ControlLock - (consts.BaseFrameRate * stepTime)
			end
			
			local flatCF = utils:CFFromNormal(char.SurfaceNormal, workspace.Camera.CFrame.LookVector)
			local globalDir = flatCF:VectorToWorldSpace(input.Direction)
			debugCast(char.Position, globalDir, 4)
			
			--Collision
			--Also this is where we do the main speed update.
			char.Position = char.Position + (char.Velocity * consts.BaseFrameRate * stepTime * (1 / phys.Scale))
			char.WasOnGround = char.OnGround
			if char.HurtState ~= types.HurtState.Dead then
				detectGround()
			end
			--So we snap to plane if needed
			if char.MovementMode == types.MovementModes.Locked then
				local cf = char.MovementLockPlaneCF
				local target = utils:projectOntoPlane(char.Position - cf.Position, cf.LookVector) + cf.Position
				char.Position = char.Position:Lerp(target, 0.25)
			end
			
			--Hurting
			char.TimeSinceLastHit = char.TimeSinceLastHit + 1
			
			if	--Player must be hurt, but not in a hurt state, with no invincibility or invulnerability (unless its an instakill)
				(char.HurtFlag == types.HurtFlags.GenericHit or char.HurtFlag == types.HurtFlags.InstantHit)
				and char.HurtState == types.HurtState.None
				and (char.InvincTimer == 0 or char.HurtFlag == types.HurtFlags.InstantHit)
			then
				char.TimeSinceLastHit = 0
				if char.HurtFlag == types.HurtFlags.GenericHit or char.HurtFlag == types.HurtFlags.InstantHit then
					--Check conditions for normal hurt or death (normal requires either >0 rings or a shield and its not an instakill)
					if (char.Rings > 0 or char.ShieldType ~= types.Shields.None) and char.HurtFlag ~= types.HurtFlags.InstantHit then
						local dir = utils:projectOntoPlane((char.Position - char.HurtPosition), phys.GravityDir * -1).Unit
						char.Velocity = (dir * 2) + (phys.GravityDir * -4)
						char.OnGround = false
						char.Rolling = false
						char.HurtState = types.HurtState.Knockback
						
						--If not using a shield, scatter rings, else, remove shield.
						if char.ShieldType == types.Shields.None then
							--Scatter Rings
							local speed = 2
							local gr = 1.61803
							for i=1, char.Rings do
								if i%16 == 0 then speed = speed + 2 end
								local dir = (CFrame.Angles(0, i * gr, 0) * CFrame.Angles(((i % 16) / 16) * (math.pi / 2), 0, 0)).lookVector
								local ring = script.Parent.Objects.Base.ScatteredRing:Clone()
								
								ring.Part.CFrame = CFrame.new(char.Position)
								ring:SetAttribute("Velocity", dir * speed)
								
								local pointer = Instance.new("ObjectValue")
								pointer.Value = ring
								pointer.Parent = game.ReplicatedStorage.SonicPlayer.ControllerModule.Objects
								
								if char.MovementMode == types.MovementModes.Locked then
									ring:SetAttribute("Velocity", utils:projectOntoPlane(dir * speed, char.MovementLockPlaneCF.LookVector))
								--	ring.Box.Velocity = utils:projectOntoPlane(ring.Box.Velocity,lock2DPlane.lookVector)
								end
								
								ring.Parent = workspace
							end
							
							char.Rings = 0
							utils:playSFX(char.Position, sfx.RingDrop)
						else
							char.ShieldType = types.Shields.None
							utils:playSFX(char.Position, sfx.Death)
						end
					else
						char.Velocity = phys.GravityDir * -1
						char.ShieldType = types.Shields.None
						char.SpeedTimer = 0
						char.InvincTimer = 0
						char.HurtState = types.HurtState.Dead
						char.Rings = 0
						utils:playSFX(char.Position, sfx.Death)
						char.Lives = char.Lives - 1
						controller.Died:Fire()
					end
				end
				char.HurtFlag = types.HurtFlags.None
			end
			if char.InvTimer > 0 then
				char.InvTimer = char.InvTimer - 1
			elseif char.InvTimer == 0 and char.HurtState == types.HurtState.Invulnerable then
				char.HurtState = types.HurtState.None
				char.InvTimer = -1
			end
			
			--Movement
			doMovement(globalDir, stepTime)
			
			--High Speed Fix. Casts a ray along velocity, and moves the player backwards if it hits something.
			--Used to prevent the player from phasing through objects at high speed. You could also use this
			--for general high speed collision detection if you wanted.
			if char.HurtState ~= types.HurtState.Dead then
				debugCast(char.Position, char.Velocity)
				local c = char.Velocity * (1 / consts.BaseFrameRate) * phys.Scale * 2
				local res, len = cast(char.Position, c.Unit, c.Magnitude)
				if res then
					char.Position = res.Position - (c / 2)
				end
			end
			
			--Camera
			updateCamera()
			if set.AutoUpdateCamera and char.HurtState ~= types.HurtState.Dead then
				workspace.CurrentCamera.CFrame = cam.CFrame
				workspace.CurrentCamera.Focus = CFrame.new(char.Position)
			end
			
			--Water
			char.WasInWater = char.InWater
			char.InWater = false	--Water is set by objects each frame, so we default to false first.
			char.CamInWater = false
			
			--Objects
			processObjects()
			
			--More Water
			if char.InWater then	--Player in water
				--Water Skipping (Water running is processed in the water object)
				char.TimeInWater = char.TimeInWater + 1
				if char.TimeInWater >= 30 * 60 then
					char.HurtFlag = types.HurtFlags.InstantHit
					sfx:Play(nil, sfx.Drown)
				end
				local skip = false
				if
					char.Rolling
					and utils:projectOntoPlane(char.Velocity, phys.GravityDir * -1).Magnitude > 6
					--and utils:projectOntoVector(char.Velocity, phys.GravityDir * -1).Magnitude < 4
				then
					--Check water height
					local par = RaycastParams.new()
					par.FilterType = Enum.RaycastFilterType.Whitelist
					par.FilterDescendantsInstances = game.CollectionService:GetTagged("TSE_WATER_CAST")
					local res = workspace:Raycast(
						char.Position + (phys.GravityDir * -1.5),
						phys.GravityDir * 1.5,
						par
					)
					if res then
						skip = true
						--char.Velocity = utils:reflect(char.Velocity, phys.GravityDir)
						if char.Velocity.Unit:Dot(phys.GravityDir.Unit) > 0 then
							char.Velocity = char.Velocity + (phys.GravityDir * -1 * phys.WaterSkipAccelDown)
						else
						--elseif utils:projectOntoVector(char.Velocity, phys.GravityDir * -1).Magnitude < 2 then
							char.Velocity = char.Velocity + (phys.GravityDir * -1 * phys.WaterSkipAccelUp)
						end
						char.Velocity = char.Velocity * phys.WaterSkipDrag
						if not char.WasInWater then
							sfx:Play(char.Position, sfx.Splash)
							--Create Splash Effect
							local splash = game.ReplicatedStorage.SonicPlayer.Objects.Base.Splash:Clone()
							splash.CFrame = CFrame.new(res.Position)
							splash.Parent = workspace
							utils:loadObject(splash)
						end
					end
				end
				if (not char.WasInWater) and not skip then	--Player just entered water (and is not skipping)
					sfx:Play(char.Position, sfx.Splash)
					--Create Splash Effect
					local splash = game.ReplicatedStorage.SonicPlayer.Objects.Base.Splash:Clone()
					splash.CFrame = CFrame.new(char.Position)
					splash.Parent = workspace
					utils:loadObject(splash)
					--Modify Velocity (A bit extra math to account for variable gravity)
					local hComp = utils:projectOntoPlane(char.Velocity, phys.GravityDir * -1)
					local vComp = utils:projectOntoVector(char.Velocity, phys.GravityDir * -1)
					char.Velocity = (hComp * 0.5) + (vComp * 0.25)
				end
			else	--Player not in water
				char.TimeInWater = 0
				if char.WasInWater then	--Player just exited water
					
				end
			end
		end
	end
	
	--Other Utilities
	controller.Enable = function()
		controller.Enabled = true
	end
	controller.Disable = function()
		controller.Enabled = false
	end
	
	return controller
end

return module
