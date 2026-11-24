# YRG — YulRun Gaming Master Addon

Modular UI and Quality-of-Life suite for **World of Warcraft Forever (`1.60.1` / `## Interface: 16001`)**, designed to work cleanly across desktop (Keyboard/Mouse) and Steamdeck / Controller UI mode.

- **Version:** `2.4.5`
- **Author:** Shaemus Shadowstep & Sylas Swiftarrow | NA RP-PVP
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
- **Controller Mode Separate Bag Strip:** Removes inline bag headers and docks bag buttons into a clean strip above items (`LEFT`, `CENTER`, or `RIGHT` alignment, adjustable row spacing, and optional 3D beveled divider line). Includes an optional **Scale Bag Buttons to Fit Column Width (Steamdeck Fix)** toggle for `GamepadBagBar` while keeping Blizzard's native Gamepad D-Pad navigation and container item actions smooth and taint-free (including during combat).
- **Desktop Combined Bags & Reagent Bag Merge:** Merges your Reagent Bag cleanly into a dedicated bottom section separated by a 3D beveled divider with soft purple tinting on empty reagent slots (while preserving item-quality borders), alongside live Search, Sort, translucent Money pill, Free Slots footer, and **Unlock Combined Bags Frame to Move (Non-Controller)** + position reset.
- **Layout, Ammo & Visibility Options (All Modes):**
  - **Empty Cell Location:** Anchor unused slots at `Top-Left`, `Bottom-Right`, or `Dynamic` (`10`, `9`, or `8` column auto-fit).
  - **Separate Quiver / Ammo Pouch Row:** Splits your equipped Quiver or Ammo Pouch into its own bottom section separated by a 3D beveled divider with bottom clearance in both Desktop and Controller modes.
  - **Wash Out Grey (Poor Quality) Items:** Enabled by default; desaturates grey junk icons to greyscale at `95%` opacity with softer contrast across both Desktop custom bags and native/Controller bags.
- **Bag Automation & Vendor Utilities (All Modes):**
  - **Auto-Sort Bags on Open**
  - **Auto-Open Clams on Loot** (opens looted clams out of combat when general bag space is available)
  - **Show Waylaid Crate Auctionator Costs in Tooltip:** Appends estimated Auction House bundle costs beside each requirement on Waylaid Supplies Crate tooltips when Auctionator is loaded.
  - **Auto-Repair Gear at Vendor NPC** with an adjustable copper/silver/gold repair cap (`Unlimited` or `1s–10g`)
  - **Auto-Sell Grey (Poor) Items at Vendor NPC** paired with a **BetterBags: Exclusion List** subpage (supports manual text entry, Shift-Click item links, and drag-and-drop)

### 2. Minimap EXP Tracker (`Modules/MinimapExpTracker.lua`)
- **4-Quadrant Radial EXP & Rested Ring:** Wraps Blizzard's native minimap with selectable color themes, radial fill styles (`Conduit`, `Crystal`, `Flat`, `Runic`), 20-bubble overlays (`Bevel`, `Glass`, `Pins`, `Simple`), opacity controls, **Minimap Master Scale**, independent **Minimap & EXP Ring Scale** (`0.60`–`1.50`), top-of-screen clamp protection (`10 px` clearance across scale/header layouts), and an option to hide the default Blizzard EXP bar.
- **Minimap Header Cleanup:** Options to always display local time and hide minimap addon buttons until hover.
- **Bottom EXP Percentage Badge:** Always-visible bottom placard with optional decimals (`40.5%`) and adjustable font size.

### 3. Dynamic Info Placard (`Modules/DynamicInfoPlacard.lua`)
Independent minimap placard that works seamlessly alongside **Minimap EXP Tracker** or standalone:
- **Layout & Anchoring:** Choose **Location** (`Bottom` / `Top`) and **Anchor Point** (`Zone Title` / `Minimap`) plus vertical offset alignment. Selecting **Zone Title** automatically centers the minimap Zone Title bar and extends it to match the Info Placard width.
- **Row 1:** Selectable left display (**Coordinates**, **Current Gold**, or **None**), free bag slots, remaining ammo/arrows (with separate Hunter vs. Rogue/Warrior warning thresholds), Warlock Soul Shards, and optional low-bag/ammo raid warnings.
- **Row 2 (Farming Data):** Estimated Time to Level and Estimated Mob Kills tracked purely from combat kill XP (`Left-Click` opens settings; `Right-Click` resets kill pace trackers).

### 4. QuestTrackerUpdater (`Modules/QuestTrackerUpdater.lua`)
- **Quest Sort Order:** Sorts tracked quests (`None`, `By-Level 1 → 60`, or `By-Level 60 → 1`) across Questie and Blizzard's built-in Quest Trackers while keeping orientation and grow direction intact.
- **Quest Automation:**
  - **Auto-Track Newly Accepted Quests** (enabled by default; keeps Blizzard `autoQuestWatch` synced and tracks accepted quests automatically).
  - **Auto Accept Quests:** Automatically accepts offered quests when speaking to NPCs (hold `Shift` while opening dialog to bypass).

