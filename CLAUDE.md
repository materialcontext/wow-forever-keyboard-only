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
ClassTrainerFrame, StaticPopup1, MerchantFrame) at keypress time rather
than tracking events, and prints numbered options when a gossip, quest
greeting, reward choice, trainer or loot window opens.

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
  L quest log, M map, B bank (Bagnon), `'` type into a text box. Vendor chores belong to
  Leatrix Plus (the `wowkeys:vendor` command still exists if ever needed). Esc closes windows. Navigating *inside* windows (bags, talents) still
  needs a UI addon or our own commands.
- **World (Left Shift, Ctrl+Alt+Shift+key):** J Frost Armor, K Arcane
  Intellect, L Conjure Water, ; Conjure Food, U drink, I eat (macros; update
  conjured item names per rank), H hearthstone, N/M camera zoom in/out.
- **Chat (Enter):** full passthrough until Enter or Esc.

## Mode banner

Each mode-entry key also emits Ctrl+Alt+Shift+<banner> (F9 combat, F10 UI,
F11 world, F12 chat; leader has none). WowKeys shows the mode label, like Vim's `-- INSERT --`.

## Native controller (Forever "Gamepad UI (Alpha)")

From Forever HQ's and NerdsChalk's beta guides (owner pasted them
2026-09-26; built from the BlizzCon demo and ConCon's video). Alpha:
subject to change; verify in game.

- **Turn on:** Options → Gameplay → Gamepad (Alpha) → "Enable Gamepad UI
  (Alpha)". **Keyboard and gamepad layouts are kept separately** when
  toggling, so a controller profile doesn't disturb the keyboard one.
- **Action bars:** a cross of 8 inputs (D-pad + face buttons) × 4 layers
  (none, LT, RT, LT+RT) × 3 arrangements (switch with LB+RB+D-pad Right)
  = 12 bars. Unmodified face buttons are fixed: A jump, X auto-attack /
  contextual interact, Y context menu (right-click), B cancel (Esc).
  Unmodified D-pad and all trigger layers take spells, items and (likely)
  macros.
- **Binding:** spellbook → highlight → X "Bind to Action Bar" → press the
  combo. Items: bags → Y "More" → Bind.
- **Targeting:** RB tap = enemy ahead, RB + D-pad/stick cycles enemies;
  LB tap = friendly ahead; hold LB + A self, X pet, B assist, Y mark;
  LB + D-pad = group members by frame position.
- **Shortcuts (hold LB+RB):** D-pad Up quests, D-pad Down chat, D-pad Right
  bar arrangement, B Combined Backpack, X sheathe, Y buff viewer, right
  stick camera zoom.
- **Menus:** Start opens a radial menu (right stick browses, LB/RB tabs):
  Character, Talents, Professions, Bags, Spellbook, Game Menu, Chat,
  Quests/Map; left tab Group Finder, Collections, Social…; right PvP,
  Calendar. In the menu, D-pad Down sit/stand, Up emotes.
- **Windows (the cursor-free navigation we lacked):** D-pad moves focus,
  triggers switch between open frames, bumpers change tabs, X confirms /
  equips, Y "More" (split, destroy, bind), B closes. Bags support moving,
  equipping, stack splitting; character panel works; quest log and map
  (bumpers zoom, X places a marker). NPCs: walk up and press the X prompt,
  D-pad picks the quest, Accept.
- **Gaps:** typing chat still needs a keyboard. Addon compatibility
  (Bagnon vs. the Combined Backpack) is untested.
- **Engine underneath** (since 9.0.1): pad buttons are binding keys
  (`PAD1`–`PAD6`, `PADDUP`…, `PADLTRIGGER`, `PADRTRIGGER`, `PADLSHOULDER`,
  …) and triggers can act as modifiers (`GamePadEmulateShift`/`Ctrl`/`Alt`).
  Whether Forever's Gamepad UI uses these standard bindings is unknown.

**First in-game probe (2026-09-26):** with the gamepad on
(`GamePadEnable = 1`, `GamePadEmulateShift = PADLTRIGGER`,
`GamePadEmulateCtrl = PADLSHOULDER`, `GamePadEmulateAlt = none`), there are
**no controller buttons in the standard bindings**, and action slots
1–180 hold only the keyboard layout. Open: whether a spell had been bound
via the controller flow before the probe. (`/wowkeys pad` wrongly listed
numpad keys; fixed. `/wowkeys slots` now scans 1–1000.)

**Second probe (same day): the controller bars are ordinary action slots
above 180.** After binding via the controller, `/wowkeys slots` showed
spells/items at 182, 183, 185, 186 and a full run 193–200 (Conjure Food,
Conjure Water, Arcane Intellect, Frost Armor ×2, Fire Blast, Fireball,
Frostbolt; likely auto-filled). Still no controller entries in standard
bindings (the Gamepad UI routes buttons itself). So the addon **can**
place `layout.toml` content into controller bars with `PlaceAction`; what's
missing is the slot → (arrangement, layer, input) map.
`/wowkeys padbuttons` lists frames showing slots > 180 with their frame
paths, to read that map off the Gamepad UI.

**Third probe: the arrangement shown is four bars, 28 slots:**
Top 181–184 (4, no trigger: D-pad only, face buttons fixed), Left 185–192,
Right 193–200, Bottom 201–208 (8 each; presumably LT, RT, LT+RT). Frame
names are `GamepadMainActionBarFramePageUnit<Side>CenteredAnchor<Side>Bar
ActionButton<n>` plus a matching `GamepadActionBarEditFrame…` for edit
mode. Unknown: which input each Button<n> is (padbuttons now prints screen
positions to read the cross layout), and where arrangements 2/3 live
(guess 209–236, 237–264; re-run after LB+RB+D-pad Right). Slot 397 is
ExtraActionButton1 (Blizzard's special-action button), not ours. WowKeys only manages slots
1–12 and 61–69, so it never touches controller slots.

**Trigger latching (decided):** the owner wants LT/RT to latch (tap on,
tap off) instead of hold. WoW can't do that (the Gamepad UI reads the
physical trigger state), so Steam Input's per-trigger "Toggle" does it;
setup in `wow/setup.md`. Chosen over Steam action-layer switching because
Blizzard's HUD keeps highlighting the latched layer. Caveat: latched
triggers switch frame focus inside windows, so release them first. A
WowKeys banner for latched layers (via the gamepad button state) is
possible later if the HUD highlight isn't enough.

**Transfer plan** (owner wants to play on controller if possible): our
layout's spells and macros become controller bar content. The addon
already places spells/macros in action slots, so `layout.toml` could gain
a controller section (combo → spell/macro) that the addon places into the
controller bars' slots. Needs, from the game: which action slot ids the
controller bars use and whether bindings are standard. Tools:
`/wowkeys pad` (bindings on pad buttons + gamepad CVars), `/wowkeys slots`
(filled action slots by id). Focus/target-focus/clear-focus become macros
on bar slots; dialogs, loot, trainers and windows are handled natively.

## Addons

Forever uses the modern API with Midnight's combat restrictions, so each
addon needs a Forever-compatible build. The owner verifies each one before
it goes in.

**Owner's picks** and how each meets the keyboard layer:

| Addon | Job | Keyboard impact |
|---|---|---|
| Leatrix Plus | auto quest accept/turn-in, sell junk, repair, QoL | **Owns quest accept/turn-in and vendor chores** (decided). UI K removed; G and 1–9 cover what it doesn't (gossip, rewards, popups, loot, trainers). No keys bound (see "Addon binding names" below). To skip its automation for one NPC, hold **Right** Shift while pressing A (Left Shift is the world-mode key and never sends Shift). |
| Leatrix Maps | world map improvements (reveal, coordinates, zone levels, scale) | UI M still opens the map (it enhances Blizzard's). No keys bound. Map zoom/pan are mouse-only in WoW; with reveal and coordinates on, reading the map needs neither. |
| Bagnon | combined bag window | UI U opens it (it takes over the bag toggle); UI B opens the bank (`BAGNON_BANK_TOGGLE`). Navigating inside it is still unsolved. |
| Plater | enemy nameplates | Q/B cycling and leader / depend on nameplates. Plater manages nameplate CVars; if it fights our `nameplateShowEnemies`, drop ours from `[cvars]`. Midnight limits nameplate addons in combat. |
| DBM | boss timers and warnings | Display only. Midnight limits boss mods hardest and the modern client has built-in boss warnings; check what the Forever build can still do. |
| Auctionator | auction house search and selling | Hardest for keyboard-only play (lists, picking a bag item to sell). Its own keybindings (believed: post / cancel undercut) can go on UI-mode keys once named. |
| AtlasLoot | loot table browser | Mouse-driven browsing; a key to open it at most. |

**Adding an addon's keybinding:** in game, `/wowkeys find <text>` lists
matching binding commands with their readable names. **Record the names
below, but don't bind them until the owner and Claude have agreed on the
layout for them** (owner's call, test 4). Then put the command into
`layout.toml`, `cargo run`, `/reload`. Don't guess command names.

**Addon binding names found** (only `BAGNON_BANK_TOGGLE` is bound; the
owner decided the rest aren't needed):
- Leatrix Plus: `LEATRIX_PLUS_GLOBAL_TOGGLE` (panel),
  `LEATRIX_PLUS_GLOBAL_WEBLINK` (web link for the hovered item; mouse-only),
  `LEATRIX_PLUS_GLOBAL_RARE` (announce rare),
  `LEATRIX_PLUS_GLOBAL_MOUNTSPECIAL` (mount special animation).
- Leatrix Maps: `LEATRIX_MAPS_GLOBAL_TOGGLE` (panel).
- Bagnon: `BAGNON_TOGGLE` (inventory; UI U already opens it via the bag
  toggle), `BAGNON_BANK_TOGGLE` (bank), `BAGNON_VAULT_TOGGLE` (void
  storage), `BAGNON_GUILD_TOGGLE` (guild bank).
- DBM: none. It's driven by chat commands (`/dbm`, `/dbm pull 10`), which
  chat mode already covers.
- Auctionator: none matched "auctionator". Still to try: `find auction`,
  `find post`, `find cancel`.
- AtlasLoot: `ATLASLOOT_TOGGLE` (open/close).

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


- **Bonus project, very low priority:** keyboard access to addon settings
  panels (Leatrix Plus `/ltp`, Leatrix Maps `/ltm`, AtlasLoot). They're
  set-once panels, so the owner uses the mouse for them for now; a known
  exception to "zero mouse". Bindings to open them are recorded above.
- Whether the owner accepts kanata mouse-movement keys as a last-resort UI
  fallback (keyboard input, but it drives a pointer).
- Leader timeout (1000 ms for now) and whether a second leader is needed.
- **Navigating inside windows** (character/equipment, bags, bank, spellbook,
  talents) is the next big piece. Owner wants no cursor kludge. Plan:
  1. Check whether Forever's native controller UI (alpha in the beta)
     exposes its navigation as bindings: `/wowkeys find` with `navigat`,
     `cursor`, `gamepad`, `pad`, `controller`, `interface`; optionally try a
     real controller on bags/character/talents.
  2. If bindable: map them into UI mode (least code). If it needs a real
     gamepad, avoid it (virtual-controller driver + Rust bridge = a second
     input system).
  3. Otherwise build our own navigator in WowKeys, ConsolePort-style:
     a focus on one clickable widget in open windows (found generically, so
     Bagnon etc. work); move focus with Vimium-style letter hints and/or
     H/J/K/L spatial steps; act with left/right-click keys bound to a
     secure click proxy (SecureActionButton `type=click`, `clickbutton` =
     focus), so protected actions like equipping work; show the focus's
     tooltip. Out of combat only. Start with bags, bank, character.
  Chat `/equip` and `/use` by name already work as a stopgap.
  New option (see "Native controller"): use a real controller for window
  navigation (hybrid), or play fully on controller with a profile
  generated from `layout.toml`.
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

Confirmed after those changes (#4): Alt+Tab family passes through, the
strafe/turn swap, nameplates hidden at login.

## Test 4 results

Works: Q reaches further and wider with `targetNearestDistance = 50` and
`TargetNearestUseNew = 0` (keep both), B cycles back, hotkey labels show
J/K/L, login clears duplicate spells, `AutoPushSpellToActionBar` exists (no
warning), A loots corpses, `.` Blood Fury, leader F/T/C focus
(`FOCUSTARGET` / `TARGETFOCUS` are right), leader J potion, leader timeout
and fall-through, learned spells land on their key, UI U/I/O/P/L/M (Bagnon
opens), world J/K/H/N/M, all addons load, Plater coexists with Q/B.

Decided: **Leatrix Plus owns quest accept/turn-in and vendor chores.** G
and 1–9 still handle what Leatrix doesn't: gossip options, reward choices,
popups, loot, trainers.

Found: numbers in a spell trainer window said "no dialog open". Fixed:
1–9 learn the Nth spell you can learn now (list reprints after each), G
learns the first one, one spell per press.

## Still to verify

- [x] Trainer: 1–9 and G learn spells; the list reprints after each.
- [x] Bar 2 is shown (it holds the , . / X C V Z buttons).
- [x] `,` Polymorphs the focus when set, the target otherwise (level 8).
- [x] Punctuation keys `,` `.` `/` once their spells are learned (WoW's
      names for them are the literal characters, as assumed).
- [ ] Talk to an NPC with gossip options (A): options print numbered in
      chat; 1–9 picks.
- [x] G takes the only reward; with several rewards it asks for a number.
- [x] G accepts a resurrection popup (so StaticPopup1's button works).
- [ ] G accepts a group invite.
- [ ] Ctrl+Alt / Ctrl+Alt+Shift chords don't trigger anything in Windows.
- [ ] UI B opens the bank window at a banker (Bagnon).
- [x] `/wowkeys find leatrix` works in game (names recorded under Addons).
- [x] `/wowkeys find` for bagnon, dbm, auctionator (names recorded under
      Addons).
- [x] `/wowkeys find atlas` (recorded under Addons).
- [ ] `/wowkeys find auction`, `post`, `cancel` (Auctionator under other
      names?).
- [ ] Loot rolls and full-bag loot windows: note what you'd want to press.

Later:
- [ ] `A` interacts with objects too (assumed `INTERACTTARGET`).
- [ ] `Z` mounts at 40 (`/run C_MountJournal.SummonByID(0)`; assumes the
      trainer's mount lands in the mount journal).
- [ ] Is there a camera-rotate keybinding that doesn't turn the character?
- [ ] Assisted Highlight exists in Forever.
- [ ] `/cast [@target,exists][@player] Blizzard` lands on the target.

## Next steps

1. Finish "Still to verify" in game.
2. Window navigation (see Open questions): the check, then route 1 or 3.
   Loot rolls after that.
3. Long cooldowns on the leader layer.
