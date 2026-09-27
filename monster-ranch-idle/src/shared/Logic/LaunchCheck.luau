--[[
	Logic/LaunchCheck: pure scan of Config for owner-created ids that are still placeholders
	(game passes, developer products, badges, the group, reminder templates and secret, the
	moderator group). Nothing here touches Roblox; Kernel/Main warns from it in Studio only,
	and tests/specs/LaunchCheck.spec.luau can fail a CI run with RELEASE_CHECK=1.

	LaunchCheck.Missing(Config) -> { { area, key, where, create } }
	  area    "pass" | "product" | "badge" | "group" | "reminders" | "moderation"
	  key     the entry's own key (pass/product key, badge milestone id, reminder kind, ...)
	  where   the Config path to fill in, as a dotted string
	  create  what to make in Creator Hub (type, suggested name, price where Config has one)

	LaunchCheck.Summary(missing) -> string   one grouped line for a warn(), e.g.
	  "Launch checklist: 8 pass ids, 11 product ids, 3 badge ids, the group id, 4 reminder ids
	   missing - see docs/GO_LIVE.md"
]]

local LaunchCheck = {}

local AREA_ORDER = { "pass", "product", "badge", "group", "reminders", "moderation" }

local function robux(price: number?): string
	if type(price) == "number" and price > 0 then
		return " (" .. tostring(price) .. " R$)"
	end
	return ""
end

function LaunchCheck.Missing(Config: any): { { area: string, key: string, where: string, create: string } }
	local out = {}

	local Monetization = Config.Monetization
	if Monetization then
		for _, p in Monetization.Passes or {} do
			if not p.gamePassId or p.gamePassId == 0 then
				table.insert(out, {
					area = "pass",
					key = p.key,
					where = "Config.Monetization.Passes." .. p.key .. ".gamePassId",
					create = "Game pass: " .. p.name .. robux(p.price),
				})
			end
		end
		for _, p in Monetization.Products or {} do
			if not p.productId or p.productId == 0 then
				table.insert(out, {
					area = "product",
					key = p.key,
					where = "Config.Monetization.Products." .. p.key .. ".productId",
					create = "Developer product: " .. p.name .. robux(p.price),
				})
			end
		end
	end

	local Codex = Config.Codex
	if Codex and Codex.BadgeIds then
		local milestones = {}
		for milestone in Codex.BadgeIds do
			table.insert(milestones, milestone)
		end
		table.sort(milestones)
		for _, milestone in milestones do
			local id = Codex.BadgeIds[milestone]
			if not id or id == 0 then
				table.insert(out, {
					area = "badge",
					key = milestone,
					where = "Config.Codex.BadgeIds." .. milestone,
					create = "Badge: Codex " .. milestone,
				})
			end
		end
	end

	local Quests = Config.Quests
	if Quests and (not Quests.GroupId or Quests.GroupId == 0) then
		table.insert(out, {
			area = "group",
			key = "group",
			where = "Config.Quests.GroupId",
			create = 'Roblox group (the game\'s group; sets the "Join our group" reward)',
		})
	end

	local Reminders = Config.Reminders
	if Reminders then
		if not Reminders.SecretName or Reminders.SecretName == "" then
			table.insert(out, {
				area = "reminders",
				key = "secret",
				where = "Config.Reminders.SecretName",
				create = "Open Cloud API key (user-notification, write) stored as an experience secret",
			})
		end
		for _, kind in Reminders.Kinds or {} do
			local id = Reminders.Templates and Reminders.Templates[kind]
			if not id or id == "" then
				table.insert(out, {
					area = "reminders",
					key = kind,
					where = "Config.Reminders.Templates." .. kind,
					create = "Notification template: " .. kind .. " reminder",
				})
			end
		end
	end

	local Workshop = Config.Workshop
	if Workshop and Workshop.ModeratorGroup and Workshop.ModeratorGroup.id == 0 then
		table.insert(out, {
			area = "moderation",
			key = "moderatorGroup",
			where = "Config.Workshop.ModeratorGroup.id",
			create = "Roblox group for moderators (optional: Config.Workshop.Moderators can list user ids instead)",
		})
	end

	return out
end

-- One grouped line per area, in a fixed order, for a single startup warn().
function LaunchCheck.Summary(missing: { any }): string
	local counts = {}
	local extra = {} -- areas outside AREA_ORDER, kept in first-seen order
	for _, entry in missing do
		if counts[entry.area] == nil and not table.find(AREA_ORDER, entry.area) then
			table.insert(extra, entry.area)
		end
		counts[entry.area] = (counts[entry.area] or 0) + 1
	end
	local fixed = {}
	for _, area in AREA_ORDER do
		if (counts[area] or 0) > 0 then
			table.insert(fixed, area)
		end
	end
	for _, area in extra do
		table.insert(fixed, area)
	end

	local NAMES = {
		pass = "pass id",
		product = "product id",
		badge = "badge id",
		group = "group id",
		reminders = "reminder id",
		moderation = "moderator group id",
	}
	local parts = {}
	for _, area in fixed do
		local n = counts[area]
		local label = NAMES[area] or (area .. " id")
		if area == "group" then
			table.insert(parts, "the group id")
		else
			table.insert(parts, tostring(n) .. " " .. label .. (if n == 1 then "" else "s"))
		end
	end
	if #parts == 0 then
		return "Launch checklist: nothing missing."
	end
	return "Launch checklist: " .. table.concat(parts, ", ") .. " missing - see docs/GO_LIVE.md"
end

return LaunchCheck
