---
-- ContractListHud
-- Renders the contract list panel as a HUD overlay on the main game screen.
-- Uses Overlay objects for backgrounds and renderText() for labels.
-- Tracks clickable button regions for mouse hit-testing.
-- Supports mouse-wheel scrolling when the list exceeds the visible area.
---

ContractListHud = {}
local ContractListHud_mt = Class(ContractListHud)

-- Layout constants (normalized screen coordinates)
-- Panel is positioned on the right side of the screen
ContractListHud.PANEL_X = 0.58
ContractListHud.PANEL_Y = 0.10
ContractListHud.PANEL_WIDTH = 0.40
ContractListHud.PANEL_HEIGHT = 0.80

-- Colors (r, g, b, a)
ContractListHud.COLOR_BG            = {0.01, 0.01, 0.01, 0.82}
ContractListHud.COLOR_HEADER_BG     = {0.08, 0.08, 0.08, 0.95}
ContractListHud.COLOR_ROW_BG        = {0.06, 0.06, 0.06, 0.60}
ContractListHud.COLOR_ROW_ALT_BG    = {0.09, 0.09, 0.09, 0.60}
ContractListHud.COLOR_ROW_HOVER_BG  = {0.15, 0.15, 0.20, 0.70}
ContractListHud.COLOR_SEPARATOR     = {0.25, 0.25, 0.25, 0.50}
ContractListHud.COLOR_TITLE         = {1.0, 1.0, 1.0, 1.0}
ContractListHud.COLOR_TEXT          = {0.88, 0.88, 0.88, 1.0}
ContractListHud.COLOR_TEXT_DIM      = {0.55, 0.55, 0.55, 1.0}
ContractListHud.COLOR_GREEN         = {0.30, 0.80, 0.30, 1.0}
ContractListHud.COLOR_YELLOW        = {0.95, 0.75, 0.15, 1.0}
ContractListHud.COLOR_PROGRESS_BG   = {0.15, 0.15, 0.15, 0.80}
ContractListHud.COLOR_PROGRESS_BAR  = {0.35, 0.70, 0.35, 0.90}
ContractListHud.COLOR_SCROLLBAR_BG  = {0.10, 0.10, 0.10, 0.60}
ContractListHud.COLOR_SCROLLBAR     = {0.40, 0.40, 0.40, 0.80}

-- Text sizes (normalized)
ContractListHud.TEXT_SIZE_TITLE  = 0.020
ContractListHud.TEXT_SIZE_NORMAL = 0.014
ContractListHud.TEXT_SIZE_SMALL  = 0.012
ContractListHud.TEXT_SIZE_TINY   = 0.010

-- Spacing
ContractListHud.HEADER_HEIGHT   = 0.038
ContractListHud.ROW_HEIGHT      = 0.055   -- Two-line rows: type+field on line 1, details on line 2
ContractListHud.ROW_LINE_GAP    = 0.004   -- Gap between the two lines within a row
ContractListHud.PADDING         = 0.008
ContractListHud.PADDING_INNER   = 0.006
ContractListHud.PROGRESS_HEIGHT = 0.006   -- Height of inline progress bar
ContractListHud.SCROLLBAR_WIDTH = 0.005
ContractListHud.SCROLL_SPEED    = 3       -- Rows scrolled per mouse wheel tick

--- Create a new ContractListHud instance.
-- @return ContractListHud
function ContractListHud.new()
    local self = setmetatable({}, ContractListHud_mt)

    self.isVisible = false
    self.bgOverlay = nil
    self.headerOverlay = nil
    self.rowOverlay = nil
    self.progressBgOverlay = nil
    self.progressBarOverlay = nil
    self.separatorOverlay = nil
    self.scrollbarBgOverlay = nil
    self.scrollbarOverlay = nil
    self.isInitialized = false

    -- Scroll state
    self.scrollOffset = 0     -- First visible row index (0-based)
    self.maxVisibleRows = 0   -- Computed during draw
    self.totalRows = 0        -- Total contract count

    -- Mouse tracking
    self.hoveredRow = -1      -- Index of the row the mouse is over (-1 = none)
    self.mouseX = 0
    self.mouseY = 0

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

    self.bgOverlay         = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.headerOverlay     = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.rowOverlay        = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.progressBgOverlay = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.progressBarOverlay= Overlay.new(pixelPath, 0, 0, 1, 1)
    self.separatorOverlay  = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.scrollbarBgOverlay= Overlay.new(pixelPath, 0, 0, 1, 1)
    self.scrollbarOverlay  = Overlay.new(pixelPath, 0, 0, 1, 1)

    self.isInitialized = true
    Logging.info("[ContractList] HUD initialized")
