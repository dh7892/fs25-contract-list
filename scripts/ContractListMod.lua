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

    -- Load saved position
    self:loadSettings()

    self.isLoaded = true
    Logging.info("[ContractList] Mod loaded successfully")
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

--- Toggle the panel visibility and manage mouse cursor.
function ContractListMod:togglePanel()
    if self.hud ~= nil then
        local visible = self.hud:toggleVisible()

        -- Show/hide mouse cursor when panel is open
        if g_inputBinding ~= nil then
            g_inputBinding:setShowMouseCursor(visible)
        end
    end
end

--- Called every frame for logic updates.
function ContractListMod:update(dt)
    if not self.isLoaded then
        return
    end

    -- Re-register input each frame to survive context changes
    self:registerInput()
end

--- Called every frame for rendering.
function ContractListMod:draw()
    if not self.isLoaded then
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

    -- Remove input bindings
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEventsByTarget(self)
    end

    -- Ensure cursor is restored
    if self.hud ~= nil and self.hud:getIsVisible() then
        if g_inputBinding ~= nil then
            g_inputBinding:setShowMouseCursor(false)
        end
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
