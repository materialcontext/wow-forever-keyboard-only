# WoW keyboard-only modal input

Play **World of Warcraft: Forever** (Windows) with **zero mouse input**, using a
Vim-style modal layer system that minimizes both finger reach and held keys.
This file is the handoff from a design conversation in claude.ai; treat it as
the current source of truth and update it as decisions change.

## The game: WoW: Forever (not retail, not Classic Era)

Always assume WoW: Forever. It's Blizzard's "Classic+": the original
continents, level 60 cap, reworked Classic-style classes, permanent (not
seasonal). Launches 2026-11-04. The beta (2026-09-17 to 2026-10-21) caps at
level 30. The client installs to
`World of Warcraft\_classic_beta_\` (beta); expect a different folder at
launch.

What follows from that, as reported by early-beta sources (verify in game):
- **Modern client and addon API** (mainline 12.1.5), including Midnight's
  combat restrictions for addons. Retail API docs apply, Classic Era ones
  don't. Classic-era addons need a Forever build.
- **toc Interface**: the beta client reports `16001` (confirmed in game);
  the toc also lists `120105` in case that's what launch uses.
- **No flying**, so no skyriding and no pitch keys. Ground mounts come at
  level 40 (riding trainer grants one), so none in the beta.
- **Frost Mage kit** is Classic-style plus Ice Lance and Fingers of Frost
  (talents). Ice Barrier at 40. No Flurry, Glacial Spike, Comet Storm, Ray
  of Frost, Shifting Power.
- Built-in damage meter and Cooldown Manager.

## Owner preferences

- Rust for any tooling we write; Lua only where WoW requires it (addons).
- Functional and extensible designs, but a manageable codebase beats domain
  purity. Prefer small, boring, obvious code.
- Edits in Neovim. Keep files plain-text and diff-friendly.
- New to WoW. Explain game-specific assumptions when they matter.
- Existing addons are fine, but the owner verifies each one before it goes
  in. Suggest, don't assume.
- Plays an **Orc Frost Mage**. Orc's only active racial is Blood Fury (a
  damage cooldown, caster version confirmed in Forever); the rest are
  passive. It's used every fight, so it sits on a combat key (`.`).
- Doesn't need to learn the rotation by heart, but wants to choose each
  cast rather than rely on the Single-Button Assistant. Plan: normal bars
  plus Blizzard's Assisted Highlight (glows the suggested button), if
  Forever has it.

Rule of thumb for placing abilities: pressed every fight -> a combat key;
situational or rare -> leader; out of combat -> world.

## Architecture (decided)

Hybrid: the **OS remapper owns ergonomics**, the **game owns meaning**.

- **kanata** (https://github.com/jtroo/kanata) does all layers and modes and
  emits plain keys or modifier+key combos.
- **WoW keybindings, bars and addons** decide what those combos do.
- Neither side can see the other's state. A tiny custom addon bridges this with
  a mode banner (see below).

kanata variant on Windows:
- `winIOv2` (LLHOOK + SendInput) is the default. It needs no install, so it's
  portable to machines the owner doesn't control.
- `wintercept` (Interception driver) is optional for the home PC only if
  winIOv2 misbehaves. Known issue: it can disable keyboard/mouse until reboot
  after sleep or heavy USB plug/unplug.
- One machine. kanata is installed and running there.
- **OS shortcuts pass through:** while Left Alt, Left Ctrl or Win is held
  (`os_hold` in `layout.toml`), every remapped key sends its plain self, so
  Alt+Tab, Alt+Shift+Tab, Win+Tab and Ctrl+Shift+Esc work (test 3: Tab as
  the UI-mode key broke Alt+Tab). The generator wraps each remapped cell
  in a kanata `fork` alias (`os-<key>-...`).
- Replaces the owner's iCUE macros. Disable the iCUE remaps on the home
  keyboard so the two don't stack.

## Design principles (decided)

1. **Combat mode is complete.** Everything a fight needs is reachable without
   leaving it. No mode switches mid-fight.
2. **Cost ladder:** base key < one-shot leader < mode switch < hold. Target
   zero sustained holds.
3. **Mode entries are absolute, never toggles.** Caps always means "go to
   combat" (Vim's Esc). Mashing it is always safe, and desync self-heals.
4. **Movement is identical in every mode** except chat.
5. **Chat is Insert mode.** Enter opens chat and switches to passthrough;
   Enter or Esc sends/cancels and returns to combat.
6. **One keypress = one game action** (Blizzard's remapping rule). No timed
   sequences or multi-action macros from kanata.

## Combat mode layout (draft v1, ANSI QWERTY)

Left hand (movement + utility):

| Key | Action | Key | Action |
|---|---|---|---|
| E | forward | D | back |
| S | turn left | F | turn right |
| W | strafe left | R | strafe right |
| Q | next enemy (repeat to cycle) | B | previous enemy |
| A | interact | Esc | also clears the target |
| T | autorun | Z | mount (level 40) |
| G | confirm (accept/complete quest, popup, loot all) | | |
| 1–9 | pick dialog option N (gossip, quests, rewards, loot) | | |
| X, C, V | extra abilities (Frost: Nova, Cone, Blink) | Space | jump |
| Esc | passthrough (close / clear target / menu) | | |


Right hand (abilities):

| Key | Slot | Key | Slot |
|---|---|---|---|
| J K L ; | rotation 1–4 | U I O P | rotation 5–8 |
| H | interrupt | Y, N | defensive 1, 2 |
| M , . | cooldown 1–3 | / | utility |
| ' | free | | |

Mode keys:

| Key | Behavior |
|---|---|
| Caps | → combat (absolute) |
| Tab | → UI mode |
| Left Shift | → world mode |
| Right Alt | leader (one-shot) |
| Enter | → chat (passthrough) |

Chat exit rules: in chat, Enter sends + returns to combat; Esc **and Caps**
cancel + return to combat. Caps must send Esc there, otherwise the chat box
keeps focus and movement keys type into it. Banner chords are sent with
`macro` so they never land in an open chat box or add modifiers to Enter.

Known desync: text boxes that open without Enter (mail, AH search, DELETE
confirm). Esc closes them; in UI mode `'` switches to chat (passthrough)
without sending Enter, so you can type into them.

