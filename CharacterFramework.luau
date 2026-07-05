-- DU: boserpro1234 RU: boserpro1234
--!strict

type MainVariables = {
	Character: Model,
	Humanoid: Humanoid,
	
	Walking: boolean,
	Running: boolean,
	Crouching: boolean,
	JumpCooldown: boolean,
	IsPressingJump: boolean,
	
	CurrentState: State,
	
	Connections: {RBXScriptConnection?},
	Animations: {[string]: AnimationTrack},
	ActiveAnimations: {AnimationTrack},
	
	MovementConnection: RBXScriptConnection?,
	HumanoidStatesConnection: RBXScriptConnection?,
	AimConnection: RBXScriptConnection?,
	InputBeganConnection: RBXScriptConnection?,
	InputEndedConnection: RBXScriptConnection?,
	
	AnimationEndedConnection: RBXScriptConnection?,
	AnimationStoppedConnection: RBXScriptConnection?,
}

type MainFunctions = {
	Initialize: (MainVariables) -> (),
	
	BindMovementLoop: (self: MainVariables) -> boolean,
	BindHumanoidStates: (self: MainVariables) -> (),
	BindAimState: (self: MainVariables) -> boolean,
	BindInputs: (self: MainVariables) -> (),
	InputsConnections: (self: MainVariables) -> (),
	ApplyStateAnimation: (self: MainVariables) -> (),
	JumpAnimationEnded: (self: MainVariables, Animation: AnimationTrack) -> (),
	TryJump: (MainVariables) -> (),
	ClearActiveAnimations: (MainVariables) -> (),
	ChangeState: (self: MainVariables, State: State) -> (),
	CleanUp: (self: MainVariables) -> (),
}

export type Main = MainVariables & MainFunctions
export type State = "Idle" | "Move" | "Jumping" | "Climbing" | "Fall"

local Main = {}
Main.__index = Main :: Main

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Project = script.Parent.Parent

local GunSystemFolder = ReplicatedStorage.GunSystem 
local ConfigFolder 	= GunSystemFolder.Config 

local AnimationsFolder = Project:WaitForChild("Animations") 
local AnimationsConfigFolder = Project:WaitForChild("AnimationsConfig")

local Config = require(ConfigFolder.Config)
local AnimationsConfigModule  = require(AnimationsConfigFolder.Animations) :: AnimationConfig

type AnimationConfig = typeof(AnimationsConfigModule)
type StateResolver = (self: Main) -> (AnimationTrack, number?)

local StateAnimations: {[State]: StateResolver} = {
	Idle = function(self: Main)
		-- If the player is idle AND croaching we want to play the CrouchingIdle, else
		-- play the normal Idle animation.
		if self.Crouching then
			return self.Animations["CrouchIdle"], nil
		end

		return self.Animations["Idle"], nil
	end,

	Move = function(self: Main)
		-- If the player is moving AND running we want to play the Running animation
		-- If they are moving AND crouching, we want to play the CrouchWalk animation
		-- If they're simply moving we play the Walk one
		if self.Running then
			return self.Animations["Run"], Config.RunningWalkSpeed
		elseif self.Crouching then
			return self.Animations["CrouchWalk"], Config.CrouchingWalkSpeed
		else
			return self.Animations["Walk"], Config.NormalWalkSpeed
		end
	end,

	Jumping = function(self: Main)
		return self.Animations["Jump"], nil
	end,

	Climbing = function(self: Main)
		return self.Animations["Climb"], Config.NormalWalkSpeed
	end,

	Fall = function(self: Main)
		return self.Animations["Fall"], nil
	end,
}

local function IsInputMatched(Input: Enum.KeyCode, InputTable: {Enum.KeyCode})
	for _, InputObject in InputTable do
		-- We want to see if the Input given matches any of the inputs in the given table
		if InputObject == Input then
			return true
		end
	end
	
	return false
end

