---
-- ContractListEvents
-- Network events for multiplayer-safe contract actions.
-- In MP, g_missionManager:startMission/cancelMission/dismissMission are
-- server-only (they assert getIsServer()). These events allow clients to
-- request contract actions that the server then executes.
--
-- Pattern: static sendEvent() checks g_server ~= nil.
--   - If server: execute directly.
--   - If client: serialize and send to server via g_client:getServerConnection().
--
-- Missions are identified across the network by their unique generationId
-- (an integer assigned by g_missionManager when the mission is generated).
---

-- ============================================================================
-- Helper: find a mission by its generationId
-- ============================================================================

--- Find a mission object by its generationId.
-- @param generationId number The mission's generationId
-- @return table|nil The mission object, or nil if not found
local function findMissionById(generationId)
    if g_missionManager == nil then
        return nil
    end

    local missions = g_missionManager:getMissions()
    if missions == nil then
        return nil
    end

    for _, mission in ipairs(missions) do
        if mission.generationId == generationId then
            return mission
        end
    end

    return nil
end

-- ============================================================================
-- ContractListStartEvent: Accept/start a contract
-- ============================================================================

ContractListStartEvent = {}
local ContractListStartEvent_mt = Class(ContractListStartEvent, Event)

InitEventClass(ContractListStartEvent, "ContractListStartEvent")

function ContractListStartEvent.emptyNew()
    local self = Event.new(ContractListStartEvent_mt)
    return self
end

function ContractListStartEvent.new(generationId, farmId)
    local self = ContractListStartEvent.emptyNew()
    self.generationId = generationId
    self.farmId = farmId
    return self
end

function ContractListStartEvent:readStream(streamId, connection)
    self.generationId = streamReadInt32(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self:run(connection)
end

function ContractListStartEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.generationId)
    streamWriteUIntN(streamId, self.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
end

function ContractListStartEvent:run(connection)
    -- This runs on the server when received from a client
    if not connection:getIsServer() then
        local mission = findMissionById(self.generationId)
        if mission == nil then
            Logging.warning("[ContractList] StartEvent: mission not found (generationId=%d)", self.generationId)
            return
        end

        if mission.status ~= MissionStatus.CREATED then
            Logging.warning("[ContractList] StartEvent: mission not in CREATED status (status=%s)", tostring(mission.status))
            return
        end

        if g_missionManager:hasFarmReachedMissionLimit(self.farmId) then
            Logging.info("[ContractList] StartEvent: farm %d has reached contract limit", self.farmId)
            return
        end

        local success, err = pcall(function()
            g_missionManager:startMission(mission, self.farmId, false)
        end)

        if success then
            Logging.info("[ContractList] StartEvent: mission started (generationId=%d, farmId=%d)",
                self.generationId, self.farmId)
        else
            Logging.warning("[ContractList] StartEvent: failed to start mission: %s", tostring(err))
        end
    end
end

--- Send a start event. If we're the server, execute directly; otherwise send to server.
-- @param mission table The mission to start
-- @param farmId number The farm ID accepting the contract
function ContractListStartEvent.sendEvent(mission, farmId)
    if mission == nil or mission.generationId == nil then
        Logging.warning("[ContractList] StartEvent.sendEvent: invalid mission or missing generationId")
        return
    end

    if g_server ~= nil then
        -- We are the server: execute directly
        if mission.status ~= MissionStatus.CREATED then
            Logging.warning("[ContractList] StartEvent: mission not in CREATED status")
            return
        end

        if g_missionManager:hasFarmReachedMissionLimit(farmId) then
            Logging.info("[ContractList] Cannot accept: contract limit reached")
            return
        end

        local success, err = pcall(function()
            g_missionManager:startMission(mission, farmId, false)
        end)

        if success then
            Logging.info("[ContractList] Mission started directly (server, generationId=%d)",
                mission.generationId)
        else
            Logging.warning("[ContractList] Failed to start mission: %s", tostring(err))
        end
    else
        -- We are a client: send event to server
        g_client:getServerConnection():sendEvent(
            ContractListStartEvent.new(mission.generationId, farmId)
        )
        Logging.info("[ContractList] StartEvent sent to server (generationId=%d, farmId=%d)",
            mission.generationId, farmId)
    end
end

-- ============================================================================
-- ContractListCancelEvent: Cancel a running contract
-- ============================================================================

ContractListCancelEvent = {}
local ContractListCancelEvent_mt = Class(ContractListCancelEvent, Event)

InitEventClass(ContractListCancelEvent, "ContractListCancelEvent")

function ContractListCancelEvent.emptyNew()
    local self = Event.new(ContractListCancelEvent_mt)
    return self
end

function ContractListCancelEvent.new(generationId)
    local self = ContractListCancelEvent.emptyNew()
    self.generationId = generationId
    return self
end

function ContractListCancelEvent:readStream(streamId, connection)
    self.generationId = streamReadInt32(streamId)
    self:run(connection)
end

function ContractListCancelEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.generationId)
end

