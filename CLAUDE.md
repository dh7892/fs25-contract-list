# FS25_ContractList - Mod Development Guide

## Project Overview

A Farming Simulator 25 mod that provides a toggleable HUD overlay on the main game screen for managing contracts without menu diving. Users press **Left Alt + C** (rebindable) to open/close a panel that lists contracts and allows interaction via mouse clicks.

## Tech Stack

- **Language**: Lua (GIANTS Engine scripting)
- **Engine**: GIANTS Engine 10 (Farming Simulator 25)
- **Mod descriptor version**: 97+
- **UI approach**: Hybrid HUD overlay with manual mouse hit-testing (not a dialog/menu)

## File Structure

```
FS25_ContractList/
├── modDesc.xml                  # Mod manifest (required, loaded by game)
├── icon_contractList.dds        # Mod icon (256x256 DDS for ModHub, PNG for dev)
├── CLAUDE.md                    # This file - agent guidance
├── scripts/
│   ├── ContractListMod.lua      # Main entry point, lifecycle hooks, event listener
│   ├── ContractListHud.lua      # HUD panel rendering (overlays + text + hit regions)
│   ├── ContractListUtil.lua     # Data helpers (query/filter/sort contracts)
│   └── ContractListEvents.lua   # Multiplayer network events (accept/dismiss/cancel)
├── languages/
│   ├── l10n_en.xml              # English strings
│   └── l10n_de.xml              # German strings
```

## Key FS25 APIs Used

### Contract/Mission System
- `g_missionManager:getMissions()` - Get all missions
- `g_missionManager:getMissionsByFarmId(farmId)` - Missions visible to a farm
- `g_missionManager:startMission(mission)` - Accept a contract
- `g_missionManager:cancelMission(mission)` - Cancel active contract
- `g_missionManager:dismissMission(mission)` - Collect payment on finished contract
- `g_missionManager:hasFarmReachedMissionLimit(farmId)` - Check contract limit
- `mission:getCompletion()` - Progress 0.0-1.0
- `mission:getIsRunning()` / `getIsFinished()` / `getIsReadyToStart()` - Status checks
- `mission:getTitle()`, `getReward()`, `getTotalReward()`, `getVehicleCosts()` - Details

### Mission Status Lifecycle
`CREATED` -> `PREPARING` -> `RUNNING` -> `FINISHED` -> `DISMISSED`

### HUD Rendering
- `Overlay.new(texturePath, x, y, width, height)` - Create overlay
- `renderOverlay(id, x, y, w, h)` - Draw overlay
- `renderText(x, y, fontSize, text)` - Draw text
- `setTextColor(r, g, b, a)`, `setTextBold()`, `setTextAlignment()` - Text style
- `getTextWidth(size, text)`, `getTextHeight(size, text)` - Text measurement
- Coordinates are normalized [0,1], origin at bottom-left

### Input System
- Actions defined in `modDesc.xml` `<actions>` + `<inputBinding>`
- `g_inputBinding:registerActionEvent(action, target, callback, ...)` - Register handler
- `addModEventListener(obj)` - Register for loadMap/update/draw/mouseEvent/keyEvent

### Key Globals
- `g_missionManager` - Mission/contract manager
- `g_currentMission` - Current game session
- `g_inputBinding` - Input binding manager
- `g_gui` - GUI controller
- `g_i18n:getText(key)` - Localized string lookup

## Implementation Phases

### Phase 1: Scaffold & Toggle (DONE)
- modDesc.xml, input action, basic HUD panel that toggles on/off

### Phase 2: Display Active Contracts (DONE)
- Query g_missionManager, render list of active/finished contracts
- Show type, field, NPC, reward, vehicle cost, completion % with progress bar
- Sorted: finished first, then by completion descending
- Mouse-wheel scrolling, hover highlighting, alternating row backgrounds

### Phase 3: Click Interaction - Dismiss/Collect (DONE)
- "Collect" button on finished contracts calls dismissMission() to collect payment
- "Cancel" button on running contracts calls cancelMission()
- Buttons have hover highlight states (green for collect, red for cancel)
- Click regions registered each frame and tested in mouseEvent()
- Draggable panel via header bar with position persistence

### Phase 4: Multiplayer Support
- Network events for server-authoritative contract mutations

### Phase 5: Available Contracts View (DONE)
- Tab switching (Active / Available) with click-to-switch tab bar
- Accept button on available contracts (tryToAccept + startMission fallback)
- Contract limit check before accepting
- Built-in progress bars hidden when panel is open, restored on close

### Phase 6: Progress Bars
- Horizontal completion bars per active contract

### Phase 7: Polish & QoL
- Sorting, filtering, persistence, full localization, ModHub prep

## Coding Conventions

- Use `CamelCase` for class/module names (e.g., `ContractListMod`)
- Use `camelCase` for function and variable names
- Prefix private/internal functions with no underscore (Lua convention in FS mods)
- All user-facing strings go through `g_i18n:getText()` with keys in l10n XML
- Log with `Logging.info()`, `Logging.warning()`, `Logging.error()`
- Mod name constant: `ContractListMod.MOD_NAME = "FS25_ContractList"`
- Use `source()` sparingly; prefer loading scripts via modDesc.xml `<extraSourceFiles>`

## Testing

- Place/symlink the mod folder into the FS25 mods directory
- Check `log.txt` in the FS25 user data folder for errors on load
- The game's `-cheats` launch flag enables the developer console
- Test in both singleplayer and multiplayer (hosted + dedicated)

## Compatibility Notes

- Should work alongside ContractBoost (we only read from g_missionManager, CB modifies limits/rewards)
- No vehicle specializations = no vehicle mod conflicts
- Multiplayer: all mutation actions must go through network events (Phase 4)