Why kanata owns the layers: WoW's combat lockdown blocks addons from
changing keybindings mid-fight, so an addon can't swap bindings per mode.


## Layout sync (decided, pulled forward from phase 2)

`layout.toml` is the single source of truth. `layoutgen` (Rust, `cargo run`
from the repo root) generates `kanata/wow.kbd` and
`addon/WowKeys/Layout.lua`; never hand-edit those. `cargo run -- --check`
fails if they're stale.

The WowKeys addon (one addon, not a separate ModeBanner):
- rewrites and saves the real bindings on each login, so the layout file
  always wins. It unbinds other keys from commands it owns (e.g. `1` from
  ACTIONBUTTON1). Real bindings, not override bindings: with overrides the
  button hotkey labels kept showing the old keys (test 1);
- applies `[cvars]` from the layout on login (auto loot, no auto-push of
  new spells onto bars, enemy nameplates off, tab-target range/behavior);
- places spells and creates macros on bars when the layout's buttons change
  (revision hash), when you learn a spell, or on `/wowkeys bars`. Managed
  slots whose spell isn't learned yet are cleared of other spells (WoW's
  starter bar left duplicates); items and macros there are left alone;
- binds each mode's banner chord to a hidden button that updates the
  on-screen mode label, and plays a warning if combat starts outside the
  home (first) mode.

Non-combat modes get `mods` (e.g. `["ctrl", "alt"]`): kanata emits
modifier+key and the addon binds that chord, so modes never collide.
Keys a mode leaves unmapped behave as in home (combat): the generator
copies home's cell, so movement and mode keys work everywhere. Passthrough
modes (chat) send unmapped keys as typed. The generator rejects two keys
fighting over one WoW chord, and one macro name with two bodies.

Action kinds in `layout.toml`: WoW binding command; spell or macro on a bar
button; spell or macro bound directly (`SPELL x` / `MACRO x`, no bar slot,
used outside combat mode); mode switch; `wowkeys:<command>` (addon
commands: `confirm`, `vendor`, `choose1`..`choose9`). One-shot modes
(`oneshot = ms`) use kanata `one-shot` over `layer-while-held` and have no
banner.

`Commands.lua` implements the addon commands. It reads which dialog is open
from Blizzard's frames (GossipFrame, QuestFrame*Panel, LootFrame,
StaticPopup1, MerchantFrame) at keypress time rather than tracking events,
and prints numbered options when a gossip, quest greeting, reward choice or
loot window opens.

`lua5.1 addon/tests/dryrun.lua` runs the addon against stubbed WoW APIs
(the level-5 scenario from test 1). Run it after changing `WowKeys.lua`.

## Other modes

- **Leader (Right Alt, one-shot 1000 ms, emits Ctrl+key):** one key, then
  straight back. J health potion, K mana potion (macros; update item names
  as you find better potions), L Frost Ward (situational; on bar 2 button 8
  so its cooldown shows), F set focus to target, T target focus, C clear
  focus, / toggle enemy nameplates. Later: long cooldowns.
  `,` is a Polymorph macro that sheeps the focus if you have one, else the
  target.