end

--- Clean up overlay objects.
function ContractListHud:delete()
    local overlays = {
        "bgOverlay", "headerOverlay", "rowOverlay",
        "progressBgOverlay", "progressBarOverlay", "separatorOverlay",
        "scrollbarBgOverlay", "scrollbarOverlay",
    }
    for _, name in ipairs(overlays) do
        if self[name] ~= nil then
            self[name]:delete()
            self[name] = nil
        end
    end
    self.isInitialized = false
end

--- Show or hide the panel.
-- @param visible boolean
function ContractListHud:setVisible(visible)
    self.isVisible = visible
    if not visible then
        self.scrollOffset = 0
        self.hoveredRow = -1
    end
end

--- Toggle panel visibility.
-- @return boolean New visibility state
function ContractListHud:toggleVisible()
    self:setVisible(not self.isVisible)
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

    -- Clear click regions each frame
    self.clickRegions = {}

    local px = ContractListHud.PANEL_X
    local py = ContractListHud.PANEL_Y
    local pw = ContractListHud.PANEL_WIDTH
    local ph = ContractListHud.PANEL_HEIGHT
    local pad = ContractListHud.PADDING
    local headerH = ContractListHud.HEADER_HEIGHT
    local rowH = ContractListHud.ROW_HEIGHT

    -- Draw panel background
    self.bgOverlay:setColor(unpack(ContractListHud.COLOR_BG))
    self.bgOverlay:setPosition(px, py)
    self.bgOverlay:setDimension(pw, ph)
    self.bgOverlay:render()

    -- Draw header bar at the top
    local headerY = py + ph - headerH
    self.headerOverlay:setColor(unpack(ContractListHud.COLOR_HEADER_BG))
    self.headerOverlay:setPosition(px, headerY)
    self.headerOverlay:setDimension(pw, headerH)
    self.headerOverlay:render()

    -- Draw title text
    local titleText = g_i18n:getText("contractList_titleActive")
    setTextColor(unpack(ContractListHud.COLOR_TITLE))
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(
        px + pad,
        headerY + (headerH - ContractListHud.TEXT_SIZE_TITLE) * 0.5,
        ContractListHud.TEXT_SIZE_TITLE,
        titleText
    )
    setTextBold(false)

    -- Get contract data
    local contracts = ContractListUtil.getActiveContracts()
    self.totalRows = #contracts

    -- Calculate content area
    local contentTop = headerY - pad
    local contentBottom = py + pad
    local contentHeight = contentTop - contentBottom
    self.maxVisibleRows = math.floor(contentHeight / rowH)

    -- Clamp scroll offset
    local maxScroll = math.max(0, self.totalRows - self.maxVisibleRows)
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, maxScroll))

    -- Draw contract count in header (right side)
    local countText = string.format("%d contract%s", self.totalRows, self.totalRows == 1 and "" or "s")
    setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(
        px + pw - pad - ContractListHud.SCROLLBAR_WIDTH - pad,
        headerY + (headerH - ContractListHud.TEXT_SIZE_SMALL) * 0.5,
        ContractListHud.TEXT_SIZE_SMALL,
        countText
    )

    if self.totalRows == 0 then
        -- Empty state
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(
            px + pw * 0.5,
            py + ph * 0.5,
            ContractListHud.TEXT_SIZE_NORMAL,
            g_i18n:getText("contractList_noActiveContracts")
        )
    else
        -- Draw visible rows
        local contentWidth = pw - pad * 2 - ContractListHud.SCROLLBAR_WIDTH - pad
        for i = 1, math.min(self.maxVisibleRows, self.totalRows - self.scrollOffset) do
            local dataIndex = i + self.scrollOffset
            local mission = contracts[dataIndex]
            if mission == nil then
                break
            end

            local rowY = contentTop - (i * rowH)
            if rowY < contentBottom then
                break
            end

            local isHovered = (self.hoveredRow == dataIndex)
            self:drawContractRow(mission, px + pad, rowY, contentWidth, rowH, dataIndex, isHovered)

            -- Draw separator line below row (except last)
            if i < math.min(self.maxVisibleRows, self.totalRows - self.scrollOffset) then
                self.separatorOverlay:setColor(unpack(ContractListHud.COLOR_SEPARATOR))
                self.separatorOverlay:setPosition(px + pad, rowY)
                self.separatorOverlay:setDimension(contentWidth, 0.001)
                self.separatorOverlay:render()
            end
        end

        -- Draw scrollbar if needed
        if self.totalRows > self.maxVisibleRows then
            self:drawScrollbar(px + pw - ContractListHud.SCROLLBAR_WIDTH - pad, contentBottom, ContractListHud.SCROLLBAR_WIDTH, contentHeight)
        end
    end

    -- Reset text state
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

