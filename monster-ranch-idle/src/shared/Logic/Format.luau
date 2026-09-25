-- Player-facing number and time formatting.
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1280 -> "1.28K", 48200 -> "48.2K", 1280000 -> "1.28M". Always 3 significant digits.
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local text = if n % 1 == 0 then tostring(n) else string.format("%.1f", n)
		return (negative and "-" or "") .. text
	end
	local tier = math.floor(math.log10(n) / 3)
	if tier >= #SUFFIXES then
		return (negative and "-" or "") .. string.format("%.2e", n)
	end
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = string.gsub(text, "%.?0+$", "")
	return (negative and "-" or "") .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.commas(n: number): string
	local whole = tostring(math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(whole), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	return (n < 0 and "-" or "") .. out
end

-- 9000 -> "2h 30m", 75 -> "1m 15s", 42 -> "42s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = math.floor(seconds / 86400)
	local h = math.floor(seconds % 86400 / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return if m > 0 then string.format("%dh %dm", h, m) else string.format("%dh", h)
	elseif m > 0 then
		return if s > 0 then string.format("%dm %ds", m, s) else string.format("%dm", m)
	end
	return string.format("%ds", s)
end

-- 161 -> "2:41", 3725 -> "1:02:05"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function Format.percent(p: number, decimals: number?): string
	local text = string.format("%." .. tostring(decimals or 0) .. "f", p * 100)
	if decimals and decimals > 0 then
		text = string.gsub(text, "%.?0+$", "")
	end
	return text .. "%"
end

function Format.weight(kg: number): string
	if kg < 10 then
		return string.format("%.1f kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- A unix time as a UTC calendar date: 1836399600 -> "11 Mar 2028".
function Format.date(unix: number): string
	-- Days-from-civil inverse (Howard Hinnant), valid for any date after 1970.
	local z = math.floor(unix / 86400) + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local day = doy - math.floor((153 * mp + 2) / 5) + 1
	local month = if mp < 10 then mp + 3 else mp - 9
	local year = yoe + era * 400 + (if month <= 2 then 1 else 0)
	return string.format("%d %s %d", day, MONTHS[month], year)
end

return Format
