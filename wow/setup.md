# WoW setup

Keybindings and action bars come from `layout.toml` through the WowKeys
addon, so nothing here needs rebinding by hand. This page covers the
one-time parts.

## Install the addon (once)

Link the repo's addon folder into WoW so every regenerate is picked up by a
`/reload`, with no copying. In PowerShell (no admin needed for a junction):

```powershell
New-Item -ItemType Junction `
  -Path "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\WowKeys" `
  -Target "C:\path\to\wow-forever-keyboard-only\addon\WowKeys"
```

Adjust both paths. If the addon list says "out of date", run
`/dump select(4, GetBuildInfo())` in game and add that number to the
`## Interface:` line in `addon/WowKeys/WowKeys.toc`.

## Change the layout

1. Edit `layout.toml`.
2. `cargo run` from the repo root.
3. Restart kanata (or reload its config).
4. `/reload` in WoW.

On every login the addon rewrites your keybindings from the layout and
saves them, so WoW's keybinding menu and the button labels show the real
keys. It also unbinds the old keys from those actions (e.g. `1` no longer
casts button 1). To undo: disable the addon, then Options → Keybindings →
Reset to Default.

Spells go onto their keys when the layout changes and whenever you learn
one. A slot whose spell you haven't learned yet is emptied of other spells
so nothing shows up twice; items and macros are left alone.
`/wowkeys bars` re-places everything by hand.

The addon also applies the `[cvars]` settings in `layout.toml` on login
(auto loot, and stopping WoW from dropping new spells on the bars).

## Settings (once, in Esc → Options)

| Setting | Value | Why |
|---|---|---|
| Interact key | on | `A` loots, talks to NPCs, uses objects without clicking |
| Soft targeting (enemy) | on | picks a target from what you face |
| Camera following style | Always | the camera swings behind you, since you can't drag it |
| Assisted Highlight | on, if Forever has it | glows the suggested next spell on your bars; you still pick |
| Click-to-move | off | mouse only |
| Action Bar 2 | shown | holds the bar-2 buttons in `layout.toml` |

## Controller: latching triggers (Steam Input)

Forever's Gamepad UI switches action layers while LT / RT are **held**.
The owner wants them to **latch** (tap on, tap off), which WoW can't do
itself, so Steam Input does it between the controller and the game.

1. Steam → Games → Add a Non-Steam Game to My Library → Battle.net
   (or browse to `C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe`).
2. Start Battle.net **from Steam**, then press Play on WoW Forever as usual.
3. Steam → Settings → Controller: Steam Input on for your controller type.
4. Right-click Battle.net in the Steam library → Manage → Controller
   layout → Triggers → Left Trigger: full-pull command "Left Trigger",
   gear icon → **Toggle** on. Same for Right Trigger.
5. If the latch doesn't reach the game, add the game's own exe (in the
   `_classic_beta_` folder) as a second non-Steam game and launch that from
   Steam with Battle.net running.

Release latched triggers before opening windows: inside bags and the
character sheet, the triggers switch focus between open frames.
