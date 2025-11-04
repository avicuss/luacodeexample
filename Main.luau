local Main = {}
Main.__index = Main

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- // Player
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local CurrentCamera = workspace.CurrentCamera

local Remotes = ReplicatedStorage.GunSystem.Remotes

-- // Modules
local Utilites = require(script.Utilities)
local CameraShaker = require(script.CameraShaker)
local ShiftlockEnabler = require(script.ShiftlockEnabler)
local CharacterFramework = require(script.CharacterFramework)
local DynamicCrosshair = require(script.DynamicCrosshair)
local Config = require(ReplicatedStorage.GunSystem.Config.Config)

-- // Essentials
local FirerateCooldowns = {}

local HitsCounter = 0

-- // Input action logic for PC
-- Because the gun system is still being worked on, some parts outside of PC devices may not work
-- so now those are exclusively for PCs
local InputActions = {
	[Enum.KeyCode.R] = function(self) self:Reload() end,
	[Enum.KeyCode.L] = function(self) Utilites.Laser(self.GunParts.Barrel, true) end,
	[Enum.KeyCode.F] = function(self) Utilites.Flashlight(self.GunParts.Barrel, true) end,
	[Enum.KeyCode.LeftShift] = function(self) self:Run() end,
}

-- // Functions

-- [[ Check if the key pressed matches a key inside the Keylist which has keys for most of the gaming devices ]]
local function IsInputMatched(Input: InputObject, KeyList: {EnumItem}): boolean
	for _, Key in ipairs(KeyList) do
		if Input.KeyCode == Key or Input.UserInputType == Key then
			return true
		end
	end
	
	return false
end

-- [[ Initializer ]]
function Main.New(Tool: Tool)
	local self = setmetatable({}, Main)
	local GetConfig = Utilites.GetConfig(Tool.Name)
	if GetConfig == nil then return end
	
	-- Gun Parts
	local Animations = Tool:FindFirstChild("Animations")
	local Sounds = Tool:FindFirstChild("Sounds")
	local GunParts = Tool:FindFirstChild("GunParts")
	
	self.Tool = Tool
	self.Ammo = Tool:FindFirstChild("AmmoValue")
	self.Config = GetConfig
	self.Sounds = Tool:FindFirstChild("Sounds")
	self.GunParts = GunParts
	self.UI = Player.PlayerGui.GunUIs.Frame
	
	self.OriginalCFrame = Tool.Grip
	
	if not GetConfig.SniperSight then
		self.Crosshair = DynamicCrosshair.New(nil, GetConfig.RecoilMinSpread, GetConfig.RecoilMaxSpread, GetConfig.RecoilDecreasePerSecond, GetConfig.RecoilIncreasePerSecond)
	end
	
	-- Essential booleans
	self.CanShoot = true
	self.NormalPosition = false
	self.Shooting = false
	self.Running = false
	self.FullAuto = GetConfig["FullAuto"]
	self.CanChangeModes = GetConfig["CanModeChange"]
	
	self.Humanoid = Player.Character:WaitForChild("Humanoid")
	
	-- If humanoid exists then load aniamtions
	if self.Humanoid then
		self.HandleAnimation = self.Humanoid.Animator:LoadAnimation(Animations.HandleAnimation)
		self.ShootAnimation = self.Humanoid.Animator:LoadAnimation(Animations.ShootAnimation)
		self.AimAnimation = self.Humanoid.Animator:LoadAnimation(Animations.AimAnimation)
	end
	
	return self
end

-- // Input handling
function Main:OnInputBegan(Input, Processed)
	if Processed then return end

	if IsInputMatched(Input, Config.AimKeyCodes) then return self:Aim(true) end
	if IsInputMatched(Input, Config.ShootKeyCodes) then return self:StartShooting() end
	if IsInputMatched(Input, Config.ReloadKeyCodes) then return self:Reload() end

	local Action = InputActions[Input.KeyCode]
	if Action then return Action(self) end

	if Input.KeyCode == Enum.KeyCode.T and not self.NormalPosition then
		ShiftlockEnabler.SwitchSide()
	end
end

