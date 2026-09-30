# WoW Forever without a mouse

Play **World of Warcraft: Forever** (Windows) with zero mouse input, two
ways: a Vim-style modal **keyboard** layer (kanata), and Forever's native
**controller** UI tuned through Steam Input. One file, `layout.toml`,
drives both. This file is the handoff between sessions: the current state,
the decisions and why. Keep it current when things change.

## The game: WoW: Forever (not retail, not Classic Era)

Blizzard's "Classic+": the original continents, level 60 cap, reworked
Classic-style classes, permanent. Launches 2026-11-04; the beta
(2026-09-17 to 2026-10-21) caps at level 30 and installs to
`World of Warcraft\_classic_beta_\` (expect a different folder at launch).

- **Modern client and addon API** (mainline 12.1.5) with Midnight's
  combat restrictions for addons. Retail API docs apply, Classic Era ones
  don't; addons need a Forever build.
- **toc Interface** `16001` (confirmed in the beta); the toc also lists
  `120105` in case launch uses it.
- No flying. Ground mounts at level 40 (none in the beta).
- **Frost Mage kit:** Classic-style plus Ice Lance and Fingers of Frost.
  Ice Barrier at 40. No Flurry, Glacial Spike, Comet Storm, Ray of Frost,
  Shifting Power.
- Built-in damage meter and Cooldown Manager. The group finder is locked
  until level 10 (probably; it did nothing at 9).

## Owner

- Rust for tooling; Lua only where WoW requires it.
- Functional, extensible, but a manageable codebase beats domain purity.
  Small, boring, obvious code. Neovim; plain-text, diff-friendly files.
- New to WoW: explain game-specific assumptions when they matter.
- Existing addons are fine once the owner has verified them. Suggest,
  don't assume. **Record addon binding names, but don't bind them until
  the layout for them is agreed.**
- Plays an **Orc Frost Mage** (~level 9 in the beta). Blood Fury is the
  only active racial; used every fight.
- Wants to pick each cast (not the Single-Button Assistant). Plan: normal
  bars plus Blizzard's Assisted Highlight, if Forever has it.

## Architecture (decided)

The **input layer owns ergonomics**, the **game owns meaning**.

- **Keyboard:** kanata (https://github.com/jtroo/kanata, `winIOv2` on
  Windows, no install) does the modes and emits plain keys or
  modifier+key chords. `wintercept` only if winIOv2 misbehaves (it can
  disable input until reboot after sleep). Replaces the owner's iCUE
  macros; turn those off so they don't stack.
- **Controller:** Forever's Gamepad UI plays the game. Steam Input adds
  what WoW can't do itself (touchpad paging, strafe toggle, Social layer)
  by sending single keys. kanata isn't needed for controller play.
- **WoW side:** the WowKeys addon applies the bindings, bars, macros and
  settings from `layout.toml`, and shows the current mode in a banner
  (kanata and WoW can't see each other's state).
- **OS shortcuts pass through:** while Left Alt, Left Ctrl or Win is held
  (`os_hold`), every remapped key sends itself, so Alt+Tab, Win+Tab and
  Ctrl+Shift+Esc work. The generator wraps each remapped cell in a kanata
  `fork` alias (`os-<key>-...`).
- WoW's combat lockdown blocks addons from changing bindings mid-fight,
  which is why the input layer, not an addon, owns modes.

## Keyboard

### Design principles (decided)

1. **Combat mode is complete.** No mode switches mid-fight.
2. **Cost ladder:** base key < one-shot leader < mode switch < hold. No
   sustained holds.
3. **Mode entries are absolute, never toggles.** Caps always means "go to
   combat" (Vim's Esc); mashing it is safe and fixes any desync.
4. **Movement is identical in every mode** except chat.
5. **Chat is Insert mode.** Enter opens chat; Enter or Esc sends/cancels
   and returns to combat.
6. **One keypress = one game action** (Blizzard's rule): no timed
   sequences or multi-action macros from kanata.

Placement rule: pressed every fight → combat key; situational → leader;
out of combat → world.

### Combat mode (home)

| Key | Action | Key | Action |
|---|---|---|---|
| E / D | forward / back | S / F | turn left / right |
| W / R | strafe left / right | Space | jump |
| Q / B | next / previous enemy | A | interact (loot, talk, use) |
| T | autorun | Z | mount (level 40) |
| G | confirm (popup, quest, reward, loot all, trainer) | 1–9 | pick dialog option N |
| J K L ; | Frostbolt (+ Blood Fury when ready), Ice Lance, Fire Blast, Fireball | U I O P | Arcane Missiles, Arcane Explosion, Cold Snap, Blizzard |
| H | Counterspell (interrupts your own cast first) | Y, N | Mana Shield, Ice Block |
| M | Evocation | , | Polymorph (focus if set, else target) |
| . | Blood Fury (by hand) | / | Remove Lesser Curse (friendly target, else you) |
| X C V | Frost Nova, Cone of Cold, Blink | Esc | WoW's own (close, clear target, menu) |

Strafe/turn: W/R strafe, S/F turn (owner preferred turning on the home row).

Mode keys: **Caps** combat · **Tab** UI · **Left Shift** world · **Right
Alt** leader (one-shot) · **Enter** chat.

### Other modes

Non-combat modes add modifiers so their chords never collide with combat.

- **Leader** (Right Alt; one-shot, 1000 ms; Ctrl+key): J health potion,
  K mana potion (macros; update item names as you find better potions),
  L Frost Ward, F set focus, T target focus, C clear focus, / toggle enemy
  nameplates, `,` sheep + set focus (combat `,` re-sheeps the focus
  later), H Counterspell your focus.
- **UI** (Tab; Ctrl+Alt+key): U bags (Bagnon), I character, O spellbook,
  P talents, L quest log, M map, B bank (Bagnon, at a banker), `'` type
  into a text box without Enter (mail, auction search). Esc closes
  windows. Navigating *inside* windows is still unsolved on the keyboard.
