-- Isolated substitutes for the GMod APIs used by the addon. No game engine runs here.
local M = {}

function M.load(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    -- The only nonstandard GLua syntax in this repository is !=.
    source = source:gsub("!=", "~=")
    local chunk = assert((loadstring or load)(source, "@" .. path))
    return chunk()
end

function M.reset(client)
    CLIENT, SERVER = client or false, not client
    NPCS = { premadeSceneList = {} }
    TOOL = { ClientConVar = {} }
    M.now, M.entities, M.timers, M.sent, M.hooks, M.receivers = 0, {}, {}, {}, {}, {}
    M.nextEntity, M.nextTimer, M.down, M.games, M.files = 100, 0, {}, {}, {}
    M.drawn, M.undoEntities = {}, {}
    M.cloneFails, M.copyFails, M.uiVisible = false, false, false
    M.includeCalls, M.downloads = {}, {}
    M.convars = { npc_scene_render = true }
    M.commands = {}
    M.lastClone, M.keyboardFocus = nil, nil

    function IsValid(value) return type(value) == "table" and value.valid == true end
    function isnumber(value) return type(value) == "number" end
    function istable(value) return type(value) == "table" end
    function CurTime() return M.now end
    RealTime = CurTime
    function AddCSLuaFile(path) M.downloads[#M.downloads + 1] = path or "self" end
    function include(path) M.includeCalls[#M.includeCalls + 1] = path end
    function math.Clamp(value, minimum, maximum) return math.min(math.max(value, minimum), maximum) end
    function string.Trim(value) return value:match("^%s*(.-)%s*$") end
    function string.GetExtensionFromFilename(value) return value:match("%.([^./]+)$") end
    function table.HasValue(values, item)
        for _, value in pairs(values) do if value == item then return true end end
        return false
    end
    function table.Copy(values)
        local result = {}
        for key, value in pairs(values) do
            result[key] = type(value) == "table" and table.Copy(value) or value
        end
        return result
    end
    function table.Merge(target, source)
        for key, value in pairs(source) do
            if type(value) == "table" and type(target[key]) == "table" then
                table.Merge(target[key], value)
            else
                target[key] = type(value) == "table" and table.Copy(value) or value
            end
        end
        return target
    end
    function SortedPairs(values)
        local keys = {}
        for key in pairs(values) do keys[#keys + 1] = key end
        table.sort(keys)
        local index = 0
        return function() index = index + 1; return keys[index], values[keys[index]] end
    end
    function GetConVar(name)
        if M.convars[name] == nil then return nil end
        return { GetBool = function() return M.convars[name] end }
    end
    function RunConsoleCommand(...) M.commands[#M.commands + 1] = {...} end
    ents = { GetByIndex = function(index) return M.entities[index] end }
    util = { AddNetworkString = function() end }
    language = { Add = function() end }
    surface = { CreateFont = function() end }
    concommand = { Add = function(name, callback) M.commands[name] = callback end }
    game = { SinglePlayer = function() return false end }
    engine = { GetGames = function() return M.games end }
    file = { Find = function(path, realm)
        local entry = M.files[realm .. ":" .. path] or { {}, {} }
        return entry[1], entry[2]
    end }
    input = { IsKeyDown = function(key) return M.down[key] or false end }
    input.IsButtonDown = input.IsKeyDown
    gui = { IsGameUIVisible = function() return M.uiVisible end }
    vgui = { GetKeyboardFocus = function() return M.keyboardFocus end }
    hook = {
        GetTable = function() return M.hooks end,
        Add = function(event, name, callback)
            M.hooks[event] = M.hooks[event] or {}
            M.hooks[event][name] = callback
        end,
        Remove = function(event, name)
            if M.hooks[event] then M.hooks[event][name] = nil end
        end
    }
    net = {
        Receive = function(name, callback) M.receivers[name] = callback end,
        ReadInt = function() return M.readIndex end,
        Start = function(name) M.message = {name = name} end,
        WriteInt = function(index) M.message.index = index end,
        Send = function(player)
            M.message.player = player
            M.sent[#M.sent + 1] = M.message
        end,
        SendToServer = function() M.sent[#M.sent + 1] = M.message end
    }
    timer = {
        Create = function(name, delay, repetitions, callback)
            assert(type(delay) == "number" and delay >= 0 and delay < math.huge and delay == delay,
                   "invalid timer delay")
            M.timers[name] = { at = M.now + math.max(delay, 0.001), delay = delay,
                               repetitions = repetitions, callback = callback }
        end,
        Remove = function(name) M.timers[name] = nil end,
        Stop = function(name)
            if M.timers[name] then M.timers[name].stopped = true end
        end,
        Simple = function(delay, callback)
            M.nextTimer = M.nextTimer + 1
            timer.Create("simple_" .. M.nextTimer, delay, 1, callback)
        end
    }
    function SafeRemoveEntity(entity)
        if not IsValid(entity) then return end
        entity.valid = false
        for _, callback in pairs(entity.onRemove) do callback(entity) end
    end
    duplicator = {
        CopyEntTable = function(entity)
            if M.copyFails then return nil end
            return { source = entity, name = entity.name, kind = entity.kind }
        end,
        CreateEntityFromTable = function(_, data)
            if M.cloneFails then return nil end
            local entity = M.entity(data.kind)
            entity.name = data.name
            M.lastClone = entity
            return entity
        end
    }
    undo = {
        Create = function() end, SetPlayer = function() end, Finish = function() end,
        AddEntity = function(entity) M.undoEntities[#M.undoEntities + 1] = entity end
    }
    draw = { DrawText = function(...) M.drawn[#M.drawn + 1] = {...} end }
    color_white, TEXT_ALIGN_CENTER = {}, 1
    local vectorMeta = {}
    function vectorMeta.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function vectorMeta:Distance(other)
        return math.sqrt((self.x-other.x)^2 + (self.y-other.y)^2 + (self.z-other.z)^2)
    end
    function vectorMeta:ToScreen() return { x = self.x, y = self.y, visible = true } end
    vectorMeta.__index = vectorMeta
    function Vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vectorMeta) end
    function LocalPlayer() return M.localPlayer end
end

function M.entity(kind, id)
    M.nextEntity = M.nextEntity + 1
    local entity = { valid = true, kind = kind or "npc", id = id or M.nextEntity,
                     nw = {}, onRemove = {}, plays = {}, duration = 2, name = "" }
    function entity:IsValid() return self.valid end
    function entity:IsNPC() return self.kind == "npc" end
    function entity:IsPlayer() return self.kind == "player" end
    function entity:IsWorld() return self.kind == "world" end
    function entity:EntIndex() return self.id end
    function entity:SetNWBool(key, value) self.nw[key] = value end
    function entity:GetNWBool(key, default)
        if self.nw[key] ~= nil then return self.nw[key] end
        return default or false
    end
    function entity:SetNWInt(key, value) self.nw[key] = value end
    function entity:GetNWInt(key, default) return self.nw[key] or default or 0 end
    entity.SetNWFloat, entity.GetNWFloat = entity.SetNWInt, entity.GetNWInt
    function entity:SetNWString(key, value) self.nw[key] = value end
    function entity:GetNWString(key, default) return self.nw[key] or default or "" end
    function entity:SetName(name) self.name = name end
    function entity:GetPos() return Vector(0, 0, 0) end
    function entity:LookupBone() return self.headBone end
    function entity:GetBonePosition() return self.headPos end
    function entity:GetModelBounds() return Vector(0, 0, 0), Vector(1, 1, 2) end
    entity.WorldSpaceAABB = entity.GetModelBounds
    function entity:CallOnRemove(name, callback) self.onRemove[name] = callback end
    function entity:PlayScene(path)
        self.plays[#self.plays + 1] = { path = path, at = M.now }
        if self.playResult then return self.playResult(#self.plays) end
        return self.duration
    end
    M.entities[entity.id] = entity
    return entity
end

function M.player()
    local player = M.entity("player")
    player.info = {}
    function player:GetInfo(key) return self.info[key] or "0" end
    M.localPlayer = player
    return player
end

function M.tool(player)
    function TOOL:GetOwner() return player end
    function TOOL:GetClientInfo(key)
        return tostring(player.info["npc_scene_" .. key] or self.ClientConVar[key] or "")
    end
    function TOOL:GetClientNumber(key) return tonumber(self:GetClientInfo(key)) or 0 end
    return TOOL
end

function M.advance(seconds)
    local target, guard = M.now + seconds, 0
    while true do
        local name, earliest
        for candidate, data in pairs(M.timers) do
            if not data.stopped and data.at <= target and (not earliest or data.at < earliest.at) then
                name, earliest = candidate, data
            end
        end
        if not earliest then break end
        guard = guard + 1
        assert(guard < 10000, "runaway timer")
        M.now = earliest.at
        if earliest.repetitions == 1 then
            M.timers[name] = nil
        else
            if earliest.repetitions > 1 then earliest.repetitions = earliest.repetitions - 1 end
            earliest.at = M.now + math.max(earliest.delay, 0.001)
        end
        earliest.callback()
    end
    M.now = target
end

function M.fire(event)
    local snapshot = {}
    for name, callback in pairs(M.hooks[event] or {}) do snapshot[name] = callback end
    for _, callback in pairs(snapshot) do callback() end
end

function M.count(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

function M.loadTool(client)
    M.reset(client)
    M.load("lua/weapons/gmod_tool/stools/npc_scene.lua")
    local player, npc = M.player(), M.entity()
    npc:SetNWString("npcscene_path", "scenes/test")
    npc:SetNWInt("npcscene_index", npc:EntIndex())
    return M.tool(player), player, npc
end

return M