### 5. ClassImprovementsModule (`Modules/ClassImprovementsModule.lua`)
- **Druid Class Bars:** Displays a secondary Mana bar below Rage or Energy on the Player Frame when shifted into Bear or Cat Form.
- **Nameplate Combo Points:** Displays 5 circular combo point pips for Rogues and Cat Form Druids on targeted enemy nameplates, either `Below Nameplate (Smart)` (automatically drops beneath active enemy cast bars) or `Right of Health Bar`, with configurable size, spacing, scale, X/Y offsets, cast-bar extra drop, and a 4/5 test preview toggle.
- **OB Prep (One-Button Prep):** Cross-class single-button preparation via the `YRGOBP` macro (`/yrgobprep`, with `/yrgrogueprep` / `YRGRP` preserved for backwards compatibility). Checks and applies 1 action per press in priority order: **Poisons** (Rogues) → **Item Enhancements** (`Wizard / Mana Oils`, superseding `Sharpening / Weight Stones` when both are checked) → **Food Buff** → **Potions / Elixirs** → **Class Self-Buffs** (level-aware priority per class or custom **Override Default Class Buffs CSV**). Automatically warns and skips missing or unusable steps so later buffs still apply, and prevents getting stuck on more powerful active buffs via both proactive aura/rank checks and live `UI_ERROR_MESSAGE` tracking. Features separate early-overbuff sliders for Weapons/Poisons and Buffs/Consumables plus a **OB Prep: Consumables & Buffs** subpage for Shift-Click / drag-and-drop configuration.
- **Hunter Pet AutoFeeder:** Automatically detects your pet's diet (`GetPetFoodTypes` + family fallback) and picks the lowest-quality usable food for its level first. Supports both Controller/SteamDeck activation via the `YRGPF` macro (`/yrg petfeed`) and PC activation by clicking the Pet Happiness frame (`PetFrameHappiness`), prints what was fed (or why no usable food was found) to chat, and includes an **Ignore Crafted / Buff Foods** toggle plus a **Hunter Pet AutoFeeder: Blacklist** subpage supporting typing, Shift-Click links, and drag-and-drop.
- **Hunter Better Party Member:** Automatically sets your Hunter pet to **Passive** and disables **Growl** auto-cast upon entering party, raid, or scenario instances.

### 6. CompactControllerBar (`Modules/CompactControllerBar.lua`)
- **Controller-Only Single Bar:** Integrates `TriggerBar`'s single-bar compact gamepad hotbar as a native YRG module (desktop UI stays completely untouched; disabling restores Blizzard's default gamepad bar cleanly after closing `/yrg`).
- **Whole-Bar Move & Scale:** Includes a draggable whole-bar overlay (with a `Vertical Only` / `All Directions` mover toggle plus **Lock Centered Horizontally** option defaulted ON to lock X=0, center snap, and corner drag-wheel scaling) alongside **Scale** (`50%`–`150%`) and **X/Y Offset** controls.
- **Button Spacing & Arrangement:** Customize **Button Padding / Spacing** (`0`–`16 px`) and **Button Arrangement** (`XYBA` (Default): `Left, Up, Right, Down / X, Y, B, A` or `XYAB`: `Left, Up, Down, Right / X, Y, A, B`).
- **Inline Square Extra Class/Pet/Stance Buttons & Centered Selection Wheel:** Docks `LT+LB` and `RT+RB` extra buttons inline left and right of the bar (or below as fallback), optionally styles them as `32x32` squares matching the main slots with `50%` scaled `LT+LB` / `RT+RB` prompts, and centers radial/flyout selection wheels on screen while keeping both extra buttons and hotbar slots anchored on the bar.
- **Look, Background & Labels:** Includes **Show Placard Bar Background** toggle (matching YRG's 9-slice placard frame with ~5 px internal padding around the bar and square extra buttons), compact top-left **Trigger Guide Icons** (`LT` / `RT`, lighting individually or together), matching top-right **Page Numbers** (white with yellow underline for the active page, semi-transparent for inactive pages) with **Page Number Size**, **Controller Button Icon Size**, **Controller Button Icon Position** (`Centered Below Button` or `Top-Left Corner`), **Button Icon Vertical Offset** (keeping `LT+LB` / `RT+RB` labels vertically aligned), and **Flash Slot on Controller Press** toggles.

---

## Slash Commands

| Command | Action |
| :--- | :--- |
| `/yrg` | Opens the YRG settings panel |
| `/bagstrip` / `/betterbags` | Prints BetterBagsModule status |
| `/yrgbagdebug` | Captures container/slot layout diagnostics to `YRGDB` |
| `/yrgcast` | Prints target nameplate, combo point anchor, and cast bar diagnostics |
| `/yrgobprep` (alias `/yrgrogueprep`) | Evaluates and prepares 1 OB Prep step (supports `status`, `macro`, `clear`, and `debug`) |
| `/yrg petfeed` (alias `/yrgpetfeed`) | Evaluates and prepares Hunter Pet AutoFeeder (supports `status`, `macro`, `clear`, and `debug`) |

---

## Project Structure

```text
YRG/
├── YRG.toc                             # Addon manifest & load order
├── Core.lua                            # Namespace (_G.YRG), DB defaults, Settings UI & Steamdeck/QOL engine
├── Modules/
│   ├── BetterBagsModule.lua            # Controller bag strip, Reagent Bag merge & vendor/bag automation
│   ├── MinimapExpTracker.lua           # Radial EXP/Rested ring, EXP badge & shared minimap UI helpers
│   ├── DynamicInfoPlacard.lua          # Independent Coordinates/Gold, Bags, Ammo, Shards & Farming placard
│   ├── QuestTrackerUpdater.lua         # Quest sorting, auto-track & auto-accept automation
│   ├── ClassImprovementsModule.lua     # Druid form Mana bar, nameplate combo points, OB Prep & Pet Feeder
│   └── CompactControllerBar.lua        # Controller-only single-bar compact gamepad bar (TriggerBar integration)
└── Textures/                           # UI textures, radial masks, bar styles, overlays & icon assets
```