function Main.New(Character: Model): Main
	local self: MainVariables = {
		Character = Character,	
		Humanoid = Character:WaitForChild("Humanoid") :: Humanoid,
	
		Walking = false,
		Running = false,
		Crouching = false,
		JumpCooldown = false,
		
		IsPressingJump = false,
		CurrentState = "Idle", 
		
		Connections = {},
		Animations = {},
		ActiveAnimations = {},
		
		MovementConnection = nil, 
		HumanoidStatesConnection = nil,
		AimConnection = nil,
		InputBeganConnection = nil,
		InputEndedConnection = nil,
		
		AnimationEndedConnection = nil,
		AnimationStoppedConnection = nil,
	}
	
	return setmetatable(self, Main) :: Main
end

function Main.Initialize(self: Main)
	local Animator = self.Humanoid:WaitForChild("Animator") :: Animator
	
	-- We want to load all the animations so we don't have to later
	for _, Animation: Animation in AnimationsFolder:GetChildren() do
		self.Animations[Animation.Name] = Animator:LoadAnimation(Animation)
	end
	
	-- We don't want the AutoJump as we have a jump cooldown on our own
	-- We also want to set the JumpHeight to 0 so the player can't jump on their own
	self.Humanoid.AutoJumpEnabled = false
	self.Humanoid.JumpHeight = 0
	
	self:BindMovementLoop()
	self:BindHumanoidStates()
	self:BindAimState()
	self:BindInputs()
end

function Main.BindMovementLoop(self: Main)	
	-- We want to make sure we don't connect to this event twice
	assert(not self.MovementConnection, "BindMovementLoop already called")
	
	self.MovementConnection = RunService.Stepped:Connect(function()
		local Velocity = self.Humanoid.MoveDirection.Magnitude
	
		-- Velocity tells us if the player is moving or not, if it's not we want to
		-- change the state and play the correct animation
		if Velocity <= 0 then
			-- If the player was climbing before the state was set to idle
			-- we want to set the speed of the climbing animation to 0
			if self.CurrentState == "Climbing" then
				-- First we want to see if the animation is playing
				if not table.find(self.ActiveAnimations, self.Animations["Climb"]) then end

				self.Animations["Climb"]:AdjustSpeed(0)

				return
			end

			-- If the state before was Move, we want to play the idle animation
			-- Because we don't handle all of the states yet
			if self.CurrentState ~= "Move" then
				return
			end

			self.Walking = false

			self:ChangeState("Idle")
			
			return
		end
	
		-- If the player is moving AND climbing we want to adjust the speed of it
		-- to the speed of the player, in case they stopped and it was set to 0
		if self.CurrentState == "Climbing" then
			if not table.find(self.ActiveAnimations, self.Animations["Climb"]) then return end
		
			self.Animations["Climb"]:AdjustSpeed(AnimationsConfigModule.Climb.AdjustSpeed)

			return
		end
	
		-- Same thing as in the check inside Velocity <= 0, since we don't handle all of 
		-- the states yet, we want to play the Move animation only if the previous one was Idle
		if self.CurrentState ~= "Idle" then
			return
		end
		
		self.Walking = true
		self:ChangeState("Move")
	end)
	
	table.insert(self.Connections, self.MovementConnection)
end

function Main.BindHumanoidStates(self: Main)
	-- We want to make sure we don't connect to this event twice
	assert(not self.HumanoidStatesConnection, "BindMovementLoop already called")
	
	self.HumanoidStatesConnection = self.Humanoid.StateChanged:Connect(function(OldState, State)
		-- State checks are here to see what the player is currently doing
		
		if State == Enum.HumanoidStateType.Jumping then
			-- If the player did another jump before the previous Jump animation ended
			-- We want to stop the animation and play it again
			if table.find(self.ActiveAnimations, self.Animations["Jump"]) then
				self.Animations["Jump"]:Stop()
				
				table.remove(self.ActiveAnimations, table.find(self.ActiveAnimations, self.Animations["Jump"]))
			end
			
			self:ChangeState("Jumping")
		end
		
		if State == Enum.HumanoidStateType.Climbing then
			self:ChangeState("Climbing")
		end
		
		-- This checks whether the player stopped climbing, so if they were climbing before and stopped
		-- We want to change the state to move so we're not stuck in the climbing anim
		if OldState == Enum.HumanoidStateType.Climbing and State ~= Enum.HumanoidStateType.Climbing then
			self:ChangeState("Move")
		end
		
		if State == Enum.HumanoidStateType.Landed then
			self:ChangeState("Move")
		end
	end)
	
	table.insert(self.Connections, self.HumanoidStatesConnection)
