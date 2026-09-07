local function request(player, npc, length)
    M.readIndex = npc.id
    M.receivers.npc_scene_play(length or 16, player)
end
local function bind()
    local tool, player, npc = M.loadTool()
    player.info.npc_scene_key = "12"
    player.info.npc_scene_start = "0"
    tool:LeftClick({Hit = true, Entity = npc})
    return tool, player, npc
end

test("network requests reject invalid indices, senders and payload sizes", function()
    local _, player, npc = bind()
    M.readIndex = -1
    M.receivers.npc_scene_play(16, player)
    request(nil, npc)
    request(player, npc, 8)
    request(player, npc, 32)
    request(npc, npc)
    equal(#npc.plays, 0)
end)

test("network key playback is limited to the player who bound the NPC", function()
    local _, player, npc = bind()
    local other = M.player()
    request(other, npc)
    equal(#npc.plays, 0)
    request(player, npc)
    equal(#npc.plays, 1)
    npc:SetNWInt("npcscene_key", 0)
    M.advance(2)
    request(player, npc)
    equal(#npc.plays, 1)
end)

test("network playback requires an actual binding rather than just a scene", function()
    local _, player, npc = M.loadTool()
    request(player, npc)
    equal(#npc.plays, 0)
end)

test("network throttle is per NPC, permits multiple NPCs and rejects floods", function()
    local tool, player, npc = bind()
    player.info.npc_scene_multiple = "1"
    local second = M.entity()
    tool:LeftClick({Hit = true, Entity = second})
    for _ = 1, 100 do request(player, npc) end
    equal(#npc.plays, 1)
    request(player, second)
    equal(#second.plays, 1)
    M.advance(0.11)
    request(player, npc)
    equal(#npc.plays, 2)
end)

test("rebinding changes the authorized player; clearing key removes permission", function()
    local tool, first, npc = bind()
    local second = M.player()
    second.info.npc_scene_key = "13"
    second.info.npc_scene_start = "0"
    M.tool(second):LeftClick({Hit = true, Entity = npc})
    equal(npc.NPCSceneKeyOwner, second)
    request(first, npc)
    equal(#npc.plays, 0)
    request(second, npc)
    equal(#npc.plays, 1)
end)

test("first client binding works without a pre-existing Tick hook table", function()
    local _, _, npc = M.loadTool(true)
    equal(M.hooks.Tick, nil)
    npc:SetNWInt("npcscene_key", 12)
    NPCS:SetKey(npc.id)
    M.down[12] = true
    M.fire("Tick")
    equal(#M.sent, 1)
end)

test("holding a key sends one request per press, not per Tick", function()
    local _, _, npc = M.loadTool(true)
    npc:SetNWInt("npcscene_key", 12)
    NPCS:SetKey(npc.id)
    M.down[12] = true
    for _ = 1, 100 do M.fire("Tick") end
    equal(#M.sent, 1)
    M.down[12] = false
    M.fire("Tick")
    M.down[12] = true
    M.fire("Tick")
    equal(#M.sent, 2)
end)

test("key presses while typing or using the game menu do not play scenes", function()
    local _, _, npc = M.loadTool(true)
    npc:SetNWInt("npcscene_key", 12)
    NPCS:SetKey(npc.id)
    M.keyboardFocus = {valid = true}
    M.down[12] = true
    M.fire("Tick")
    M.keyboardFocus = nil
    M.fire("Tick")
    equal(#M.sent, 0, "closing a text field while holding a key is not a new press")
    M.down[12] = false
    M.fire("Tick")
    M.uiVisible = true
    M.down[12] = true
    M.fire("Tick")
    equal(#M.sent, 0)
end)

test("key registration waits for entity and networked key replication", function()
    M.loadTool(true)
    NPCS:SetKey(500)
    M.fire("Tick")
    M.advance(1)
    local npc = M.entity("npc", 500)
    M.fire("Tick")
    equal(M.count(M.hooks.Tick), 1)
    npc:SetNWInt("npcscene_key", 12)
    M.down[12] = true
    M.fire("Tick")
    equal(#M.sent, 1)
end)

test("removed or unbound NPCs and expired unresolved bindings clean up hooks", function()
    local _, _, npc = M.loadTool(true)
    npc:SetNWInt("npcscene_key", 12)
    NPCS:SetKey(npc.id)
    M.fire("Tick")
    npc:SetNWInt("npcscene_key", 0)
    M.fire("Tick")
    equal(M.count(M.hooks.Tick), 0)
    NPCS:SetKey(999)
    M.advance(6)
    M.fire("Tick")
    equal(M.count(M.hooks.Tick), 0)
end)

test("repeated key registration replaces the old hook for a reused index", function()
    local _, _, npc = M.loadTool(true)
    npc:SetNWInt("npcscene_key", 12)
    NPCS:SetKey(npc.id)
    M.fire("Tick")
    SafeRemoveEntity(npc)
    local replacement = M.entity("npc", npc.id)
    replacement:SetNWInt("npcscene_key", 13)
    NPCS:SetKey(replacement.id)
    M.down[13] = true
    M.fire("Tick")
    equal(M.count(M.hooks.Tick), 1)
    equal(#M.sent, 1)
end)
