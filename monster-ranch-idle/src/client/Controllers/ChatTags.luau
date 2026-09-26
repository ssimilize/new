--[[
	ChatTags controller: a gold [VIP] prefix on chat messages from VIP Rancher owners.

	Who is VIP comes from global.Monetization.vip (['u'..userId] = true), which the server sets
	from its pass cache, so every client tags everyone's messages, not just its own. The prefix
	is drawn with TextChatService.OnIncomingMessage (Config.Monetization.VipChatTag, rich text
	built by Logic/Vip.ChatPrefix).

	Dormant, never an error, when TextChatService is missing, when the place still uses the
	legacy chat (ChatVersion ~= TextChatService), or when the callback can't be set (Lune mock).
	The callback is this game's only OnIncomingMessage, set once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Vip = require(Shared.Logic.Vip)

local ChatTags = {
	Name = "ChatTags",
	Dependencies = {},
}

local ctx
local installed = false

local function isVip(userId: any): boolean
	if type(userId) ~= "number" then
		return false
	end
	local list = ctx.Store:Get("global.Monetization.vip")
	return type(list) == "table" and list["u" .. tostring(userId)] == true
end

local function onIncomingMessage(message)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source and isVip(source.UserId) then
		props.PrefixText = Vip.ChatPrefix(message.PrefixText, true, Config.Monetization.VipChatTag)
	end
	return props
end

-- Returns true when the tag hook is live.
local function install(): boolean
	local ok, result = pcall(function()
		local service = game:FindService("TextChatService") or game:GetService("TextChatService")
		if not service or service.ChatVersion ~= Enum.ChatVersion.TextChatService then
			return false
		end
		service.OnIncomingMessage = onIncomingMessage
		return true
	end)
	return ok and result == true
end

function ChatTags.Init(context)
	ctx = context
end

function ChatTags.Start()
	installed = install()
end

-- For specs and debugging: whether the hook is set, and the prefix a message would get.
function ChatTags:Installed(): boolean
	return installed
end

function ChatTags:PrefixFor(userId: number, prefixText: string?): string
	return Vip.ChatPrefix(prefixText, isVip(userId), Config.Monetization.VipChatTag)
end

return ChatTags
