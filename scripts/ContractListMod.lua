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

    self.isLoaded = true
    Logging.info("[ContractList] Mod loaded successfully")
end

--- Register (or re-register) the toggle input action.
-- Called every frame from update() because the engine clears action events
-- on input context changes (entering vehicles, opening menus, etc.).
-- This is the standard pattern for addModEventListener-based mods.
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
-- @param unicode number Unicode character code
-- @param sym number Key symbol
-- @param modifier number Modifier key flags
-- @param isDown boolean Key pressed down
function ContractListMod:keyEvent(unicode, sym, modifier, isDown)
    -- No direct key handling needed; using action events via update() registration
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
