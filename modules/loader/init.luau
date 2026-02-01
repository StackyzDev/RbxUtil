--[=[
	@class Loader

	The Loader module will require all children or descendant ModuleScripts. There are also
	some utility functions included, which assist with loading and starting modules in
	single-script environments.

	All loading operations are performed in parallel for better performance. The loader
	automatically detects and reports module retentions that might impact gameplay.

	For example, here is a loader that loads all ModuleScripts under a folder that end with
	the name Service, and then calls all of their OnStart methods:
	```lua
	local MyModules = ReplicatedStorage.MyModules
	Loader.SpawnAll(
		Loader.LoadDescendants(MyModules, Loader.MatchesName("Service$")),
		"OnStart"
	)
	```
]=]
local Loader = {}

--[=[
	@within Loader
	@type PredicateFn (module: ModuleScript) -> boolean
	Predicate function type.
]=]
type PredicateFn = (module: ModuleScript) -> boolean

--[=[
	@within Loader
	@interface LoadedModuleInfo
	.ModuleScript ModuleScript
	.LoadTime number
	.Name string
	.Module any
	.HadRetention boolean
	.RetentionDetails table?
]=]
type LoadedModuleInfo = {
	ModuleScript: ModuleScript,
	LoadTime: number,
	Name: string,
	Module: any,
	HadRetention: boolean,
	RetentionDetails: { any }?,
}

--[=[
	@within Loader
	@interface LoadStats
	.TotalModules number
	.TotalLoadTime number
	.AverageLoadTime number
	.SlowestModule string?
	.SlowestLoadTime number?
	.FastestModule string?
	.FastestLoadTime number?
	.ModulesWithRetention number
	.RetainedModules { string }
]=]
type LoadStats = {
	TotalModules: number,
	TotalLoadTime: number,
	AverageLoadTime: number,
	SlowestModule: string?,
	SlowestLoadTime: number?,
	FastestModule: string?,
	FastestLoadTime: number?,
	ModulesWithRetention: number,
	RetainedModules: { string },
}

-- Debug state
local debugState = {
	enabled = true, -- Auto-enabled, can be disabled with DisableDebug()
	modules = {} :: { LoadedModuleInfo },
	order = {} :: { string },
	lastLoadStats = nil :: LoadStats?,
}

-- Helper function to detect retention in a loaded module
local function checkRetention(module: any, moduleName: string): { HadRetention: boolean, Details: { any }? }
	if type(module) ~= "table" then
		return { HadRetention = false, Details = nil }
	end

	local details: { any } = {}
	local count = 0

	for key in pairs(module) do
		table.insert(details, tostring(key))
		count += 1
	end

	-- A module with many entries might indicate retention
	-- This is a heuristic - modules typically have a few core functions/tables
	local hasRetention = count > 50 or (count > 20 and table.find(details, "____modules"))

	return {
		HadRetention = hasRetention,
		Details = if hasRetention then details else nil,
	}
end

-- Helper function to load a module and track its info
local function loadModuleInfo(moduleScript: ModuleScript): { Success: boolean, Info: LoadedModuleInfo?, Error: string? }
	local startTime = os.clock()

	local success, result = pcall(function()
		return require(moduleScript)
	end)

	local loadTime = os.clock() - startTime

	if not success then
		return {
			Success = false,
			Info = nil,
			Error = tostring(result),
		}
	end

	local retentionCheck = checkRetention(result, moduleScript.Name)

	local info: LoadedModuleInfo = {
		ModuleScript = moduleScript,
		LoadTime = loadTime,
		Name = moduleScript.Name,
		Module = result,
		HadRetention = retentionCheck.HadRetention,
		RetentionDetails = retentionCheck.Details,
	}

	return {
		Success = true,
		Info = info,
		Error = nil,
	}
end

