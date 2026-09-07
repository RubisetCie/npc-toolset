--[[
    NPC Scene - by Xalalau Xubilozo

    MIT License 2021
]]

-- --------------
-- Base
-- --------------

TOOL.Category = "Poser"
TOOL.Name = "#Tool.npc_scene.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar["scene"] = "scenes/npc/Gman/gman_intro"
TOOL.ClientConVar["actor"] = "Alyx"
TOOL.ClientConVar["remove_actor_name_on_reload"] = 0
TOOL.ClientConVar["loop"] = 0
TOOL.ClientConVar["loop_delay"] = 0
TOOL.ClientConVar["key"] = 0
TOOL.ClientConVar["start"] = 1
TOOL.ClientConVar["multiple"] = 0
TOOL.ClientConVar["render"] = 1
TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" }
}

if CLIENT then
    language.Add("Tool.npc_scene.name", "NPC Scene")
    language.Add("Tool.npc_scene.desc", "Make NPCs act using \".vcd\" files!")
    language.Add("Tool.npc_scene.left", "Left click to play the scene.")
    language.Add("Tool.npc_scene.right", "Right click to set the actor name.")
    language.Add("Tool.npc_scene.reload", "Reload to stop the scene.")

    surface.CreateFont("NPCS_TargetID", {
        font = "TargetID",
        extended = false,
        size = 20,
        weight = 1000,
        blursize = 0,
        scanlines = 0,
        antialias = true,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        outline = false,
    })
end

-- --------------
-- Net
-- --------------

if SERVER then
    util.AddNetworkString("npc_scene_hook_key")
    util.AddNetworkString("npc_scene_play")
    util.AddNetworkString("npc_scene_render_actor")

    net.Receive("npc_scene_play", function(length, ply)
        if length ~= 16 or not IsValid(ply) or not ply:IsPlayer() then return end

        local index = net.ReadInt(16)
        local npc = ents.GetByIndex(index)
        if not IsValid(npc) or not npc:IsNPC() then return end
        -- A client may only trigger the key binding it configured through the tool.
        if npc.NPCSceneKeyOwner ~= ply or npc:GetNWInt("npcscene_key") <= 0 then return end
        if (npc.NPCSceneNextKeyPlay or 0) > CurTime() then return end

        npc.NPCSceneNextKeyPlay = CurTime() + 0.1
        NPCS:PlayScene(ply, index)
    end)
end
    
if CLIENT then
    net.Receive("npc_scene_hook_key", function()
        NPCS:SetKey(net.ReadInt(16))
    end)

    net.Receive("npc_scene_render_actor", function()
        NPCS:RenderActorName(net.ReadInt(16))
    end)
end

-- --------------
-- General
-- --------------

local function boundedNumber(value, maximum)
    value = tonumber(value) or 0
    if value ~= value then return 0 end -- Reject NaN from client convars.
    return math.Clamp(value, 0, maximum)
end

-- Share the scene values between server and client
function NPCS:SetNWVars(npc, sceneData)
    if sceneData.active ~= nil then npc:SetNWBool("npcscene_active", sceneData.active) end
    if sceneData.index then npc:SetNWInt("npcscene_index", sceneData.index) end
    if sceneData.loop then npc:SetNWInt("npcscene_loop", sceneData.loop) end
    if sceneData.loop_delay ~= nil then npc:SetNWFloat("npcscene_loop_delay", sceneData.loop_delay) end
    if sceneData.path then npc:SetNWString("npcscene_path", sceneData.path) end
    if sceneData.actor then npc:SetNWString("npcscene_actor", sceneData.actor) end
    if sceneData.key then npc:SetNWInt("npcscene_key", sceneData.key) end
end