function Main:OnInputEnded(Input, Processed)
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

	local LastFired = FirerateCooldowns[self.Tool.Name] or 0

	-- Check in order to fix a bug where you could spam weapons and shoot
	-- this part checks the last fired bullet and puts it inside a table with tick()
	-- that then later gets checked in the if statement to fix the spam bug.
	if tick() - LastFired < self.Config.Firerate then return end
	FirerateCooldowns[self.Tool.Name] = tick()

	self.Shooting = true

	while self.Shooting and self.CanShoot and not self.NormalPosition and self.Humanoid.Health > 0 and not self.Running do
		if self.Ammo.Value > 0 then
			self.Ammo.Value -= 1
			self.UI.Ammo.Text = tostring(self.Ammo.Value)

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
	-- Utilites as well as CharacterFramework to move arms & head with the mouse position
	CharacterFramework.Setup()
	Utilites.EnableUI(true, self.Tool.Name)

	-- If the gun has a sniper sight then the ZoomDistance is different
	Player.CameraMinZoomDistance = self.Crosshair and 3 or 0

	self.HandleAnimation:Play()
	self.NormalPosition = true

	self.UI.Ammo.Text = self.Ammo.Value
	self.UI.GunName.Text = self.Tool.Name
	self.UI.Mode.Text = self.FullAuto and "AUTO" or "SEMI"

	self.Tool.Grip = self.OriginalCFrame
	self.Sounds.EquippedSound:Play()
	
	self.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input, G)
		self:OnInputBegan(Input, G)
	end)
	
	self.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input, G)
		self:OnInputEnded(Input, G)
	end)
end

-- [[ Aim Function that makes the gun be able to shoot ]]
function Main:EnterAim()
	if self.Running then
		self:Run()
	end

	self.NormalPosition = false

	if self.Crosshair then
		self:EnterNormalAim()
	else
		self:EnterSniperAim()
	end

	self.HandleAnimation:Stop()
	self.AimAnimation:Play()
	self.Tool.Grip = self.Config.AimCFrame
end

function Main:ExitAim()
	-- Exits the aim
	
	-- sets the normalposition to true so the other parts of the code know what mode it is
	self.NormalPosition = true
	Player.CameraMaxZoomDistance = 30

	if self.Crosshair then
		self:ExitNormalAim()
	else
		self:ExitSniperAim()
	end

	self.HandleAnimation:Play()
	self.AimAnimation:Stop()

	Utilites.Laser(self.GunParts.Barrel, false)
	Utilites.Flashlight(self.GunParts.Barrel, false)

	self.Tool.Grip = self.OriginalCFrame
end

function Main:EnterNormalAim()
	-- Enables the normal aim mode
	
	Player.CameraMaxZoomDistance = 15
	
	self.Crosshair:Enable()
	
	ShiftlockEnabler.SetShiftLock(true)
	self.Crosshair:FollowMouse(true)
	CharacterFramework.Framework(true)
end

function Main:ExitNormalAim()
	-- Pretty much self explanatory, disables the normal aim
	
	self.Crosshair:Disable()
	
	ShiftlockEnabler.SetShiftLock(false)
	CharacterFramework.Framework(false)
end

