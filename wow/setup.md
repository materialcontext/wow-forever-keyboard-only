# WoW setup

Keybindings and action bars come from `layout.toml` through the WowKeys
addon, so nothing here needs rebinding by hand. This page covers the
one-time parts.

## Install the addon (once)

Link the repo's addon folder into WoW so every regenerate is picked up by a
`/reload`, with no copying. In PowerShell (no admin needed for a junction):

```powershell
New-Item -ItemType Junction `
  -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\WowKeys" `
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

On login the addon sets every binding. It re-places spells and macros on
your bars only when those changed, since that overwrites whatever is in
those slots. `/wowkeys bars` forces it.

The bindings are "override" bindings: they sit on top of WoW's normal
ones and WoW's keybinding menu won't show them. Disable the addon and
your old bindings are back untouched.

## Settings (once, in Esc → Options)

| Setting | Value | Why |
|---|---|---|
| Interact key | on | `A` loots, talks to NPCs, uses objects without clicking |
| Soft targeting (enemy) | on | picks a target from what you face |
| Auto loot | on | no loot window to navigate |
| Camera following style | Always | the camera swings behind you, since you can't drag it |
| Assisted Highlight | on | glows the suggested next spell on your bars; you still pick |
| Click-to-move | off | mouse only |
| Action Bar 2 | shown | holds the bar-2 buttons in `layout.toml` |
