--!strict
-- Base64 (standard alphabet) over Luau buffers. decode skips any other character (newlines,
-- "=" padding), exactly like the Ranch's MeshMonster decode; encode pads with "=".

local Base64 = {}

----------------------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SEXTET: { [number]: number } = {}
for i = 1, #ALPHABET do
	SEXTET[string.byte(ALPHABET, i)] = i - 1
end

function Base64.decode(text: string): buffer
	local clean = string.gsub(text, "[^%w%+/]", "")
	local n = #clean
	local out = buffer.create(n // 4 * 3 + (if n % 4 == 3 then 2 elseif n % 4 == 2 then 1 else 0))
	local o, i = 0, 1
	while i + 3 <= n do
		local a, b, c, d = string.byte(clean, i, i + 3)
		local v = SEXTET[a] * 262144 + SEXTET[b] * 4096 + SEXTET[c] * 64 + SEXTET[d]
		buffer.writeu8(out, o, v // 65536)
		buffer.writeu8(out, o + 1, v // 256 % 256)
		buffer.writeu8(out, o + 2, v % 256)
		o += 3
		i += 4
	end
	if n - i + 1 >= 2 then
		local a, b = string.byte(clean, i, i + 1)
		local v = SEXTET[a] * 262144 + SEXTET[b] * 4096
		if n - i + 1 == 3 then
			v += SEXTET[string.byte(clean, i + 2)] * 64
			buffer.writeu8(out, o + 1, v // 256 % 256)
		end
		buffer.writeu8(out, o, v // 65536)
	end
	return out
end

function Base64.encode(buf: buffer): string
	local n = buffer.len(buf)
	local parts = table.create(n // 3 + 1)
	local i = 0
	while i + 2 < n do
		local v = buffer.readu8(buf, i) * 65536 + buffer.readu8(buf, i + 1) * 256 + buffer.readu8(buf, i + 2)
		local a, b, c, d = v // 262144, v // 4096 % 64, v // 64 % 64, v % 64
		table.insert(parts, string.sub(ALPHABET, a + 1, a + 1) .. string.sub(ALPHABET, b + 1, b + 1)
			.. string.sub(ALPHABET, c + 1, c + 1) .. string.sub(ALPHABET, d + 1, d + 1))
		i += 3
	end
	local rest = n - i
	if rest > 0 then
		local v = buffer.readu8(buf, i) * 65536 + (if rest == 2 then buffer.readu8(buf, i + 1) * 256 else 0)
		local a, b, c = v // 262144, v // 4096 % 64, v // 64 % 64
		local s = string.sub(ALPHABET, a + 1, a + 1) .. string.sub(ALPHABET, b + 1, b + 1)
		s ..= if rest == 2 then string.sub(ALPHABET, c + 1, c + 1) .. "=" else "=="
		table.insert(parts, s)
	end
	return table.concat(parts)
end

return Base64
