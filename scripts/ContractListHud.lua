---
-- ContractListHud
-- Renders the contract list panel as a HUD overlay on the main game screen.
-- Uses Overlay objects for backgrounds and renderText() for labels.
-- Tracks clickable button regions for mouse hit-testing.
-- Supports mouse-wheel scrolling and drag-to-move via the header bar.
---

ContractListHud = {}
local ContractListHud_mt = Class(ContractListHud)

-- Default panel position and size (normalized screen coordinates)
ContractListHud.DEFAULT_X      = 0.78
ContractListHud.DEFAULT_Y      = 0.10
ContractListHud.PANEL_WIDTH    = 0.21
ContractListHud.PANEL_HEIGHT   = 0.80

-- Colors (r, g, b, a)
ContractListHud.COLOR_BG            = {0.01, 0.01, 0.01, 0.82}
ContractListHud.COLOR_HEADER_BG     = {0.08, 0.08, 0.08, 0.95}
ContractListHud.COLOR_HEADER_DRAG   = {0.12, 0.12, 0.18, 0.95}  -- Header while dragging
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
ContractListHud.COLOR_BTN_COLLECT   = {0.20, 0.55, 0.20, 0.90}  -- Green button
ContractListHud.COLOR_BTN_COLLECT_H = {0.25, 0.70, 0.25, 1.00}  -- Green hover
ContractListHud.COLOR_BTN_CANCEL    = {0.55, 0.20, 0.20, 0.90}  -- Red button
ContractListHud.COLOR_BTN_CANCEL_H  = {0.70, 0.25, 0.25, 1.00}  -- Red hover
ContractListHud.COLOR_BTN_TEXT      = {1.0, 1.0, 1.0, 1.0}

-- Text sizes (normalized)
ContractListHud.TEXT_SIZE_TITLE  = 0.020
ContractListHud.TEXT_SIZE_NORMAL = 0.014
ContractListHud.TEXT_SIZE_SMALL  = 0.012
ContractListHud.TEXT_SIZE_TINY   = 0.010

-- Spacing
ContractListHud.HEADER_HEIGHT   = 0.038
ContractListHud.ROW_HEIGHT      = 0.062
ContractListHud.ROW_LINE_GAP    = 0.004
ContractListHud.PADDING         = 0.008
ContractListHud.PADDING_INNER   = 0.006
ContractListHud.PROGRESS_HEIGHT = 0.006
ContractListHud.SCROLLBAR_WIDTH = 0.005
ContractListHud.SCROLL_SPEED    = 3
ContractListHud.BUTTON_HEIGHT   = 0.018
ContractListHud.BUTTON_PADDING  = 0.003

-- Drag settings
ContractListHud.DRAG_DEAD_ZONE  = 0.003   -- Min movement to start drag (normalized)

--- Create a new ContractListHud instance.
-- @return ContractListHud
function ContractListHud.new()
    local self = setmetatable({}, ContractListHud_mt)

    self.isVisible = false
    self.isInitialized = false

    -- Panel position (mutable, can be dragged)
    self.panelX = ContractListHud.DEFAULT_X
    self.panelY = ContractListHud.DEFAULT_Y

    -- Overlays
    self.bgOverlay = nil
    self.headerOverlay = nil
    self.rowOverlay = nil
    self.progressBgOverlay = nil
    self.progressBarOverlay = nil
    self.separatorOverlay = nil
    self.scrollbarBgOverlay = nil
    self.scrollbarOverlay = nil

    -- Scroll state
    self.scrollOffset = 0
    self.maxVisibleRows = 0
    self.totalRows = 0

    -- Mouse tracking
    self.hoveredRow = -1
    self.mouseX = 0
    self.mouseY = 0

    -- Drag state
    self.isDragging = false
    self.dragStartMouseX = 0
    self.dragStartMouseY = 0
    self.dragOffsetX = 0     -- Mouse offset from panel origin at drag start
    self.dragOffsetY = 0
    self.dragStarted = false -- True once mouse moves past dead zone

    -- Click regions: list of {x, y, w, h, action, data} tables
    self.clickRegions = {}

    -- Callback for when position changes (set by ContractListMod for persistence)
    self.onMoveCallback = nil

    -- Callback for contract actions: function(actionType, mission)
    -- actionType: "collect" or "cancel"
    self.onActionCallback = nil

    return self
end