end

function Main.BindInputs(self: Main)
	assert(not self.InputBeganConnection, "BindInputs already called")
	
	self.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input, Processed)
		-- We don't want to register inputs that are from textboxes, chat etc.
		if Processed then return end

		local CurrentState = self.Humanoid:GetState()

		-- We want to see if the player input matches any of the keybinds we have		
		if IsInputMatched(Input.KeyCode, Config.JumpKeyCodes) then
			if not self.JumpCooldown then
				self:TryJump()
			end 
		end
		
		-- Obviously, climbing is a high priority, we don't want to enable Run
		-- When the player is actively climbing
		if CurrentState == Enum.HumanoidStateType.Climbing then return end
		
		if IsInputMatched(Input.KeyCode, Config.RunKeyCodes) then
			-- What's important is we cannot let the player run when they're aiming a weapon
			local Attribute = self.Character:GetAttribute("Aiming")
			if Attribute then return end

			self.Running = true

			self:ChangeState("Move")
		end

		if IsInputMatched(Input.KeyCode, Config.CrouchKeyCodes) then			
			self.Crouching = not self.Crouching

			self:ChangeState("Move")
		end
	end)

	self.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input, Processed)
		-- Same as before, we don't want to register gameproccesed events
		if Processed then return end

		-- As you can hold shift to run we also need to check whether this stopped
		-- So we can change the state to Move
		if IsInputMatched(Input.KeyCode, Config.RunKeyCodes) then
			self.Running = false

			local HumanoidState = self.Humanoid:GetState()
			-- When the player runs into something they can climb we don't want to play the 
			-- Move animation as climbing has a higher priority
			if HumanoidState == Enum.HumanoidStateType.Climbing then
				return
			end

			self:ChangeState("Move")
		end
	end)

	table.insert(self.Connections, self.InputBeganConnection)
	table.insert(self.Connections, self.InputEndedConnection)
end

function Main.BindAimState(self: Main)
	-- We don't want to register the same event twice
	assert(not self.AimConnection, "AimConnection already called")
	
	self.AimConnection = self.Character:GetAttributeChangedSignal("Aiming"):Connect(function()	
		local Attribute = self.Character:GetAttribute("Aiming")

		-- Because our movmement system was made for the Gun System, we don't want to let the user run
		-- When the aim state is enabled
		if Attribute then
			self.Running = false

			self:ChangeState("Move")
		end
	end)

	table.insert(self.Connections, self.AimConnection)
end

