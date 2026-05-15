-- DU: boserpro1234 RU: boserpro1234

type Main = {
	-- Parts
	Head:             BasePart,
	Humanoid:         Humanoid,
	GunParts:         Folder,
	Tool:             Tool,
	Sounds:           Folder,
	Ammo:             NumberValue,
	OriginalCFrame:   CFrame,
	Config:           {[any]: any},
	ViewModel:        any, 

	-- State
	CanShoot:         boolean,
	NormalPosition:   boolean,
	Shooting:         boolean,
	Aiming:           boolean,
	Reloading:        boolean,
	IsInViewModel:    boolean,
	ShootingVersion:  number,
	FullAuto:         boolean,
	CanChangeModes:   boolean,
	CurrentSensitivity: number,
	LastZoom:         number?,
	UI:               Frame,
	Connections:      {RBXScriptConnection},

	-- Animations
	HandleAnimation:  AnimationTrack,
	ShootAnimation:   AnimationTrack,
	AimAnimation:     AnimationTrack,
}

type MainImplementation = Main & {
	__index: MainImplementation,
	
	New:              (Tool: Tool) -> Main?,
	Equip:            (self: Main) -> (),
	UnEquip:          (self: Main) -> (),
	Aim:              (self: Main, Boolean: boolean) -> (),
	EnterAim:         (self: Main) -> (),
	ExitAim:          (self: Main) -> (),
	EnterNormalAim:   (self: Main) -> (),
	ExitNormalAim:    (self: Main) -> (),
	EnterSniperAim:   (self: Main) -> (),
	ExitSniperAim:    (self: Main) -> (),
	EnableViewModel:  (self: Main) -> (),
	DisableViewModel: (self: Main) -> (),
	Reload:           (self: Main) -> (),
	StartShooting:    (self: Main) -> (),
	Shoot:            (self: Main) -> (),
	FireBullet:       (self: Main) -> {any}?,
	FireRaycast:      (self: Main) -> {any},
	HandleUtilities:  (self: Main) -> (),
	ChangeMode:       (self: Main) -> (),
	OnInputBegan:     (self: Main, Input: InputObject, Processed: boolean) -> (),
	OnInputEnded:     (self: Main, Input: InputObject, Processed: boolean) -> (),
}

local Main = {} :: MainImplementation
Main.__index = Main

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService 	= game:GetService("UserInputService")
local Players 			= game:GetService("Players")
local TweenService 		= game:GetService("TweenService")

local FieldOfViewInfo 	= TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut) :: TweenInfo

-- // Player
local Player			= Players.LocalPlayer :: Player

local AimSensitivity	= Player:WaitForChild("AimSensitivity") :: NumberValue
local SniperSensitivity = Player:WaitForChild("SniperSensitivity") :: NumberValue

local CurrentCamera = workspace.CurrentCamera :: Camera

local Remotes = ReplicatedStorage.GunSystem.Remotes

-- // Modules
local UtilitiesFolder = script.Parent.Utilities

local MouseFramework	  = require(UtilitiesFolder.MouseFramework)
local Utilities 		  = require(UtilitiesFolder.Utilities)
local ShiftlockEnabler 	  = require(UtilitiesFolder.ShiftlockEnabler)
local CharacterFramework  = require(UtilitiesFolder.CharacterFramework)
local Config			  = require(ReplicatedStorage.GunSystem.Config.Config)
local ViewModelController = require(UtilitiesFolder.ViewModelController)
local VisualsHandler 	  = require(UtilitiesFolder.VisualsHandler)

-- // Essentials
local FirerateCooldowns = {} :: {[string]: number}

-- // Input action logic for PC
-- Because the gun system is still being worked on, some parts outside of PC devices may not work
-- so now those are exclusively for PCs
local InputActions = {
	[Enum.KeyCode.R] = function(self: Main) self:Reload() end,
	[Enum.KeyCode.L] = function(self: Main) Utilities.Laser(self.GunParts.Barrel, true) end,
	[Enum.KeyCode.F] = function(self: Main) Utilities.Flashlight(self.GunParts.Barrel, true) end,
	[Enum.KeyCode.V] = function(self: Main) self:ChangeMode() end
}

