test("fractional delay is only inserted between plays, not before first or after last", function()
    local _, player, npc = M.loadTool()
    npc:SetNWInt("npcscene_loop", 2)
    NPCS:SetNWVars(npc, {loop_delay = 1.5})
    equal(NPCS:PlayScene(player, npc.id), true)
    equal(npc.plays[1].at, 0)
    M.advance(3.49)
    equal(#npc.plays, 1)
    equal(npc:GetNWBool("npcscene_active"), true, "sequence stays active in the gap")
    M.advance(0.01)
    equal(npc.plays[2].at, 3.5)
    M.advance(3.5)
    equal(npc.plays[3].at, 7)
    M.advance(2)
    equal(npc:GetNWBool("npcscene_active"), false)
    equal(M.count(M.timers), 0)
end)

test("zero delay preserves back-to-back loop timing", function()
    local _, player, npc = M.loadTool()
    equal(TOOL.ClientConVar.loop_delay, 0)
    npc:SetNWInt("npcscene_loop", 1)
    NPCS:PlayScene(player, npc.id)
    M.advance(2)
    equal(npc.plays[2].at, 2)
    M.advance(2)
    equal(npc:GetNWBool("npcscene_active"), false)
end)

test("delay has no effect when there are no repeats", function()
    local _, player, npc = M.loadTool()
    npc:SetNWFloat("npcscene_loop_delay", 60)
    NPCS:PlayScene(player, npc.id)
    M.advance(2)
    equal(npc:GetNWBool("npcscene_active"), false)
    equal(#npc.plays, 1)
end)

test("each run snapshots delay and tolerates changed scene duration", function()
    local _, player, npc = M.loadTool()
    npc:SetNWInt("npcscene_loop", 2)
    npc:SetNWFloat("npcscene_loop_delay", 1)
    npc.playResult = function(count) return count == 1 and 2 or 3 end
    NPCS:PlayScene(player, npc.id)
    npc:SetNWFloat("npcscene_loop_delay", 50)
    M.advance(7)
    equal(npc.plays[2].at, 3)
    equal(npc.plays[3].at, 7)
    M.advance(3)
    equal(npc:GetNWBool("npcscene_active"), false)
end)

test("negative and NaN delays become zero; excessive delays are capped", function()
    for _, case in ipairs({{-1, 0}, {0/0, 0}, {math.huge, 60}, {100, 60}}) do
        local _, player, npc = M.loadTool()
        npc:SetNWInt("npcscene_loop", 1)
        npc:SetNWFloat("npcscene_loop_delay", case[1])
        NPCS:PlayScene(player, npc.id)
        M.advance(2 + case[2])
        equal(npc.plays[2].at, 2 + case[2])
    end
end)

test("removal in the delay gap prevents the next loop", function()
    local _, player, npc = M.loadTool()
    npc:SetNWInt("npcscene_loop", 2)
    npc:SetNWFloat("npcscene_loop_delay", 5)
    NPCS:PlayScene(player, npc.id)
    M.advance(3)
    SafeRemoveEntity(npc)
    M.advance(50)
    equal(#npc.plays, 1)
    equal(M.count(M.timers), 0)
end)

test("tool transfers fractional delay from the player's convar", function()
    local tool, player, npc = M.loadTool()
    player.info.npc_scene_loop_delay = "2.25"
    player.info.npc_scene_loop = "1"
    equal(tool:LeftClick({Hit = true, Entity = npc}), true)
    equal(npc:GetNWFloat("npcscene_loop_delay"), 2.25)
    M.advance(4.25)
    equal(npc.plays[2].at, 4.25)
end)

test("tool panel exposes a two-decimal delay slider", function()
    M.loadTool(true)
    local panel = { controls = {} }
    function panel:AddControl() end
    function panel:ControlHelp() end
    function panel:Help() end
    function panel:NumSlider(...) self.controls[#self.controls + 1] = {...} end
    TOOL.BuildCPanel(panel)
    equal(panel.controls[1][2], "npc_scene_loop_delay")
    equal(panel.controls[1][3], 0)
    equal(panel.controls[1][4], 60)
    equal(panel.controls[1][5], 2)
end)

test("overlapping tool clicks apply the current delay without changing older runs", function()
    local tool, player, npc = M.loadTool()
    player.info.npc_scene_multiple = "1"
    player.info.npc_scene_scene = "scenes/test"
    player.info.npc_scene_loop = "1"
    player.info.npc_scene_loop_delay = "1"
    equal(tool:LeftClick({Hit = true, Entity = npc}), true)
    M.advance(1)
    player.info.npc_scene_loop_delay = "4"
    equal(tool:LeftClick({Hit = true, Entity = npc}), true)
    equal(npc:GetNWFloat("npcscene_loop_delay"), 4)
    M.advance(2)
    equal(#npc.plays, 3)
    equal(npc.plays[3].at, 3, "older run retains its one-second pause")
    M.advance(4)
    equal(#npc.plays, 4)
    equal(npc.plays[4].at, 7, "newer run uses its four-second pause")
    M.advance(2)
    equal(npc:GetNWBool("npcscene_active"), false)
end)

test("same-scene multiple mode still honors Start On when configuring a key", function()
    local tool, player, npc = M.loadTool()
    player.info.npc_scene_multiple = "1"
    player.info.npc_scene_scene = "scenes/test"
    player.info.npc_scene_key = "12"
    player.info.npc_scene_start = "0"
    equal(tool:LeftClick({Hit = true, Entity = npc}), true)
    equal(#npc.plays, 0)
    equal(npc.NPCSceneKeyOwner, player)
end)
