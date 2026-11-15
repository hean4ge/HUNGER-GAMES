--[[
	StudioSync - moves script sources and data files between the repo on disk and this place, exactly, without typing
	them through an editor. Studio only, Edit mode only. The disk side is tools/studio_sync/sync.py (see its README).

	PUSH (disk -> Studio)
	  sync.py push ...   writes a pack: an .rbxmx of base64 chunks in Studio's local content folder (ls_import/).
	  StudioSync.apply(packName, opts?) loads it with game:GetObjects("rbxasset://ls_import/<pack>.rbxmx"), checks every
	  source against the pack's own size and FNV-1a, checks that the script in Studio is still the version the repo last
	  saw (so a Studio-side edit is never overwritten silently), then writes the Source and checks it again.
	  opts.force = true writes even when Studio has drifted; opts.dry = true only reports.
	  sync.py confirm <pack> then reads the result lines (LSS|...) from Studio's log and records the new fingerprints.

	PULL (Studio -> disk)
	  StudioSync.export(runId, prefixes?) prints every script (or those under the given Studio paths) to the log as
	  base64 lines (LSX|...); sync.py pull <runId> rebuilds the files from the log and verifies each one.
	  StudioSync.fingerprints(runId, prefixes?) prints only path, class, size and hash (LSF|...).

	DATA
	  local pack = StudioSync.open(packName)   -- a pack made with: sync.py blob <packName> name=file ...
	  local b = pack:blob("Height")            -- buffer with the file's exact bytes
	  pack:close()

	From execute_luau (Edit). Studio caches required modules, so require a clone:
	  return require(game.ServerStorage.Dev.StudioSync:Clone()).apply("p0412_ab12")
]]
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local StudioSync = {}
StudioSync.VERSION = 1

local SERVICES = {
	"StarterPlayer",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"Workspace",
	"Lighting",
}
local LOG_CHUNK = 800 -- Studio's log file cuts lines at about 1,000 characters

local bxor, lshift = bit32.bxor, bit32.lshift

-- FNV-1a 32-bit over the bytes of s, lowercase hex (the same fingerprint as src/manifest.json)
function StudioSync.fnv(s: string): string
	local h = 2166136261
	local n = #s
	for i = 1, n, 4096 do
		local bytes = { string.byte(s, i, math.min(i + 4095, n)) }
		for j = 1, #bytes do
			h = bxor(h, bytes[j])
			h = (lshift(h, 24) + (h * 403) % 4294967296) % 4294967296
		end
	end
	return string.format("%08x", h)
end

function StudioSync.fnvBuffer(b: buffer): string
	local h = 2166136261
	for i = 0, buffer.len(b) - 1 do
		h = bxor(h, buffer.readu8(b, i))
		h = (lshift(h, 24) + (h * 403) % 4294967296) % 4294967296
	end
	return string.format("%08x", h)
end

local function pathOf(inst: Instance): string
	local parts = {}
	local cur: Instance? = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function resolve(path: string): Instance?
	local parts = string.split(path, ".")
	local ok, service = pcall(function()
		return game:GetService(parts[1])
	end)
	if not ok or not service then
		return nil
	end
	local cur: Instance = service
	for i = 2, #parts do
		local nextInst = cur:FindFirstChild(parts[i])
		if not nextInst then
			return nil
		end
		cur = nextInst
	end
	return cur
end

-- the instance at the given path parts, making Folders for the missing ones
local function ensureContainer(parts: { string }): Instance
	local cur: Instance = game:GetService(parts[1])
	for i = 2, #parts do
		local nextInst = cur:FindFirstChild(parts[i])
		if not nextInst then
			nextInst = Instance.new("Folder")
			nextInst.Name = parts[i]
			nextInst.Parent = cur
		end
		cur = nextInst :: Instance
	end
	return cur
end