-- // Functions

-- [[ Check if the key pressed matches a key inside the Keylist which has keys for most of the gaming devices ]]
local function IsInputMatched(Input: InputObject, KeyList: {EnumItem}): boolean
	for _, Key in KeyList do
		if Input.KeyCode == Key or Input.UserInputType == Key then
			return true
		end
	end
	
	return false
end

-- [[ Initializer ]]
function Main.New(Tool: Tool)
	local self = setmetatable({}, Main) :: Main
	local GetConfig = Utilities.GetConfig(Tool.Name)
	if GetConfig == nil then return end
	
	if not Player.Character then return end
	
	self.Head 			= Player.Character:FindFirstChild("Head") :: BasePart
	if not self.Head then return end
	
	self.Humanoid 		= Player.Character:FindFirstChild("Humanoid") :: Humanoid
	if not self.Humanoid then return end
	
	-- Gun Parts
	
	local Animations 	= Tool:FindFirstChild("Animations") :: Folder
	local Sounds 		= Tool:FindFirstChild("Sounds") :: Folder
	local GunParts 		= Tool:FindFirstChild("GunParts") :: Folder

	self.GunParts 		= GunParts :: Folder
	self.Tool 			= Tool :: Tool
	self.Sounds			= Sounds  :: Folder
	
	self.Ammo 			= Tool:WaitForChild("AmmoValue") :: NumberValue
	
	self.OriginalCFrame = Tool.Grip :: CFrame
	
	self.Config 		= GetConfig :: {any}
	
	if self.Config.ViewModel then
		self.ViewModel 	= ViewModelController.New(self.Config, self.Tool.Name)
	end

	-- Essential booleans
	self.CanShoot 		= true  :: boolean
	self.NormalPosition = false :: boolean
	self.Shooting 		= false :: boolean
	self.Aiming 		= false :: boolean
	self.Reloading 		= false :: boolean
	self.IsInViewModel 	= false :: boolean
	
	self.ShootingVersion = 0 :: number
	
	self.FullAuto 		= GetConfig["FullAuto"] :: boolean
	self.CanChangeModes = GetConfig["CanModeChange"] :: boolean
	
	self.CurrentSensitivity = UserInputService.MouseDeltaSensitivity :: number
	
	self.UI 			= Player.PlayerGui.GunUIs:WaitForChild('Frame') :: Frame
	
	self.Connections 	= {} :: {RBXScriptConnection}
	
	self.HandleAnimation = self.Humanoid.Animator:LoadAnimation(Animations.HandleAnimation) :: AnimationTrack
	self.ShootAnimation  = self.Humanoid.Animator:LoadAnimation(Animations.ShootAnimation) :: AnimationTrack
	self.AimAnimation 	 = self.Humanoid.Animator:LoadAnimation(Animations.AimAnimation) :: AnimationTrack
	
	return self
end

-- // Input handling
function Main:OnInputBegan(Input: InputObject, Processed: boolean)
	if Processed then return end

	if IsInputMatched(Input, Config.AimKeyCodes) then return self:Aim(true) end

	if Input.KeyCode == Enum.KeyCode.T and not self.NormalPosition then
		ShiftlockEnabler.SwitchSide()
	end
	
	if IsInputMatched(Input, Config.ShootKeyCodes) then return self:StartShooting() end
	if IsInputMatched(Input, Config.ReloadKeyCodes) then return self:Reload() end

	local Action = InputActions[Input.KeyCode] :: any
	if Action then return Action(self) end
end

function Main:OnInputEnded(Input: InputObject, Processed: boolean)
	if Processed then return end

	if Input.UserInputType == Enum.UserInputType.MouseButton2 then
		return self:Aim(false)
	end

	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		self.Shooting = false
	end
