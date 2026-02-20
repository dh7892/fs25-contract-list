---
-- ContractListMod
-- Main entry point for the Contract List mod.
-- Registers as a mod event listener for loadMap, update, draw, mouseEvent, keyEvent.
-- Manages the HUD panel lifecycle, input action binding, and settings persistence.
---

ContractListMod = {}

ContractListMod.MOD_NAME = "FS25_ContractList"
ContractListMod.MOD_DIR = g_currentModDirectory or ""
ContractListMod.SETTINGS_FILE = "modSettings/FS25_ContractList.xml"

-- Singleton instance state
ContractListMod.hud = nil
ContractListMod.toggleEventId = nil
ContractListMod.isLoaded = false

-- Built-in progress bar suppression state
ContractListMod.suppressBuiltinProgress = false
ContractListMod._origAddSideNotificationProgressBar = nil
ContractListMod._origMarkSideNotificationProgressBarForDrawing = nil
ContractListMod._origRemoveSideNotificationProgressBar = nil
ContractListMod._hudOverridesInstalled = false

-- Input capture state (prevent scroll zoom and click-to-switch over panel)
ContractListMod._inputOverridesInstalled = false

--- Called when the map is loaded. Initialize the mod.
-- @param filename string Map filename
function ContractListMod:loadMap(filename)
    Logging.info("[ContractList] Loading mod (map: %s)", filename)

    -- Create and initialize the HUD
    self.hud = ContractListHud.new()
    self.hud:init()

    -- Set up position persistence callback
    self.hud:setOnMoveCallback(function(x, y)
        ContractListMod:saveSettings()
    end)

    -- Set up contract action callback
    self.hud:setOnActionCallback(function(actionType, mission)
        ContractListMod:onContractAction(actionType, mission)
    end)

    -- Load saved position
    self:loadSettings()

    -- Install built-in progress bar suppression hooks
    self:installProgressBarOverrides()

    -- Install input capture overrides (block scroll zoom / click-to-switch over panel)
    self:installInputOverrides()

    self.isLoaded = true
    Logging.info("[ContractList] Mod loaded successfully")
end