--- Draw a single contract row with two lines of info.
-- Line 1: Type name + field (left), Reward (right)
-- Line 2: NPC name (left), Status/Progress (right)
-- @param mission table The mission object
-- @param x number Left edge
-- @param y number Bottom edge
-- @param width number Row width
-- @param height number Row height
-- @param index number Row index in the full list (1-based)
-- @param isHovered boolean Whether the mouse is over this row
function ContractListHud:drawContractRow(mission, x, y, width, height, index, isHovered)
    local data = ContractListUtil.getMissionDisplayData(mission)
    local pad = ContractListHud.PADDING_INNER
    local lineGap = ContractListHud.ROW_LINE_GAP

    -- Row background (alternating + hover)
    local bgColor
    if isHovered then
        bgColor = ContractListHud.COLOR_ROW_HOVER_BG
    elseif index % 2 == 0 then
        bgColor = ContractListHud.COLOR_ROW_ALT_BG
    else
        bgColor = ContractListHud.COLOR_ROW_BG
    end
    self.rowOverlay:setColor(unpack(bgColor))
    self.rowOverlay:setPosition(x, y)
    self.rowOverlay:setDimension(width, height)
    self.rowOverlay:render()

    -- == Line 1: Type + Field (left) | Reward (right) ==
    local line1Y = y + height - ContractListHud.TEXT_SIZE_NORMAL - pad

    -- Type name (bold, colored by status)
    if data.isFinished then
        setTextColor(unpack(ContractListHud.COLOR_GREEN))
    elseif data.isRunning then
        setTextColor(unpack(ContractListHud.COLOR_YELLOW))
    else
        setTextColor(unpack(ContractListHud.COLOR_TEXT))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    renderText(x + pad, line1Y, ContractListHud.TEXT_SIZE_NORMAL, data.typeName)
    setTextBold(false)

    -- Field description (dimmed, after type name)
    if data.fieldDesc ~= "" then
        local typeW = getTextWidth(ContractListHud.TEXT_SIZE_NORMAL, data.typeName .. " ")
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        renderText(x + pad + typeW, line1Y, ContractListHud.TEXT_SIZE_NORMAL, data.fieldDesc)
    end

    -- Reward (right-aligned on line 1)
    local rewardStr = ContractListUtil.formatMoney(data.reward)
    setTextColor(unpack(ContractListHud.COLOR_TEXT))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(x + width - pad, line1Y, ContractListHud.TEXT_SIZE_NORMAL, rewardStr)

    -- == Line 2: NPC (left) | Status or progress (right) ==
    local line2Y = line1Y - ContractListHud.TEXT_SIZE_SMALL - lineGap

    -- NPC name
    if data.npcName ~= "" then
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(x + pad, line2Y, ContractListHud.TEXT_SIZE_SMALL, data.npcName)
    end

    -- Vehicle cost (if any, shown after NPC)
    if data.vehicleCost > 0 then
        local costStr = "Equipment: " .. ContractListUtil.formatMoney(data.vehicleCost)
        local npcW = 0
        if data.npcName ~= "" then
            npcW = getTextWidth(ContractListHud.TEXT_SIZE_SMALL, data.npcName .. "  ")
        end
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(x + pad + npcW, line2Y, ContractListHud.TEXT_SIZE_SMALL, costStr)
    end

    -- Status / progress (right side of line 2)
    if data.isFinished then
        -- "Finished" label
        setTextColor(unpack(ContractListHud.COLOR_GREEN))
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextBold(true)
        renderText(x + width - pad, line2Y, ContractListHud.TEXT_SIZE_SMALL, g_i18n:getText("contractList_statusFinished"))
        setTextBold(false)
    elseif data.isRunning then
        -- Progress bar + percentage
        local progressW = 0.08
        local progressH = ContractListHud.PROGRESS_HEIGHT
        local progressX = x + width - pad - progressW
        local progressY = line2Y + ContractListHud.TEXT_SIZE_SMALL * 0.2

        -- Background
        self.progressBgOverlay:setColor(unpack(ContractListHud.COLOR_PROGRESS_BG))
        self.progressBgOverlay:setPosition(progressX, progressY)
        self.progressBgOverlay:setDimension(progressW, progressH)
        self.progressBgOverlay:render()

        -- Filled portion
        local fillW = progressW * data.completion
        if fillW > 0 then
            self.progressBarOverlay:setColor(unpack(ContractListHud.COLOR_PROGRESS_BAR))
            self.progressBarOverlay:setPosition(progressX, progressY)
            self.progressBarOverlay:setDimension(fillW, progressH)
            self.progressBarOverlay:render()
        end

        -- Percentage text to left of bar
        local pctStr = string.format("%d%%", math.floor(data.completion * 100))
        setTextColor(unpack(ContractListHud.COLOR_YELLOW))
        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(progressX - pad, line2Y, ContractListHud.TEXT_SIZE_SMALL, pctStr)
    end