end

-- // Main shooting function
function Main:StartShooting()
	if self.NormalPosition then return end
	if self.Shooting then return end

	local LastFired 	= FirerateCooldowns[self.Tool.Name] or 0 :: number

	-- Check in order to fix a bug where you could spam weapons and shoot
	-- this part checks the last fired bullet and puts it inside a table with tick()
	-- that then later gets checked in the if statement to fix the spam bug.
	if tick() - LastFired < self.Config.Firerate then return end
	FirerateCooldowns[self.Tool.Name] = tick()

	self.Shooting = true
	self.ShootingVersion += 1
	
	local CurrentVersion = self.ShootingVersion

	while self.Shooting and self.CanShoot and not self.NormalPosition and self.Humanoid.Health > 0 do
		if self.ShootingVersion ~= CurrentVersion then
			break
		end
		
		if self.Ammo.Value > 0 then
			Remotes.SoundHandler:FireServer(self.Sounds.Sound)
			self:Shoot()
		else
			Remotes.SoundHandler:FireServer(self.Sounds.Out)
		end

		if not self.FullAuto then
			self.Shooting = false
		end

		task.wait(self.Config.Firerate)
	end
end

-- [[ Equip which is the main function ]]
function Main:Equip()
	-- Utilities as well as CharacterFramework to move arms & head with the mouse position
	CharacterFramework.Setup()
	Utilities.EnableUI(true, self.Tool.Name)

	-- If the gun has a sniper sight then the ZoomDistance is different
	if self.Config.SniperSight or self.Config.ViewModel then
		Player.CameraMinZoomDistance = 0
	elseif not self.Config.SniperSight and not self.Config.ViewModel then
		Player.CameraMinZoomDistance = Config.MaxZoomOut
	end

	self.HandleAnimation:Play()
	self.NormalPosition = true
	
	self.UI.Ammo.Text = self.Ammo.Value
	self.UI.GunName.Text = self.Tool.Name
	self.UI.Mode.Text = self.FullAuto and "AUTO" or "SEMI"

	self.Tool.Grip = self.OriginalCFrame
	self.Sounds.EquippedSound:Play()
	
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	
	self.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input, G)
		self:OnInputBegan(Input, G)
	end)
	
	self.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input, G)
		self:OnInputEnded(Input, G)
	end)
	
	self.AmmoChanged = self.Ammo:GetPropertyChangedSignal("Value"):Connect(function()
		if self.Reloading then return end
		
		self.UI.Ammo.Text = self.Ammo.Value
	end)
	
	local PartsConnections 	= {} :: {RBXScriptConnection}
	
	for _, Part in Player.Character:GetChildren() do
		if Part.Name:find("Hand") or Part.Name:find("Arm") then
			local Connection = Part.Changed:Connect(function()
				if self.IsInViewModel then return end
				
				Part.LocalTransparencyModifier = 0
			end)
			
			table.insert(PartsConnections, Connection)
		end
	end
	
	self.ZoomChanged = self.Head:GetPropertyChangedSignal('LocalTransparencyModifier'):Connect(function()
		if not self.Config.ViewModel then return end
		
		local GetLastZoom = nil :: number?
		if not self.LastZoom then
			GetLastZoom = 0
		else
			GetLastZoom = self.LastZoom
		end
		
		self.LastZoom = self.Head.LocalTransparencyModifier

		
		if GetLastZoom <= self.LastZoom and self.LastZoom ~= 0 then
			if self.IsInViewModel then return end
			
			self:EnableViewModel()
		else
			if not self.IsInViewModel then return end
			
			self:DisableViewModel()
		end
	end)
	
	self.CharacterRemoved = Player.CharacterRemoving:Connect(function()
		self:UnEquip()
	end)
	
	self.GunRemoved = self.Tool.AncestryChanged:Connect(function(_, Parent: Instance?)
		if not Parent then
			self:UnEquip()
		end
	end)

	self.HumanoidStateChanged = self.Humanoid.StateChanged:Connect(function(_, State: Enum.HumanoidStateType)
		if not self.Aiming then return end
		
		if State == Enum.HumanoidStateType.Swimming or State == Enum.HumanoidStateType.Climbing then
			self:ExitAim()
		end
	end)
	
	self.Died = self.Humanoid.Died:Connect(function()
		self:UnEquip()
	end)
	
	self.Connections = {
		self.InputBeganConnection,
		self.InputEndedConnection,
		self.HumanoidStateChanged,
		self.AmmoChanged,
		self.ZoomChanged,
		self.CharacterRemoved,
		self.GunRemoved,
		self.Died,	
	}
	
	for _, Connection: RBXScriptConnection in PartsConnections do
		table.insert(self.Connections, Connection)
	end