--- Initialize overlay objects. Called once after the game has loaded.
function ContractListHud:init()
    if self.isInitialized then
        return
    end

    local pixelPath = "dataS/scripts/shared/graph_pixel.dds"

    self.bgOverlay          = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.headerOverlay      = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.rowOverlay         = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.progressBgOverlay  = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.progressBarOverlay = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.separatorOverlay   = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.scrollbarBgOverlay = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.scrollbarOverlay   = Overlay.new(pixelPath, 0, 0, 1, 1)
    self.buttonOverlay      = Overlay.new(pixelPath, 0, 0, 1, 1)

    self.isInitialized = true
    Logging.info("[ContractList] HUD initialized")
end

--- Clean up overlay objects.
function ContractListHud:delete()
    local overlays = {
        "bgOverlay", "headerOverlay", "rowOverlay",
        "progressBgOverlay", "progressBarOverlay", "separatorOverlay",
        "scrollbarBgOverlay", "scrollbarOverlay", "buttonOverlay",
    }
    for _, name in ipairs(overlays) do
        if self[name] ~= nil then
            self[name]:delete()
            self[name] = nil
        end
    end
    self.isInitialized = false
end

--- Set the panel position, clamped so the header bar always stays on screen.
-- The body can extend off the bottom of the screen, but the header
-- (the drag handle) must remain fully visible and reachable.
-- @param x number Normalized X (left edge)
-- @param y number Normalized Y (bottom edge)
function ContractListHud:setPosition(x, y)
    local pw = ContractListHud.PANEL_WIDTH
    local ph = ContractListHud.PANEL_HEIGHT
    local headerH = ContractListHud.HEADER_HEIGHT

    -- Horizontal: keep full panel width on screen
    self.panelX = math.max(0, math.min(x, 1.0 - pw))

    -- Vertical: the header is at the top of the panel (y + ph - headerH).
    -- Ensure header top (y + ph) <= 1.0  =>  y <= 1.0 - ph
    -- Ensure header bottom (y + ph - headerH) >= 0  =>  y >= headerH - ph
    -- This lets the body hang off the bottom while the header stays visible.
    self.panelY = math.max(headerH - ph, math.min(y, 1.0 - ph))
end

--- Get the current panel position.
-- @return number x, number y
function ContractListHud:getPosition()
    return self.panelX, self.panelY
end

--- Set a callback to be called when the panel is moved.
-- @param callback function(x, y) Called with new position after drag ends
function ContractListHud:setOnMoveCallback(callback)
    self.onMoveCallback = callback
end

--- Set a callback for contract actions (collect payment, cancel).
-- @param callback function(actionType, mission) Called when a button is clicked
function ContractListHud:setOnActionCallback(callback)
    self.onActionCallback = callback
end

--- Show or hide the panel.
-- @param visible boolean
function ContractListHud:setVisible(visible)
    self.isVisible = visible
    if not visible then
        self.scrollOffset = 0
        self.hoveredRow = -1
        self.isDragging = false
        self.dragStarted = false
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

--- Check if a point is inside the header bar.
-- @param posX number Normalized X
-- @param posY number Normalized Y
-- @return boolean
function ContractListHud:isInsideHeader(posX, posY)
    local headerY = self.panelY + ContractListHud.PANEL_HEIGHT - ContractListHud.HEADER_HEIGHT
    return posX >= self.panelX
       and posX <= self.panelX + ContractListHud.PANEL_WIDTH
       and posY >= headerY
       and posY <= headerY + ContractListHud.HEADER_HEIGHT
end

--- Check if a point is inside the panel.
-- @param posX number Normalized X
-- @param posY number Normalized Y
-- @return boolean
function ContractListHud:isInsidePanel(posX, posY)
    return posX >= self.panelX
       and posX <= self.panelX + ContractListHud.PANEL_WIDTH
       and posY >= self.panelY
       and posY <= self.panelY + ContractListHud.PANEL_HEIGHT
end