- **World** (Left Shift; Ctrl+Alt+Shift+key): J Frost Armor, K Arcane
  Intellect (friendly target, else you), L Conjure Water, ; Conjure Food, U drink, I eat (macros;
  update conjured item names per rank), H hearthstone, N/M camera zoom.
- **Chat** (Enter): full passthrough. Enter sends, Esc **and Caps** cancel;
  both return to combat. Caps sends Esc there, or the chat box keeps focus
  and movement keys type into it.

**Banner:** each mode entry also sends Ctrl+Alt+Shift+F9/F10/F11/F12
(combat/UI/world/chat), sent with kanata `macro` so it never lands in an
open chat box. WowKeys shows `-- COMBAT --` etc. and warns (red, raid
sound) if combat starts outside combat mode. Leader has no banner.

Known desync: text boxes that open without Enter (mail, AH search, DELETE
confirm): Esc closes them; UI `'` switches to chat to type into them.

## Controller (Forever's Gamepad UI)

### What Blizzard provides

From Forever HQ's / NerdsChalk's beta guides plus our probes. Alpha
feature: verify after patches.

- **Turn on:** Options → Gameplay → Gamepad (Alpha) → Enable Gamepad UI.
  Keyboard and controller layouts are stored separately.
- **Bars:** 8 inputs (D-pad + face buttons) × 4 layers (none, LT, RT,
  LT+RT) × 3 arrangements. Without a trigger only the D-pad takes actions;
  the face buttons stay Blizzard's: Cross jump, Square attack/interact,
  Triangle context menu (right-click), Circle cancel.
- **Targeting:** RB tap enemy ahead, RB + D-pad/stick cycles; LB tap
  friendly ahead; hold LB + Cross self; LB + D-pad party members.
- **Shortcuts (hold LB+RB):** D-pad Up quests, Down chat, Right next
  arrangement; Circle backpack; Square sheathe; Triangle buffs.
- **Radial menu** (Options/Start): character, talents, professions, bags,
  spellbook, game menu, chat, quests/map; tabs for group finder, social…
  The owner uses it for windows.
- **Windows:** D-pad (and sticks) move focus, Cross confirms/equips,
  Circle closes, bumpers change tabs, triggers switch between open frames.
  Cross also confirms popups (group invites; verify on a real one).
- Typing chat still needs the keyboard.

### How WowKeys fills the bars

The controller bars are ordinary action slots above 180, so WowKeys places
spells and macros there like the keyboard bars. There are **no standard
PAD bindings**; the Gamepad UI routes buttons itself.