end

-- [[ Aim Function that makes the gun be able to shoot ]]
function Main:EnterAim()
	local HumanoidState = self.Humanoid:GetState()
	if HumanoidState == Enum.HumanoidStateType.Swimming or HumanoidState == Enum.HumanoidStateType.Climbing then return end

	Player.Character:SetAttribute("Aiming", true)

	self.NormalPosition = false
	self.Aiming = true

	if not self.Config.SniperSight then
		self:EnterNormalAim()
		Utilities.TurnScreenUI(true)
	else
		self:EnterSniperAim()
	end
	
	if self.Head.LocalTransparencyModifier ~= 0 then
		self:EnableViewModel()
	end
	
	self.HandleAnimation:Stop()
	self.AimAnimation:Play()
	
	self.Tool.Grip = self.Config.AimCFrame
end

function Main:DisableViewModel()
	if not self.Config.ViewModel then return end
	self.IsInViewModel = false

	if self.Aiming then
		ShiftlockEnabler.SetShiftLock(true)
		MouseFramework.ChangeIcon(Config['AimMouseIcon'], false)
	end
	
	Player.CameraMinZoomDistance = Config.MaxZoomOut
	
	-- The task.wait() is here to evade a bug where the camera would glitch out while in viewmodel making you 
	-- see "over the shoulder" while being nearly fully zoomed
	task.wait()
	
	Player.CameraMinZoomDistance = Config.MinZoomIn
	
	self.ViewModel:Disable()	
end

function Main:EnableViewModel()	
	if not self.Aiming then return end
	if not self.Config.ViewModel then return end
	
	Player.CameraMode = Enum.CameraMode.LockFirstPerson
	Player.CameraMode = Enum.CameraMode.Classic
	
	self.IsInViewModel = true
	ShiftlockEnabler.SetShiftLock(false)
	
	self.ViewModel:Enable()	
	
	if CurrentCamera:FindFirstChild(self.Tool.Name):FindFirstChild("AimPart") then
		MouseFramework.StopConnections()
	end
end

function Main:ExitAim()
	-- Exits the aim
	
	if self.IsInViewModel then
		self:DisableViewModel()
	end
	
	-- sets the normalposition to true so the other parts of the code know what mode it is
	self.NormalPosition = true
	Player.CameraMaxZoomDistance = Config["MaxZoomDistance"]
	UserInputService.MouseDeltaSensitivity = self.CurrentSensitivity

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	self.Aiming = false

	Utilities.TurnScreenUI(false)

	Player.Character:SetAttribute("Aiming", false)

	if not self.Config.SniperSight then
		self:ExitNormalAim()
	else
		self:ExitSniperAim()
	end

	self.HandleAnimation:Play()
	self.AimAnimation:Stop()

	if self.GunParts then
		Utilities.Laser(self.GunParts.Barrel, false)
		Utilities.Flashlight(self.GunParts.Barrel, false)
	end

	if self.Tool then
		self.Tool.Grip = self.OriginalCFrame
	end
end