function Main:EnterSniperAim()
	self.UI.Parent.ImageLabel.Visible = true
	Player.CameraMaxZoomDistance = 0
	CurrentCamera.FieldOfView = 20

	task.spawn(function()
		Utilites.CameraSightRecoil(true)
	end)

	UserInputService.MouseDeltaSensitivity = 0.3

	-- Turns off the gun visibilty due to the fact that the sniper is zoomed in
	for _, Part in pairs(self.Tool:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.Transparency = 1
		end
	end
end

function Main:ExitSniperAim()
	self.UI.Parent.ImageLabel.Visible = false
	
	-- Sensitivities
	CurrentCamera.FieldOfView = 70
	UserInputService.MouseDeltaSensitivity = 1
	
	Utilites.CameraSightRecoil(false)

	for _, Part in pairs(self.Tool:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.Transparency = 0
		end
	end
end

function Main:Aim(Boolean)
	if Boolean and self.CanShoot then
		self:EnterAim()
	else
		self:ExitAim()
	end
end

-- [[Uneqiup which disables the whole gun and does a cleanup ]]
function Main:UnEquip()
	-- Disables UI & cleans up all the things
	Utilites.EnableUI(false, self.Tool.Name)
	
	self:Aim(false)
	self.HandleAnimation:Stop()
	self.AimAnimation:Stop()
	
	if self.Crosshair then
		self.Crosshair:Destroy()
	else
		self.UI.Parent.ImageLabel.Visible = false
	end
	
	Player.CameraMinZoomDistance = 0
	
	-- Disables all the connections
	if self.InputBeganConnection then
		self.InputBeganConnection:Disconnect()
	end
	
	if self.InputEndedConnection then
		self.InputEndedConnection:Disconnect()
	end
end

-- [[ Main Reload ]]
function Main:Reload()
	if not self.CanShoot then return end
	
	-- Stop animations and plays handle anim 
	self.AimAnimation:Stop()
	self.HandleAnimation:Play()
	
	-- Fires the reload sound as it's vital for combat so the other users can knwow
	-- when the player is reloading
	Remotes.SoundHandler:FireServer(self.Sounds, "Reload", self.Config.ReloadTime)
	
	self:Aim(false)
	self.CanShoot = false
	
	-- Visuals & sets the ammo to 0
	self.UI.Ammo.Text = "..."
	self.Ammo.Value = 0
	
	task.wait(self.Config["ReloadTime"])
	
	self.CanShoot = true

	self.Ammo.Value = self.Config["Ammo"]
	self.UI.Ammo.Text = self.Ammo.Value
end

-- [[ Main Shoot Function ]]
function Main:FireRaycast()
	-- Does a raycast and returns the raycast properties for FireBullet function
	-- Raycasts are done via an external community made module
	
	local RaycastInstance, Position, Normal, Origin, Direction

	if self.Crosshair then
		RaycastInstance, Position, Normal, Origin, Direction = self.Crosshair:Raycast()
	else
		RaycastInstance, Position, Normal, Origin, Direction = Utilites.MouseRaycast(self.Tool)
	end
	
	return RaycastInstance, Position, Normal, Origin, Direction
end

function Main:FireBullet()
	-- Creates a bullet and fires it
	
	-- The Raycast function
	local RaycastInstance, Position, Normal, Origin, Direction = self:FireRaycast()
	
	-- This part basically checks if the raycast hit something and then fires the bullet to that target
	-- if it's not then it does it 500 studs to the direction of the mouse so the bullet will still be created
	-- Purely for visuals
	local EndPosition = RaycastInstance and Position or Origin + Direction.Unit * 500
	
	-- Main server checks 
	if RaycastInstance then
		Remotes.GunRemote:FireServer(false, 
			self.GunParts.Barrel.MuzzleFlash,
			self.GunParts.Barrel.MuzzleLight,
			RaycastInstance, 
			self.Config["HeadDamage"], 
			self.Config["BodyDamage"], 
			Normal, 
			Position
		)
	end
	
	if not RaycastInstance then
		EndPosition = Origin + (Direction.Unit * 500)
		
		Remotes.GunRemote:FireServer(true, self.GunParts.Barrel.MuzzleFlash, self.GunParts.Barrel.MuzzleLight)
	end
	
	task.spawn(function()
		Utilites.CreateBullet(self.GunParts.Barrel.Position, EndPosition)
	end)
end

function Main:HandleUtilities()
	-- Handles utilities functions for the Shoot function
	
	Utilites.ArmsAnimation(1)
	Utilites.Recoil(self.Tool.Name, self.Crosshair)

	self.ShootAnimation:Play()
end

function Main:Shoot()
	-- Handles utilities & main shoot functions
	
	self:HandleUtilities()
	
	local Rounds = self.Config.ShotgunRounds or 1
	
	for _ = 1, Rounds do
		self:FireBullet()
	end
end

-- [[Run Function done via server]]
function Main:Run()
	-- Pretty much just enables running, nothing to explain much here
	self.Running = not self.Running
	self.Shooting = false
	
	if not self.NormalPosition then
		self:Aim()
	end
	
	Remotes.RunRemote:FireServer(self.Running, self.Config["RunSpeed"])
end

return Main
