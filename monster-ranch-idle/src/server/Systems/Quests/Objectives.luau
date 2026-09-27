--[[
	Quests/Objectives: moved to Shared/Logic/Objectives in 3.8 (the Weekly system uses it too).
	This module re-exports it so existing requires keep working.
]]

return require(game:GetService("ReplicatedStorage").Shared.Logic.Objectives)