function Main.ApplyStateAnimation(self: Main)
	-- As we're applying a new state, we need to clear the previous animations
	self:ClearActiveAnimations()
	
	local Resolver = StateAnimations[self.CurrentState]
	local FinalAnimation, WalkSpeed = Resolver(self)
	local Name = FinalAnimation.Name

	-- Some animations have a WalkSpeed value change (e.g. Run or Crouch)
	-- Therefore we have to check if the animation has a custom WalkSpeed and if so apply it
	if WalkSpeed then
		self.Humanoid.WalkSpeed = WalkSpeed
	end

	FinalAnimation:Play()
	
	-- Some animations have a special AdjustSpeed value, this is to make the animation play at a different speed
	-- So it maches the pace
	if AnimationsConfigModule[Name] and AnimationsConfigModule[Name]["AdjustSpeed"] then
		FinalAnimation:AdjustSpeed(AnimationsConfigModule[Name]["AdjustSpeed"])
	end
	
	table.insert(self.ActiveAnimations, FinalAnimation)
	
	-- As the jump animation is a special kind that needs to be played fully without stopping to look good
	-- We need to register two connections to listen to the end of the animation 
	-- And once it ends , we need to do a clean up
	if Name == "Jump" then
		self.AnimationEndedConnection = FinalAnimation.Ended:Connect(function()
			self:JumpAnimationEnded(FinalAnimation)
		end)
		
		self.AnimationStoppedConnection = FinalAnimation.Stopped:Connect(function()
			self:JumpAnimationEnded(FinalAnimation)		
		end)
		
		table.insert(self.Connections, self.AnimationEndedConnection)
		table.insert(self.Connections, self.AnimationStoppedConnection)
	end
end

function Main.JumpAnimationEnded(self: Main, AnimationTrack: AnimationTrack) 
	-- Once it ended we want to remove the animation from active animations as we end it manually
	table.remove(self.ActiveAnimations, table.find(self.ActiveAnimations, AnimationTrack))

	local HumanoidState = self.Humanoid:GetState()
	local FoundEndedConnection = table.find(self.Connections, self.AnimationEndedConnection)
	local FoundStoppedConnection = table.find(self.Connections, self.AnimationStoppedConnection)

	-- We want to know if after the animation ended, the humanoid is in a normal Move or Climbing state
	if HumanoidState == Enum.HumanoidStateType.Climbing then
		self:ChangeState("Climbing")
	else
		self:ChangeState("Move")
	end

	-- We want to check whether those connections are still there, if so we want to disconnect them
	if self.AnimationEndedConnection then
		self.AnimationEndedConnection:Disconnect()
	end

	if self.AnimationStoppedConnection then
		self.AnimationStoppedConnection:Disconnect()
	end

	-- We also want to remove the connections from the table
	if FoundEndedConnection then
		table.remove(self.Connections, FoundEndedConnection)
	end

	if FoundStoppedConnection then
		table.remove(self.Connections, FoundStoppedConnection)
	end
end

function Main.ClearActiveAnimations(self: Main)
	for Index, Animation in pairs(self.ActiveAnimations) do
		-- We want the Jump animation to play fully unless we're climbing
		-- Thanks to that we won't be seen climbing during the Jump animation
		if Animation.Name == "Jump" and self.Humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
			return
		end

		Animation:Stop()
	end

	table.clear(self.ActiveAnimations)
end

function Main.ChangeState(self: Main, NewState: State)
	-- We want to register a new state
	self.CurrentState = NewState
	
	self:ApplyStateAnimation()
end

function Main.TryJump(self: Main)
	-- Obviously, we don't want to let the player jump when there's a cooldown
	if self.JumpCooldown then return end

	self.JumpCooldown = true
	self.Humanoid.JumpHeight = Config.JumpHeight
	self.Humanoid.Jump = true
	
	-- We want to wait a bit for the jump impulse to be applied
	task.wait(Config.JumpImpulseDuration)

	self.Humanoid.JumpHeight = 0

	-- We want to wait a bit more for the cooldown to be removed, we also have to acccount the impulseduration so the jump cooldown is not actually affected by it
	task.delay(Config.JumpCooldown - Config.JumpImpulseDuration, function()
		self.JumpCooldown = false
	end)
end

function Main.CleanUp(self: Main)
	-- A cleanup faction
	
	for _, Connection in self.Connections do
		-- We want to see if the connection is still there and then disconnect to prevent errors
		if Connection then
			Connection:Disconnect()
		end
	end

	for _, Animation in self.ActiveAnimations do
		Animation:Stop()
	end
	
	-- We want to clear the tables
	table.clear(self.Connections)
	table.clear(self.ActiveAnimations)
end

return Main
