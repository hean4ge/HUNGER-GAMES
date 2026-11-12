--[[
	Signal - a tiny event object for Luau code (no Instances).
	local s = Signal.new(); local c = s:Connect(fn); s:Fire(...); c:Disconnect(); s:Once(fn); s:Wait()
	Handlers run in their own thread (task.spawn), so one erroring handler can't break the others.
]]
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handler = { fn = fn, connected = true }
	local handlers = self._handlers
	table.insert(handlers, handler)
	local connection = { Connected = true }
	function connection.Disconnect()
		if not handler.connected then
			return
		end
		handler.connected = false
		connection.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Once(fn: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local snapshot = table.clone(self._handlers)
	for _, handler in ipairs(snapshot) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, handler in ipairs(self._handlers) do
		handler.connected = false
	end
	table.clear(self._handlers)
end

return Signal
