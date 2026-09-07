function M.node(label)
    local node = {valid = true, label = label, children = {}, expanded = false}
    function node:AddNode(name)
        local child = M.node(name)
        self.children[#self.children + 1] = child
        return child
    end
    function node:SetIcon() end
    function node:SetExpanded(value) self.expanded = value end
    function node:GetExpanded() return self.expanded end
    return node
end

test("scene tree merge unions lists, preserves nested scenes and deduplicates", function()
    M.loadTool(true)
    local destination = { "local.vcd", npc = {"a.vcd", "same.vcd", custom = {"inner.vcd"}} }
    local source = { "base.vcd", npc = {"b.vcd", "same.vcd", imported = {"other.vcd"}} }
    local result = NPCS:MergeSceneLists(destination, source)
    equal(M.count(M.flatten(result)), 7)
    equal(#result.npc, 3)
    result.npc.imported[1] = "changed.vcd"
    equal(source.npc.imported[1], "other.vcd", "merge must not alias source tables")
    equal(NPCS:MergeSceneLists(destination, nil), destination)
end)

test("all mounted catalogs retain every original path after merging", function()
    M.loadTool(true)
    M.loadCatalogs()
    local expected = {}
    for title, tree in pairs(NPCS.premadeSceneList) do
        M.games[#M.games + 1] = {title = title, mounted = true}
        for path in pairs(M.flatten(tree)) do expected[path] = true end
    end
    local result = M.flatten(NPCS:BuildPremandeSceneList())
    for path in pairs(expected) do assert(result[path], "lost catalog scene: " .. path) end
    equal(M.count(result), M.count(expected))
    -- Rebuilding must be stable and leave all six original catalogs intact.
    equal(M.count(M.flatten(NPCS:BuildPremandeSceneList())), M.count(expected))
    local count = 0
    for _, tree in pairs(NPCS.premadeSceneList) do count = count + M.count(M.flatten(tree)) end
    equal(count, M.catalogTotal)
    print("  merged mounted catalog union: " .. M.count(result) .. " paths")
end)

test("bundled HL2 title merges episodes without losing base NPC scenes", function()
    M.loadTool(true)
    NPCS.premadeSceneList = {
        ["Half-Life 2"] = {npc = {"base.vcd"}},
        ["Half-Life 2: Episode 1"] = {npc = {"ep1.vcd"}},
        ["Half-Life 2: Episode 2"] = {npc = {"ep2.vcd"}},
        ["Half-Life 2: Lost Coast"] = {npc = {"lost.vcd"}},
        ["Portal"] = {npc = {"portal.vcd"}}
    }
    M.games = {{title = "Half-Life 2 & Episodes", mounted = true}, {title = "Portal", mounted = false}}
    equal(M.count(M.flatten(NPCS:BuildPremandeSceneList())), 4)
end)

test("loose scene discovery uses mounted GAME paths and accepts uppercase extensions", function()
    M.loadTool(true)
    M.files["GAME:scenes/*"] = {{"one.vcd", "UPPER.VCD", "one.vcd.bak", "notes.txt"}, {"custom"}}
    M.files["GAME:scenes/custom/*"] = {{"child.vcd"}, {}}
    local result = NPCS:ScanDir("scenes/")
    equal(M.count(M.flatten({result[1], custom = result.custom})), 2)
    equal(result[2], "UPPER.VCD")
    file.Find = function() return nil, nil end
    equal(M.count(NPCS:ScanDir("scenes/missing/")), 0)
end)

test("scene browser filters backup files, sorts leaves and selects complete paths", function()
    M.loadTool(true)
    local parent = M.node("root")
    NPCS:CreateNodes(parent, "", {
        "z.vcd", "a.vcd", "backup.vcd.bak", folder = {"inner.vcd"}
    })
    equal(#parent.children, 3)
    equal(parent.children[1].label, "folder")
    equal(parent.children[2].label, "a.vcd")
    equal(parent.children[3].label, "z.vcd")
    parent.children[1].children[1].DoClick()
    equal(M.commands[1][2], "scenes/folder/inner.vcd")
    parent.children[1].DoClick()
    equal(parent.children[1].expanded, true)
end)

test("scene browser recreates a deleted window and retains loose and premade scenes", function()
    M.loadTool(true)
    local panels = {}
    function ScrW() return 1920 end
    function Color(...) return {...} end
    vgui.Create = function(kind)
        local panel = M.node(kind)
        for _, method in ipairs({"SetTitle", "SetSize", "SetPos", "SetDeleteOnClose", "SetVisible",
                                 "SetPadding", "SetBackgroundColor", "MakePopup"}) do
            panel[method] = function() end
        end
        panels[#panels + 1] = panel
        return panel
    end
    NPCS.premadeSceneList["Half-Life 2"] = {npc = {"base.vcd"}}
    M.files["GAME:scenes/*"] = {{}, {"npc"}}
    M.files["GAME:scenes/npc/*"] = {{"custom.vcd"}, {}}
    M.commands.npc_scene_list()
    equal(#panels, 2)
    equal(#panels[2].children[1].children[1].children, 2)
    panels[1].valid = false
    M.commands.npc_scene_list()
    equal(#panels, 4)
end)
