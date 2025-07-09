
<h1 align="center">🔁 RateManager</h1>
<p align="center">
  A lightweight utility for handling <strong>cooldowns</strong> and <strong>rate limits</strong> in Roblox Lua.
</p>
<p align="center">
  Debounce, rolling limits, queueing, pause/resume, and more: all in one clean module.
</p>

---

## 🚀 Features

- ⏱️ Debounce (classic cooldown)
- 🔁 RateLimit (e.g. 10 calls per 60 seconds)
- 🧱 Optional call queueing (RateLimit only)
- ⏸️ Pause & Resume
- 🔄 Manual `Reset()` and `Cancel()` (with queue control)
- 🔔 Signals: `OnReset`, `OnLimitHit`
- 📦 Self-contained, no external dependencies
- 🧼 MIT licensed

---

## 📦 Installation

### Manual

1. Drop `RateManager.lua` into your project (e.g. `ReplicatedStorage.Packages`)
2. Require it in your scripts:

```lua
local RateManager = require(game.ReplicatedStorage.Packages.RateManager)
```

---

## 🔨 Example Usage

### 🕒 Debounce (Cooldown that ignores spam)

```lua
local cooldown = RateManager.new(2) -- 2 second cooldown

button.MouseButton1Click:Connect(function()
	cooldown:Execute(function()
		print("Clicked!") -- Fires once every 2 seconds max
	end)
end)
```

---

### 🔁 RateLimit (e.g. 5 calls per 10 seconds)

```lua
local limiter = RateManager.new(5, 10, RateManager.Mode.RateLimit)

RunService.Heartbeat:Connect(function()
	limiter:Execute(function()
		print("Allowed!")
	end)
end)
```

---

### 🧱 Queueing (for RateLimit)

```lua
limiter:SetQueueEnabled(true)
```

> Excess calls will be queued instead of dropped

---

### ⏸️ Pause / Resume

```lua
limiter:Pause()
wait(5)
limiter:Resume()
```

---

### ⚠️ Reset vs Cancel

```lua
cooldown:Reset()      -- Ends timer and fires OnReset
cooldown:Cancel()     -- Ends timer silently

cooldown:Reset(true)  -- Ends and clears queued calls (RateLimit only)
cooldown:Cancel(true) -- Cancels and clears queue (no OnReset)
```

---

### 🔔 Events

```lua
cooldown.OnReset:Connect(function()
	print("Cooldown/rate limit reset!")
end)

cooldown.OnLimitHit:Connect(function()
	print("Call was blocked (cooldown active or limit hit)")
end)
```

---

## 📚 API

```lua
RateManager.new(delayOrMaxCalls: number, perSeconds?: number, mode?: RateManager.Mode) → RateManager
```

| Method                            | Description                                                  |
|-----------------------------------|--------------------------------------------------------------|
| `:Execute(func, ...)`             | Executes the callback if allowed                             |
| `:Reset(dropQueuedCalls?)`        | Ends cooldown/rate window and fires `OnReset`                |
| `:Cancel(dropQueuedCalls?)`       | Ends it silently, skips `OnReset`                            |
| `:Pause()` / `:Resume()`          | Temporarily pause/resume timer logic                         |
| `:IsOnCooldown()`                 | Returns true if currently blocked                            |
| `:GetTimeLeft()`                  | Returns remaining cooldown time (in seconds)                 |
| `:SetQueueEnabled(enabled: bool)` | Enables queueing (RateLimit mode only)                       |
| `:Destroy()`                      | Cleans up signals and state                                  |

| Event             | Description                                 |
|-------------------|---------------------------------------------|
| `OnReset`         | Fires when timer or rate window is reset    |
| `OnLimitHit`      | Fires when a call is blocked by cooldown    |

---

## 📎 Links

- 🔗 [Creator Store](https://create.roblox.com/store/asset/110870034905030/RateManager)
- 🧵 [DevForum Post](https://devforum.roblox.com/t/new-ratemanager-cooldown-rate-limiting-utility-debounce-rolling-limit-queued-calls-pause-resume/3803316)

---

## 🧩 Final Notes

RateManager was built to simplify cooldown and rate-limiting logic in Roblox without bloating your code. It’s clean, event-based, and flexible for nearly any input-related system.

Suggestions and contributions are always welcome.