-- Set a key association
function NPCS:SetKey(index)
    if SERVER then return end

    local npc
    local hookName = "npc_scene" .. index
    local expires = RealTime() + 5
    local wasDown = false

    -- Replace the previous binding rather than accumulating hooks. Networked entities
    -- and their convars can arrive after this message, so resolve them on Tick.
    hook.Add("Tick", hookName, function()
        if not npc then
            local candidate = ents.GetByIndex(index)
            if not IsValid(candidate) or candidate:GetNWInt("npcscene_key") <= 0 then
                if RealTime() >= expires then hook.Remove("Tick", hookName) end
                return
            end
            npc = candidate
        end

        if not IsValid(npc) or npc:GetNWInt("npcscene_key") <= 0 then
            hook.Remove("Tick", hookName)
            return
        end

        local down = input.IsButtonDown(npc:GetNWInt("npcscene_key"))
        local typing = gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus())
        if down and not wasDown and not typing then
            net.Start("npc_scene_play")
                net.WriteInt(npc:EntIndex(), 16)
            net.SendToServer()
        end
        wasDown = down
    end)
end

-- Cancel every playback sequence, including overlapping scenes.
function NPCS:StopSceneTimers(npc)
    if CLIENT then return end

    local runs = self.runningScenes and self.runningScenes[npc]
    if not runs then return end

    for run in pairs(runs) do
        if run.timer then timer.Remove(run.timer) end
        SafeRemoveEntity(run.scene)
        runs[run] = nil
    end

    self.runningScenes[npc] = nil
    if IsValid(npc) then npc:SetNWBool("npcscene_active", false) end
end

-- Play a scene. Each sequence keeps its own configuration and timers.
function NPCS:PlayScene(ply, index)
    if CLIENT or not IsValid(ply) or not ply:IsPlayer() then return false end

    local npc = ents.GetByIndex(index)
    if not IsValid(npc) or not npc:IsNPC() then return false end

    local path = npc:GetNWString("npcscene_path")
    if path == "" then return false end

    local multiple = ply:GetInfo("npc_scene_multiple") == "1"
    if npc:GetNWBool("npcscene_active") and not multiple then return false end

    local remaining = math.floor(boundedNumber(npc:GetNWInt("npcscene_loop"), 100))
    local loopDelay = boundedNumber(npc:GetNWFloat("npcscene_loop_delay"), 60)
    self.runningScenes = self.runningScenes or {}
    local runs = self.runningScenes[npc] or {}
    self.runningScenes[npc] = runs
    self.nextSceneID = (self.nextSceneID or 0) + 1
    local timerName = "npc_scene_" .. npc:EntIndex() .. "_" .. self.nextSceneID
    local run = {}
    runs[run] = true

    npc:CallOnRemove("npc_scene_timers", function(ent)
        self:StopSceneTimers(ent)
    end)

    local function finish()
        if run.timer then timer.Remove(run.timer) end
        if self.runningScenes[npc] ~= runs then return end
        runs[run] = nil
        local active = next(runs) ~= nil
        if not active then self.runningScenes[npc] = nil end
        if IsValid(npc) then npc:SetNWBool("npcscene_active", active) end
    end

    local function play()
        if not IsValid(npc) or not runs[run] then finish() return false end

        local length, scene = npc:PlayScene(path)
        run.scene = scene
        if not isnumber(length) or length ~= length or length <= 0 or length == math.huge then
            SafeRemoveEntity(scene)
            finish()
            return false
        end

        npc:SetNWBool("npcscene_active", true)
        -- A different name per iteration avoids replacing a timer inside its own callback.
        run.timer = timerName .. "_" .. remaining
        local interval = length + (remaining > 0 and loopDelay or 0)
        timer.Create(run.timer, interval, 1, function()
            if not IsValid(npc) or not runs[run] then
                finish()
            elseif remaining > 0 then
                remaining = remaining - 1
                play()
            else
                finish()
            end
        end)
        return true
    end

    return play()
end