- **UI (Tab, Ctrl+Alt+key):** U bags, I character, O spellbook, P talents,
  L quest log, M map, `'` type into a text box. Vendor chores belong to
  Leatrix Plus (the `wowkeys:vendor` command still exists if ever needed). Esc closes windows. Navigating *inside* windows (bags, talents) still
  needs a UI addon or our own commands.
- **World (Left Shift, Ctrl+Alt+Shift+key):** J Frost Armor, K Arcane
  Intellect, L Conjure Water, ; Conjure Food, U drink, I eat (macros; update
  conjured item names per rank), H hearthstone, N/M camera zoom in/out.
- **Chat (Enter):** full passthrough until Enter or Esc.

## Mode banner

Each mode-entry key also emits Ctrl+Alt+Shift+<banner> (F9 combat, F10 UI,
F11 world, F12 chat; leader has none). WowKeys shows the mode label, like Vim's `-- INSERT --`.

## Addons

Forever uses the modern API with Midnight's combat restrictions, so each
addon needs a Forever-compatible build. The owner verifies each one before
it goes in.

**Owner's picks** and how each meets the keyboard layer:

| Addon | Job | Keyboard impact |
|---|---|---|
| Leatrix Plus | auto quest accept/turn-in, sell junk, repair, QoL | **Owns vendor chores** (decided); UI K vendor key removed. Quest automation overlaps G; still to decide. |
| Bagnon | combined bag window | UI U should open it (it takes over the bag toggle). Navigating inside it is still unsolved. |
| Plater | enemy nameplates | Q/B cycling and leader / depend on nameplates. Plater manages nameplate CVars; if it fights our `nameplateShowEnemies`, drop ours from `[cvars]`. Midnight limits nameplate addons in combat. |
| DBM | boss timers and warnings | Display only. Midnight limits boss mods hardest and the modern client has built-in boss warnings; check what the Forever build can still do. |
| Auctionator | auction house search and selling | Hardest for keyboard-only play (lists, picking a bag item to sell). Its own keybindings (believed: post / cancel undercut) can go on UI-mode keys once named. |
| AtlasLoot | loot table browser | Mouse-driven browsing; a key to open it at most. |

**Adding an addon's keybinding:** in game, `/wowkeys find <text>` lists
matching binding commands with their readable names. Put the command into
`layout.toml` (usually UI mode), `cargo run`, `/reload`. Don't guess
command names.

**Rules for coexisting:**
- `Commands.lua` finds dialogs by Blizzard's frame names. An addon that
  replaces the gossip, quest or loot frames (DialogueUI, Immersion) would
  break 1–9 and G; none of the picks above does.
- WowKeys rewrites only the keys in `layout.toml` at login, so an addon's
  own default keys survive unless they collide with ours (ours win).
- An addon that changes the same CVar as `[cvars]` will fight it; remove
  the entry from `[cvars]` and let the addon own it.

**Other candidates** (not picked): Interaction (Adaptvx) or DialogueUI for
keyboard dialogs; KeyboardUI (maintenance unclear); Bartender4/Dominos;
KeyUI; ConsolePort (only for a virtual-gamepad route).

Useful in-game settings: Interact key, soft targeting, auto-loot, camera
following style "Always", and `/cast [@player] Spell` macros for
ground-targeted spells.

## Proposed repo layout

```
CLAUDE.md
layout.toml               # the layout; edit this
layoutgen/                # Rust: layout.toml -> the generated files below
kanata/wow.kbd            # GENERATED
addon/WowKeys/Layout.lua  # GENERATED
addon/WowKeys/Commands.lua # dialog/loot/popup/vendor commands (wowkeys:*)
addon/WowKeys/WowKeys.lua # applies Layout.lua, mode banner
addon/tests/dryrun.lua    # offline test of the addon with stubbed WoW APIs
wow/setup.md              # addon install, one-time game settings
```

## Open questions


- Whether the owner accepts kanata mouse-movement keys as a last-resort UI
  fallback (keyboard input, but it drives a pointer).
- Leader timeout (1000 ms for now) and whether a second leader is needed.
- Navigating inside windows (bags, talents, spellbook): a verified UI addon,
  or more of our own commands.
- Group loot rolls (need/greed/pass) by key.

## Test 1 results (level 5, beta)

Works: kanata config, addon loads, banner (so Ctrl+Alt+Shift+F chords reach
WoW), chat round trips, Caps (goes to combat; nothing visible if already
there), movement, Q targeting, letter and `;` spell keys, keyboard turning
("okay"). Camera set to rotate with the character; soft targeting on.

