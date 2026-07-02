local Main = {}
Main.__index = Main

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local GunSystemFolder = ReplicatedStorage.GunSystem 
local ConfigFolder = GunSystemFolder.Config 

local AnimationsFolder = script.Parent.Parent:WaitForChild("Animations") 
local AnimationsConfigFolder = script.Parent.Parent:WaitForChild("AnimationsConfig")

local Config = require(ConfigFolder.Config)
local AnimationsConifg = require(AnimationsConfigFolder.Animations)

local function IsInputMatched(Input, InputTable)
	for _, InputObject in pairs(InputTable) do
		if InputObject == Input then
			return true
		end
	end
	
	return false
end

function Main.New(Character: Model)
	local self = setmetatable({}, Main)
	
	self.Character = Character
	self.Humanoid = Character:WaitForChild("Humanoid")
	self.Humanoid.AutoJumpEnabled = false
	self.Humanoid.JumpHeight = 0
	
	self.Walking = false
	self.Running = false
	self.Crouching = false
	self.JumpCooldown = false
	
	self.IsPressingJump = false
	
	self.CurrentState = "Idle"
	
	self.Connections = {}
	self.Animations = {}
	self.ActiveAnimations = {}
	
	for _, Animation in pairs(AnimationsFolder:GetChildren()) do
		self.Animations[Animation.Name] = self.Humanoid:LoadAnimation(Animation)
	end
	
	return self
end

function Main:IsWalking()
	local Connection
	
	Connection = RunService.Stepped:Connect(function()
		local Velocity = self.Humanoid.MoveDirection.Magnitude
	
		if Velocity > 0 then
			if self.CurrentState == "Climbing" then
				if table.find(self.ActiveAnimations, self.Animations["Climb"]) then
					self.Animations["Climb"]:AdjustSpeed(AnimationsConifg.Climb.AdjustSpeed)
				end
				
				return
			end
			
			if self.CurrentState ~= "Idle" then
				return
			end
			
			self.Walking = true
			
			self:ChangeState("Move")
		else
			if self.CurrentState == "Climbing" then
				if table.find(self.ActiveAnimations, self.Animations["Climb"]) then
					self.Animations["Climb"]:AdjustSpeed(0)
				end
				
				return
			end
			
			if self.CurrentState ~= "Move" then
				return
			end
			
			self.Walking = false

			self:ChangeState("Idle")
		end
	end)
	
	table.insert(self.Connections, Connection)
end

function Main:HumanoidStates()
	local HumanoidStatesConnection
	
	HumanoidStatesConnection = self.Humanoid.StateChanged:Connect(function(OldState, State)
		if State == Enum.HumanoidStateType.Jumping then
			if table.find(self.ActiveAnimations, self.Animations["Jump"]) then
				self.Animations["Jump"]:Stop()
				
				table.remove(self.ActiveAnimations, table.find(self.ActiveAnimations, self.Animations["Jump"]))
			end
			
			self:ChangeState("Jumping")
		end
		
		if State == Enum.HumanoidStateType.Climbing then
			if table.find(self.ActiveAnimations, self.Animations["Climb"]) then
				self.Animations["Climb"]:Stop()
			end
			
			self:ChangeState("Climbing")
		end
		
		if OldState == Enum.HumanoidStateType.Climbing and State ~= Enum.HumanoidStateType.Climbing then
			self:ChangeState("Move")
		end
		
		if State == Enum.HumanoidStateType.Landed then
			self:ChangeState("Move")
		end
	end)
	
	table.insert(self.Connections, HumanoidStatesConnection)
end