-- Remove our modifications from the npc
function NPCS:ReloadNPC(ply, npc, removeActorName)
    if CLIENT then return end

    if not IsValid(ply) or not IsValid(npc) or npc:IsPlayer() or npc:IsWorld() then return npc end

    local scenePath = npc:GetNWString("npcscene_path")
    local actorName = npc:GetNWString("npcscene_actor")

    if scenePath == "" and (not removeActorName or actorName == "") then return npc end

    -- Do not delete or interrupt the original if duplication fails.
    local data = duplicator.CopyEntTable(npc)
    if not istable(data) then return npc end
    local newNpc = duplicator.CreateEntityFromTable(ply, data)
    if not IsValid(newNpc) then return npc end

    self:StopSceneTimers(npc)
    SafeRemoveEntity(npc)
    self:SetNWVars(newNpc, {
        active = false, index = 0, loop = 0, loop_delay = 0, path = "", actor = "", key = 0
    })
    newNpc.NPCSceneKeyOwner = nil
    newNpc.NPCSceneNextKeyPlay = nil
    if removeActorName then newNpc:SetName("") end

    -- Add undo
    undo.Create("NPC")
        undo.AddEntity(newNpc)
        undo.SetPlayer(ply)
    undo.Finish()

    -- Reapply the name
    if not removeActorName and actorName ~= "" then
        local sceneData = {
            index = newNpc:EntIndex(),
            actor = actorName
        }

        newNpc:SetName(actorName)

        self:SetNWVars(newNpc, sceneData)

        timer.Simple(0.5, function()
            if not IsValid(ply) or not IsValid(newNpc) then return end

            net.Start("npc_scene_render_actor")
                net.WriteInt(sceneData.index, 16)
            net.Send(ply)
        end)
    end

    return newNpc
end

-- Render actor names
function NPCS:RenderActorName(index)
    if SERVER then return end

    local npc = ents.GetByIndex(index)

    if not npc then return end

    local hookName = "NPCScene_ActorName" .. tostring(npc) .. math.random(1, 999)

    hook.Add("HUDPaint", hookName, function()
        if not npc:IsValid() then return hook.Remove("HUDPaint", hookName) end

        if GetConVar("npc_scene_render"):GetBool() then
            -- Actor name
            local actorName = npc:GetNWString("npcscene_actor")

            if not actorName then return end

            -- Distance
            local distance = LocalPlayer():GetPos():Distance(npc:GetPos())

            if distance > 300 then return end

            local head = npc:LookupBone("ValveBiped.Bip01_Head1")
            local up = Vector(0, 0, 17 * distance/300)

            -- NPCs
            if head then
                local headpos, headang = npc:GetBonePosition(head)
                headpos = headpos + up
                drawposscreen = (headpos + Vector(0, 0, 10)):ToScreen()
            -- Props
            else
                local mins, maxs = npc:GetModelBounds()
                local pos = npc:GetPos() + Vector(0, 0, maxs.z + 7)
                local min, max = npc:WorldSpaceAABB()
                local drawpos = Vector(pos.x, pos.y, max.z) + up
                drawposscreen = drawpos:ToScreen()
            end

            -- Draw
            draw.DrawText(actorName, "NPCS_TargetID", drawposscreen.x, drawposscreen.y, color_white, TEXT_ALIGN_CENTER)
        end
    end)
end

-- Scan for .vcds and folders in a folder
function NPCS:CreateNodes(parentNode, parentDir, sceneList)
    if SERVER then return end

    local folders, files = {}, {}

    for k, item in pairs(sceneList) do
        if istable(item) then
            local tab = { [k] = item }
            folders[k] = tab
        else
            table.insert(files, item)
        end
    end

    for _, item in SortedPairs(folders) do
        for folderName, folder in pairs(item) do
            local node = parentNode:AddNode(folderName)

            node.DoClick = function()
                node:SetExpanded(not node:GetExpanded())
            end

            self:CreateNodes(node, parentDir .. folderName .. "/", folder)
        end
    end

    for _, fileName in pairs(files) do
        local node = parentNode:AddNode(fileName)

        node:SetIcon("icon16/page.png")
        node.DoClick = function() RunConsoleCommand("npc_scene_scene", "scenes/" .. parentDir .. fileName) end
    end
end

-- Scan for .vcds and folders in a folder
function NPCS:ScanDir(parentDir, foundScenes)
    if SERVER then return end

    if not foundScenes then foundScenes = {} end

    local files, dirs = file.Find(parentDir .. "*", "MOD")

    for _, dirName in ipairs(dirs) do
        foundScenes[dirName] = {}
        self:ScanDir(parentDir .. dirName .. "/", foundScenes[dirName])
    end

    for _, fileName in ipairs(files) do
        if string.GetExtensionFromFilename(fileName) == "vcd" then
            table.insert(foundScenes, fileName)
        end
    end 

    return foundScenes