local function loadPack(packName: string): (Instance, any)
	local objects = game:GetObjects("rbxasset://ls_import/" .. packName .. ".rbxmx")
	local root = objects[1]
	if not root or root.Name ~= "LSPack" then
		error("StudioSync: pack " .. packName .. " has no LSPack root (is the file in Studio's content/ls_import?)")
	end
	local indexValue = root:FindFirstChild("Index")
	if not indexValue or not indexValue:IsA("StringValue") then
		error("StudioSync: pack " .. packName .. " has no Index")
	end
	return root, HttpService:JSONDecode(indexValue.Value)
end

local function entryBytes(root: Instance, index: number, chunks: number): buffer
	if chunks == 0 then
		return buffer.create(0)
	end
	local parts = table.create(chunks)
	for k = 1, chunks do
		local value = root:FindFirstChild(string.format("E%d_%d", index, k))
		if not value or not value:IsA("StringValue") then
			error(string.format("chunk E%d_%d is missing from the pack", index, k))
		end
		parts[k] = value.Value
	end
	return EncodingService:Base64Decode(buffer.fromstring(table.concat(parts)))
end

local function writeSource(target: any, src: string)
	pcall(function()
		ScriptEditorService:UpdateSourceAsync(target, function()
			return src
		end)
	end)
	if target.Source ~= src then
		target.Source = src
	end
end

