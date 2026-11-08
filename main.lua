local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer

local Ctrl = require(plr:WaitForChild("PlayerScripts")
	:WaitForChild("Client")
	:WaitForChild("Controllers")
	:WaitForChild("Islands")
	:WaitForChild("IslandMisc")
	:WaitForChild("IceFishing"))
local Cfg = require(ReplicatedStorage.Shared.Config.IceFishingConfig)

local defaults = {
	Enabled = true,
	AutoFish = false,
	AutoDecision = "",
	ClaimFishExact = 0,
	Quiet = false,
}

if not getgenv().IceAutoRing then
	getgenv().IceAutoRing = table.clone(defaults)
end
for k, v in pairs(defaults) do
	if getgenv().IceAutoRing[k] == nil then
		getgenv().IceAutoRing[k] = v
	end
end

local Config = getgenv().IceAutoRing
local gen = (getgenv().IceAutoRingGen or 0) + 1
getgenv().IceAutoRingGen = gen

local function alive()
	return getgenv().IceAutoRingGen == gen and Config.Enabled
end

local function stop()
	Config.Enabled = false
	Config.AutoFish = false
	Config.AutoDecision = ""
	Config.ClaimFishExact = 0
	getgenv().IceAutoRingGen = math.huge
end

local function log(...)
	if not Config.Quiet then
		print("[IceAutoRing]", ...)
	end
end

getgenv().IceAutoRingLast = nil

do
	local removed = {}

	local function purge(parent)
		for _, v in ipairs(parent:GetChildren()) do
			local n = v.Name:lower()
			if n:find("luna", 1, true) or n:find("autoring", 1, true)
				or n:find("starlight", 1, true) or n:find("rayfield", 1, true) then
				table.insert(removed, v.Name)
				v:Destroy()
			end
		end
	end

	pcall(function()
		local ok, hui = pcall(gethui)
		if ok and hui then
			purge(hui)
		end
	end)
	pcall(function()
		purge(game:GetService("CoreGui"))
	end)

	if #removed > 0 then
		log("cleared old UI: " .. table.concat(removed, ", "))
	end
end

local Luna
do
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/refs/heads/master/source.lua", true))()
	end)
	if ok and type(lib) == "table" then
		Luna = lib
	else
		log("Luna failed to load (" .. tostring(lib) .. ")")
	end
end

local status

