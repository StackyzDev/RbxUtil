--[=[
	@class Loader

	The Loader module will require all children or descendant ModuleScripts. There are also
	some utility functions included, which assist with loading and starting modules in
	single-script environments.

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
]=]
type LoadedModuleInfo = {
	ModuleScript: ModuleScript,
	LoadTime: number,
	Name: string,
	Module: any,
}

-- Debug tracking
local DEBUG_ENABLED = false
local loadedModules: { LoadedModuleInfo } = {}
local loadOrder: { string } = {}

--[=[
	Requires all children ModuleScripts.

	If a `predicate` function is provided, then the module will only
	be loaded if the predicate returns `true` for the the given
	ModuleScript.

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
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") then
			if predicate and not predicate(child) then
				continue
			end
			local startTime = if DEBUG_ENABLED then os.clock() else 0
			local m = require(child)
			modules[child.Name] = m

			if DEBUG_ENABLED then
				local loadTime = os.clock() - startTime
				table.insert(loadedModules, {
					ModuleScript = child,
					LoadTime = loadTime,
					Name = child.Name,
					Module = m,
				})
				table.insert(loadOrder, child.Name)
			end
		end
	end
	return modules
end

--[=[
	Requires all descendant ModuleScripts.

	If a `predicate` function is provided, then the module will only
	be loaded if the predicate returns `true` for the the given
	ModuleScript.

	```lua
	-- Load all ModuleScripts under MyModules:
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	-- Load startTime = if DEBUG_ENABLED then os.clock() else 0
			local m = require(descendant)
			modules[descendant.Name] = m

			if DEBUG_ENABLED then
				local loadTime = os.clock() - startTime
				table.insert(loadedModules, {
					ModuleScript = descendant,
					LoadTime = loadTime,
					Name = descendant.Name,
					Module = m,
				})
				table.insert(loadOrder, descendant.Name)
			endtedStorage.MyModules, function(moduleScript)
		return moduleScript.Name:match("Service$") ~= nil
	end)
]=]
function Loader.LoadDescendants(parent: Instance, predicate: PredicateFn?): { [string]: any }
	local modules: { [string]: any } = {}
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			if predicate and not predicate(descendant) then
				continue
			end
			local m = require(descendant)
			modules[descendant.Name] = m
		end
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
	Enables debug tracking for the loader. When enabled, the loader will
	track all loaded modules, their load times, and load order.

	```lua
	-- Enable debug mode:
	Loader.EnableDebug()

	-- Load modules:
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	-- Get statistics:
	print(Loader.GetLoadStats())
	```
]=]
function Loader.EnableDebug()
	DEBUG_ENABLED = true
end

--[=[
	Disables debug tracking for the loader.
]=]
function Loader.DisableDebug()
	DEBUG_ENABLED = false
end

--[=[
	Returns whether debug tracking is enabled.
]=]
function Loader.IsDebugEnabled(): boolean
	return DEBUG_ENABLED
end

--[=[
	Clears all debug tracking data.
]=]
function Loader.ClearDebugData()
	table.clear(loadedModules)
	table.clear(loadOrder)
end

--[=[
	Returns a list of all loaded modules with their information.
	Only works if debug mode is enabled.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	for _, info in Loader.GetLoadedModules() do
		print(info.Name, "loaded in", info.LoadTime, "seconds")
	end
	```
]=]
function Loader.GetLoadedModules(): { LoadedModuleInfo }
	return table.clone(loadedModules)
end

--[=[
	Returns the order in which modules were loaded.
	Only works if debug mode is enabled.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	print("Load order:", table.concat(Loader.GetLoadOrder(), ", "))
	```
]=]
function Loader.GetLoadOrder(): { string }
	return table.clone(loadOrder)
end

--[=[
	Returns statistics about loaded modules.
	Only works if debug mode is enabled.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	local stats = Loader.GetLoadStats()
	print("Total modules:", stats.TotalModules)
	print("Total load time:", stats.TotalLoadTime)
	print("Average load time:", stats.AverageLoadTime)
	print("Slowest module:", stats.SlowestModule)
	```
]=]
function Loader.GetLoadStats(): {
	TotalModules: number,
	TotalLoadTime: number,
	AverageLoadTime: number,
	SlowestModule: string?,
	SlowestLoadTime: number?,
	FastestModule: string?,
	FastestLoadTime: number?,
}
	local totalModules = #loadedModules
	local totalLoadTime = 0
	local slowestModule: string? = nil
	local slowestTime = 0
	local fastestModule: string? = nil
	local fastestTime = math.huge

	for _, info in loadedModules do
		totalLoadTime += info.LoadTime

		if info.LoadTime > slowestTime then
			slowestTime = info.LoadTime
			slowestModule = info.Name
		end

		if info.LoadTime < fastestTime then
			fastestTime = info.LoadTime
			fastestModule = info.Name
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
	}
end

--[=[
	Returns a detailed report of all loaded modules, sorted by load time.
	Only works if debug mode is enabled.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	print(Loader.GetLoadReport())
	```
]=]
function Loader.GetLoadReport(): string
	if #loadedModules == 0 then
		return "No modules loaded (debug mode might be disabled)"
	end

	local sorted = table.clone(loadedModules)
	table.sort(sorted, function(a, b)
		return a.LoadTime > b.LoadTime
	end)

	local lines = { "=== Loader Report ===" }
	table.insert(lines, `Total Modules: {#loadedModules}`)

	local stats = Loader.GetLoadStats()
	table.insert(lines, `Total Load Time: {string.format("%.4f", stats.TotalLoadTime)}s`)
	table.insert(lines, `Average Load Time: {string.format("%.4f", stats.AverageLoadTime)}s`)
	table.insert(lines, "")
	table.insert(lines, "Modules by Load Time:")

	for i, info in sorted do
		local time = string.format("%.4f", info.LoadTime)
		table.insert(lines, `{i}. {info.Name}: {time}s`)
	end

	return table.concat(lines, "\n")
end

--[=[
	Returns information about module retentions by analyzing the loaded modules.
	This provides insight into which modules are being held in memory and by what.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)

	local retentions = Loader.GetRetentions()
	for moduleName, info in retentions do
		print(moduleName, "has", info.ReferenceCount, "direct references")
	end
	```
]=]
function Loader.GetRetentions(): { [string]: { ReferenceCount: number, ModuleScript: ModuleScript } }
	local retentions: { [string]: { ReferenceCount: number, ModuleScript: ModuleScript } } = {}

	for _, info in loadedModules do
		local refs = 0
		local module = info.Module

		-- Count table references
		if type(module) == "table" then
			for _ in pairs(module) do
				refs += 1
			end
		end

		retentions[info.Name] = {
			ReferenceCount = refs,
			ModuleScript = info.ModuleScript,
		}
	end

	return retentions
end

--[=[
	Prints a summary of module retentions to the output.
	Only works if debug mode is enabled.

	```lua
	Loader.EnableDebug()
	Loader.LoadDescendants(ReplicatedStorage.MyModules)
	Loader.PrintRetentions()
	```
]=]
function Loader.PrintRetentions()
	local retentions = Loader.GetRetentions()
	local sorted: { { Name: string, ReferenceCount: number } } = {}

	for name, info in retentions do
		table.insert(sorted, { Name = name, ReferenceCount = info.ReferenceCount })
	end

	table.sort(sorted, function(a, b)
		return a.ReferenceCount > b.ReferenceCount
	end)

	print("=== Module Retentions ===")
	for _, item in sorted do
		print(`{item.Name}: {item.ReferenceCount} table entries`)
	end
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