function Main:InitiateState()
	for Index, Animation in pairs(self.ActiveAnimations) do
		if Animation.Name == "Jump" and self.Humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
			return
		end
		
		Animation:Stop()
	end
	
	table.clear(self.ActiveAnimations)
	
	local FinalAnimation: AnimationTrack
	
	if self.CurrentState == "Idle" then
		if self.Crouching then
			FinalAnimation = self.Animations["CrouchIdle"]
		else
			FinalAnimation = self.Animations["Idle"]
		end
	end
	
	if self.CurrentState == "Move" then
		if not self.Running and not self.Crouching then
			FinalAnimation = self.Animations["Walk"]

			self.Humanoid.WalkSpeed = Config.NormalWalkSpeed
		end
		
		if self.Running then
			FinalAnimation = self.Animations["Run"]
			
			self.Humanoid.WalkSpeed = Config.RunningWalkSpeed
		end
		
		if self.Crouching then
			FinalAnimation = self.Animations["CrouchWalk"]
			
			self.Humanoid.WalkSpeed = Config.CrouchingWalkSpeed
		end
	end
	
	if self.CurrentState == "Jumping" then
		FinalAnimation = self.Animations["Jump"]
	end
	
	if self.CurrentState == "Climbing" then
		FinalAnimation = self.Animations["Climb"]
		
		self.Humanoid.WalkSpeed = Config.NormalWalkSpeed
	end
	
	if self.CurrentState == "Fall" then
		FinalAnimation = self.Animations["Fall"]
	end
	
	FinalAnimation:Play()
	
	local Name = FinalAnimation.Name
	
	if AnimationsConifg[Name] and AnimationsConifg[Name]["AdjustSpeed"] then
		FinalAnimation:AdjustSpeed(AnimationsConifg[Name]["AdjustSpeed"])
	end
	
	table.insert(self.ActiveAnimations, FinalAnimation)
	
	if Name == "Jump" then
		local EndedConnection
		local StoppedConnection
		
		EndedConnection = FinalAnimation.Ended:Connect(function()
			table.remove(self.ActiveAnimations, table.find(self.ActiveAnimations, FinalAnimation))

			local HumanoidState = self.Humanoid:GetState()

			if HumanoidState == Enum.HumanoidStateType.Climbing then
				self:ChangeState("Climbing")
			else
				self:ChangeState("Move")
			end
			
			EndedConnection:Disconnect()
			
			if table.find(self.Connections, EndedConnection) then
				table.remove(self.Connections, table.find(self.Connections, EndedConnection))
			end
			
			if table.find(self.Connections, StoppedConnection) then
				table.remove(self.Connections, table.find(self.Connections, StoppedConnection))
			end
		end)
		
		StoppedConnection = FinalAnimation.Stopped:Connect(function()
			table.remove(self.ActiveAnimations, table.find(self.ActiveAnimations, FinalAnimation))
			
			local HumanoidState = self.Humanoid:GetState()

			if HumanoidState == Enum.HumanoidStateType.Climbing then
				self:ChangeState("Climbing")
			else
				self:ChangeState("Move")
			end
			
			EndedConnection:Disconnect()
			StoppedConnection:Disconnect()
			
			if table.find(self.Connections, EndedConnection) then
				table.remove(self.Connections, table.find(self.Connections, EndedConnection))
			end			
			
			if table.find(self.Connections, StoppedConnection) then
				table.remove(self.Connections, table.find(self.Connections, StoppedConnection))
			end			
		end)
		
		table.insert(self.Connections, StoppedConnection)
		table.insert(self.Connections, EndedConnection)
	end
end

function Main:ChangeState(NewState)
	self.CurrentState = NewState
	
	self:InitiateState()
end

function Main:JumpCheck()
	if self.JumpCooldown then return end

	self.JumpCooldown = true
	self.Humanoid.JumpHeight = Config.JumpHeight
	self.Humanoid.Jump = true
	
	task.wait(0.1)

	self.Humanoid.JumpHeight = 0

	task.delay(Config.JumpCooldown - 0.1, function()
		self.JumpCooldown = false
	end)
end

function Main:InputsConnections()
	local InputBeganConnection
	local InputEndedConnection
	
	InputBeganConnection = UserInputService.InputBegan:Connect(function(Input, Processed)
		if Processed then return end
		
		local CurrentState = self.Humanoid:GetState()
		
		if IsInputMatched(Input.KeyCode, Config.RunKeyCodes) and CurrentState ~= Enum.HumanoidStateType.Climbing then
			local Attribute = self.Character:GetAttribute("Aiming")
			if Attribute then return end
			
			self.Running = true
			
			self:ChangeState("Move")
		end
		
		if IsInputMatched(Input.KeyCode, Config.CrouchKeyCodes) and CurrentState ~= Enum.HumanoidStateType.Climbing then			
			self.Crouching = not self.Crouching
			
			self:ChangeState("Move")
		end
		
		if IsInputMatched(Input.KeyCode, Config.JumpKeyCodes) then
			if not self.JumpCooldown then
				self:JumpCheck()
			end 
		end
	end)
	
	InputEndedConnection = UserInputService.InputEnded:Connect(function(Input, Processed)
		if Processed then return end
		
		if IsInputMatched(Input.KeyCode, Config.RunKeyCodes) then
			self.Running = false
			
			local HumanoidState = self.Humanoid:GetState()
			if HumanoidState == Enum.HumanoidStateType.Climbing then
				return
			end
			
			self:ChangeState("Move")
		end
	end)
	
	table.insert(self.Connections, InputBeganConnection)
	table.insert(self.Connections, InputEndedConnection)
end

function Main:IsAiming()
	local AimConnection
	
	AimConnection = self.Character:GetAttributeChangedSignal("Aiming"):Connect(function()	
		local Attribute = self.Character:GetAttribute("Aiming")
		
		if Attribute then
			self.Running = false
			
			self:ChangeState("Move")
		end
	end)
	
	table.insert(self.Connections, AimConnection)
end

function Main:CleanUp()
	for _, Connection in self.Connections do
		if Connection then
			Connection:Disconnect()
		end
	end

	for _, Animation in self.ActiveAnimations do
		Animation:Stop()
	end
	
	table.clear(self.Connections)
	table.clear(self.ActiveAnimations)
end

return Main
