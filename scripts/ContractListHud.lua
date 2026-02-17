---
-- ContractListHud
-- Renders the contract list panel as a HUD overlay on the main game screen.
-- Uses Overlay objects for backgrounds and renderText() for labels.
-- Tracks clickable button regions for mouse hit-testing.
---

ContractListHud = {}
local ContractListHud_mt = Class(ContractListHud)

-- Layout constants (normalized screen coordinates)
-- Panel is positioned on the right side of the screen
ContractListHud.PANEL_X = 0.60        -- Left edge of panel
ContractListHud.PANEL_Y = 0.15        -- Bottom edge of panel
ContractListHud.PANEL_WIDTH = 0.38    -- Panel width
ContractListHud.PANEL_HEIGHT = 0.70   -- Panel height

-- Colors (r, g, b, a)
ContractListHud.COLOR_BG = {0.0, 0.0, 0.0, 0.75}           -- Panel background
ContractListHud.COLOR_HEADER_BG = {0.1, 0.1, 0.1, 0.9}     -- Header bar
ContractListHud.COLOR_TITLE = {1.0, 1.0, 1.0, 1.0}         -- Title text
ContractListHud.COLOR_TEXT = {0.9, 0.9, 0.9, 1.0}           -- Normal text
ContractListHud.COLOR_TEXT_DIM = {0.6, 0.6, 0.6, 1.0}       -- Dimmed text
ContractListHud.COLOR_ACCENT = {0.35, 0.75, 0.35, 1.0}      -- Green accent (finished)
ContractListHud.COLOR_WARNING = {0.9, 0.7, 0.2, 1.0}        -- Yellow (in progress)

-- Text sizes (normalized)
ContractListHud.TEXT_SIZE_TITLE = 0.022
ContractListHud.TEXT_SIZE_NORMAL = 0.016
ContractListHud.TEXT_SIZE_SMALL = 0.013

-- Spacing
ContractListHud.HEADER_HEIGHT = 0.04
ContractListHud.ROW_HEIGHT = 0.035
ContractListHud.PADDING = 0.01

--- Create a new ContractListHud instance.
-- @return ContractListHud
function ContractListHud.new()
    local self = setmetatable({}, ContractListHud_mt)

    self.isVisible = false
    self.bgOverlay = nil
    self.headerOverlay = nil
    self.isInitialized = false

    -- Click regions: list of {x, y, w, h, action, data} tables
    -- Rebuilt each frame during draw()
    self.clickRegions = {}

    return self
end

--- Initialize overlay objects. Called once after the game has loaded.
function ContractListHud:init()
    if self.isInitialized then
        return
    end

    -- Use the engine's built-in pixel texture for solid-color rectangles
    local pixelPath = "dataS/scripts/shared/graph_pixel.dds"

    -- Main panel background
    self.bgOverlay = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.bgOverlay:setColor(unpack(ContractListHud.COLOR_BG))

    -- Header bar
    self.headerOverlay = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.headerOverlay:setColor(unpack(ContractListHud.COLOR_HEADER_BG))

    self.isInitialized = true

    Logging.info("[ContractList] HUD initialized")
end

--- Clean up overlay objects.
function ContractListHud:delete()
    if self.bgOverlay ~= nil then
        self.bgOverlay:delete()
        self.bgOverlay = nil
    end
    if self.headerOverlay ~= nil then
        self.headerOverlay:delete()
        self.headerOverlay = nil
    end
    self.isInitialized = false
end

--- Show or hide the panel.
-- @param visible boolean
function ContractListHud:setVisible(visible)
    self.isVisible = visible
end

--- Toggle panel visibility.
-- @return boolean New visibility state
function ContractListHud:toggleVisible()
    self.isVisible = not self.isVisible
    return self.isVisible
end

--- Get current visibility state.
-- @return boolean
function ContractListHud:getIsVisible()
    return self.isVisible
end