--- Install overrides on camera zoom and click-to-switch to prevent
-- game input from passing through our HUD panel.
-- Uses the AutoDrive pattern: a per-frame flag set in mouseEvent(),
-- checked in the zoom override. This avoids complex hit-testing in
-- the override function itself.
function ContractListMod:installInputOverrides()
    if self._inputOverridesInstalled then
        return
    end

    -- Override VehicleCamera.zoomSmoothly (AutoDrive's exact pattern)
    -- This is the low-level zoom function called by the camera system.
    -- We check the flag set by ContractListHud:onMouseEvent() when it
    -- consumes a scroll wheel event.
    if VehicleCamera ~= nil and VehicleCamera.zoomSmoothly ~= nil then
        VehicleCamera.zoomSmoothly = Utils.overwrittenFunction(
            VehicleCamera.zoomSmoothly,
            function(self, superFunc, offset, ...)
                if ContractListHud.mouseWheelUsed then
                    return
                end
                return superFunc(self, offset, ...)
            end
        )
        Logging.info("[ContractList] VehicleCamera.zoomSmoothly override installed")
    end

    -- Override GuiTopDownCamera.onZoom (map view zoom, AutoDrive also does this)
    if GuiTopDownCamera ~= nil and GuiTopDownCamera.onZoom ~= nil then
        GuiTopDownCamera.onZoom = Utils.overwrittenFunction(
            GuiTopDownCamera.onZoom,
            function(self, superFunc, ...)
                if ContractListHud.mouseWheelUsed then
                    return
                end
                return superFunc(self, ...)
            end
        )
        Logging.info("[ContractList] GuiTopDownCamera.onZoom override installed")
    end

    -- Override click-to-switch-vehicle when clicking on our panel
    if Player ~= nil and Player.enterVehicleRaycastClickToSwitch ~= nil then
        Player.enterVehicleRaycastClickToSwitch = Utils.overwrittenFunction(
            Player.enterVehicleRaycastClickToSwitch,
            function(self, superFunc, x, y, ...)
                local success, isOver = pcall(function()
                    local hud = ContractListMod.hud
                    if hud ~= nil and hud.isVisible then
                        return hud:isInsidePanel(hud.mouseX, hud.mouseY)
                    end
                    return false
                end)
                if success and isOver then
                    return
                end
                return superFunc(self, x, y, ...)
            end
        )
        Logging.info("[ContractList] Click-to-switch override installed")
    end

    self._inputOverridesInstalled = true
end

--- Install overrides on the game HUD to conditionally suppress mission progress bars.
-- When our panel is visible, the built-in side notification progress bars are suppressed.
-- When our panel is hidden, they work normally.
function ContractListMod:installProgressBarOverrides()
    if self._hudOverridesInstalled then
        return
    end

    -- g_currentMission.hud may not be available yet at loadMap time;
    -- we'll try in update() if it fails here
    if g_currentMission == nil or g_currentMission.hud == nil then
        Logging.info("[ContractList] HUD not available yet, will install overrides later")
        return
    end

    local hud = g_currentMission.hud

    -- Check that the methods exist before overriding
    if hud.addSideNotificationProgressBar == nil then
        Logging.info("[ContractList] addSideNotificationProgressBar not found, skipping overrides")
        return
    end

    -- Save originals
    self._origAddSideNotificationProgressBar = hud.addSideNotificationProgressBar
    self._origMarkSideNotificationProgressBarForDrawing = hud.markSideNotificationProgressBarForDrawing
    self._origRemoveSideNotificationProgressBar = hud.removeSideNotificationProgressBar

    -- Override: addSideNotificationProgressBar
    -- When suppressed, return a dummy object so AbstractMission.update() doesn't error
    hud.addSideNotificationProgressBar = function(hudSelf, title, subtitle, progress)
        if ContractListMod.suppressBuiltinProgress then
            return { progress = progress or 0, _isDummy = true }
        end
        return ContractListMod._origAddSideNotificationProgressBar(hudSelf, title, subtitle, progress)
    end

    -- Override: markSideNotificationProgressBarForDrawing
    -- When suppressed, skip marking (so nothing draws)
    hud.markSideNotificationProgressBarForDrawing = function(hudSelf, bar)
        if ContractListMod.suppressBuiltinProgress then
            return
        end
        if ContractListMod._origMarkSideNotificationProgressBarForDrawing ~= nil then
            ContractListMod._origMarkSideNotificationProgressBarForDrawing(hudSelf, bar)
        end
    end

    -- Override: removeSideNotificationProgressBar
    -- Handle dummy bars gracefully (don't pass them to the original)
    hud.removeSideNotificationProgressBar = function(hudSelf, bar)
        if bar ~= nil and bar._isDummy then
            return  -- dummy bar, nothing to remove
        end
        if ContractListMod._origRemoveSideNotificationProgressBar ~= nil then
            ContractListMod._origRemoveSideNotificationProgressBar(hudSelf, bar)
        end
    end

    self._hudOverridesInstalled = true
    Logging.info("[ContractList] Built-in progress bar overrides installed")
end

--- Remove existing progress bars from all active missions and nil them out.
-- Called when our panel opens so the bars disappear immediately.
function ContractListMod:removeExistingProgressBars()
    if g_missionManager == nil or g_currentMission == nil or g_currentMission.hud == nil then
        return
    end

    local missions = g_missionManager:getMissions()
    if missions == nil then
        return
    end

    for _, mission in ipairs(missions) do
        if mission.progressBar ~= nil and not mission.progressBar._isDummy then
            local success, _ = pcall(function()
                self._origRemoveSideNotificationProgressBar(g_currentMission.hud, mission.progressBar)
            end)
            if not success then
                -- If remove failed, just nil it out
            end
        end
        mission.progressBar = nil
    end
end

--- Restore progress bars by clearing mission.progressBar so AbstractMission:update()
-- recreates them on the next frame.
function ContractListMod:clearProgressBarReferences()
    if g_missionManager == nil then
        return
    end

    local missions = g_missionManager:getMissions()
    if missions == nil then
        return
    end

    for _, mission in ipairs(missions) do
        -- Nil out the progressBar so AbstractMission:update() will create a fresh one
        mission.progressBar = nil
    end
end

--- Load settings (panel position) from XML file.
function ContractListMod:loadSettings()
    local filePath = getUserProfileAppPath() .. ContractListMod.SETTINGS_FILE

    if not fileExists(filePath) then
        Logging.info("[ContractList] No settings file found, using defaults")
        return
    end

    local xmlFile = loadXMLFile("ContractListSettings", filePath)
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[ContractList] Failed to load settings file")
        return
    end

    local posX = getXMLFloat(xmlFile, "ContractList.hud#posX")
    local posY = getXMLFloat(xmlFile, "ContractList.hud#posY")
    local height = getXMLFloat(xmlFile, "ContractList.hud#height")

    if height ~= nil then
        self.hud:setHeight(height)
        Logging.info("[ContractList] Loaded panel height: %.3f", height)
    end

    if posX ~= nil and posY ~= nil then
        self.hud:setPosition(posX, posY)
        Logging.info("[ContractList] Loaded panel position: %.3f, %.3f", posX, posY)
    end

    delete(xmlFile)
end

--- Save settings (panel position) to XML file.
function ContractListMod:saveSettings()
    if self.hud == nil then
        return
    end

    local filePath = getUserProfileAppPath() .. ContractListMod.SETTINGS_FILE
    local dirPath = getUserProfileAppPath() .. "modSettings"

    -- Ensure modSettings directory exists
    createFolder(dirPath)

    local xmlFile = createXMLFile("ContractListSettings", filePath, "ContractList")
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[ContractList] Failed to create settings file")
        return
    end

    local posX, posY = self.hud:getPosition()
    setXMLFloat(xmlFile, "ContractList.hud#posX", posX)
    setXMLFloat(xmlFile, "ContractList.hud#posY", posY)
    setXMLFloat(xmlFile, "ContractList.hud#height", self.hud:getHeight())

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

--- Register (or re-register) the toggle input action.
-- Called every frame from update() because the engine clears action events
-- on input context changes (entering vehicles, opening menus, etc.).
function ContractListMod:registerInput()
    -- Clean up previous registration
    if self.toggleEventId ~= nil then
        g_inputBinding:removeActionEvent(self.toggleEventId)
        self.toggleEventId = nil
    end

    if InputAction.CONTRACTLIST_TOGGLE == nil then
        return
    end

    local _, toggleEventId = g_inputBinding:registerActionEvent(
        InputAction.CONTRACTLIST_TOGGLE,
        self,
        ContractListMod.onToggleAction,
        false,  -- triggerUp
        true,   -- triggerDown
        false,  -- triggerAlways
        true    -- isActive
    )

    if toggleEventId ~= nil then
        self.toggleEventId = toggleEventId
        g_inputBinding:setActionEventTextPriority(toggleEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventText(toggleEventId, g_i18n:getText("contractList_toggleAction"))
        g_inputBinding:setActionEventTextVisibility(toggleEventId, true)
    end
end

--- Callback for the toggle keybinding.
function ContractListMod:onToggleAction(actionName, inputValue)
    self:togglePanel()
end

--- Handle contract actions from HUD button clicks.
-- Uses network events so actions work in both singleplayer and multiplayer.
-- In SP (where we are the server), the event executes directly.
-- In MP clients, the event is sent to the server for execution.
-- @param actionType string "collect", "cancel", or "accept"
-- @param mission table The mission object
function ContractListMod:onContractAction(actionType, mission)
    if mission == nil or g_missionManager == nil then
        return
    end

    if actionType == "collect" then
        -- Dismiss a finished contract (collects payment)
        if mission.status == MissionStatus.FINISHED then
            Logging.info("[ContractList] Collecting payment for mission: %s",
                tostring(ContractListUtil.getMissionTypeName(mission)))
            ContractListDismissEvent.sendEvent(mission)
        end

    elseif actionType == "cancel" then
        -- Cancel a running contract
        if mission.status == MissionStatus.RUNNING then
            Logging.info("[ContractList] Cancelling mission: %s",
                tostring(ContractListUtil.getMissionTypeName(mission)))
            ContractListCancelEvent.sendEvent(mission)
        end

    elseif actionType == "accept" then
        -- Accept an available contract (without borrowing vehicles)
        if mission.status == MissionStatus.CREATED then
            local farmId = ContractListUtil.getFarmId()
            Logging.info("[ContractList] Accepting mission: %s (farmId=%s, generationId=%s)",
                tostring(ContractListUtil.getMissionTypeName(mission)),
                tostring(farmId),
                tostring(mission.generationId))

            if mission.generationId == nil then
                -- generationId not available -- fall back to direct call (SP only)
                Logging.warning("[ContractList] Mission has no generationId, using direct start")
                if g_server ~= nil then
                    mission.farmId = farmId
                    local success, err = pcall(function()
                        g_missionManager:startMission(mission)
                    end)
                    if success then
                        if mission.farmId ~= farmId then
                            mission.farmId = farmId
                        end
                        Logging.info("[ContractList] Mission accepted (direct fallback)")
                    else
                        Logging.warning("[ContractList] Direct start failed: %s", tostring(err))
                    end
                else
                    Logging.warning("[ContractList] Cannot accept without generationId in MP")
                end
            else
                ContractListStartEvent.sendEvent(mission, farmId)
            end
        end
    end
end

--- Toggle the panel visibility and manage mouse cursor.
function ContractListMod:togglePanel()
    if self.hud ~= nil then
        local visible = self.hud:toggleVisible()
        self:applyPanelState(visible)
    end
end

--- Explicitly close the panel (used by safety auto-close).
function ContractListMod:closePanel()
    if self.hud ~= nil and self.hud:getIsVisible() then
        self.hud:setVisible(false)
        self:applyPanelState(false)
    end
end

--- Apply side effects of panel visibility change (progress bars).
-- The panel does NOT manage the mouse cursor -- cursor visibility is
-- left to the player / other mods (e.g. right-click or middle-click).
-- @param visible boolean Whether the panel is now visible
function ContractListMod:applyPanelState(visible)
    -- Suppress/restore built-in progress bars
    if self._hudOverridesInstalled then
        self.suppressBuiltinProgress = visible
        if visible then
            -- Panel opened: remove existing bars immediately
            self:removeExistingProgressBars()
        else
            -- Panel closed: clear references so bars get recreated next frame
            self:clearProgressBarReferences()
        end
    end
end

--- Check if the game is in a state where our panel should not be shown
-- (e.g., the ESC menu, any dialog, the map screen, the shop, etc.).
-- If so, auto-close the panel to prevent cursor/input lockup.
-- @return boolean True if a GUI screen is active and panel should be hidden
function ContractListMod:isGameGuiActive()
    if g_gui ~= nil and g_gui.currentGuiName ~= nil and g_gui.currentGuiName ~= "" then
        return true
    end
    return false
end

--- Called every frame for logic updates.
function ContractListMod:update(dt)
    if not self.isLoaded then
        return
    end

    -- Re-register input each frame to survive context changes
    self:registerInput()

    -- Retry installing progress bar overrides if they weren't ready at load time
    if not self._hudOverridesInstalled then
        self:installProgressBarOverrides()
    end

    -- Safety: auto-close panel if a game GUI/menu is active.
    -- This prevents the cursor from getting stuck when the user opens
    -- the ESC menu, shop, map, etc. while our panel is visible.
    if self.hud ~= nil and self.hud:getIsVisible() then
        if self:isGameGuiActive() then
            Logging.info("[ContractList] GUI detected while panel open, auto-closing")
            self:closePanel()
        end
    end
end

--- Called every frame for rendering.
function ContractListMod:draw()
    if not self.isLoaded then
        return
    end

    -- Don't draw over game GUI screens (ESC menu, shop, map, etc.)
    if self:isGameGuiActive() then
        return
    end

    if self.hud ~= nil then
        self.hud:draw()
    end
end

--- Called for mouse input events.
function ContractListMod:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isLoaded then
        return
    end

    -- Don't consume mouse events when a game GUI is active
    if self:isGameGuiActive() then
        return
    end

    if self.hud ~= nil then
        self.hud:onMouseEvent(posX, posY, isDown, isUp, button)
    end
end

--- Called for keyboard input events.
function ContractListMod:keyEvent(unicode, sym, modifier, isDown)
    -- No direct key handling needed; using action events via update() registration
end

--- Called when the map is being unloaded. Clean up.
function ContractListMod:deleteMap()
    Logging.info("[ContractList] Unloading mod")

    -- Save settings before cleanup
    self:saveSettings()

    -- Restore built-in progress bar functions
    self.suppressBuiltinProgress = false
    if self._hudOverridesInstalled and g_currentMission ~= nil and g_currentMission.hud ~= nil then
        local hud = g_currentMission.hud
        if self._origAddSideNotificationProgressBar ~= nil then
            hud.addSideNotificationProgressBar = self._origAddSideNotificationProgressBar
        end
        if self._origMarkSideNotificationProgressBarForDrawing ~= nil then
            hud.markSideNotificationProgressBarForDrawing = self._origMarkSideNotificationProgressBarForDrawing
        end
        if self._origRemoveSideNotificationProgressBar ~= nil then
            hud.removeSideNotificationProgressBar = self._origRemoveSideNotificationProgressBar
        end
        self:clearProgressBarReferences()
        Logging.info("[ContractList] Built-in progress bar overrides restored")
    end
    self._hudOverridesInstalled = false
    self._origAddSideNotificationProgressBar = nil
    self._origMarkSideNotificationProgressBarForDrawing = nil
    self._origRemoveSideNotificationProgressBar = nil

    -- Remove input bindings
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEventsByTarget(self)
    end

    -- Clean up HUD
    if self.hud ~= nil then
        self.hud:delete()
        self.hud = nil
    end

    self.isLoaded = false
    self.toggleEventId = nil
end

-- Register as a mod event listener so the engine calls our lifecycle methods
addModEventListener(ContractListMod)