Found and fixed in test 2's build:
- Hotkey labels showed old keys -> real bindings instead of overrides.
- Duplicate spells on bars -> clear stale spells from managed slots, place
  spells as they're learned, turn off WoW's auto-push.
- `A` opened corpses but didn't loot -> `autoLootDefault = 1`.

Not available: F13–F24 (keyboard can't send them).

## Test 3 partial results

Works: all mode keys, movement in every mode, Q cycles enemies, leader /
toggles nameplates.

Changed after it:
- Strafe and turn swapped (W/R strafe, S/F turn): the owner found turning
  on the home row more intuitive.
- Alt+Tab broke (Tab is the UI key) -> `os_hold` passthrough.
- Enemy nameplates off by default (`nameplateShowEnemies = 0`).
- Q was very picky (narrow cone, short range) -> `targetNearestDistance =
  50` and `TargetNearestUseNew = 0` (older targeting). Unverified; with
  nameplates off the newer targeting may be pickier still.
- Leatrix Plus owns vendor chores; UI K removed.

## To verify in game (test 2)

- [ ] Hotkey labels show J, K, L… instead of 1, 2, 3….
- [ ] Login prints what it took off the bars; no spell shows up twice.
- [ ] `A` on a corpse loots everything.
- [ ] Does the client know `AutoPushSpellToActionBar`? (It prints if not.)
- [ ] Learning a spell (Fire Blast at 6) puts it on its key with no
      `/wowkeys bars`.
- [ ] Bar 2 is shown (it holds the , . / X C V Z buttons).
- [ ] Punctuation keys `,` `.` `/` once their spells are learned
      (Polymorph first).
- [ ] Loot rolls and full-bag loot windows still need keyboard navigation:
      note when they come up.

Later:
- [ ] `A` interacts with objects too (assumed `INTERACTTARGET`).
- [ ] `Z` mounts at 40 (`/run C_MountJournal.SummonByID(0)`; assumes the
      trainer's mount lands in the mount journal).
- [ ] Is there a camera-rotate keybinding that doesn't turn the character?
- [ ] Assisted Highlight exists in Forever.
- [ ] `/cast [@target,exists][@player] Blizzard` lands on the target.

## To verify in game (test 3: modes and dialogs)

Needs a kanata restart (new layers) and `/reload`.
- [ ] Tab shows `-- UI --`, Left Shift `-- WORLD --`, Caps back to COMBAT.
- [ ] Movement keys still work in UI and world mode.
- [ ] UI: U bags, I character, O spellbook, P talents, L quest log, M map.
- [ ] World: J Frost Armor, K Arcane Intellect, H hearthstone, N/M zoom.
- [ ] Leader: Right Alt then J uses a healing potion; a stray Right Alt
      times out after 1 s; Right Alt then E just moves.
- [ ] `.` casts Blood Fury; Right Alt then L casts Frost Ward (once learned).
- [ ] Q picks up enemies in a wider arc and at longer range now; B cycles
      back. If worse, try `/console TargetNearestUseNew 1` and report.
- [ ] Alt+Tab, Alt+Shift+Tab and Win+Tab switch windows; Tab alone still
      enters UI mode.
- [ ] Nameplates start hidden; leader / shows them.
- [ ] Leader F sets focus (focus frame appears), T targets it, C clears it.
- [ ] Leader / toggles enemy nameplates (assumed binding `NAMEPLATES`).
- [ ] `,` Polymorphs the focus when set, the target otherwise (level 8).
- [ ] Talk to a quest NPC (A): options print numbered in chat; 1–9 picks.
- [ ] G accepts a quest, completes it, takes the only reward; with several
      rewards it asks for a number.
- [ ] G accepts a group invite / resurrection popup.
- [ ] Mixed-up bindings after the change? (Old keys from test 2 on G/B.)
- [ ] Ctrl+Alt / Ctrl+Alt+Shift chords don't trigger anything in Windows
      (language switch, overlays).

## To verify in game (addons)

- [ ] Each pick has a Forever build and loads (no "out of date" or Lua errors).
- [ ] Leatrix Plus: decide who owns quest accept/turn-in (vendor: Leatrix).
- [ ] Bagnon opens with UI U.
- [ ] Plater: Q/B still cycle; leader / still toggles; login CVar doesn't fight it.
- [ ] `/wowkeys find auctionator` (and `dbm`, `atlas`, `bagnon`) lists
      their binding commands; paste the output here.

## Next steps

1. Tests 2 and 3 in game, with the addons installed.
2. Loot rolls, bag navigation, talents: pick a UI addon or extend Commands.
3. Long cooldowns on the leader layer.