**Slot map (confirmed with `/wowkeys padbuttons` and known pairs):**
`slot = 180 + 28·(arrangement − 1) + layer offset + index`; layer offsets
none 0 (4 slots, D-pad only), LT 4, RT 12, LT+RT 20; index 1–4 D-pad
Left/Up/Right/Down, 5–8 face West/North/East/South (Square/Triangle/
Circle/Cross; Xbox X/Y/B/A). Arrangement 1 = 181–208, 2 = 209–236 (both
confirmed), 3 = 237–264 (assumed). Known pairs: RT+Triangle 198,
RT+Circle 199, RT+Cross 200. Implemented and tested as `layout::pad_slot`.
Slot 397 is Blizzard's extra action button, not ours.

### Layout v3 (decided 2026-09-26)

Both triggers are **plain holds**. Every arrangement ranks its layers the
same way: **no trigger** all the time, **RT** often (above all in combat),
**LT** less often, **LT+RT** rarely. Within a layer, **face buttons =
instants used on the move** (right thumb), **D-pad = casts while
standing** (left thumb; moving cancels a cast bar anyway).

| Arrangement 1 (combat) | Face (on the move) | D-pad (standing) |
|---|---|---|
| No trigger | Blizzard's (attack is Square) | ↑ Frostbolt (+ Blood Fury) → Fireball ← Polymorph ↓ Fire Blast |
| RT | ✕ Ice Lance □ Frost Nova △ Cone of Cold ○ Blink | ↑ Blizzard → Blood Fury ← Arcane Explosion ↓ Mana Shield |
| LT | ✕ Ice Barrier (40) □ Counterspell △ Ice Block ○ health potion | ↑ Evocation → Arcane Missiles ← sheep + set focus ↓ clear focus |
| LT+RT | ✕ mana potion □ Cold Snap △ Frost Ward ○ Remove Lesser Curse | ↑ target focus ← Counterspell focus |

Arrangement 2 (out of combat): no trigger D-pad ↑ drink → eat ↓ Conjure
Water ← Conjure Food; RT D-pad ↑ Frost Armor → Arcane Intellect ↓ hearth
← mount. Arrangement 3 spare.

**Macros** (shared by keyboard and controller; keyboard modes define the
body, controller entries name them). A macro may run any number of free
commands (`/focus`, `/stopcasting`, `/target`) plus one spell on the
global cooldown per press.

| Macro | Body | Why |
|---|---|---|
| `Poly` | `/cast [@focus,harm,nodead][] Polymorph` | re-sheep the focus, else sheep the target |
| `SheepFocus` | `/focus` + `/cast [@focus] Polymorph` | sheep the target and remember it |
| `Interrupt` | `/stopcasting` + `/cast Counterspell` | interrupt now, even mid-Frostbolt |
| `InterruptFocus` | `/stopcasting` + `/cast [@focus,harm,nodead] Counterspell` | interrupt the focus without retargeting; separate because the focus is often the sheep |
| `Bolt` | `/cast Blood Fury` + `/cast Frostbolt` + clear the error text | Frostbolt that pops the racial whenever it's ready, so it goes off on the first bolt of every fight (owner's idea); assumes Blood Fury is off the GCD. Plain Blood Fury stays on `.` / RT → for manual use |
| `Intellect`, `Decurse` | `/cast [@target,help,nodead][@player] …` | friendly target if any, else yourself |
| `Blizzard` | `/cast [@player] Blizzard` | ground spell at your feet |
| potions, drink, eat, hearth, mount, focus | `/use …`, `/focus`… | items and focus commands on keys and bars |

History: v1 put the main spells on the D-pad (the left thumb can't move
and press it); v2 latched LT as a combat home layer, which hid Blizzard's
Square attack. Latching is possible with Steam's per-trigger Toggle if
ever wanted again.

### Paging arrangements (built, works in combat)

