# YRG — YulRun Gaming Master Addon

Modular UI and Quality-of-Life suite for **World of Warcraft Forever (`1.60.1` / `## Interface: 16001`)**, designed to work cleanly across desktop (Keyboard/Mouse) and Steamdeck / Controller UI mode.

- **Version:** `2.4.2`
- **Author:** YulRun Gaming
- **SavedVariables:** `YRGDB`
- **Settings Command:** `/yrg`

---

## Installation

1. Place this folder at:
   `World of Warcraft/_forever_/Interface/AddOns/YRG`
2. Launch WoW Forever (or run `/reload` if already in-game).
3. Open **Options → AddOns → YRG** or run `/yrg` in chat to configure core settings and individual modules.

---

## Core Features (Steamdeck, Chat & Gameplay QOL)

Configured directly on the main `/yrg` settings page (`Core.lua`):

- **Steamdeck & Compact Chat Improvements**
  - **Disable Chat Scroll Bar & Snap Left:** Hides the chat scroll bar and side button strip and snaps the chat window closer to the left screen edge (re-applies cleanly across `/reload` and Controller ↔ Desktop mode switches).
  - **Auto-Hide Chat Input Box:** Docks the input box over the bottom edge of the chat frame and keeps it invisible/mouse-disabled until you start typing (`Enter` or `/`).
  - **Auto-Fade Chat Tabs & Scroll Bar:** Fades tabs and scroll controls out when idle and reveals them on hover.
  - **Half-Radial Gradient Chat Background:** Replaces the default chat backdrop with a smooth dark gradient (`Textures/ChatGradientBg.tga`) with adjustable **Width (%)**, **Height (%)**, and **Opacity (%)**.
  - **Inactivity Chat Fade:** Automatically fades out the chat frame after a configurable timer (`1–30` minutes) with no new messages.
- **General Gameplay Improvements**
  - **Quick Loot:** Accelerates auto-looting when `LOOT_READY` fires.
  - **Max Camera Zoom:** Expands the camera zoom distance factor (`1.9` → `2.6`).
  - **Faster Movie Skip:** Lets `Space`, `Escape`, or `Enter` skip cinematics without confirmation prompts.
  - **Show Flight Times:** Adds estimated flight durations to taxi map tooltips and displays a draggable countdown progress bar while flying.

---

## Modules

Each module can be toggled independently on the main `YRG` panel and has its own dedicated subpage under `/yrg`:

### 1. BetterBagsModule (`Modules/BetterBagsModule.lua`)
- **Controller Mode Separate Bag Strip:** Optionally removes inline bag headers and docks bag buttons into a clean strip above items (`LEFT`, `CENTER`, or `RIGHT` alignment, adjustable row spacing, and optional divider line) for smooth D-pad navigation.
- **Non-Controller Reagent Bag Merge:** Optionally merges your Reagent Bag slots directly into the bottom of Blizzard's Combined Bags window below a subtle dark separator line, with a soft purple tint on empty reagent slots while preserving native item-quality borders on items.
- **Bag Automation & Vendor Utilities (All Modes):**
  - **Auto-Sort Bags on Open**
  - **Auto-Repair Gear at Vendor NPC** with an adjustable copper/silver/gold repair cap (`Unlimited` or `1s–10g`)
  - **Auto-Sell Grey (Poor) Items at Vendor NPC** paired with a **BetterBags: Exclusion List** subpage (supports manual text entry, Shift-Click item links, and drag-and-drop)

### 2. Minimap EXP Tracker (`Modules/MinimapExpTracker.lua`)
- **4-Quadrant Radial EXP & Rested Ring:** Wraps Blizzard's native minimap with selectable color themes, radial fill styles (`Conduit`, `Crystal`, `Flat`, `Runic`), 20-bubble overlays (`Bevel`, `Glass`, `Pins`, `Simple`), opacity controls, master scale, and an option to hide the default Blizzard EXP bar.
- **Minimap Header Cleanup:** Options to always display local time, hide minimap addon buttons until hover, center the minimap title bar, and match title bar width to the info placard.
- **Bottom EXP Percentage Badge:** Always-visible bottom placard with optional decimals (`40.5%`) and adjustable font size.
- **Dynamic Info Placard:** Multi-row panel (`Follow Map Header Orientation` supported) showing:
  - **Row 1:** Selectable left display (**Coordinates**, **Current Gold**, or **None**), free bag slots, remaining ammo/arrows, Warlock Soul Shards, and optional low-bag/ammo raid warnings.
  - **Row 2 (Farming Data):** Estimated Time to Level and session Mob Kills (`Left-Click` opens settings; `Right-Click` resets session trackers).

### 3. QuestTrackerUpdater (`Modules/QuestTrackerUpdater.lua`)
- **Quest Sort Order:** Sorts tracked quests (`None`, `By-Level 1 → 60`, or `By-Level 60 → 1`) across Questie and Blizzard's built-in Quest Trackers while keeping orientation and grow direction intact.
- **Quest Automation:**
  - **Auto-Track Newly Accepted Quests** (enabled by default; keeps Blizzard `autoQuestWatch` synced and tracks accepted quests automatically).
  - **Auto Accept Quests:** Automatically accepts offered quests when speaking to NPCs (hold `Shift` while opening dialog to bypass).

### 4. ClassImprovementsModule (`Modules/ClassImprovementsModule.lua`)
- **Druid Class Bars:** Displays a secondary Mana bar below Rage or Energy on the Player Frame when shifted into Bear or Cat Form.
- **Nameplate Combo Points:** Displays 5 circular combo point pips for Rogues and Cat Form Druids on targeted enemy nameplates, either `Below Nameplate (Smart)` (automatically drops beneath active enemy cast bars) or `Right of Health Bar`, with configurable size, spacing, scale, X/Y offsets, cast-bar extra drop, and a 4/5 test preview toggle.

---

## Slash Commands

| Command | Action |
| :--- | :--- |
| `/yrg` | Opens the YRG settings panel |
| `/bagstrip` / `/betterbags` | Prints BetterBagsModule status |
| `/yrgbagdebug` | Captures container/slot layout diagnostics to `YRGDB` |
| `/yrgcast` | Prints target nameplate, combo point anchor, and cast bar diagnostics |

---

## Project Structure

```text
YRG/
├── YRG.toc                             # Addon manifest & load order
├── Core.lua                            # Namespace (_G.YRG), DB defaults, Settings UI & Steamdeck/QOL engine
├── Modules/
│   ├── BetterBagsModule.lua            # Controller bag strip, Reagent Bag merge & vendor/bag automation
│   ├── MinimapExpTracker.lua           # Radial EXP/Rested ring, EXP badge & dynamic session placard
│   ├── QuestTrackerUpdater.lua         # Quest sorting, auto-track & auto-accept automation
│   └── ClassImprovementsModule.lua     # Druid form Mana bar & circular nameplate combo points
└── Textures/                           # UI textures, radial masks, bar styles, overlays & icon assets
```