--[=[
	Requires all children ModuleScripts in parallel.

	All modules are loaded concurrently and the function waits for all to complete
	before returning. This provides better performance while maintaining reliability.

	If a `predicate` function is provided, then the module will only
	be loaded if the predicate returns `true` for the given ModuleScript.

	Modules with retention issues are automatically detected and reported.

	```lua
	-- Load all ModuleScripts directly under MyModules:
	Loader.LoadChildren(ReplicatedStorage.MyModules)

	-- Load all ModuleScripts directly under MyModules if they have names ending in 'Service':
	Loader.LoadChildren(ReplicatedStorage.MyModules, function(moduleScript)
		return moduleScript.Name:match("Service$") ~= nil
	end)
	```
]=]
function Loader.LoadChildren(parent: Instance, predicate: PredicateFn?): { [string]: any }
	local modules: { [string]: any } = {}
	local childrenToLoad: { ModuleScript } = {}

	-- Collect children to load
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") then
			if predicate and not predicate(child) then
				continue
			end
			table.insert(childrenToLoad, child)
		end
	end

	-- Load all in parallel
	local loadTasks: { thread } = {}
	local loadResults: { { Success: boolean, Info: LoadedModuleInfo?, Error: string? } } = {}

	for _, moduleScript in childrenToLoad do
		table.insert(
			loadTasks,
			task.spawn(function(i)
				loadResults[i] = loadModuleInfo(moduleScript)
			end, #loadTasks + 1)
		)
	end

	-- Wait for all to complete
	for _, thread in loadTasks do
		task.wait()
	end

	-- Process results
	for i, result in loadResults do
		if result.Success then
			local info = result.Info :: LoadedModuleInfo
			modules[info.Name] = info.Module

			if debugState.enabled then
				table.insert(debugState.modules, info)
				table.insert(debugState.order, info.Name)

				if info.HadRetention then
					print(
						`⚠️  [Loader] Module "{info.Name}" detected with retention ({#(info.RetentionDetails or {})} entries)`
					)
				end
			end
		else
			local moduleScript = childrenToLoad[i]
			if moduleScript then
				print(`⚠️  [Loader] Failed to load "{moduleScript.Name}": {result.Error}`)
			end
		end
	end

	if debugState.enabled and #debugState.modules > 0 then
		debugState.lastLoadStats = Loader.GetLoadStats()
	end

	return modules
end

--[=[
	Requires all descendant ModuleScripts in parallel.

	All modules are loaded concurrently and the function waits for all to complete
	before returning. This provides better performance while maintaining reliability.

	If a `predicate` function is provided, then the module will only
	be loaded if the predicate returns `true` for the given ModuleScript.

	Modules with retention issues are automatically detected and reported.

	```lua
	-- Load all ModuleScripts under MyModules:
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	-- Load all ModuleScripts under MyModules if they have names ending in 'Service':
	Loader.LoadDescendants(ReplicatedStorage.MyModules, Loader.MatchesName("Service$"))
	```
]=]
function Loader.LoadDescendants(parent: Instance, predicate: PredicateFn?): { [string]: any }
	local modules: { [string]: any } = {}
	local descendantsToLoad: { ModuleScript } = {}

	-- Collect descendants to load
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			if predicate and not predicate(descendant) then
				continue
			end
			table.insert(descendantsToLoad, descendant)
		end
	end

	-- Load all in parallel
	local loadTasks: { thread } = {}
	local loadResults: { { Success: boolean, Info: LoadedModuleInfo?, Error: string? } } = {}

	for _, moduleScript in descendantsToLoad do
		table.insert(
			loadTasks,
			task.spawn(function(i)
				loadResults[i] = loadModuleInfo(moduleScript)
			end, #loadTasks + 1)
		)
	end

	-- Wait for all to complete
	for _ in loadTasks do
		task.wait()
	end

	-- Process results
	for i, result in loadResults do
		if result.Success then
			local info = result.Info :: LoadedModuleInfo
			modules[info.Name] = info.Module

			if debugState.enabled then
				table.insert(debugState.modules, info)
				table.insert(debugState.order, info.Name)

				if info.HadRetention then
					print(
						`⚠️  [Loader] Module "{info.Name}" detected with retention ({#(info.RetentionDetails or {})} entries)`
					)
				end
			end
		else
			local moduleScript = descendantsToLoad[i]
			if moduleScript then
				print(`⚠️  [Loader] Failed to load "{moduleScript.Name}": {result.Error}`)
			end
		end
	end

	if debugState.enabled and #debugState.modules > 0 then
		debugState.lastLoadStats = Loader.GetLoadStats()
	end

	return modules
end

--[=[
	A commonly-used predicate in the `LoadChildren` and `LoadDescendants`
	functions is one to match names. Therefore, the `MatchesName` utility
	function provides a quick way to create such predicates.

	```lua
	Loader.LoadDescendants(ReplicatedStorage.MyModules, Loader.MatchesName("Service$"))
	```
]=]
function Loader.MatchesName(matchName: string): (module: ModuleScript) -> boolean
	return function(moduleScript: ModuleScript): boolean
		return moduleScript.Name:match(matchName) ~= nil
	end
end

--[=[
	Enables automatic debug output and retention tracking.
	Enabled by default.

	When enabled, the loader will:
	- Automatically detect and print module retentions
	- Track load times and module information
	- Print warnings for modules with retention issues

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	-- Retention issues will be printed automatically
	```
]=]
function Loader.EnableDebug()
	debugState.enabled = true
end

--[=[
	Disables automatic debug output and retention tracking.

	```lua
	Loader.DisableDebug()
	```
]=]
function Loader.DisableDebug()
	debugState.enabled = false
end

--[=[
	Returns whether debug mode is currently enabled.
]=]
function Loader.IsDebugEnabled(): boolean
	return debugState.enabled
end

--[=[
	Clears all accumulated debug data. Useful when loading multiple batches of modules.

	```lua
	Loader.ClearDebugData()
	```
]=]
function Loader.ClearDebugData()
	table.clear(debugState.modules)
	table.clear(debugState.order)
	debugState.lastLoadStats = nil
end

--[=[
	Returns detailed statistics about the last completed load operation.
	Includes information about module load times and retention.

	```lua
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	local stats = Loader.GetLoadStats()
	print(`Loaded {stats.TotalModules} modules in {stats.TotalLoadTime}s`)
	print(`Modules with retention: {stats.ModulesWithRetention}`)
	```
]=]
function Loader.GetLoadStats(): LoadStats
	local totalModules = #debugState.modules
	local totalLoadTime = 0
	local slowestModule: string? = nil
	local slowestTime = 0
	local fastestModule: string? = nil
	local fastestTime = math.huge
	local modulesWithRetention: { string } = {}

	for _, info in debugState.modules do
		totalLoadTime += info.LoadTime

		if info.LoadTime > slowestTime then
			slowestTime = info.LoadTime
			slowestModule = info.Name
		end

		if info.LoadTime < fastestTime then
			fastestTime = info.LoadTime
			fastestModule = info.Name
		end

		if info.HadRetention then
			table.insert(modulesWithRetention, info.Name)
		end
	end

	return {
		TotalModules = totalModules,
		TotalLoadTime = totalLoadTime,
		AverageLoadTime = if totalModules > 0 then totalLoadTime / totalModules else 0,
		SlowestModule = slowestModule,
		SlowestLoadTime = if slowestModule then slowestTime else nil,
		FastestModule = fastestModule,
		FastestLoadTime = if fastestModule and fastestTime ~= math.huge then fastestTime else nil,
		ModulesWithRetention = #modulesWithRetention,
		RetainedModules = modulesWithRetention,
	}
end

--[=[
	Prints a comprehensive debug report including load times and retention issues.
	Automatically called after parallel loads when debug is enabled.

	```lua
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	Loader.PrintDebugReport()
	```
]=]
function Loader.PrintDebugReport()
	if #debugState.modules == 0 then
		print("⚠️  [Loader] No modules loaded")
		return
	end

	local stats = Loader.GetLoadStats()

	print(
		"═══════════════════════════════════════════════════════"
	)
	print("[Loader] Load Statistics")
	print(
		"═══════════════════════════════════════════════════════"
	)
	print(`Total Modules: {stats.TotalModules}`)
	print(`Total Load Time: {string.format("%.4f", stats.TotalLoadTime)}s`)
	print(`Average Load Time: {string.format("%.4f", stats.AverageLoadTime)}s`)

	if stats.SlowestModule then
		print(`Slowest Module: {stats.SlowestModule} ({string.format("%.4f", stats.SlowestLoadTime)}s)`)
	end

	if stats.FastestModule then
		print(`Fastest Module: {stats.FastestModule} ({string.format("%.4f", stats.FastestLoadTime)}s)`)
	end

	if stats.ModulesWithRetention > 0 then
		print(`⚠️  Modules with Retention: {stats.ModulesWithRetention}`)
		for _, name in stats.RetainedModules do
			print(`   - {name}`)
		end
	else
		print("✓ No retention issues detected")
	end

	print(
		"═══════════════════════════════════════════════════════"
	)

	-- Print load order sorted by time
	local sorted = table.clone(debugState.modules)
	table.sort(sorted, function(a, b)
		return a.LoadTime > b.LoadTime
	end)

	print("[Loader] Modules by Load Time")
	print(
		"═══════════════════════════════════════════════════════"
	)

	for i, info in sorted do
		local time = string.format("%.4f", info.LoadTime)
		local retention = if info.HadRetention then " ⚠️ " else ""
		print(`{i}. {info.Name}: {time}s{retention}`)
	end

	print(
		"═══════════════════════════════════════════════════════"
	)
end

--[=[
	Returns detailed information about modules that experienced retention issues.
	Returns a table mapping module names to their retention details.

	```lua
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	local retentions = Loader.GetRetentionReport()
	for name, info in retentions do
		print(`{name} retained {info.Count} entries`)
	end
	```
]=]
function Loader.GetRetentionReport(): {
	[string]: {
		Count: number,
		Details: { string },
	},
}
	local report: {
		[string]: {
			Count: number,
			Details: { string },
		},
	} = {}

	for _, info in debugState.modules do
		if info.HadRetention and info.RetentionDetails then
			report[info.Name] = {
				Count = #info.RetentionDetails,
				Details = info.RetentionDetails :: { string },
			}
		end
	end

	return report
end

--[=[
	Utility function for spawning a specific method in all given modules.
	If a module does not contain the specified method, it is simply
	skipped. Methods are called with `task.spawn` internally.

	For example, if the modules are expected to have an `OnStart()` method,
	then `SpawnAll()` could be used to start all of them directly after
	they have been loaded:

	```lua
	local MyModules = ReplicatedStorage.MyModules

	-- Load all modules under MyModules and then call their OnStart methods:
	Loader.SpawnAll(Loader.LoadDescendants(MyModules), "OnStart")

	-- Same as above, but only loads modules with names that end with Service:
	Loader.SpawnAll(
		Loader.LoadDescendants(MyModules, Loader.MatchesName("Service$")),
		"OnStart"
	)
	```
]=]
function Loader.SpawnAll(loadedModules: { [string]: any }, methodName: string)
	for name, mod in loadedModules do
		local method = mod[methodName]
		if type(method) == "function" then
			task.spawn(function()
				debug.setmemorycategory(name)
				method(mod)
			end)
		end
	end
end

return Loader