--- Draw the HUD panel. Called every frame from ContractListMod:draw().
function ContractListHud:draw()
    if not self.isVisible or not self.isInitialized then
        return
    end

    -- Clear click regions each frame
    self.clickRegions = {}

    local px = self.panelX
    local py = self.panelY
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

    -- Draw header bar at the top (different color while dragging)
    local headerY = py + ph - headerH
    local headerColor = self.isDragging and ContractListHud.COLOR_HEADER_DRAG or ContractListHud.COLOR_HEADER_BG
    self.headerOverlay:setColor(unpack(headerColor))
    self.headerOverlay:setPosition(px, headerY)
    self.headerOverlay:setDimension(pw, headerH)
    self.headerOverlay:render()

    -- Get contract data (before title so we can show count)
    local contracts = ContractListUtil.getActiveContracts()
    self.totalRows = #contracts

    -- Draw title text with count
    local titleText = string.format("%s (%d)", g_i18n:getText("contractList_titleActive"), self.totalRows)
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

    -- Draw drag hint in header (right side)
    local hintText = self.isDragging and "..." or string.format("%d contract%s", self.totalRows, self.totalRows == 1 and "" or "s")
    setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(
        px + pw - pad - ContractListHud.SCROLLBAR_WIDTH - pad,
        headerY + (headerH - ContractListHud.TEXT_SIZE_SMALL) * 0.5,
        ContractListHud.TEXT_SIZE_SMALL,
        hintText
    )

    -- Calculate content area
    local contentTop = headerY - pad
    local contentBottom = py + pad
    local contentHeight = contentTop - contentBottom
    self.maxVisibleRows = math.floor(contentHeight / rowH)

    -- Clamp scroll offset
    local maxScroll = math.max(0, self.totalRows - self.maxVisibleRows)
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, maxScroll))

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

    -- Field + completion % (dimmed, after type name)
    local afterType = getTextWidth(ContractListHud.TEXT_SIZE_NORMAL, data.typeName .. " ")
    local detailParts = {}
    if data.fieldDesc ~= "" then
        table.insert(detailParts, data.fieldDesc)
    end
    if data.isRunning then
        table.insert(detailParts, string.format("%d%%", math.floor(data.completion * 100)))
    end
    if #detailParts > 0 then
        local detailStr = table.concat(detailParts, " | ")
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        renderText(x + pad + afterType, line1Y, ContractListHud.TEXT_SIZE_NORMAL, detailStr)
    end

    -- Reward (right-aligned on line 1)
    local rewardStr = ContractListUtil.formatMoney(data.reward)
    setTextColor(unpack(ContractListHud.COLOR_TEXT))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(x + width - pad, line1Y, ContractListHud.TEXT_SIZE_NORMAL, rewardStr)

    -- == Line 2: NPC (left) | buttons (right) ==
    local line2Y = line1Y - ContractListHud.TEXT_SIZE_SMALL - lineGap

    -- NPC name
    if data.npcName ~= "" then
        setTextColor(unpack(ContractListHud.COLOR_TEXT_DIM))
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(x + pad, line2Y, ContractListHud.TEXT_SIZE_SMALL, data.npcName)
    end

    -- Status / progress / buttons (right side of line 2)
    local btnH = ContractListHud.BUTTON_HEIGHT
    local btnPad = ContractListHud.BUTTON_PADDING
    local btnY = line2Y - btnPad

    if data.isFinished then
        -- "Collect" button for finished contracts
        local btnText = g_i18n:getText("contractList_collectPayment")
        local btnTextW = getTextWidth(ContractListHud.TEXT_SIZE_SMALL, btnText)
        local btnW = btnTextW + btnPad * 4
        local btnX = x + width - pad - btnW

        -- Check if mouse is over this button
        local btnHovered = (self.mouseX >= btnX and self.mouseX <= btnX + btnW
                        and self.mouseY >= btnY and self.mouseY <= btnY + btnH)

        local btnColor = btnHovered and ContractListHud.COLOR_BTN_COLLECT_H or ContractListHud.COLOR_BTN_COLLECT
        self.buttonOverlay:setColor(unpack(btnColor))
        self.buttonOverlay:setPosition(btnX, btnY)
        self.buttonOverlay:setDimension(btnW, btnH)
        self.buttonOverlay:render()

        setTextColor(unpack(ContractListHud.COLOR_BTN_TEXT))
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(btnX + btnW * 0.5, btnY + (btnH - ContractListHud.TEXT_SIZE_SMALL) * 0.5, ContractListHud.TEXT_SIZE_SMALL, btnText)

        -- Register click region
        table.insert(self.clickRegions, {
            x = btnX, y = btnY, w = btnW, h = btnH,
            action = function()
                if self.onActionCallback then
                    self.onActionCallback("collect", mission)
                end
            end,
        })

    elseif data.isRunning then
        -- "Cancel" button
        local btnText = g_i18n:getText("contractList_cancel")
        local btnTextW = getTextWidth(ContractListHud.TEXT_SIZE_SMALL, btnText)
        local btnW = btnTextW + btnPad * 4
        local cancelBtnX = x + width - pad - btnW
        local cancelBtnHovered = (self.mouseX >= cancelBtnX and self.mouseX <= cancelBtnX + btnW
                              and self.mouseY >= btnY and self.mouseY <= btnY + btnH)

        local cancelColor = cancelBtnHovered and ContractListHud.COLOR_BTN_CANCEL_H or ContractListHud.COLOR_BTN_CANCEL
        self.buttonOverlay:setColor(unpack(cancelColor))
        self.buttonOverlay:setPosition(cancelBtnX, btnY)
        self.buttonOverlay:setDimension(btnW, btnH)
        self.buttonOverlay:render()

        setTextColor(unpack(ContractListHud.COLOR_BTN_TEXT))
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(cancelBtnX + btnW * 0.5, btnY + (btnH - ContractListHud.TEXT_SIZE_SMALL) * 0.5, ContractListHud.TEXT_SIZE_SMALL, btnText)

        -- Register click region for cancel
        table.insert(self.clickRegions, {
            x = cancelBtnX, y = btnY, w = btnW, h = btnH,
            action = function()
                if self.onActionCallback then
                    self.onActionCallback("cancel", mission)
                end
            end,
        })
    end