function Main:EnterNormalAim()
	-- Enables the normal aim mode
	
	Player.CameraMaxZoomDistance = Config.MaxZoomOut
	UserInputService.MouseDeltaSensitivity = AimSensitivity.Value
	
	TweenService:Create(CurrentCamera, FieldOfViewInfo, {FieldOfView = Config.NormalAimFieldOfView}):Play()
	
	ShiftlockEnabler.SetShiftLock(true)
	MouseFramework.ChangeIcon(Config["AimMouseIcon"], false)
	CharacterFramework.Framework(true)
end

function Main:ExitNormalAim()
	-- Disables the normal "Over the Shoulder" camera mode
	
	TweenService:Create(CurrentCamera, FieldOfViewInfo, {FieldOfView = Config.FieldOfViewCurrent}):Play()
	
	MouseFramework.StopConnections()
	ShiftlockEnabler.SetShiftLock(false)
	CharacterFramework.Framework(false)
end

function Main:EnterSniperAim()
	self.UI.Parent.ImageLabel.Visible = true
	Player.CameraMaxZoomDistance = 0
	CurrentCamera.FieldOfView = Config["SniperFieldOfView"]

	task.spawn(function()
		Utilities.CameraSightRecoil(true)
	end)

	UserInputService.MouseDeltaSensitivity = SniperSensitivity.Value

	-- Turns off the gun visibilty due to the fact that the sniper is zoomed in
	for _, Part in self.Tool:GetDescendants() do
		if Part:IsA("BasePart") then
			Part.Transparency = 1
		end
	end
end

function Main:ExitSniperAim()
	if not self.UI then
		self:UnEquip()
	else
		self.UI.Parent.ImageLabel.Visible = false
	end
	
	-- Sensitivities
	CurrentCamera.FieldOfView = Config.FieldOfViewCurrent
	
	Utilities.CameraSightRecoil(false)

	if self.Tool then
		for _, Part in self.Tool:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.Transparency = 0
			end
		end
	end
end

function Main:Aim(Boolean: boolean)
	if Boolean and self.CanShoot then
		self:EnterAim()
	else
		self:ExitAim()
	end
end

-- [[UnEquip which disables the whole gun and does a cleanup ]]
function Main:UnEquip()
	-- Disables UI & cleans up all the things
	Utilities.EnableUI(false, self.Tool.Name)
	
	self:Aim(false)
	
	if self.IsInViewModel then
		self:DisableViewModel()
	end
	
	if self.UI then
		self.UI.Parent.ImageLabel.Visible = false
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	Player.CameraMinZoomDistance = 0

	-- Disables all the connections
	for _, Connection: RBXScriptConnection in self.Connections do
		if Connection then
			Connection:Disconnect()
		end
	end
	
	self.HandleAnimation:Stop()
	self.AimAnimation:Stop()
end

-- [[ Main Reload ]]
function Main:Reload()
	if not self.CanShoot then return end
	if self.Tool.AmmoValue.Value == self.Config.Ammo then return end
	
	-- Stop animations and plays handle anim 
	self.AimAnimation:Stop()
	self.HandleAnimation:Play()
	
	-- Fires the reload sound as it's vital for combat so the other users can know
	-- when the player is reloading
	Remotes.SoundHandler:FireServer(self.Sounds, "Reload", self.Config.ReloadTime)
	
	self:Aim(false)
	self.CanShoot = false
	self.Reloading = true
	
	Remotes.ReloadRemote:FireServer()
	self.UI.Ammo.Text = "..."
	
	task.wait(self.Config["ReloadTime"])
	
	self.Reloading = false
	self.CanShoot = true
	
	self.UI.Ammo.Text = self.Tool.AmmoValue.Value
end

