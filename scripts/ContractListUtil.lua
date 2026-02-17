---
-- ContractListUtil
-- Data helpers for querying, filtering, and sorting contracts from g_missionManager.
-- Loaded before ContractListHud and ContractListMod (see modDesc.xml order).
---

ContractListUtil = {}

-- Human-readable names for mission types.
-- Keys are the internal type names from mission.type.name.
ContractListUtil.TYPE_DISPLAY_NAMES = {
    harvestMission       = "Harvest",
    sowMission           = "Sowing",
    plowMission          = "Plowing",
    cultivateMission     = "Cultivating",
    fertilizeMission     = "Fertilizing",
    herbicideMission     = "Spraying",
    weedMission          = "Weeding",
    hoeMission           = "Hoeing",
    mowMission           = "Mowing",
    tedderMission        = "Tedding",
    baleMission          = "Baling",
    baleWrapMission      = "Bale Wrapping",
    stonePickMission     = "Stone Picking",
    deadwoodMission      = "Deadwood",
    treeTransportMission = "Tree Transport",
    destructibleRockMission = "Rock Destruction",
}

--- Get the current player's farm ID.
-- Tries multiple access paths as the API varies between FS versions.
-- @return number farmId
function ContractListUtil.getFarmId()
    -- Method 1: Direct player farmId
    if g_currentMission ~= nil and g_currentMission.player ~= nil then
        if g_currentMission.player.farmId ~= nil then
            return g_currentMission.player.farmId
        end
    end

    -- Method 2: Via accessHandler
    if g_currentMission ~= nil and g_currentMission.accessHandler ~= nil then
        local success, farmId = pcall(function()
            return g_currentMission.accessHandler:getFarmId()
        end)
        if success and farmId ~= nil then
            return farmId
        end
    end

    -- Method 3: Via farmManager, get first non-spectator farm
    if g_farmManager ~= nil then
        local success, farms = pcall(function()
            return g_farmManager:getFarms()
        end)
        if success and farms ~= nil then
            for _, farm in ipairs(farms) do
                if farm.farmId ~= nil and farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
                    return farm.farmId
                end
            end
        end
    end

    return FarmManager.SPECTATOR_FARM_ID
end