end

--- Draw a scrollbar on the right edge of the content area.
function ContractListHud:drawScrollbar(x, y, w, h)
    self.scrollbarBgOverlay:setColor(unpack(ContractListHud.COLOR_SCROLLBAR_BG))
    self.scrollbarBgOverlay:setPosition(x, y)
    self.scrollbarBgOverlay:setDimension(w, h)
    self.scrollbarBgOverlay:render()

    if self.totalRows > 0 then
        local thumbRatio = self.maxVisibleRows / self.totalRows
        local thumbH = math.max(h * thumbRatio, 0.02)
        local scrollRange = h - thumbH
        local maxScroll = math.max(1, self.totalRows - self.maxVisibleRows)
        local thumbOffset = (self.scrollOffset / maxScroll) * scrollRange
        local thumbY = y + h - thumbH - thumbOffset

        self.scrollbarOverlay:setColor(unpack(ContractListHud.COLOR_SCROLLBAR))
        self.scrollbarOverlay:setPosition(x, thumbY)
        self.scrollbarOverlay:setDimension(w, thumbH)
        self.scrollbarOverlay:render()
    end
end

--- Determine which row index the mouse is hovering over.
-- @return number Row index (1-based into full list) or -1
function ContractListHud:getRowAtPosition(posX, posY)
    local pad = ContractListHud.PADDING
    local headerH = ContractListHud.HEADER_HEIGHT
    local rowH = ContractListHud.ROW_HEIGHT

    local contentTop = self.panelY + ContractListHud.PANEL_HEIGHT - headerH - pad

    if posY > contentTop or posY < self.panelY + pad then
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

--- Handle mouse events for dragging, hover tracking, scrolling, and click detection.
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

    -- === Handle active drag ===
    if self.isDragging then
        if button == Input.MOUSE_BUTTON_LEFT and isUp then
            -- End drag
            self.isDragging = false
            self.dragStarted = false

            -- Notify callback for persistence
            if self.onMoveCallback ~= nil then
                self.onMoveCallback(self.panelX, self.panelY)
            end

            return true
        end

        -- Check if we've moved past the dead zone
        local dx = math.abs(posX - self.dragStartMouseX)
        local dy = math.abs(posY - self.dragStartMouseY)
        if not self.dragStarted then
            if dx > ContractListHud.DRAG_DEAD_ZONE or dy > ContractListHud.DRAG_DEAD_ZONE then
                self.dragStarted = true
            end
        end

        -- Move the panel
        if self.dragStarted then
            local newX = posX - self.dragOffsetX
            local newY = posY - self.dragOffsetY
            self:setPosition(newX, newY)
        end

        return true
    end

    -- === Not currently dragging ===

    -- Check if mouse is inside the panel at all
    if not self:isInsidePanel(posX, posY) then
        self.hoveredRow = -1
        return false
    end

    -- Track hovered row (only when not in header)
    if self:isInsideHeader(posX, posY) then
        self.hoveredRow = -1
    else
        self.hoveredRow = self:getRowAtPosition(posX, posY)
    end

    -- Mouse wheel scrolling
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

    -- Left mouse button
    if button == Input.MOUSE_BUTTON_LEFT then
        if isDown then
            -- Start drag if clicking the header
            if self:isInsideHeader(posX, posY) then
                self.isDragging = true
                self.dragStarted = false
                self.dragStartMouseX = posX
                self.dragStartMouseY = posY
                self.dragOffsetX = posX - self.panelX
                self.dragOffsetY = posY - self.panelY
                return true
            end

            -- Check click regions (buttons)
            for _, region in ipairs(self.clickRegions) do
                if posX >= region.x and posX <= region.x + region.w
                   and posY >= region.y and posY <= region.y + region.h then
                    if region.action ~= nil then
                        region.action(region.data)
                    end
                    return true
                end
            end

            -- Consume click in content area
            return true
        end
    end

    -- Consume all mouse events inside the panel
    return true
end