-- [[ Main Shoot Function ]]
function Main:FireRaycast()
	
	-- Does a raycast and returns the raycast properties for FireBullet function
	-- Raycasts are done via an external community made module
	
	local Result 		  = Utilities.MouseRaycast(self.Tool, self.Config.Spread)
	local RaycastInstance = Result.Instance :: Instance
	local Position 		  = Result.Position :: Vector3
	local Normal 		  = Result.Normal :: Vector3
	local Origin 		  = Result.Origin :: Vector3
	local Direction		  = Result.Direction :: Vector3
	
	-- Checks if the raycast hit a character and if it's a player or not
	if not RaycastInstance then
		return Result
	end
	
	local Parent = RaycastInstance:FindFirstAncestorOfClass("Model") :: Model?
	if not Parent then
		return Result
	end
	
	local Humanoid = Parent:FindFirstChild("Humanoid") :: Humanoid?
	if not Humanoid then
		return Result
	end
	
	task.defer(function()
		Utilities.HitCounter()
	end)
	
	return Result
end

function Main:FireBullet()
	if self.Config.GrenadeLauncher then
		Remotes.GrenadeLauncherRemote:FireServer(Utilities.GetMouseHit())
		return
	end
	
	-- Creates a bullet and fires it
	
	-- The Raycast function
	local Result		  = self:FireRaycast()
	local RaycastInstance = Result.Instance :: Instance
	local Position 		  = Result.Position :: Vector3
	local Normal 		  = Result.Normal :: Vector3
	local Origin 		  = Result.Origin :: Vector3
	local Direction 	  = Result.Direction :: Vector3
	
	-- This part basically checks if the raycast hit something and then fires the bullet to that target
	-- if it's not then it does it the Config range to the direction of the mouse so the bullet will still be created
	-- Purely for visuals
	local EndPosition = RaycastInstance and Position or Origin + Direction.Unit * Config.RaycastRange :: Vector3
	
	local ServerParameters = {
		Origin = Origin,
		Direction = Direction,
		HitPosition = EndPosition,
		TimeStamp = tick(),
	}
	
	task.spawn(function()
		if self.IsInViewModel then
			Utilities.CreateBullet(CurrentCamera:FindFirstChildWhichIsA("Model")[self.Tool.Name].GunParts.Barrel.Position, EndPosition)
		else
			Utilities.CreateBullet(self.GunParts.Barrel.Position, EndPosition)
		end
	end)
	
	return ServerParameters
end

function Main:HandleUtilities()
	-- Applies recoil and plays the shoot animation before the bullet is fired
	
	Utilities.Recoil(self.Tool.Name)

	self.ShootAnimation:Play()
end

function Main:Shoot()
	-- Determines barrel source based on viewmodel state then collects raycast results and sends them to the server
	
	self:HandleUtilities()
		
	local Rounds = self.Config.Rounds or 1 :: number
	
	if self.IsInViewModel then
		local ViewModel = CurrentCamera:FindFirstChildWhichIsA("Model") :: Model?
		if not ViewModel then return end
		
		local Gun = ViewModel:FindFirstChildWhichIsA("Model") :: Model?
		if not Gun then return end
		
		local GunParts = Gun:FindFirstChild("GunParts") :: Folder?
		if not GunParts then return end
		
		local Barrel = GunParts:FindFirstChild("Barrel") :: BasePart?
		if not Barrel then return end
		
		self.ViewModel:TriggerBackwardsOffset()
		
		VisualsHandler.MuzzleEffects(Barrel:FindFirstChild("MuzzleFlash"), Barrel:FindFirstChild("MuzzleLight"))
	else
		VisualsHandler.MuzzleEffects(self.GunParts.Barrel.MuzzleFlash, self.GunParts.Barrel.MuzzleLight)
	end
	
	local Raycasts = {}  :: {}
	
	for _ = 1, Rounds do
		local ServerParameters = self:FireBullet()
		table.insert(Raycasts, ServerParameters)
	end
	
	if not self.Config.GrenadeLauncher then
		Remotes.GunRemote:FireServer(Raycasts)
	end
end

function Main:ChangeMode()
	if not self.UI then return end
	
	-- Handles the modes, auto, semi
	if not self.CanChangeModes then return end
	
	self.FullAuto = not self.FullAuto
	self.UI.Mode.Text = self.FullAuto and "AUTO" or "SEMI"
end

return Main
