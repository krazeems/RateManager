--!nocheck

--[[
	@RateManager.lua (PACKAGE)
	krazeems @ 2025

	A small, cooldown utility for Roblox Lua.
	Supports Debounce and advanced RateLimit behavior for preventing input spam.

	-->> MODES <<--

	• Debounce (default):
	  → Only allows a function to run once per cooldown.
	  → Ignores all triggers while the cooldown is active.
	  → Example: clicking a button quickly will only fire once.

	• RateLimit:
	  → Allows up to maxCalls per perSeconds period.
	  → Tracks calls in a rolling time window and blocks excess calls.
	  → Optionally queues calls instead of dropping.
	  → Example: limiting a remote to 10 uses per minute.
	  
	  
	  
	  
	  
	-->> Methods <<--

	• RateManager.new(delayOrMaxCalls: number, perSeconds?: number, mode?: RateManager.Mode) → RateManager
	  Creates a new RateManager instance.
	  - Debounce mode (default): delayOrMaxCalls is cooldown seconds.
	  - RateLimit mode: delayOrMaxCalls is max calls per perSeconds seconds.

	• RateManager:Execute(func: function, ...: any)
	  Runs the given function if cooldown or rate limit allows.
	  - Fires OnLimitHit if blocked.
	  - Queues call if queuing enabled (RateLimit mode).

	• RateManager:Reset(dropQueuedCalls?: boolean)
	  Resets cooldown or rate limit and optionally clears queued calls.
	  - Fires OnReset.
	  - If dropQueuedCalls is true (default: true), queued calls are cleared.  (for rate limit debouces)

	• RateManager:Cancel(dropQueuedCalls?: boolean)
	  Cancels cooldown or rate limit without firing OnReset.
	  - If dropQueuedCalls is true (default: true), queued calls are cleared. (for rate limit debouces)

	• RateManager:IsOnCooldown() → boolean
	  Returns true if currently blocked by cooldown or rate limit.

	• RateManager:GetTimeLeft() → number
	  Returns seconds remaining until cooldown or rate limit resets.
	  - 0 if ready to run immediately.

	• RateManager:Pause()
	  Pauses the cooldown or rate limit timer.

	• RateManager:Resume()
	  Resumes a paused cooldown or rate limit timer.

	• RateManager:SetQueueEnabled(enabled: boolean)
	  Enables/disables queuing calls when rate limit is hit (RateLimit mode).

	• RateManager:Destroy()
	  Cleans up internal state and disconnects events.

	-->> Events <<--

	• RateManager.OnReset:Connect(fn)
	  Fired when cooldown or rate limit resets or is manually reset.

	• RateManager.OnLimitHit:Connect(fn)
	  Fired when a call is blocked due to active cooldown or rate limit.
	  
	  
	  
	  
	  

	-->> USAGE/EXAMPLES <<--

	local RateManager = require(ReplicatedStorage.Packages.RateManager)

	-->> DEBOUNCE MODE (default) <<--
	local cd = RateManager.new(2) -- 2 seconds cooldown
	cd.OnLimitHit:Connect(function()
		print("Tried to call but cooldown active!")
	end)
	
	cd.onReset:Connect(function()
		print('Cooldown has been reset, do whatever you want now')
	end)
	
	while true do
		wait(0.5) -- spam every half second
		cd:Execute(function()
			print("Runs once, then waits 2 seconds cooldown")
		end)
	end


	-->> RATE-LIMIT MODE <<--
	local rateLimit = RateManager.new(3, 5, RateManager.Mode.RateLimit) -- allow max 3 calls per 5 seconds
	rateLimit:SetQueueEnabled(true) -- queue calls instead of dropping when rate limit is hit
	rateLimit.OnLimitHit:Connect(function()
		print("Rate limit hit! Call queued or ignored.")
	end)
	
	rateLimit.onReset:Connect(function()
		print('Cooldown has been reset, do whatever you want now')
	end)

	local count = 0
	while true do
		wait(1)
		rateLimit:Execute(function()
			count += 1
			print("Allowed call number " .. count)
		end)
	end



	

	DEPENDENCIES:
	• [Signal](https://github.com/Sleitnick/RbxUtil)

	MIT License. Use it. Fork it. Whatever.
]]

local Signal = require(script.signal)

local Mode = {
	Debounce = 1,
	RateLimit = 2,
}

local RateManager = {}
RateManager.__index = RateManager
RateManager.Mode = Mode


--[[
	Creates a new rateManager object
	
	@param delayOrMaxCalls number: the maximum amount of calls allowed if using RateLimit mode or the cooldown if using cooldown mode (in seconds)
	@param perSeconds number: the number of seconds the maxCalls applies to (only applies in RateLimit mode)
	@param mode RateManager.Mode: The mode of the rate manager (defaults to debounce mode)
	
	@return RateManager object
]]
function RateManager.new(delayOrMaxCalls:number, perSeconds:number, mode:number) 
	mode = mode or Mode.Debounce
	local self = setmetatable({}, RateManager)

	self.mode = mode
	self.OnReset = Signal.new()
	self.OnLimitHit = Signal.new()
	self._paused = false
	self._queueEnabled = false
	self._queuedCalls = {}

	if mode == Mode.Debounce then
		assert(type(delayOrMaxCalls) == "number" and delayOrMaxCalls > 0, "Delay must be > 0")
		self.delay = delayOrMaxCalls
		self.active = false
		self._pauseStart = nil
		self._pauseRemaining = nil
		self._lastStartTime = nil
	elseif mode == Mode.RateLimit then
		assert(type(delayOrMaxCalls) == "number" and delayOrMaxCalls > 0, "maxCalls must be > 0")
		assert(type(perSeconds) == "number" and perSeconds > 0, "perSeconds must be > 0")
		self.maxCalls = delayOrMaxCalls
		self.perSeconds = perSeconds
		self.callTimestamps = {}
		self._queueEnabled = false
		self._queuedCalls = {}
	else
		error("Invalid mode")
	end

	return self
end

local function cleanupOldTimestamps(self, now)
	while #self.callTimestamps > 0 and now - self.callTimestamps[1] > self.perSeconds do
		table.remove(self.callTimestamps, 1)
	end
end

--[[
	Enables or disables the queuing system for RateLimit mode
	Queuing allows calls that could not be executed to be executed at a later time when the cooldown is over.
	
	@param enabled boolean: If true, enables queuing. If false, disables queuing.
]]
function RateManager:SetQueueEnabled(enabled)
	self._queueEnabled = enabled and true or false
	-- If queue disabled, flush queued calls
	if not self._queueEnabled then
		self._queuedCalls = {}
	end
end

function RateManager:_tryProcessQueue()
	if self.mode ~= Mode.RateLimit or not self._queueEnabled or self._paused then return end

	local now = os.clock()
	cleanupOldTimestamps(self, now)

	while #self._queuedCalls > 0 and #self.callTimestamps < self.maxCalls do
		local queuedFunc, args = table.unpack(table.remove(self._queuedCalls, 1))
		table.insert(self.callTimestamps, now)
		coroutine.wrap(function() queuedFunc(table.unpack(args)) end)()
	end
end

--[[
	Executes the given function if cooldown or rate limit allows.
	If rate limit queue is enabled, will queue calls instead of dropping.

	@param func function: callback to run
	@param ... any: arguments to func

	@return self
]]
function RateManager:Execute(func, ...) 
	if self._paused then return self end

	local now = os.clock()

	if self.mode == Mode.Debounce then
		if self.active then
			self.OnLimitHit:Fire()
			return self
		end

		self.active = true
		self._lastStartTime = now
		task.delay(self.delay, function()
			if self._paused then
				-- cooldown paused, do nothing here
				return
			end
			self.active = false
			self.OnReset:Fire()
		end)

		func(...)
		return self
	end

	-- RateLimit mode
	cleanupOldTimestamps(self, now)

	if #self.callTimestamps >= self.maxCalls then
		self.OnLimitHit:Fire()

		if self._queueEnabled then
			-- Queue the call (store func and args)
			table.insert(self._queuedCalls, {func, {...}})
		end
		return self
	end

	table.insert(self.callTimestamps, now)
	func(...)

	-- Fire OnReset after perSeconds delay from this call
	task.delay(self.perSeconds, function()
		if self._paused then return end
		cleanupOldTimestamps(self, os.clock())
		self.OnReset:Fire()
		-- Try to run queued calls
		self:_tryProcessQueue()
	end)

	return self
end

--[[
	Returns seconds remaining in cooldown or rate limit window, or 0 if ready.
	@return number seconds left
]]
function RateManager:GetTimeLeft() : number
	if self._paused then return math.huge end

	local now = os.clock()
	if self.mode == Mode.Debounce then
		if not self.active or not self._lastStartTime then return 0 end
		local elapsed = now - self._lastStartTime
		return math.max(self.delay - elapsed, 0)
	elseif self.mode == Mode.RateLimit then
		cleanupOldTimestamps(self, now)
		if #self.callTimestamps < self.maxCalls then return 0 end
		-- Time left is when the oldest timestamp expires
		local oldest = self.callTimestamps[1]
		return math.max(self.perSeconds - (now - oldest), 0)
	end
	return 0
end

--[[
	Pauses the cooldown or rate limit timer.

	@return self
]]
function RateManager:Pause()
	if self._paused then return self end

	self._paused = true

	if self.mode == Mode.Debounce and self.active then
		local now = os.clock()
		local elapsed = now - (self._lastStartTime or now)
		self._pauseRemaining = math.max(self.delay - elapsed, 0)
		self._pauseStart = now
	end

	return self
end

--[[
	Resumes the cooldown or rate limit timer.

	@return self
]]
function RateManager:Resume()
	if not self._paused then return self end
	self._paused = false

	if self.mode == Mode.Debounce and self.active and self._pauseRemaining then
		-- Resume cooldown delay from where it left off
		task.delay(self._pauseRemaining, function()
			if self._paused then return end
			self.active = false
			self.OnReset:Fire()
		end)
	end

	-- For rate limit mode, queued calls will be processed automatically as time passes

	return self
end

--[[
	Manually resets the cooldown or rate limit window.
	Optionally drops any queued calls (RateLimit mode).

	@param dropQueuedCalls boolean? - If true (default), clears queued calls. (RateLimit mode only)

	@return self
]]
function RateManager:Reset(dropQueuedCalls)
	dropQueuedCalls = if dropQueuedCalls == nil then true else dropQueuedCalls

	if self.mode == Mode.Debounce then
		self.active = false
		self._pauseRemaining = nil
		self._lastStartTime = nil
	elseif self.mode == Mode.RateLimit then
		self.callTimestamps = {}
		if dropQueuedCalls then
			self._queuedCalls = {}
		end
	end
	self.OnReset:Fire()
	return self
end

--[[
	Cancels cooldown or rate limit without firing OnReset.
	Optionally drops any queued calls (RateLimit mode).

	@param dropQueuedCalls boolean? - If true (default), clears queued calls. (RateLimit mode only)

	@return self
]]
function RateManager:Cancel(dropQueuedCalls)
	dropQueuedCalls = if dropQueuedCalls == nil then true else dropQueuedCalls

	if self.mode == Mode.Debounce then
		self.active = false
		self._pauseRemaining = nil
		self._lastStartTime = nil
	elseif self.mode == Mode.RateLimit then
		self.callTimestamps = {}
		if dropQueuedCalls then
			self._queuedCalls = {}
		end
	end
	return self
end

--[[
	Returns whether the cooldown or rate limit is active.

	@return boolean
]]
function RateManager:IsOnCooldown() : boolean
	if self._paused then return false end

	local now = os.clock()
	if self.mode == Mode.Debounce then
		return self.active
	elseif self.mode == Mode.RateLimit then
		cleanupOldTimestamps(self, now)
		return #self.callTimestamps >= self.maxCalls
	end
	return false
end

--[[
	Destroys the instance, cleaning up signals and state.
]]
function RateManager:Destroy()
	if self.OnReset then
		self.OnReset:Destroy()
		self.OnReset = nil
	end
	if self.OnLimitHit then
		self.OnLimitHit:Destroy()
		self.OnLimitHit = nil
	end
	self.active = nil
	self.delay = nil
	self.maxCalls = nil
	self.perSeconds = nil
	self.callTimestamps = nil
	self._queuedCalls = nil
	self.mode = nil
	self._paused = nil
	self._queueEnabled = nil
	self._pauseRemaining = nil
	self._pauseStart = nil
	self._lastStartTime = nil
end

return RateManager
