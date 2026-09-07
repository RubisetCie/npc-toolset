M.catalogFiles = {
    "ep1_list.lua", "ep2_list.lua", "hl2_list.lua", "l4d2_list.lua", "lostcoast_list.lua", "portal_list.lua"
}
function M.loadCatalogs()
    for _, name in ipairs(M.catalogFiles) do M.load("lua/npcscene/client/" .. name) end
end
function M.flatten(tree, prefix, result)
    prefix, result = prefix or "", result or {}
    for key, value in pairs(tree) do
        if type(value) == "table" then
            assert(type(key) == "string", "directory must have a name")
            M.flatten(value, prefix .. key .. "/", result)
        else
            assert(type(key) == "number" and type(value) == "string", "invalid catalog leaf")
            assert(not value:find("[/\\]"), "scene leaf contains a directory: " .. value)
            local path = prefix .. value
            assert(not result[path], "duplicate scene: " .. path)
            result[path] = true
        end
    end
    return result
end

test("all six complete scene catalogs compile and have valid tree structure", function()
    M.reset(true)
    M.loadCatalogs()
    equal(M.count(NPCS.premadeSceneList), 6)
    local total = 0
    for title, tree in pairs(NPCS.premadeSceneList) do
        local count = M.count(M.flatten(tree))
        assert(count > 0, title .. " is empty")
        total = total + count
        print("  " .. title .. ": " .. count .. " scenes")
    end
    M.catalogTotal = total
end)

test("experimental scenes.image reader remains disabled", function()
    M.reset(true)
    OpenScenesImage = nil
    M.load("lua/autorun/client/scenes.image_reader.lua")
    equal(OpenScenesImage, nil)
end)

test("tool compiles and loads in both realms", function()
    M.loadTool(false)
    M.loadTool(true)
end)