No binding pages the controller bars (`ACTIONPAGE1–6` only page the
keyboard bar), and calling the page unit's `SetCurrentPage` from an addon
is **blocked** ("only available to the Blizzard UI"). What works: a key
press clicking Blizzard's own `GamepadMainActionBarFramePageUnit.PageTracker
.ChangePageButton` through a secure proxy. WowKeys creates `WowKeysPage`
(SecureActionButton, `type=click`, set up out of combat by a ticker once
the Gamepad UI exists); `CLICK WowKeysPage:LeftButton` = next,
`:RightButton` = previous. Touchpad right half → F8 next, left half → F7
previous. The banner shows `· BAR n` (read from the first controller
button's slot every 0.25 s).

### Strafe mode (built, works)

L3 → F9 → `wowkeys:strafe` toggles the face-movement angle
(`GamePadFaceMovementMaxAngle` and `…Combat`) between **180** (the stick
strafes and backpedals) and the previous values (default **0**: the
character turns toward the stick). Saved per character; the banner shows
`· STRAFE`. Forever's meaning is the reverse of our first guess.

### Social layer (built)

A Steam **hold** layer on Create: target first (bumpers), hold Create,
press, let go; windows then navigate natively. Left stick, D-pad, Cross
and Circle stay Blizzard's.

| Hold Create + | Key | Does |
|---|---|---|
| △ | Numpad 8 | social window (`TOGGLESOCIAL`) |
| □ | Numpad 4 | guild & communities (`TOGGLEGUILDTAB`) |
| Right stick ↑ | Numpad 6 | group finder (`TOGGLEGROUPFINDER`; level 10) |
| Right stick ↓ | Numpad 1 | leave group (macro `C_PartyInfo.LeaveParty()`) |
| LT | Numpad 9 | follow target (`FOLLOWTARGET`) |
| RT | Numpad 3 | trade with target (macro `/trade`) |
| RB | Numpad 2 | invite target (macro `/invite`) |

Spare: LB, right stick ←/→, R3. Rarer actions (inspect, whisper,
promote, loot settings) are in Blizzard's context menu: target a player,
Triangle. Leaving a group natively: hold LB + Cross (self), Triangle,
Leave Group.

### Steam Input lessons

- **One key per input** (no chords): single keys only (F7–F9, numpad
  digits `kp0`–`kp9`, which kanata passes through and no mode uses).
- **Layers must be holds.** A latched layer (Create toggling window keys
  on the D-pad) fought Blizzard's D-pad window navigation; dropped.
- New layers may come up **blank**: copy the base inputs. Stick
  directions need the stick's style set to **Directional Pad** first;
  triggers bind on the full pull.
- Check the WoW side of any Steam key by pressing it on the keyboard
  (Num Lock on for the keypad).
- With kanata also running it sees Steam's injected keys; plain keys pass
  untouched (untested with chords, which we no longer send).
- Setup steps: `wow/setup.md`; what to bind: `wow/steam-layers.md`.

## Generator and addon

`layout.toml` is the single source of truth. `layoutgen` (Rust; `cargo
run` from the repo root) writes the three generated files; never edit
those by hand. `cargo run -- --check` fails if they're stale.

**`layout.toml` sections:** `os_hold`; `[cvars]` (applied at login);
`[[mode]]` (name, label, banner, `oneshot` ms, `passthrough`, `mods`,
keys); `[controller.<layer>]` (layers `none`, `lt`, `rt`, `ltrt`,
suffix `2`/`3` for other arrangements; inputs `up right down left north
east south west`); `[[steam_button]]` (input, key, command or `macro` +
`body`, does, optional `layer`); `[steam_layer]` (name, button; always a
hold layer).

**Action kinds:** WoW binding command; spell or macro on a bar button
(`bar` 1–8, `button` 1–12); spell or macro bound directly (`SPELL x` /
`MACRO x`, no bar slot); mode switch (optionally sending a key);
`wowkeys:<command>` (`confirm`, `strafe`, `choose1`–`choose9`).
`{ macro = "Poly" }` may name a macro defined elsewhere without its body.

**The generator rejects:** unknown keys or modes, two keys fighting over
one WoW chord (give the mode `mods`), one macro name with two bodies, two
things in one keyboard bar slot, face buttons without a trigger, unknown addon
commands, steam buttons naming a missing layer.

Keys a mode leaves unmapped behave as in home (the generator copies the
home cell), so movement and mode keys work everywhere; passthrough modes
send unmapped keys as typed. kanata aliases are emitted banners →
switches → os forks, since kanata needs an alias declared before use.

**The WowKeys addon** (files share the addon's private namespace `ns`):

- `Layout.lua` (generated) → `ns.layout`.
- `WowKeys.lua`, runtime:
  - **Bindings:** rewrites and saves the real bindings at every login (so
    the layout wins and hotkey labels show our keys), unbinding other keys
    from commands it owns. It warns about any bound command the game
    doesn't know.
  - **CVars and macros:** applies `[cvars]` and creates/edits macros.
  - **Bars:** places spells and macros when the layout's buttons change
    (revision hash), when a spell is learned, or on `/wowkeys bars`. A
    slot whose spell isn't learned yet is cleared of other spells and of
    WowKeys' own leftover macros; items and your own macros stay.
  - **Also:** the mode banner, strafe mode, `WowKeysPage`, and the
    `/wowkeys` registry. Bindings and bars queue until combat ends.
- `Commands.lua`: `confirm` and `choose1`–`9`. It reads which dialog is
  open from Blizzard's frames at keypress time (StaticPopup1, Quest
  frames, LootFrame, ClassTrainerFrame, GossipFrame) and prints numbered
  options when one opens. Trainer: 1–9 learn the Nth available spell, G
  the first; the list reprints.
- `Diagnostics.lua`: the probes below. Nothing depends on them.

**Tests:** `cargo test` (layout parsing, validation, slot map, chords),
`cargo clippy -- -D warnings`, `lua5.1 addon/tests/dryrun.lua` (the addon
against stubbed WoW APIs; run after any Lua change), `kanata --cfg
kanata/wow.kbd --check`.

## Diagnostics (`/wowkeys`)

`/wowkeys` alone lists these with their usage (from the registry, so the
list can't go stale). A failing command prints its Lua error.

| Command | Does | Used for |
|---|---|---|
| `bars` | re-place spells and macros (not a probe) | after moving spells by hand |
| `find <text>` | binding commands matching text, with names and keys | exact names for `layout.toml` |
| `pad` | bindings on PAD keys, GamePad settings, all GamePad CVar names | controller settings (found the strafe CVars) |
| `slots` | every filled action slot 1–1000 | found the controller slots |
| `padbuttons` | controller-bar buttons: slot, short name, screen position | built the slot map |
| `page` | the Gamepad UI's current page and pageable bars (read-only) | paging |
| `pagecontrols` | page tracker and shortcut menu, children two deep | found ChangePageButton |
| `frames <text>` | named frames containing text, shown or hidden | finding frames by name |
| `newframes [s]` | frames that appear within s seconds (default 5) | menus that close when chat opens |
| `inspect <name>` | a frame's fields, functions and children | reading Blizzard's frames |

Frames whose names aren't plain text (some addons', values the client
hides) are skipped. In chat output the matches print *above* each
"N match" summary line.

## Addons

Each addon needs a Forever-compatible build and the owner's OK.

| Addon | Job | Impact |
|---|---|---|
| Leatrix Plus | auto quest accept/turn-in, sell junk, repair, QoL | **Owns quest accept/turn-in and vendoring** (decided). G and 1–9 cover the rest. To skip its automation at one NPC, hold **Right** Shift while pressing A (Left Shift is the world key). |
| Leatrix Maps | map reveal, coordinates, zone levels | UI M opens the (enhanced) map. Map zoom/pan are mouse-only. |
| Bagnon | combined bags and bank | UI U opens bags; UI B opens the bank (`BAGNON_BANK_TOGGLE`). Untested with the controller's backpack. |
| Plater | enemy nameplates | Q/B and leader / rely on nameplates. If it fights `nameplateShowEnemies`, drop that from `[cvars]`. |
| DBM | boss timers | Display only; chat commands (`/dbm`). |
| Auctionator | auction house | Hardest without a mouse; no bindings found yet. |
| AtlasLoot | loot tables | Mouse-driven; a key to open it at most. |
| EllesmereUI | UI replacement: action-bar extras, unit/raid frames, micro menu, chat skin | **Owns the chat's look and visibility:** Chat → Visibility (the owner's choice) and Idle Fade. No bindings; its chat background is unnamed frames, so don't try to hide it from WowKeys. |

**Binding names found** (bound: only `BAGNON_BANK_TOGGLE`):
Leatrix Plus `LEATRIX_PLUS_GLOBAL_TOGGLE`, `_WEBLINK`, `_RARE`,
`_MOUNTSPECIAL`; Leatrix Maps `LEATRIX_MAPS_GLOBAL_TOGGLE`; Bagnon
`BAGNON_TOGGLE`, `BAGNON_BANK_TOGGLE`, `BAGNON_VAULT_TOGGLE`,
`BAGNON_GUILD_TOGGLE`; AtlasLoot `ATLASLOOT_TOGGLE`; DBM and EllesmereUI
none; Auctionator none under "auctionator" (try `auction`, `post`,
`cancel`).

**Coexisting:** `Commands.lua` finds dialogs by Blizzard frame names, so
an addon replacing gossip/quest/loot frames (DialogueUI, Immersion) would
break 1–9 and G. WowKeys rewrites only the keys in `layout.toml`; an
addon's own keys survive unless they collide. An addon changing a
`[cvars]` setting will fight it: remove ours. With a UI suite, check its
own settings before building a workaround (the chat toggle lesson).

Not picked: Interaction / DialogueUI (keyboard dialogs), KeyboardUI,
Bartender4 / Dominos, KeyUI, ConsolePort.

Useful game settings (`wow/setup.md`): Interact key, soft targeting,
auto-loot, camera following "Always", `/cast [@player] Spell` for
ground-targeted spells.

## Repo layout

```
CLAUDE.md                  # this handoff
layout.toml                # the layout; edit this
layoutgen/                 # Rust generator: layout.toml -> GENERATED files
kanata/wow.kbd             # GENERATED: kanata config
addon/WowKeys/Layout.lua   # GENERATED: data for the addon
addon/WowKeys/WowKeys.lua  # bindings, bars, banner, strafe, paging, /wowkeys
addon/WowKeys/Commands.lua # confirm / choose1-9 (dialogs, loot, trainers)
addon/WowKeys/Diagnostics.lua # /wowkeys probes
addon/tests/dryrun.lua     # the addon against stubbed WoW APIs
wow/setup.md               # install, game settings, Steam plumbing
wow/steam-layers.md        # GENERATED: what to bind in Steam
```

## Verified in game

- **Keyboard:** kanata config, all mode keys, movement in every mode,
  banner chords, chat round trips, Caps from chat, Alt+Tab family
  passthrough, spell keys (letters and `, . /`), hotkey labels show our
  keys, duplicate spells cleared at login, learned spells land on their
  key, A loots (`autoLootDefault = 1`), Q/B cycling (keep
  `targetNearestDistance = 50` and `TargetNearestUseNew = 0`), leader
  keys and timeout, focus commands, Polymorph on focus, UI keys (Bagnon
  opens), world keys, trainer 1–9/G, G on single rewards and
  resurrection, all addons load, Plater with Q/B. F13–F24 aren't
  available (the keyboard can't send them).
- **Controller:** layout v3 on arrangements 1 and 2, touchpad paging in
  and out of combat, triggers as holds, keyboard bars untouched, strafe
  mode, Social layer (all inputs; invite/trade/follow need a target).

## Still to verify

- [ ] Group finder opens at level 10.
- [ ] New macros: Interrupt cancels a Frostbolt cast and Counterspells;
      InterruptFocus hits the focus; the Frostbolt key pops Blood Fury
      *and* casts Frostbolt (if only Blood Fury happens, it's on the GCD in
      Forever: undo Bolt), with no "not ready" error text afterwards; Intellect/Decurse land on a friendly target, else
      you; SheepFocus sheeps and sets focus.
- [ ] Cross accepts a real group invite; G does too on the keyboard.
- [ ] Gossip options print numbered and 1–9 pick them.
- [ ] Ctrl+Alt / Ctrl+Alt+Shift chords trigger nothing in Windows.
- [ ] UI B opens the bank at a banker (Bagnon).
- [ ] `/wowkeys find auction`, `post`, `cancel` for Auctionator.
- [ ] Loot rolls and full-bag loot windows: what should keys do?
- Later: A on objects (`INTERACTTARGET`); Z mounts at 40; a camera key
  that doesn't turn the character; Assisted Highlight in Forever;
  `/cast [@target,exists][@player] Blizzard` placement.

## Open questions

- **Keyboard window navigation** (bags, character, talents) is unsolved.
  The controller does it natively; for the keyboard the plan is a
  ConsolePort-style navigator in WowKeys (focus one clickable widget,
  move by hints or H/J/K/L, click through a secure proxy like
  `WowKeysPage`; out of combat). `/equip` and `/use` by name are the
  stopgap.
- Group loot rolls (need/greed/pass) by key.
- Leader timeout (1000 ms) and whether a second leader is needed.
- Whether kanata mouse-movement keys are acceptable as a last resort.
- Very low priority: keyboard access to addon settings panels (Leatrix
  `/ltp`, `/ltm`, AtlasLoot); the owner uses the mouse for these.

## Next steps

1. Finish "Still to verify" in game.
2. Arrangement 3: content once the owner wants it (and confirm its slots).
3. Keyboard window navigation, then loot rolls.
4. Long cooldowns on the leader layer.