end

--- Draw a scrollbar on the right edge of the content area.
-- @param x number Left edge of scrollbar
-- @param y number Bottom of scrollbar track
-- @param w number Width of scrollbar
-- @param h number Height of scrollbar track
function ContractListHud:drawScrollbar(x, y, w, h)
    -- Track background
    self.scrollbarBgOverlay:setColor(unpack(ContractListHud.COLOR_SCROLLBAR_BG))
    self.scrollbarBgOverlay:setPosition(x, y)
    self.scrollbarBgOverlay:setDimension(w, h)
    self.scrollbarBgOverlay:render()

    -- Thumb
    if self.totalRows > 0 then
        local thumbRatio = self.maxVisibleRows / self.totalRows
        local thumbH = math.max(h * thumbRatio, 0.02) -- minimum thumb size
        local scrollRange = h - thumbH
        local maxScroll = math.max(1, self.totalRows - self.maxVisibleRows)
        local thumbOffset = (self.scrollOffset / maxScroll) * scrollRange

        -- Thumb is at top when scrollOffset=0, moves down as we scroll
        local thumbY = y + h - thumbH - thumbOffset

        self.scrollbarOverlay:setColor(unpack(ContractListHud.COLOR_SCROLLBAR))
        self.scrollbarOverlay:setPosition(x, thumbY)
        self.scrollbarOverlay:setDimension(w, thumbH)
        self.scrollbarOverlay:render()
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

--- Determine which row index the mouse is hovering over.
-- @param posX number Normalized X
-- @param posY number Normalized Y
-- @return number Row index (1-based into full list) or -1
function ContractListHud:getRowAtPosition(posX, posY)
    local px = ContractListHud.PANEL_X
    local py = ContractListHud.PANEL_Y
    local ph = ContractListHud.PANEL_HEIGHT
    local pad = ContractListHud.PADDING
    local headerH = ContractListHud.HEADER_HEIGHT
    local rowH = ContractListHud.ROW_HEIGHT

    local contentTop = py + ph - headerH - pad

    -- Check if we're in the content area
    if posY > contentTop or posY < py + pad then
        return -1
    end

    local offsetFromTop = contentTop - posY
    local visibleIndex = math.floor(offsetFromTop / rowH) + 1
    local dataIndex = visibleIndex + self.scrollOffset

    if dataIndex >= 1 and dataIndex <= self.totalRows then
        return dataIndex
    end

    return -1
end

--- Handle mouse events for hover tracking, scrolling, and click detection.
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

    self.mouseX = posX
    self.mouseY = posY

    -- Check if mouse is inside the panel
    if not self:isInsidePanel(posX, posY) then
        self.hoveredRow = -1
        return false
    end

    -- Track hovered row
    self.hoveredRow = self:getRowAtPosition(posX, posY)

    -- Mouse wheel scrolling (button 4 = scroll up, button 5 = scroll down in FS25)
    if isDown then
        if button == Input.MOUSE_BUTTON_WHEEL_UP then
            self.scrollOffset = math.max(0, self.scrollOffset - ContractListHud.SCROLL_SPEED)
            return true
        elseif button == Input.MOUSE_BUTTON_WHEEL_DOWN then
            local maxScroll = math.max(0, self.totalRows - self.maxVisibleRows)
            self.scrollOffset = math.min(maxScroll, self.scrollOffset + ContractListHud.SCROLL_SPEED)
            return true
        end
    end

    -- Consume left clicks inside the panel to prevent game actions
    -- Phase 3 will add actual button hit-testing here
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        -- Check click regions (future: buttons)
        for _, region in ipairs(self.clickRegions) do
            if posX >= region.x and posX <= region.x + region.w
               and posY >= region.y and posY <= region.y + region.h then
                if region.action ~= nil then
                    region.action(region.data)
                end
                return true
            end
        end
        return true
    end

    -- Consume all mouse events inside the panel
    return true
end
