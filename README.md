<h1>amptieRaidTools</h1>
<img width="2816" height="1536" alt="aRT_Logo" src="https://github.com/user-attachments/assets/663ae786-1756-46f2-8068-686e08129862" />

A modular raid management addon for **TurtleWoW** (Vanilla 1.12). Designed for 40-man raiding, it combines spec tracking, buff verification, cooldown management, loot council, and a variety of quality-of-life tools in a single unified interface with a collapsible navigation sidebar.

Requires **SuperWoW**.

---

## Table of Contents

- [Installation & Usage](#installation--usage)
- [Interface Overview](#interface-overview)
- [Character](#character)
  - [Overview](#overview)
  - [Bar Profiles](#bar-profiles)
  - [Auto-Buffs](#auto-buffs)
  - [Auto-Rolls](#auto-rolls)
- [Raids](#raids)
  - [Raid Roles](#raid-roles)
  - [Raid Assist](#raid-assist)
  - [Raid CDs](#raid-cds)
  - [Raid Setups](#raid-setups)
- [Rules](#rules)
  - [Item Checks](#item-checks)
  - [Buff Checks](#buff-checks)
  - [Class Buffs](#class-buffs)
  - [Loot Rules](#loot-rules)
- [Others](#others)
  - [NPC Trading](#npc-trading)
  - [QoL Settings](#qol-settings)
- [Overlays](#overlays)
- [About](#about)

---

## Installation & Usage

1. Place the `amptieRaidTools` folder into `Interface/AddOns/`.
2. Log in — the minimap button appears automatically.
3. **Left-click** the minimap button to open or close the main frame.
4. The minimap button can be dragged to any position around the minimap.

**Slash commands:**

| Command | Effect |
|---|---|
| `/art` | Toggle the main frame open/closed |
| `/amptieraidtools` | Same as above |
| `/art council show` | Open the loot council frame directly |

---

## Interface Overview

[Screenshot: Main frame with navbar on the left and content panel on the right]

The main frame (780 × 570 px) has a vertical navigation sidebar on the left. Clicking any nav item switches the content panel on the right. The frame is draggable and remembers its position between sessions.

The navbar is organized into four sections: **Character**, **Raids**, **Rules**, and **Others**.

---

## Character

### Overview

[Screenshot: Overview tab]

The Overview tab is your character dashboard. It displays:

- **Class** — detected automatically.
- **Specialization** — determined by scanning your talent tree. The spec is re-evaluated every 5 seconds and announced in chat when it changes.
- **Role** — mapped from your spec (Tank / Healer / Melee DPS / Caster DPS), used by Raid Roles and Buff Checks.

**Alternative Specs** lets you register additional roles your character can fill beyond your main spec. Each alt-role entry includes a **gear tier** (Dungeon / MC / BWL / AQ40 / Naxx / K40), so the raid leader can see not just that you *can* tank, but how well-geared you are for it. These alt specs are broadcast to the raid and appear in the Raid Roles roster.

**Salvation Override** controls how Blessing of Salvation is handled, independently of whichever Auto-Buffs profile is active:

| Setting | Effect |
|---|---|
| Profile | Follow the active Auto-Buffs profile setting |
| Allow | Never remove Salvation, even if the profile removes it |
| Remove | Always remove Salvation, even if the profile keeps it |

---

### Bar Profiles

[Screenshot: Bar Profiles tab]

Bar Profiles manages named presets for the Buff Bars overlay. Each profile can be bound to a specific specialization, so the bars automatically switch when your spec changes (e.g., show different tracked auras while tanking vs. healing).

Profiles can be created, renamed, deleted, and exported/imported as strings for sharing.

---

### Auto-Buffs

[Screenshot: Auto-Buffs tab showing buff categories]

Auto-Buffs automatically removes unwanted buffs from your character based on the active profile. This is useful for stripping low-rank world buffs before getting properly buffed for raid.

Buffs are organized into categories (Scrolls, Paladin blessings, Priest buffs, Mage buffs, Druid buffs, etc.). Within each category you enable or disable individual buff names. The system continuously checks your buff list and cancels any enabled entries.

> **Note:** The Blessing of Salvation setting on the Overview tab (Salvation Override) takes precedence over the Auto-Buffs profile for Salvation specifically.

---

### Auto-Rolls

[Screenshot: Auto-Rolls tab showing item group list]

Auto-Rolls watches for loot roll popups and automatically rolls Need, Greed, or Pass on specific item categories. For each category you select one of: **None** (no auto-roll), **Need**, **Greed**, or **Pass**.

Supported item groups include:

- Black Morass Hourglass Sand
- Zul'Gurub bijous and coins
- Ahn'Qiraj scarabs and idols
- Molten Core materials
- Naxxramas scraps
- Karazhan Arcane Essences (10-man and 40-man variants)

For Hourglass Sand, the addon detects your Wardens of Time reputation — if you are Exalted, the options are restricted to None or Pass.

---

## Raids

### Raid Roles

[Screenshot: Raid Roles tab showing the four-column roster]

Raid Roles is a live roster that shows every player's detected spec and role. Columns are color-coded by broad role:

| Column | Role | Color |
|---|---|---|
| T | Tank | Blue |
| H | Healer | Green |
| M | Melee DPS | Yellow |
| C | Caster DPS | Purple |

The roster is populated by listening to spec broadcasts from other players running amptieRaidTools. Your own spec is broadcast automatically when you enter a group or when your spec changes. The list refreshes every 5 seconds.

**Filter** — a dropdown lets you narrow the display to a single role group.

**Alt specs** appear as small tier badges under a player's name, indicating which other roles they have geared alternatives for.

---

### Raid Assist

[Screenshot: Raid Assist tab showing MT fields, auto-invite, auto-assist sections]

Raid Assist has three independent features:

#### Main Tanks (MT1 – MT8)

Eight text fields for the names of your designated main tanks. These names are:

- Broadcast to the entire raid via addon message when you click **Broadcast MTs to Raid** (requires at least one filled field and being in a raid).
- Received by all addon users automatically and stored in their local MT list.
- Used by the **MT Targets Overlay** (see [Overlays](#overlays)) and by AmptiePlates for nameplate coloring.
- Cleared automatically when you leave the raid.

#### Auto-Invite

A keyword list — if someone whispers you a word from the list (case-insensitive), they are automatically invited to your group or raid. If you are in a party, the addon converts it to a raid before inviting.

#### Auto-Assist

A name list — if a player on this list joins your raid, they are automatically promoted to Raid Assistant (requires you to be Raid Leader).

---

### Raid CDs

[Screenshot: Raid CDs tab with spell checkboxes and overlay preview]

Raid CDs tracks the cooldowns of important raid utility spells for all players in your raid. Detection uses SuperWoW's addon messaging — players broadcast their cooldown usage automatically when running amptieRaidTools.

**Tracked spells:**

| Spell | Class | Cooldown |
|---|---|---|
| Rebirth | Druid | 30 min |
| Innervate | Druid | 6 min |
| Tranquility | Druid | 5 min |
| Challenging Roar | Druid | 10 min |
| Hand of Protection | Paladin | 5 min |
| Divine Intervention | Paladin | 60 min |
| Shield Wall | Warrior | 30 min |
| Challenging Shout | Warrior | 10 min |
| Reincarnation | Shaman | 60 min |

Each spell has a checkbox in the settings to enable or disable tracking.

The tab also contains the **Taunt Tracker** section — see [Overlays](#overlays) for both overlays.

---

### Raid Setups

[Screenshot: Raid Setups tab showing 8 group grid]

Raid Setups is a visual composition planner. It displays a grid of 8 groups with 5 slots each (40 total), where you manually type player names for your planned raid composition.

- Names are **color-coded** by class if the player is currently in your raid, red if their name is unrecognized, and neutral if you are solo.
- Slots can be **locked** (click to toggle) to prevent accidental edits.
- Names can be swapped between slots by drag-and-drop.
- Compositions can be saved as named profiles and reloaded at any time.

This is a planning tool only — it does not auto-assign players to groups.

---

## Rules

### Item Checks

[Screenshot: Item Checks tab with profile list on left and rule list on right]

Item Checks verifies that raid members are carrying the correct consumables and resistance items. A raid leader broadcasts a check, and all addons respond with their inventory counts. Results are collected and displayed in the overlay.

**Profiles** — rules are organized into named profiles. Profiles can be exported and imported as strings.

**Rules** — each rule defines:

- **Who** the rule applies to: Everyone, a specific Class, a Role (Tank/Healer/Melee/Caster), a Damage Category (Melee/Ranged/Caster), or a specific Spec.
- **Conditions** — one or more OR-groups, each containing AND-items. If any OR-group is fully satisfied, the player passes. Each AND-item specifies an item or resistance and a required quantity.

**Items available for conditions include:**

- Flasks (Flask of the Titans, Distilled Wisdom, Supreme Power, Chromatic Resistance, etc.)
- Elixirs and potions (Juju Power, Greater Arcane Elixir, Elixir of the Mongoose, etc.)
- Food buffs (Dirge's Kickin' Chimaerok Chops, Runn Tum Tuber Surprise, etc.)
- Resistance gear checks (Fire / Nature / Frost / Shadow / Arcane resistance via `UnitResistance`)
- Oils and stones (Brilliant Wizard Oil, Dense Sharpening Stone, etc.)
- Runes (Rune of the Dawn, etc.)

[Screenshot: Item Checks rule editor]

**From IC Profile** — Buff Checks can optionally import rules from an Item Checks profile, avoiding duplication.

---

### Buff Checks

[Screenshot: Buff Checks tab with profile list on left and rule list on right]

Buff Checks verifies active buffs on raid members. Like Item Checks, it is profile-based with the same OR/AND condition structure, but conditions reference buffs rather than items.

**Profiles** — named profiles with zone-based auto-switching (e.g., automatically use your AQ40 profile when entering that zone).

**Rules** — each rule specifies:

- **Who** — same options as Item Checks (Everyone, Class, Role, Damage Type, Spec).
- **Conditions** — OR-groups of AND-buff requirements. If any OR-group has all buffs present, the player passes.

Available buffs span hundreds of entries: world buffs, consumable buffs, class buffs, and resistance buffs.

The **rule editor** opens within the rules panel when you click **+ Add Rule** or **Edit** on an existing rule.

[Screenshot: Buff Checks rule editor with WHO header and scrollable conditions]

**Overlay** — when a check is running, the overlay shows which players are failing which rules. It auto-shows when failures are detected and auto-hides when all players pass. The overlay is only visible while in a raid.

**Zone Bindings** — profiles can be bound to raid zones (MC, BWL, AQ40, ZG, etc.) and switch automatically on entry.

---

### Class Buffs

[Screenshot: Class Buffs tab showing buff group list with toggles]

Class Buffs tracks which raid members are missing standard class-provided buffs. Unlike Buff Checks (which requires a manual check broadcast), Class Buffs runs continuously by scanning all visible unit auras.

**Tracked buff groups:**

| Group | Caster Class | Applies To |
|---|---|---|
| Arcane Intellect | Mage | Mana users |
| Prayer of Fortitude | Priest | Everyone |
| Shadow Protection | Priest | Everyone |
| Divine Spirit | Priest | Mana users |
| Mark of the Wild | Druid | Everyone |
| Blessing of Salvation | Paladin | Everyone |
| Blessing of Wisdom | Paladin | Everyone |
| Blessing of Might | Paladin | Everyone |
| Blessing of Kings | Paladin | Everyone |
| Blessing of Light | Paladin | Everyone |

Each group has a checkbox to enable or disable tracking.

**Show All Buffs** — when checked, the overlay shows every player and whether they have the buff (green) or not (red), even if the buff is present. When unchecked, only missing buffs are shown. Show All Buffs requires a raid; own-class tracking works in any group.

**Overlay** — a movable overlay frame displays a table of players with their buff status. Rows are sorted by role.

---

### Loot Rules

[Screenshot: Loot Rules tab showing profile sidebar and right-side configuration]

Loot Rules is a full in-game loot council system. When a loot window opens, a **vote popup** appears for all players running the addon, letting them roll or vote according to the configured profile.

**Profile settings:**

- **Mode** — None / Council / Suicide / DKP
- **Trigger** — minimum item quality and an optional item ID whitelist
- **Buttons** — custom vote buttons with names and priority values (e.g., Main Spec, Off Spec, Pass)
- **Timer** — seconds before voting closes automatically
- **Officers** — named players with voting authority
- **Zone Bindings** — bind a profile to a raid zone so it activates automatically

[Screenshot: Loot council popup frame showing item, voter list, and vote buttons]

**Council frame** — a separate movable window (also accessible via `/art council show`) shows each officer's vote in real time, sortable by priority, roll, name, class, or DKP value.

**Simulate Loot** — opens a test item input to simulate the loot flow without actual loot.

Profiles can be **exported and imported** as strings for sharing across officers.

---

## Others

### NPC Trading

[Screenshot: NPC Trading tab]

NPC Trading automates vendor interactions when you open a merchant window.

| Feature | Effect |
|---|---|
| Auto-Sell Grey Items | Sells all quality 0 (grey) items in your bags |
| Auto-Repair | Repairs all armor at the vendor |
| Auto-Buy Time-Worn Rune | Restocks Time-Worn Runes to 1 if you have none |
| Material Auto-Buy | Buys class reagents and consumables up to a defined quantity |

The material buy list includes common class reagents (Symbol of Kings, Ankh, Arcane Powder, Sacred Candle, etc.) with customizable restock quantities. You can add additional items by name or item ID.

Purchases are queued and executed with a small delay between each to avoid client-side drops.

---

### QoL Settings

[Screenshot: QoL Settings tab with checkbox list]

QoL Settings provides individual toggles for convenience features unrelated to raiding:

| Feature | Effect |
|---|---|
| Accept Guild Invites | Auto-accepts invites from guild members |
| Accept Friend Invites | Auto-accepts invites from friends |
| Accept Stranger Invites | Auto-accepts any invite |
| BG Auto-Enter | Accepts battleground invites automatically |
| BG Auto-Leave | Leaves the battleground when it ends |
| BG Auto-Queue | Re-queues after a battleground |
| BG Auto-Release | Releases spirit automatically on death |
| Accept Summons | Auto-accepts summoning stones |
| Accept Instance Res | Auto-accepts in-instance resurrections |
| Mute World Chat (instance) | Suppresses world/general chat in dungeons and raids |
| Mute World Chat (always) | Suppresses world/general chat everywhere |
| Auto-Decline Duels | Silently declines all duel requests |
| Auto-Gossip | Auto-selects the only option in single-choice NPC dialogs |
| Auto-Dismount on Action | Dismounts automatically when using an ability |
| Extended Camera Distance | Increases the max camera zoom distance |

---

## Overlays

Several components have movable, always-on-top overlay frames that can be positioned anywhere on your screen. All overlays are hidden when you are not in the appropriate group type (raid or party) and are restored to their last position on login.

### MT Targets Overlay

[Screenshot: MT Targets overlay showing 8 tank names and their current targets]

Displays the names of MT1–MT8 and their current targets in real time. Activated from the Raid Assist tab. Requires a raid.

### Raid CDs Overlay

[Screenshot: Raid CDs overlay with spell icons and cooldown timers]

Shows all tracked cooldowns for raid members. Each row is one player with up to four spell icons. A countdown timer appears on each icon. Visible in any group (raid or party).

### Taunt Tracker Overlay

[Screenshot: Taunt Tracker overlay with taunt icons and 10-second countdown]

A compact overlay tracking taunt spell cooldowns for all tanks in your raid. Tracked spells: **Taunt**, **Hand of Reckoning**, **Growl**, **Earthshaker Slam** (10-second cooldown each). Requires a raid.

### Class Buffs Overlay

[Screenshot: Class Buffs overlay showing players with missing buff indicators]

Displays which players are missing tracked class buffs. Updates continuously based on aura scans. Visible in any group when Show All Buffs is off; requires a raid when Show All Buffs is on.

### Buff Checks Overlay

[Screenshot: Buff Checks overlay with player names and failed buff rules]

Shows players failing active Buff Check rules. Auto-shows when failures are detected, auto-hides when all players pass. Requires a raid.

---

## About

**Addon:** amptieRaidTools
**Version:** 0.8.2
**Author:** amptie
**Server:** Nordanaar (TurtleWoW)
**Character:** Celebrindal

Built for 40-man raiding on TurtleWoW. Requires the **SuperWoW** client extension for GUID-based unit tracking, extended API access, and addon messaging features.

If you encounter bugs or want to contribute, feel free to open an issue or pull request.