if Luna then
	local Window = Luna:CreateWindow({
		Name = "Ice Fishing",
		Subtitle = "Automation",
		LogoID = nil,
		LoadingEnabled = false,
		ConfigSettings = {
			RootFolder = nil,
			ConfigFolder = "IceAutoRing",
		},
		KeySystem = false,
	})

	local Main = Window:CreateTab({
		Name = "Main",
		Icon = "tune",
		ImageSource = "Material",
		ShowTitle = true,
	})

	Main:CreateToggle({
		Name = "Auto Drop",
		Description = "Drops the fish at the perfect moment",
		CurrentValue = Config.Enabled,
		Callback = function(v)
			Config.Enabled = v
		end,
	}, "AutoDrop")

	Main:CreateToggle({
		Name = "Auto Cast",
		Description = "Starts a new round while you are in the zone",
		CurrentValue = Config.AutoFish,
		Callback = function(v)
			Config.AutoFish = v
		end,
	}, "AutoCast")

	Main:CreateDropdown({
		Name = "After Catch",
		Description = "Action taken when the offer screen appears",
		Options = { "Manual", "Claim", "Bait" },
		CurrentOption = { if Config.AutoDecision == "" then "Manual" else Config.AutoDecision },
		MultipleOptions = false,
		Callback = function(opt)
			local pick = if type(opt) == "table" then opt[1] else opt
			Config.AutoDecision = if pick == "Claim" or pick == "Bait" then pick else ""
		end,
	}, "AfterCatch")

	Main:CreateDropdown({
		Name = "Claim Fish #",
		Description = "The exact fish to claim before restarting (3 = the 3rd fish, 10 = the top fish)",
		Options = { "Never", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" },
		CurrentOption = { if Config.ClaimFishExact > 0 then tostring(Config.ClaimFishExact) else "Never" },
		MultipleOptions = false,
		Callback = function(opt)
			local pick = if type(opt) == "table" then opt[1] else opt
			Config.ClaimFishExact = tonumber(pick) or 0
			if Config.ClaimFishExact > 0 then
				log("will claim fish #" .. Config.ClaimFishExact)
			end
		end,
	}, "ClaimFishExact")

	Main:CreateDivider()

	status = Main:CreateLabel({
		Text = "Status: Waiting for swing",
		Style = 2,
	})

	Main:CreateButton({
		Name = "Unload",
		Description = "Stops the script and closes this menu",
		Callback = function()
			stop()
			pcall(function()
				Luna:Destroy()
			end)
		end,
	})

	pcall(function()
		Luna:Notification({
			Title = "Ice Fishing",
			Icon = "check_circle",
			ImageSource = "Material",
			Content = "Loaded. Stand in the fishing zone to begin.",
		})
	end)
end

local function setStatus(text)
	if not status then return end
	local full = "Status: " .. text
	if not pcall(function() status:Set(full) end) then
		pcall(function() status:Set({ Text = full, Style = 2 }) end)
	end
end

local function waitUntil(t, valid)
	while valid() and os.clock() < t - 0.35 do
		task.wait(0.05)
	end
	while valid() and os.clock() < t do
	end
end

local function runSwing(markedAt)
	local level = math.max(1, Ctrl.SwingLevel or 1)
	local period = Cfg.SwingTime(level)
	local elapsed = os.clock() - markedAt
	local guard = math.max(elapsed + 0.05, Cfg.Drop.SwingIn)
	local k = math.max(1, math.ceil(guard / period))
	local target = k * period

	setStatus(("Aiming for t=%.2fs (L%d)"):format(target, level))

	waitUntil(markedAt + target, function()
		return Ctrl.SwingAt == markedAt and Ctrl.Mode == "Swing" and alive()
	end)

	if Ctrl.SwingAt ~= markedAt or Ctrl.Mode ~= "Swing" then
		return
	end

	pcall(function()
		Ctrl:Send("Tap", target)
	end)
	pcall(function()
		Ctrl:StartDrop()
	end)

	getgenv().IceAutoRingLast = {
		level = level,
		sent = target,
		at = os.clock(),
	}
	log(("dropped t=%.3fs (L%d, period=%.2fs)"):format(target, level, period))
end

task.spawn(function()
	local lastToken = -1

	while getgenv().IceAutoRingGen == gen do
		if Config.Enabled then
			local mode = rawget(Ctrl, "Mode")

			if mode == "Swing" and Ctrl.SwingAt then
				pcall(runSwing, Ctrl.SwingAt)
			elseif mode == "Idle" and Config.AutoFish and (os.clock() - (Ctrl.IdleAt or 0)) > 0.8 then
				pcall(Ctrl.PressFish, Ctrl)
			elseif mode == "Decide" and (Config.AutoDecision ~= "" or Config.ClaimFishExact > 0) then
				local token = math.floor(os.clock() * 4)
				if token ~= lastToken then
					lastToken = token
					local card = rawget(Ctrl, "Level") or 0

					if Config.ClaimFishExact > 0 and card >= Config.ClaimFishExact then
						pcall(Ctrl.PressClaim, Ctrl)
						log(("claiming fish #%d and restarting"):format(card))
						setStatus(("Claimed fish #%d - restarting"):format(card))
					elseif Config.AutoDecision == "Claim" then
						pcall(Ctrl.PressClaim, Ctrl)
					elseif Config.AutoDecision == "Bait" then
						pcall(Ctrl.PressBait, Ctrl)
					end
				end
			end
		end
		task.wait(0.05)
	end

	setStatus("Stopped")
	log("stopped")
end)
