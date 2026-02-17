---
-- ContractListUtil
-- Data helpers for querying, filtering, and sorting contracts from g_missionManager.
-- Loaded before ContractListHud and ContractListMod (see modDesc.xml order).
---

ContractListUtil = {}

--- Get the current player's farm ID.
-- @return number farmId
function ContractListUtil.getFarmId()
    if g_currentMission ~= nil and g_currentMission.player ~= nil then
        return g_currentMission.player.farmId
    end
    return FarmManager.SPECTATOR_FARM_ID
end

--- Get all active contracts (RUNNING or FINISHED) for the current farm.
-- @return table Array of mission objects
function ContractListUtil.getActiveContracts()
    local farmId = ContractListUtil.getFarmId()
    local result = {}

    if g_missionManager == nil then
        return result
    end

    local missions = g_missionManager:getMissions()
    if missions == nil then
        return result
    end

    for _, mission in ipairs(missions) do
        if mission.farmId == farmId then
            if mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.FINISHED then
                table.insert(result, mission)
            end
        end
    end

    return result
end

--- Get all available contracts (CREATED) visible to the current farm.
-- @return table Array of mission objects
function ContractListUtil.getAvailableContracts()
    local farmId = ContractListUtil.getFarmId()
    local result = {}

    if g_missionManager == nil then
        return result
    end

    local missions = g_missionManager:getMissions()
    if missions == nil then
        return result
    end

    for _, mission in ipairs(missions) do
        if mission.status == MissionStatus.CREATED then
            table.insert(result, mission)
        end
    end

    return result
end

--- Check if the current farm has reached the maximum number of active contracts.
-- @return boolean
function ContractListUtil.hasReachedContractLimit()
    if g_missionManager == nil then
        return true
    end

    local farmId = ContractListUtil.getFarmId()
    return g_missionManager:hasFarmReachedMissionLimit(farmId)
end

--- Get a display-friendly type name for a mission.
-- @param mission table The mission object
-- @return string Human-readable type name
function ContractListUtil.getMissionTypeName(mission)
    if mission.type ~= nil and mission.type.name ~= nil then
        return mission.type.name
    end
    return "Unknown"
end

--- Get the field number string for a mission, if applicable.
-- @param mission table The mission object
-- @return string Field identifier or empty string
function ContractListUtil.getFieldDescription(mission)
    if mission.field ~= nil then
        local fieldId = mission.field.fieldId
        if fieldId ~= nil then
            return string.format("Field %d", fieldId)
        end
    end
    return ""
end