end

-- Build a scene list checking for mounted games and using our pre-made scene tables
function NPCS:BuildPremandeSceneList()
    local premadeSceneList = {}

    table.Merge(premadeSceneList, self.premadeSceneList["Half-Life 2"])

    for _, game in ipairs(engine.GetGames()) do
        if game.mounted then
            if game.title == "Half-Life 2 & Episodes" then
                table.Merge(premadeSceneList, self.premadeSceneList["Half-Life 2: Episode 2"])
                table.Merge(premadeSceneList, self.premadeSceneList["Half-Life 2: Episode 1"])
                table.Merge(premadeSceneList, self.premadeSceneList["Half-Life 2: Lost Coast"]) -- Not sure if it's included in the HL Anniversary update
            elseif self.premadeSceneList[game.title] then
                table.Merge(premadeSceneList, self.premadeSceneList[game.title])
            end
        end
    end

    return premadeSceneList
end

-- Open the scenes list
local initialized
local sceneListPanel
local function ListScenes()
    if SERVER then return end

    if not initialized then
        local width, height = 300, 700
        local padding = 35

        sceneListPanel = vgui.Create("DFrame")
            sceneListPanel:SetTitle("Scenes")
            sceneListPanel:SetSize(width, height)
            sceneListPanel:SetPos(ScrW() - width - padding, padding)
            sceneListPanel:SetDeleteOnClose(false)
            sceneListPanel:SetVisible(false)

        local ctrl = vgui.Create("DTree", sceneListPanel)
            ctrl:SetPadding(5)
            ctrl:SetSize(width, height - 25)
            ctrl:SetPos(0, 25)
            ctrl:SetBackgroundColor(Color(255, 255, 255, 255))

        local node = ctrl:AddNode("Scenes! (click one to select)")
            local premadeSceneList = NPCS:BuildPremandeSceneList()
            local foundSceneList = NPCS:ScanDir("scenes/")
            table.Merge(foundSceneList, premadeSceneList)
            NPCS:CreateNodes(node, "", foundSceneList)
            node:SetExpanded(true)

        initialized = true
    end

    sceneListPanel:SetVisible(true)
    sceneListPanel:MakePopup()
end

if CLIENT then
    concommand.Add("npc_scene_list", ListScenes)
end

-- --------------
-- Toolgun
-- --------------

local function toolGunChecks(tr, anyEnt)
    -- Check if we're modifying a NPC
    if not (tr.Hit and not tr.HitWorld and IsValid(tr.Entity)
        and not tr.Entity:IsPlayer() and not tr.Entity:IsWorld()
        and (anyEnt or tr.Entity:IsNPC())) then
        return false
    end

    return true
end

-- Play a scene
function TOOL:LeftClick(tr)
    if not toolGunChecks(tr) then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    local npc = tr.Entity
    local path  = string.gsub(self:GetClientInfo("scene"), ".vcd", "")
    local actor
    local multiple = self:GetClientNumber("multiple") == 1 and true or false

    -- Checks if there's a scene applied
    if npc:GetNWInt("npcscene_index") > 0 then
        -- Apply the scene on top scene if it's configured to do so
        if multiple and npc:GetNWString("npcscene_path") == path then
            NPCS:PlayScene(ply, npc:GetNWInt("npcscene_index"))

            return true
        end

        -- Get the actor name if there's one
        if npc:GetNWString("npcscene_actor") ~= "" then
            actor = npc:GetNWString("npcscene_actor")
        end

        -- Reload the scenes by deleting the loops and reloading the NPCs
        if npc:GetNWBool("npcscene_active") and not multiple then
            local newNpc = NPCS:ReloadNPC(ply, npc)
            if not IsValid(newNpc) or newNpc == npc then return false end
            npc = newNpc
        end
    end

    -- Get the scene configuration and set it
    local sceneData = {
        active = npc:GetNWBool("npcscene_active"),
        index  = npc:EntIndex(),
        loop   = math.floor(boundedNumber(self:GetClientNumber("loop"), 100)),
        loop_delay = boundedNumber(self:GetClientNumber("loop_delay"), 60),
        path   = path,
        actor  = actor,
        key    = self:GetClientNumber("key"),
        start  = self:GetClientNumber("start") == 1 and true or false,
    }

    NPCS:SetNWVars(npc, sceneData)

    npc.NPCSceneKeyOwner = sceneData.key ~= 0 and ply or nil
    npc.NPCSceneNextKeyPlay = nil

    -- Prepare the scene to be played by key
    if sceneData.key != 0 then
        net.Start("npc_scene_hook_key")
            net.WriteInt(sceneData.index, 16)
        net.Send(ply)
    end
    
    -- Play the scene
    if sceneData.start or sceneData.key == 0 then
        NPCS:PlayScene(ply, sceneData.index)
    end

    return true