function ContractListCancelEvent:run(connection)
    if not connection:getIsServer() then
        local mission = findMissionById(self.generationId)
        if mission == nil then
            Logging.warning("[ContractList] CancelEvent: mission not found (generationId=%d)", self.generationId)
            return
        end

        if mission.status ~= MissionStatus.RUNNING then
            Logging.warning("[ContractList] CancelEvent: mission not RUNNING (status=%s)", tostring(mission.status))
            return
        end

        local success, err = pcall(function()
            g_missionManager:cancelMission(mission)
        end)

        if success then
            Logging.info("[ContractList] CancelEvent: mission cancelled (generationId=%d)", self.generationId)
        else
            Logging.warning("[ContractList] CancelEvent: failed to cancel: %s", tostring(err))
        end
    end
end

--- Send a cancel event.
-- @param mission table The mission to cancel
function ContractListCancelEvent.sendEvent(mission)
    if mission == nil or mission.generationId == nil then
        Logging.warning("[ContractList] CancelEvent.sendEvent: invalid mission or missing generationId")
        return
    end

    if g_server ~= nil then
        if mission.status ~= MissionStatus.RUNNING then
            Logging.warning("[ContractList] CancelEvent: mission not RUNNING")
            return
        end

        local success, err = pcall(function()
            g_missionManager:cancelMission(mission)
        end)

        if success then
            Logging.info("[ContractList] Mission cancelled directly (server, generationId=%d)",
                mission.generationId)
        else
            Logging.warning("[ContractList] Failed to cancel mission: %s", tostring(err))
        end
    else
        g_client:getServerConnection():sendEvent(
            ContractListCancelEvent.new(mission.generationId)
        )
        Logging.info("[ContractList] CancelEvent sent to server (generationId=%d)",
            mission.generationId)
    end
end

-- ============================================================================
-- ContractListDismissEvent: Dismiss/collect payment for a finished contract
-- ============================================================================

ContractListDismissEvent = {}
local ContractListDismissEvent_mt = Class(ContractListDismissEvent, Event)

InitEventClass(ContractListDismissEvent, "ContractListDismissEvent")

function ContractListDismissEvent.emptyNew()
    local self = Event.new(ContractListDismissEvent_mt)
    return self
end

function ContractListDismissEvent.new(generationId)
    local self = ContractListDismissEvent.emptyNew()
    self.generationId = generationId
    return self
end

function ContractListDismissEvent:readStream(streamId, connection)
    self.generationId = streamReadInt32(streamId)
    self:run(connection)
end

function ContractListDismissEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.generationId)
end

function ContractListDismissEvent:run(connection)
    if not connection:getIsServer() then
        local mission = findMissionById(self.generationId)
        if mission == nil then
            Logging.warning("[ContractList] DismissEvent: mission not found (generationId=%d)", self.generationId)
            return
        end

        if mission.status ~= MissionStatus.FINISHED then
            Logging.warning("[ContractList] DismissEvent: mission not FINISHED (status=%s)", tostring(mission.status))
            return
        end

        local success, err = pcall(function()
            g_missionManager:dismissMission(mission)
        end)

        if success then
            Logging.info("[ContractList] DismissEvent: payment collected (generationId=%d)", self.generationId)
        else
            Logging.warning("[ContractList] DismissEvent: failed to dismiss: %s", tostring(err))
        end
    end
end

--- Send a dismiss event.
-- @param mission table The mission to dismiss (collect payment)
function ContractListDismissEvent.sendEvent(mission)
    if mission == nil or mission.generationId == nil then
        Logging.warning("[ContractList] DismissEvent.sendEvent: invalid mission or missing generationId")
        return
    end

    if g_server ~= nil then
        if mission.status ~= MissionStatus.FINISHED then
            Logging.warning("[ContractList] DismissEvent: mission not FINISHED")
            return
        end

        local success, err = pcall(function()
            g_missionManager:dismissMission(mission)
        end)

        if success then
            Logging.info("[ContractList] Payment collected directly (server, generationId=%d)",
                mission.generationId)
        else
            Logging.warning("[ContractList] Failed to dismiss mission: %s", tostring(err))
        end
    else
        g_client:getServerConnection():sendEvent(
            ContractListDismissEvent.new(mission.generationId)
        )
        Logging.info("[ContractList] DismissEvent sent to server (generationId=%d)",
            mission.generationId)
    end
end