--- Draw the HUD panel. Called every frame from ContractListMod:draw().
function ContractListHud:draw()
    if not self.isVisible or not self.isInitialized then
        return
    end

    -- Clear click regions each frame (rebuilt during rendering)
    self.clickRegions = {}

    local panelX = ContractListHud.PANEL_X
    local panelY = ContractListHud.PANEL_Y
    local panelW = ContractListHud.PANEL_WIDTH
    local panelH = ContractListHud.PANEL_HEIGHT
    local padding = ContractListHud.PADDING
    local headerH = ContractListHud.HEADER_HEIGHT

    -- Draw panel background
    self.bgOverlay:setPosition(panelX, panelY)
    self.bgOverlay:setDimension(panelW, panelH)
    self.bgOverlay:render()

    -- Draw header bar at the top of the panel
    local headerY = panelY + panelH - headerH
    self.headerOverlay:setPosition(panelX, headerY)
    self.headerOverlay:setDimension(panelW, headerH)
    self.headerOverlay:render()

    -- Draw title text centered in header
    local titleText = g_i18n:getText("contractList_titleActive")
    setTextColor(unpack(ContractListHud.COLOR_TITLE))
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    renderText(
        panelX + panelW * 0.5,
        headerY + headerH * 0.25,
        ContractListHud.TEXT_SIZE_TITLE,
        titleText
    )
    setTextBold(false)

    -- Draw contract list content
    local contentY = headerY - padding
    local contracts = ContractListUtil.getActiveContracts()

    if #contracts == 0 then
        -- Empty state message
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(
            panelX + panelW * 0.5,
            contentY - ContractListHud.ROW_HEIGHT,
            ContractListHud.TEXT_SIZE_NORMAL,
            g_i18n:getText("contractList_noActiveContracts")
        )
    else
        -- Render each contract row
        for i, mission in ipairs(contracts) do
            local rowY = contentY - (i * ContractListHud.ROW_HEIGHT)

            -- Stop rendering if we've gone below the panel
            if rowY < panelY + padding then
                break
            end

            self:drawContractRow(mission, panelX + padding, rowY, panelW - padding * 2)
        end
    end

    -- Reset text state
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

--- Draw a single contract row.
-- @param mission table The mission object
-- @param x number Left edge X position
-- @param y number Bottom edge Y position
-- @param width number Available width for the row
function ContractListHud:drawContractRow(mission, x, y, width)
    local isFinished = mission.status == MissionStatus.FINISHED
    local isRunning = mission.status == MissionStatus.RUNNING

    -- Type name
    local typeName = ContractListUtil.getMissionTypeName(mission)
    local fieldDesc = ContractListUtil.getFieldDescription(mission)

    -- Choose text color based on status
    if isFinished then
        setTextColor(unpack(ContractListHud.COLOR_ACCENT))
    elseif isRunning then
        setTextColor(unpack(ContractListHud.COLOR_WARNING))
    else
        setTextColor(unpack(ContractListHud.COLOR_TEXT))
    end

    -- Contract type and field
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    renderText(x, y, ContractListHud.TEXT_SIZE_NORMAL, typeName)
    setTextBold(false)

    if fieldDesc ~= "" then
        local typeWidth = getTextWidth(ContractListHud.TEXT_SIZE_NORMAL, typeName .. "  ")
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        renderText(x + typeWidth, y, ContractListHud.TEXT_SIZE_SMALL, fieldDesc)
    end

    -- Reward (right-aligned)
    local reward = mission:getReward()
    if reward ~= nil then
        local rewardText = string.format("$%d", reward)
        setTextColor(unpack(ContractListHud.COLOR_TEXT))
        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(x + width, y, ContractListHud.TEXT_SIZE_NORMAL, rewardText)
    end

    -- Status indicator / completion
    if isFinished then
        local statusText = g_i18n:getText("contractList_statusFinished")
        setTextColor(unpack(ContractListHud.COLOR_ACCENT))
        setTextAlignment(RenderText.ALIGN_RIGHT)
        local statusX = x + width - 0.08
        renderText(statusX, y, ContractListHud.TEXT_SIZE_SMALL, statusText)
    elseif isRunning then
        local completion = mission:getCompletion()
        if completion ~= nil then
            local progressText = string.format("%d%%", math.floor(completion * 100))
            setTextColor(unpack(ContractListHud.COLOR_WARNING))
            setTextAlignment(RenderText.ALIGN_RIGHT)
            local progressX = x + width - 0.08
            renderText(progressX, y, ContractListHud.TEXT_SIZE_SMALL, progressText)
        end
    end
end

--- Check if a screen position is inside the panel.
-- @param posX number Normalized X position
-- @param posY number Normalized Y position
-- @return boolean
function ContractListHud:isInsidePanel(posX, posY)
    return posX >= ContractListHud.PANEL_X
       and posX <= ContractListHud.PANEL_X + ContractListHud.PANEL_WIDTH
       and posY >= ContractListHud.PANEL_Y
       and posY <= ContractListHud.PANEL_Y + ContractListHud.PANEL_HEIGHT
end

--- Handle mouse events for click detection.
-- @param posX number Normalized X position
-- @param posY number Normalized Y position
-- @param isDown boolean Mouse button pressed
-- @param isUp boolean Mouse button released
-- @param button number Mouse button index
-- @return boolean True if event was consumed
function ContractListHud:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.isVisible then
        return false
    end

    -- Check if mouse is inside the panel at all
    if not self:isInsidePanel(posX, posY) then
        return false
    end

    -- For now (Phase 1), just consume mouse events inside the panel
    -- to prevent game input from leaking through.
    -- Phase 3 will add actual button click handling here.

    return true
end