--- Get all active contracts (RUNNING or FINISHED) for the current farm.
-- Returns them sorted: FINISHED first, then RUNNING sorted by completion descending.
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

    -- Log diagnostics once (first call only)
    if not ContractListUtil._hasLoggedDiag then
        ContractListUtil._hasLoggedDiag = true
        Logging.info("[ContractList] Diagnostics: farmId=%s, total missions=%d",
            tostring(farmId), #missions)
        -- Log only active missions (owned by this farm) for clearer diagnostics
        local logCount = 0
        for i, m in ipairs(missions) do
            if m.farmId == farmId and (m.status == MissionStatus.RUNNING or m.status == MissionStatus.FINISHED) then
                logCount = logCount + 1
                Logging.info("[ContractList]   active[%d]: status=%s, farmId=%s, type=%s, field=%s",
                    logCount,
                    tostring(m.status),
                    tostring(m.farmId),
                    m.type and m.type.name or "nil",
                    m.field and tostring(m.field.fieldId) or "nil")
            end
        end
        Logging.info("[ContractList] Found %d active contracts for farm %s", logCount, tostring(farmId))
    end

    for _, mission in ipairs(missions) do
        if mission.farmId == farmId then
            if mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.FINISHED then
                table.insert(result, mission)
            end
        end
    end

    -- Sort: finished contracts first, then by completion % descending
    table.sort(result, function(a, b)
        if a.status == MissionStatus.FINISHED and b.status ~= MissionStatus.FINISHED then
            return true
        elseif a.status ~= MissionStatus.FINISHED and b.status == MissionStatus.FINISHED then
            return false
        end

        local compA = ContractListUtil.getCompletion(a)
        local compB = ContractListUtil.getCompletion(b)
        return compA > compB
    end)

    return result
end

--- Get all available contracts (CREATED) visible to the current farm.
-- @return table Array of mission objects
function ContractListUtil.getAvailableContracts()
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
        local displayName = ContractListUtil.TYPE_DISPLAY_NAMES[mission.type.name]
        if displayName ~= nil then
            return displayName
        end
        return mission.type.name
    end
    return "Unknown"
end

--- Get a short context string for a mission based on its type.
-- For field missions: "Field 5" or "Field 5 - Wheat"
-- For transport missions: tries to extract pickup/delivery from getDetails()
-- For other missions: uses getLocation() or title
-- @param mission table The mission object
-- @return string Context description or empty string
function ContractListUtil.getFieldDescription(mission)
    local typeName = mission.type and mission.type.name or ""

    -- Field-based missions: show field number + crop if available
    if mission.field ~= nil then
        local parts = {}

        -- Field ID
        if mission.field.fieldId ~= nil then
            table.insert(parts, string.format("Field %d", mission.field.fieldId))
        end

        -- Crop name for harvest/sow missions
        local cropName = ContractListUtil.getCropName(mission)
        if cropName ~= "" then
            table.insert(parts, cropName)
        end

        if #parts > 0 then
            return table.concat(parts, " - ")
        end
    end

    -- Non-field missions: try to build a useful description
    -- from getDetails() or getLocation()
    local extraInfo = ContractListUtil.getExtraInfo(mission)
    if extraInfo ~= "" then
        return extraInfo
    end

    -- Fallback: try getLocation()
    local success, location = pcall(function() return mission:getLocation() end)
    if success and location ~= nil and location ~= "" then
        return location
    end

    return ""
end

--- Get the crop/fruit name for a mission.
-- @param mission table The mission object
-- @return string Crop name or empty string
function ContractListUtil.getCropName(mission)
    -- Try fruitTypeIndex (sow/harvest missions)
    if mission.fruitTypeIndex ~= nil and g_fruitTypeManager ~= nil then
        local success, result = pcall(function()
            local fillType = g_fruitTypeManager.fruitTypeIndexToFillType[mission.fruitTypeIndex]
            if fillType ~= nil and fillType.title ~= nil then
                return fillType.title
            end
            return nil
        end)
        if success and result ~= nil then
            return result
        end
    end

    -- Try fillTypeIndex (harvest missions)
    if mission.fillTypeIndex ~= nil and g_fillTypeManager ~= nil then
        local success, result = pcall(function()
            local fillType = g_fillTypeManager.fillTypes[mission.fillTypeIndex]
            if fillType ~= nil and fillType.title ~= nil then
                return fillType.title
            end
            return nil
        end)
        if success and result ~= nil then
            return result
        end
    end

    return ""
end

--- Extract extra info from a mission's details or properties.
-- Particularly useful for transport missions where we want pickup/delivery locations.
-- @param mission table The mission object
-- @return string Extra info string or empty string
function ContractListUtil.getExtraInfo(mission)
    local typeName = mission.type and mission.type.name or ""

    -- For tree transport: try to find selling station name and any location info
    if typeName == "treeTransportMission" or typeName == "supplyTransportMission" then
        local parts = {}

        -- Try sellingStation (delivery point)
        if mission.sellingStation ~= nil then
            local success, name = pcall(function() return mission.sellingStation:getName() end)
            if success and name ~= nil and name ~= "" then
                table.insert(parts, "To: " .. name)
            end
        end

        -- Try loadingStation / pickupStation (pickup point)
        if mission.loadingStation ~= nil then
            local success, name = pcall(function() return mission.loadingStation:getName() end)
            if success and name ~= nil and name ~= "" then
                table.insert(parts, "From: " .. name)
            end
        end

        if #parts > 0 then
            return table.concat(parts, " | ")
        end

        -- Fallback: parse getDetails() for location info
        return ContractListUtil.extractLocationFromDetails(mission)
    end

    return ""
end

--- Parse getDetails() to extract location-related values.
-- @param mission table The mission object
-- @return string Location info or empty string
function ContractListUtil.extractLocationFromDetails(mission)
    local success, details = pcall(function() return mission:getDetails() end)
    if not success or details == nil then
        return ""
    end

    -- Log details once per mission type for debugging
    local typeName = mission.type and mission.type.name or "unknown"
    if not ContractListUtil._loggedDetailTypes then
        ContractListUtil._loggedDetailTypes = {}
    end
    if not ContractListUtil._loggedDetailTypes[typeName] then
        ContractListUtil._loggedDetailTypes[typeName] = true
        Logging.info("[ContractList] Details for %s:", typeName)
        for i, detail in ipairs(details) do
            Logging.info("[ContractList]   [%d] title=%s, value=%s",
                i, tostring(detail.title), tostring(detail.value))
        end

        -- Also dump direct properties for transport missions
        if typeName == "treeTransportMission" then
            Logging.info("[ContractList] TreeTransport properties:")
            for k, v in pairs(mission) do
                if type(v) ~= "function" and type(v) ~= "table" then
                    Logging.info("[ContractList]   %s = %s", tostring(k), tostring(v))
                elseif type(v) == "table" then
                    Logging.info("[ContractList]   %s = [table]", tostring(k))
                end
            end
        end
    end

    -- Look for location-related detail entries
    local parts = {}
    for _, detail in ipairs(details) do
        local titleLower = detail.title and string.lower(detail.title) or ""
        -- Match common location-related titles
        if string.find(titleLower, "location") or string.find(titleLower, "pickup")
           or string.find(titleLower, "deliver") or string.find(titleLower, "drop")
           or string.find(titleLower, "station") or string.find(titleLower, "destination")
           or string.find(titleLower, "from") or string.find(titleLower, "to") then
            if detail.value ~= nil and detail.value ~= "" then
                table.insert(parts, detail.value)
            end
        end
    end

    if #parts > 0 then
        return table.concat(parts, " | ")
    end

    return ""
end

--- Get the NPC name associated with a mission.
-- @param mission table The mission object
-- @return string NPC name or empty string
function ContractListUtil.getNpcName(mission)
    if mission.npc ~= nil and mission.npc.title ~= nil then
        return mission.npc.title
    end
    -- Some missions store npc name differently
    local success, npc = pcall(function() return mission:getNPC() end)
    if success and npc ~= nil and npc.title ~= nil then
        return npc.title
    end
    return ""
end

--- Get the reward for a mission, safely.
-- @param mission table The mission object
-- @return number Reward amount or 0
function ContractListUtil.getReward(mission)
    local success, reward = pcall(function() return mission:getReward() end)
    if success and reward ~= nil then
        return reward
    end
    return 0
end

--- Get the total reward (reward - vehicle costs + reimbursement) for a mission.
-- @param mission table The mission object
-- @return number Total reward or 0
function ContractListUtil.getTotalReward(mission)
    local success, reward = pcall(function() return mission:getTotalReward() end)
    if success and reward ~= nil then
        return reward
    end
    -- Fallback to base reward
    return ContractListUtil.getReward(mission)
end

--- Get the vehicle costs for a mission.
-- @param mission table The mission object
-- @return number Vehicle costs or 0
function ContractListUtil.getVehicleCosts(mission)
    local success, costs = pcall(function() return mission:getVehicleCosts() end)
    if success and costs ~= nil then
        return costs
    end
    return 0
end

--- Get the completion fraction for a mission.
-- @param mission table The mission object
-- @return number Completion 0.0-1.0
function ContractListUtil.getCompletion(mission)
    if mission.status == MissionStatus.FINISHED then
        return 1.0
    end
    local success, completion = pcall(function() return mission:getCompletion() end)
    if success and completion ~= nil then
        return completion
    end
    return 0
end

--- Format a money amount as a string.
-- @param amount number The amount
-- @return string Formatted string like "$12,345"
function ContractListUtil.formatMoney(amount)
    if amount == nil then
        return "$0"
    end

    local formatted = tostring(math.floor(amount))
    -- Insert commas for thousands
    local result = ""
    local count = 0
    for i = #formatted, 1, -1 do
        count = count + 1
        result = string.sub(formatted, i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end

    return "$" .. result
end

--- Build a structured data table for a mission suitable for display.
-- @param mission table The mission object
-- @return table {typeName, fieldDesc, npcName, reward, totalReward, vehicleCost, completion, isFinished, isRunning, mission}
function ContractListUtil.getMissionDisplayData(mission)
    local isFinished = mission.status == MissionStatus.FINISHED
    local isRunning = mission.status == MissionStatus.RUNNING

    return {
        typeName    = ContractListUtil.getMissionTypeName(mission),
        fieldDesc   = ContractListUtil.getFieldDescription(mission),
        npcName     = ContractListUtil.getNpcName(mission),
        reward      = ContractListUtil.getReward(mission),
        totalReward = ContractListUtil.getTotalReward(mission),
        vehicleCost = ContractListUtil.getVehicleCosts(mission),
        completion  = ContractListUtil.getCompletion(mission),
        isFinished  = isFinished,
        isRunning   = isRunning,
        mission     = mission,
    }
end
