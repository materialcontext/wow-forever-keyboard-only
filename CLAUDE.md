# WoW keyboard-only modal input

Play World of Warcraft (retail, Windows) with **zero mouse input**, using a
Vim-style modal layer system that minimizes both finger reach and held keys.
This file is the handoff from a design conversation in claude.ai; treat it as
the current source of truth and update it as decisions change.

## Owner preferences

- Rust for any tooling we write; Lua only where WoW requires it (addons).
- Functional and extensible designs, but a manageable codebase beats domain
  purity. Prefer small, boring, obvious code.
- Edits in Neovim. Keep files plain-text and diff-friendly.
- New to WoW. Explain game-specific assumptions when they matter.
- Existing addons are fine, but the owner verifies each one before it goes
  in. Suggest, don't assume.
- Plays **Frost Mage**. Doesn't need to learn the rotation by heart, but
  wants to choose each cast rather than rely on the Single-Button Assistant.
  Plan: normal bars plus Blizzard's Assisted Highlight (glows the suggested
  button).

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
| S | strafe left | F | strafe right |
| W | turn left | R | turn right |
| Q | target (tab) | A | interact |
| T | autorun | Z | mount |
| G | pitch up | B | pitch down |
| X, C, V | extra abilities (Frost: Nova, Cone, Blink) | Space | jump |
| Esc | passthrough (close / clear target / menu) | | |

Pitch lives here, not in world mode: steering while skyriding is movement.

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
confirm). Esc closes them; UI mode will get a passthrough key for typing
into them.

Why kanata owns the layers: WoW's combat lockdown blocks addons from
changing keybindings mid-fight, so an addon can't swap bindings per mode.

Skyriding abilities land on the main bar automatically when mounted, so they
use the combat keys with no extra work.

## Layout sync (decided, pulled forward from phase 2)

`layout.toml` is the single source of truth. `layoutgen` (Rust, `cargo run`
from the repo root) generates `kanata/wow.kbd` and
`addon/WowKeys/Layout.lua`; never hand-edit those. `cargo run -- --check`
fails if they're stale.

The WowKeys addon (one addon, not a separate ModeBanner):
- sets every binding as an **override binding** on each login, so WoW's
  saved bindings are never touched and the layout file always wins;
- places spells and creates macros on bars, but only when the buttons in
  the layout change (tracked by a revision hash) or on `/wowkeys bars`;
- binds each mode's banner chord to a hidden button that updates the
  on-screen mode label, and plays a warning if combat starts outside the
  home (first) mode.

Non-combat modes get `mods` (e.g. `["ctrl", "alt"]`): kanata emits
modifier+key and the addon binds that chord, so modes never collide.
Keys a mode leaves unmapped fall through to combat, which keeps movement
identical everywhere. The generator rejects two keys fighting over one WoW
chord.

## Other modes (draft)

- **Leader (one-shot, Right Alt):** tap, then one key from a second right-hand
  set, then auto-return to combat. Used for potions, racials, battle rez and
  long cooldowns. Short timeout so a stray tap doesn't linger.
- **UI (Tab):** J/K/H/L translate to the UI addon's navigation chords (likely
  KeyboardUI's Ctrl+arrows), number row picks dialogue options, letters open
  bags/character/spellbook/map. Movement still works.
- **World (Shift):** flight pitch, hearthstone, toys, camera zoom and saved
  views, professions.
- **Chat (Enter):** full passthrough until Enter or Esc.

## Mode banner

Each mode-entry key also emits Ctrl+Alt+Shift+<banner> (F9 combat, F12
chat so far). WowKeys shows the mode label, like Vim's `-- INSERT --`.

## Addons to evaluate

Midnight changed the addon API, so confirm each works on current retail.

- KeyboardUI: keyboard navigation of bags, NPC dialogs, quest log, options.
  Last seen listing dated 2022, so verify it's maintained.
- DialogueUI: quest and gossip dialogs by key.
- Leatrix Plus: auto quest accept/turn-in, sell junk, repair.
- Bartender4 or Dominos: action bar layout and paging.
- KeyUI: on-screen keyboard view of bindings for tuning layers.
- ConsolePort: only relevant if we ever go the virtual-gamepad route.

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
addon/WowKeys/WowKeys.lua # applies Layout.lua, mode banner
wow/setup.md              # addon install, one-time game settings
```

## Open questions

- Whether the owner accepts kanata mouse-movement keys as a last-resort UI
  fallback (keyboard input, but it drives a pointer).
- Leader timeout value and whether a second leader is ever needed.
- Exact key set for UI mode, which depends on which UI addon works in current
  retail.

## To verify in game (test 1)

- [ ] WowKeys loads (toc Interface number) and prints "bars placed".
- [ ] Banner: Caps shows `-- COMBAT --`, Enter shows `-- CHAT --`
      (proves the Ctrl+Alt+Shift+F chords reach WoW).
- [ ] Punctuation keys (`;` `,` `.` `/`) fire their buttons (WoW's names
      for them are assumed to be the literal characters).
- [ ] Button hotkey labels show the new keys (override bindings may not
      update them; cosmetic).
- [ ] `A` interacts (assumed binding command `INTERACTTARGET`).
- [ ] `Z` mounts (`/run C_MountJournal.SummonByID(0)` macro).
- [ ] Spell names in `layout.toml` match your talents (the addon lists
      any it couldn't place).
- [ ] Caps / Enter while holding a movement key doesn't stutter movement.
- [ ] Chat: Enter opens, Enter sends, Esc and Caps cancel; all land in combat.
- [ ] Keyboard turn speed with W/R is usable for facing a target.
- [ ] Is there a camera-rotate keybinding that doesn't turn the character?
- [ ] Pitch Up / Pitch Down bindings exist and work while skyriding.
- [ ] Assisted Highlight exists in Midnight.
- [ ] `/cast [@target,exists][@player] Blizzard` lands on the target.
- [ ] F13–F24 are bindable in WoW (spare key namespace for later modes).

## Next steps

1. Test 1: install per `wow/setup.md`, play, record results above.
2. Add UI, world and leader modes to `layout.toml` (using `mods`).
3. Maybe: in-game settings as CVars in `layout.toml`, applied by WowKeys.
