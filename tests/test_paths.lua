test("scene normalization removes only a trailing .vcd extension", function()
    for _, case in ipairs({
        {"scenes/avcd_folder/avcd_actor.vcd", "scenes/avcd_folder/avcd_actor"},
        {" scenes/test.VCD  ", "scenes/test"},
        {"scenes/test", "scenes/test"},
        {"scenes/inside.vcd/test.vcd", "scenes/inside.vcd/test"}
    }) do
        local tool, player, npc = M.loadTool()
        player.info.npc_scene_scene = case[1]
        equal(tool:LeftClick({Hit = true, Entity = npc}), true)
        equal(npc.plays[1].path, case[2])
    end
end)

test("empty scene input is rejected before replacing an active NPC", function()
    local tool, player, npc = M.loadTool()
    NPCS:PlayScene(player, npc.id)
    player.info.npc_scene_scene = "   "
    equal(tool:LeftClick({Hit = true, Entity = npc}), false)
    equal(IsValid(npc), true)
    equal(npc:GetNWString("npcscene_path"), "scenes/test")
    equal(M.count(M.timers), 1)
end)

test("tool reports failed playback rather than a successful click", function()
    local tool, _, npc = M.loadTool()
    npc.duration = 0
    equal(tool:LeftClick({Hit = true, Entity = npc}), false)
    equal(npc:GetNWBool("npcscene_active"), false)
end)

test("overlapping left click targets the traced NPC, not a stale stored index", function()
    local tool, player, npc = M.loadTool()
    player.info.npc_scene_multiple = "1"
    player.info.npc_scene_scene = "scenes/test"
    local other = M.entity()
    other:SetNWString("npcscene_path", "scenes/other")
    npc:SetNWInt("npcscene_index", other.id)
    equal(tool:LeftClick({Hit = true, Entity = npc}), true)
    equal(#npc.plays, 1)
    equal(#other.plays, 0)
end)

test("actor naming repairs stale stored entity indices", function()
    local tool, _, npc = M.loadTool()
    npc:SetNWInt("npcscene_index", 999)
    equal(tool:RightClick({Hit = true, Entity = npc}), true)
    equal(npc:GetNWInt("npcscene_index"), npc.id)
    equal(M.sent[1].index, npc.id)
    equal(tool:RightClick({Hit = true, Entity = npc}), false)
end)
