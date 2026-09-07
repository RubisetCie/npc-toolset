AddCSLuaFile()

NPCS = NPCS or {}
NPCS.premadeSceneList = NPCS.premadeSceneList or {}

local function includeLibs(dir, isClientLib)
    local files, dirs = file.Find( dir.."*", "LUA" )

    for _, fdir in pairs(dirs or {}) do
        includeLibs(dir .. fdir .. "/", isClientLib)
    end

    for k,v in pairs(files or {}) do
        if v:match("%.lua$") then
            if SERVER and isClientLib then
                AddCSLuaFile(dir .. v)
            else
                include(dir .. v)
            end
        end
    end 
end

NPCS.folder = { lua = "npcscene/" }

-- Catalogs are client-only; the server only needs to distribute their files.
includeLibs(NPCS.folder.lua .. "client/", true)
