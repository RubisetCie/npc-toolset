NPCS = {
	premadeSceneList = {}
}
NPCS.folder = { lua = "npcscene/" }
local function includeLibs(dir,isClientLib)
	local files,dirs = file.Find(dir.."*","LUA")
	if not dirs then return end
	for _,fdir in pairs(dirs) do
		includeLibs(dir..fdir.."/",isClientLib)
	end
	for k,v in pairs(files) do
		if SERVER and isClientLib then
			AddCSLuaFile(dir..v)
		else
			include(dir..v)
		end
	end
end
game.AddParticles("particles/plate_green.pcf")
PrecacheParticleSystem("plate_green")
if(SERVER) then
	AddCSLuaFile()
	AddCSLuaFile("includes/modules/json.lua")
	AddCSLuaFile("autorun/client/cl_npctools_relationships.lua")
	includeLibs(NPCS.folder.lua)
end
includeLibs(NPCS.folder.lua,true)