function StudioSync.apply(packName: string, opts: { force: boolean?, dry: boolean? }?): string
	assert(not RunService:IsRunning(), "StudioSync works in Edit mode only")
	local options = opts or {}
	local root, index = loadPack(packName)
	local counts = { created = 0, updated = 0, same = 0, drift = 0, failed = 0 }
	local lines = {}
	for _, e in ipairs(index.entries) do
		if e.kind == "script" then
			local status, detail = "failed", ""
			local ok, err = pcall(function()
				local src = buffer.tostring(entryBytes(root, e.i, e.chunks))
				if #src ~= e.bytes or StudioSync.fnv(src) ~= e.fnv then
					error("the pack's data does not match its own fingerprint")
				end
				local target = resolve(e.path)
				if target then
					if target.ClassName ~= e.class then
						error("Studio has a " .. target.ClassName .. " there, the pack says " .. e.class)
					end
					local cur = (target :: any).Source
					local curFnv = StudioSync.fnv(cur)
					if #cur == e.bytes and curFnv == e.fnv then
						status = "same"
					elseif e.before and curFnv ~= e.before and not options.force then
						status = "drift"
						detail = string.format("Studio has %d bytes %s; the repo last saw %s", #cur, curFnv, e.before)
					else
						if not options.dry then
							writeSource(target, src)
							local now = (target :: any).Source
							if #now ~= e.bytes or StudioSync.fnv(now) ~= e.fnv then
								error("the Source read back differently after the write")
							end
						end
						status = "updated"
					end
				else
					local parts = string.split(e.path, ".")
					local name = table.remove(parts) :: string
					if not options.dry then
						local parent = ensureContainer(parts)
						local inst = Instance.new(e.class) :: any
						inst.Name = name
						if e.class == "Script" and e.runContext then
							pcall(function()
								inst.RunContext = (Enum.RunContext :: any)[e.runContext]
							end)
						end
						inst.Source = src
						inst.Parent = parent
						if #inst.Source ~= e.bytes then
							error("the new script's Source read back differently")
						end
					end
					status = "created"
				end
			end)
			if not ok then
				status = "failed"
				detail = tostring(err)
			end
			counts[status] += 1
			print(string.format("LSS|%s|%s|%s|%d|%s|%s", packName, status, e.path, e.bytes, e.fnv, detail))
			if status ~= "same" then
				table.insert(lines, status .. "  " .. e.path .. (if detail ~= "" then "  (" .. detail .. ")" else ""))
			end
		end
	end
	root:Destroy()
	if not options.dry then
		pcall(function()
			ChangeHistoryService:SetWaypoint("StudioSync " .. packName)
		end)
	end
	local summary = string.format(
		"StudioSync %s%s: %d updated, %d created, %d same, %d DRIFT, %d FAILED",
		packName,
		if options.dry then " (dry run)" else "",
		counts.updated,
		counts.created,
		counts.same,
		counts.drift,
		counts.failed
	)
	print(string.format("LSS|%s|done|%s|%s", packName, if options.dry then "dry" else "real", summary))
	table.insert(lines, 1, summary)
	return table.concat(lines, "\n")
end

local function scripts(prefixes: { string }?): { { inst: any, path: string } }
	local list = {}
	for _, serviceName in ipairs(SERVICES) do
		for _, d in ipairs(game:GetService(serviceName):GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				local path = pathOf(d)
				local take = prefixes == nil
				if prefixes then
					for _, prefix in ipairs(prefixes) do
						if path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "." then
							take = true
							break
						end
					end
				end
				if take then
					table.insert(list, { inst = d, path = path })
				end
			end
		end
	end
	return list
end

local function runContextOf(inst: any): string
	if inst.ClassName == "Script" then
		return inst.RunContext.Name
	end
	return ""
end

function StudioSync.export(runId: string, prefixes: { string }?): string
	local list = scripts(prefixes)
	print(string.format("LSX|%s|S|%d", runId, #list))
	local lines, total = 0, 0
	for idx, item in ipairs(list) do
		local src = item.inst.Source
		total += #src
		local b64 = if #src > 0 then buffer.tostring(EncodingService:Base64Encode(buffer.fromstring(src))) else ""
		local n = math.ceil(#b64 / LOG_CHUNK)
		print(string.format(
			"LSX|%s|B|%d|%s|%s|%s|%d|%s|%d",
			runId, idx, item.path, item.inst.ClassName, runContextOf(item.inst), #src, StudioSync.fnv(src), n
		))
		for k = 1, n do
			print(string.format("LSX|%s|C|%d|%d|%s", runId, idx, k, string.sub(b64, (k - 1) * LOG_CHUNK + 1, k * LOG_CHUNK)))
			lines += 1
			if lines % 150 == 0 then
				task.wait()
			end
		end
		task.wait()
	end
	print(string.format("LSX|%s|E|%d|%d|%d", runId, #list, lines, total))
	return string.format("StudioSync export %s: %d scripts, %d bytes, %d log lines", runId, #list, total, lines)
end

function StudioSync.fingerprints(runId: string, prefixes: { string }?): string
	local list = scripts(prefixes)
	print(string.format("LSF|%s|S|%d", runId, #list))
	for idx, item in ipairs(list) do
		local src = item.inst.Source
		print(string.format(
			"LSF|%s|B|%d|%s|%s|%s|%d|%s", runId, idx, item.path, item.inst.ClassName, runContextOf(item.inst), #src, StudioSync.fnv(src)
		))
		if idx % 20 == 0 then
			task.wait()
		end
	end
	print(string.format("LSF|%s|E|%d", runId, #list))
	return string.format("StudioSync fingerprints %s: %d scripts", runId, #list)
end

-- data packs (sync.py blob): pack:blob(name) -> buffer with the file's exact bytes; pack:names(); pack:close()
function StudioSync.open(packName: string)
	local root, index = loadPack(packName)
	local pack = {}
	function pack:names(): { string }
		local names = {}
		for _, e in ipairs(index.entries) do
			if e.kind == "blob" then
				table.insert(names, e.name)
			end
		end
		return names
	end
	function pack:info(name: string): any
		for _, e in ipairs(index.entries) do
			if e.kind == "blob" and e.name == name then
				return e
			end
		end
		return nil
	end
	function pack:blob(name: string, verify: boolean?): buffer
		local e = pack:info(name)
		if not e then
			error("StudioSync: no blob named " .. name .. " in pack " .. packName)
		end
		local b = entryBytes(root, e.i, e.chunks)
		if buffer.len(b) ~= e.bytes then
			error(string.format("StudioSync: blob %s is %d bytes, the pack says %d", name, buffer.len(b), e.bytes))
		end
		if verify ~= false and StudioSync.fnvBuffer(b) ~= e.fnv then
			error("StudioSync: blob " .. name .. " does not match its fingerprint")
		end
		return b
	end
	function pack:close()
		root:Destroy()
	end
	return pack
end

return StudioSync
