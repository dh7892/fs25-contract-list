---
-- ContractListMod
-- Main entry point for the Contract List mod.
-- Registers as a mod event listener for loadMap, update, draw, mouseEvent, keyEvent.
-- Manages the HUD panel lifecycle and input action binding.
---

ContractListMod = {}

ContractListMod.MOD_NAME = "FS25_ContractList"
ContractListMod.MOD_DIR = g_currentModDirectory or ""

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

    -- Register input action for toggling the panel
    self:registerInput()

    self.isLoaded = true
    Logging.info("[ContractList] Mod loaded successfully")
end

--- Register the toggle keybinding action.
function ContractListMod:registerInput()
    -- Check if the InputAction exists (it should if modDesc.xml loaded correctly)
    if InputAction.CONTRACTLIST_TOGGLE == nil then
        Logging.warning("[ContractList] InputAction.CONTRACTLIST_TOGGLE not found - keybinding may not work")
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
        Logging.info("[ContractList] Input action registered (eventId: %s)", tostring(toggleEventId))
    else
        Logging.warning("[ContractList] Failed to register input action - registerActionEvent returned nil")
    end
end

--- Callback for the toggle keybinding.
-- @param actionName string Name of the triggered action
-- @param inputValue number Input value
function ContractListMod:onToggleAction(actionName, inputValue)
    Logging.info("[ContractList] onToggleAction fired")
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

        Logging.info("[ContractList] Panel %s", visible and "opened" or "closed")
    end
end

--- Called every frame for logic updates.
-- @param dt number Delta time in milliseconds
function ContractListMod:update(dt)
    if not self.isLoaded then
        return
    end
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
-- @param posX number Normalized X position [0,1]
-- @param posY number Normalized Y position [0,1]
-- @param isDown boolean Mouse button pressed down
-- @param isUp boolean Mouse button released
-- @param button number Mouse button index
function ContractListMod:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.isLoaded then
        return
    end

    if self.hud ~= nil then
        self.hud:onMouseEvent(posX, posY, isDown, isUp, button)
    end
end

--- Called for keyboard input events.
-- Provides a fallback toggle if the action event system isn't working.
-- @param unicode number Unicode character code
-- @param sym number Key symbol
-- @param modifier number Modifier key flags
-- @param isDown boolean Key pressed down
function ContractListMod:keyEvent(unicode, sym, modifier, isDown)
    if not self.isLoaded or not isDown then
        return
    end

    -- Fallback: if the registered action event isn't working,
    -- detect Right Ctrl + C directly as an emergency toggle.
    -- Input.KEY_rctrl = 285, Input.KEY_c = 46
    if sym == Input.KEY_c and modifier == Input.MOD_RCTRL then
        Logging.info("[ContractList] Fallback keyEvent toggle triggered (RCtrl+C)")
        self:togglePanel()
    end
end

--- Called when the map is being unloaded. Clean up.
function ContractListMod:deleteMap()
    Logging.info("[ContractList] Unloading mod")

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
