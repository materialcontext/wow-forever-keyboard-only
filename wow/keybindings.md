# WoW keybinding checklist

The in-game half of the layout. kanata's combat layer passes keys through
unchanged, so these bindings *are* the combat layout. Set them under
Esc → Options → Keybindings.

When you bind a key, WoW moves it off whatever it did before (e.g. `M`
stops opening the map). That's expected: the letter keys are all taken by
combat mode, and UI mode will get those windows back later.

## Settings

| Setting | Value | Why |
|---|---|---|
| Interact key | on | `A` loots, talks to NPCs, uses objects without clicking |
| Soft targeting (enemy) | on | picks a target from what you face |
| Auto loot | on | no loot window to navigate |
| Camera following style | Always | the camera swings behind you, since you can't drag it |
| Assisted Highlight | on | glows the suggested next spell on your bars; you still pick |
| Click-to-move | off | mouse only |

## Movement and targeting (combat mode, left hand)

| Key | WoW binding |
|---|---|
| E | Move Forward |
| D | Move Backward |
| S | Strafe Left |
| F | Strafe Right |
| W | Turn Left |
| R | Turn Right |
| Space | Jump (also ascends while flying) |
| T | Toggle Autorun |
| G | Pitch Up |
| B | Pitch Down |
| Q | Target Nearest Enemy |
| A | Interact With Target |
| Esc | leave as is (close window / clear target / game menu) |
| Enter | leave as is (Open Chat) |
| Tab | leave as is for now (becomes UI mode later) |

Pitch is on the left hand with the other movement keys, so steering while
skyriding never needs a mode switch.

## Ability slots (combat mode)

Rotation keys go on the main bar (Action Button 1–12) because mounted
skyriding abilities replace main-bar slots automatically.

| Key | WoW binding | Frost Mage suggestion |
|---|---|---|
| J | Action Button 1 | Frostbolt |
| K | Action Button 2 | Ice Lance |
| L | Action Button 3 | Flurry |
| ; | Action Button 4 | Frozen Orb |
| U | Action Button 5 | Glacial Spike |
| I | Action Button 6 | Comet Storm |
| O | Action Button 7 | Ray of Frost |
| P | Action Button 8 | Blizzard (`/cast [@player] Blizzard` macro) |
| H | Action Button 9 | Counterspell |
| Y | Action Button 10 | Ice Barrier |
| N | Action Button 11 | Ice Block |
| M | Action Button 12 | Icy Veins |
| , | Action Bar 2 Button 1 | Shifting Power |
| . | Action Bar 2 Button 2 | Mirror Image |
| / | Action Bar 2 Button 3 | Spellsteal |
| X | Action Bar 2 Button 4 | Frost Nova |
| C | Action Bar 2 Button 5 | Cone of Cold |
| V | Action Bar 2 Button 6 | Blink / Shimmer |
| Z | Action Bar 2 Button 7 | Mount (drag "Summon Random Favorite Mount" here) |

The spell column is a starting point. Midnight changed the specs, so swap
in whatever your talents actually give you and note it here. Long
cooldowns, potions, Time Warp and Alter Time will go to the leader layer.

Ground-targeted spells (Blizzard) need a macro because there's no cursor
to aim with. `[@player]` drops it on you; try `/cast [@target,exists][@player]
Blizzard` to see if it lands on your target instead.

## Mode banner chords

kanata sends these on every mode change. They stay unbound until the
ModeBanner addon exists.

| Chord | Mode |
|---|---|
| Ctrl+Alt+Shift+F9 | combat |
| Ctrl+Alt+Shift+F10 | UI |
| Ctrl+Alt+Shift+F11 | world |
| Ctrl+Alt+Shift+F12 | chat |