end

-- Set an actor name
function TOOL:RightClick(tr)
    if not toolGunChecks(tr, true) then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()    
    local npc = tr.Entity
    local oldName = npc:GetNWString("npcscene_actor")
    local newName = self:GetClientInfo("actor")

    if oldName == newName then
        return false
    end

    -- Add the name to the entity
    local sceneData = {
        index = npc:GetNWInt("npcscene_index") == 0 and npc:EntIndex() or nil,
        actor = newName
    }

    npc:SetName(sceneData.actor)

    NPCS:SetNWVars(npc, sceneData)

    -- Render the name on the client
    net.Start("npc_scene_render_actor")
        net.WriteInt(sceneData.index or npc:GetNWInt("npcscene_index"), 16)
    net.Send(ply)

    return true
end

-- Clear modifications
function TOOL:Reload(tr)
    if not toolGunChecks(tr, true) then return false end

    local ply = self:GetOwner()
    local npc = tr.Entity

    -- Stop any loops and reload the NPC
    if npc:GetNWInt("npcscene_index") > 0 then
        if SERVER then
            local removeActorName = self:GetClientNumber("remove_actor_name_on_reload") == 1
            local newNpc = NPCS:ReloadNPC(ply, npc, removeActorName)

            if npc == newNpc then
                return false
            end
        end

        return true
    else
        return false
    end
end

-- --------------
-- CPanel
-- --------------

function TOOL.BuildCPanel(CPanel)
    CPanel:AddControl ("Header"  , { Text  = '#Tool.npc_scene.name', Description = '#Tool.npc_scene.desc' })
    CPanel:AddControl ("Numpad"  , { Label = "Scene key", Command = "npc_scene_key" })
    CPanel:AddControl ("TextBox" , { Label = "Scene Name" , Command = "npc_scene_scene", MaxLength = 500 })
    CPanel:AddControl ("TextBox" , { Label = "Actor Name" , Command = "npc_scene_actor", MaxLength = 30 })
    if game.SinglePlayer() then
        CPanel:ControlHelp("\nApply a scene and open the console to see which actor names you need to set.")
    end
    CPanel:AddControl ("Slider"  , { Label = "Loop", Type = "int", Min = "0", Max = "100", Command = "npc_scene_loop"})
    CPanel:NumSlider("Loop delay (seconds)", "npc_scene_loop_delay", 0, 60, 2)
    CPanel:ControlHelp("Pause after each scene before repeating. Loop counts extra plays; 0 delay disables the pause.")
    CPanel:AddControl ("CheckBox", { Label = "Allow to apply scene multiple times", Command = "npc_scene_multiple" })
    CPanel:AddControl ("CheckBox", { Label = "Start On (When using a key)", Command = "npc_scene_start" })
    CPanel:AddControl ("CheckBox", { Label = "Render actor names", Command = "npc_scene_render" })
    CPanel:AddControl ("CheckBox", { Label = "Remove actor name on reload", Command = "npc_scene_remove_actor_name_on_reload" })
    CPanel:Help       ("")
    CPanel:AddControl ("Button" , { Text  = "List Scenes", Command = "npc_scene_list" })
end
