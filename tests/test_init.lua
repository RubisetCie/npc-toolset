local function prepare(client)
    M.loadTool(client)
    M.files["LUA:npcscene/client/*"] = {{"list.lua", "notes.txt"}, {"nested"}}
    M.files["LUA:npcscene/client/nested/*"] = {{"other.lua"}, {}}
    M.downloads, M.includeCalls = {}, {}
end

test("server distributes client catalogs without executing them", function()
    prepare(false)
    M.load("lua/autorun/npc_scene_init.lua")
    equal(#M.includeCalls, 0)
    equal(#M.downloads, 3, "initializer plus two Lua catalogs")
end)

test("client includes each catalog exactly once and ignores non-Lua files", function()
    prepare(true)
    M.load("lua/autorun/npc_scene_init.lua")
    equal(#M.includeCalls, 2)
    equal(M.includeCalls[1], "npcscene/client/nested/other.lua")
    equal(M.includeCalls[2], "npcscene/client/list.lua")
end)

test("initializer hot reload preserves tool methods and active playback state", function()
    local _, player, npc = M.loadTool()
    NPCS:PlayScene(player, npc.id)
    local namespace, method, state = NPCS, NPCS.PlayScene, NPCS.runningScenes
    M.load("lua/autorun/npc_scene_init.lua")
    equal(NPCS, namespace)
    equal(NPCS.PlayScene, method)
    equal(NPCS.runningScenes, state)
    M.advance(2)
    equal(npc:GetNWBool("npcscene_active"), false)
end)

test("initializer tolerates missing directories and a fresh namespace", function()
    M.reset(false)
    NPCS = nil
    file.Find = function() return nil, nil end
    M.load("lua/autorun/npc_scene_init.lua")
    equal(type(NPCS.premadeSceneList), "table")
end)
