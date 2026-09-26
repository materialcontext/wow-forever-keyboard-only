//! layout.toml: types, parsing and validation.

use crate::keys;
use serde::Deserialize;
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Layout {
    /// While any of these physical keys is held, every key sends its plain
    /// self, so OS shortcuts (Alt+Tab, Win+Tab, Ctrl+Shift+Esc) still work.
    #[serde(default)]
    pub os_hold: Vec<String>,
    /// Game settings the addon applies on login (name -> value).
    #[serde(default)]
    pub cvars: BTreeMap<String, String>,
    #[serde(rename = "mode")]
    pub modes: Vec<Mode>,
    /// Forever's Gamepad UI bars: layer -> input -> spell or macro.
    #[serde(default)]
    pub controller: BTreeMap<String, BTreeMap<String, Button>>,
    /// A Steam Input layer that makes controller inputs send a mode's key
    /// combos (e.g. UI mode on the Create button).
    pub steam_layer: Option<SteamLayer>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SteamLayer {
    /// The mode whose key combos the layer sends; its banner shows while
    /// the layer is latched.
    pub mode: String,
    /// The controller button that latches the layer (for the setup sheet).
    pub button: String,
    /// Controller input (see `PAD_INPUTS`) -> key in that mode.
    pub keys: BTreeMap<String, String>,
}

/// Controller inputs, D-pad then face buttons by position.
pub const PAD_INPUTS: &[&str] = &[
    "left", "up", "right", "down", "west", "north", "east", "south",
];

/// Action slot for a controller layer and input on bar arrangement 1.
/// Slots are 180 + layer offset + button index. Mapped in game: the Top bar
/// (no trigger, D-pad only) is 181-184, LT 185-192, RT 193-200, LT+RT
/// 201-208; buttons 1-4 are D-pad left/up/right/down, 5-8 the face buttons
/// west/north/east/south (Square/Triangle/Circle/Cross, Xbox X/Y/B/A).
pub fn pad_slot(layer: &str, input: &str) -> Result<u16, String> {
    let offset = match layer {
        "none" => 0,
        "lt" => 4,
        "rt" => 12,
        "ltrt" => 20,
        _ => return Err(format!("unknown layer `{layer}` (none, lt, rt, ltrt)")),
    };
    let index = match input {
        "left" => 1,
        "up" => 2,
        "right" => 3,
        "down" => 4,
        "west" => 5,
        "north" => 6,
        "east" => 7,
        "south" => 8,
        _ => {
            return Err(format!(
                "unknown input `{input}` (up, right, down, left, north, east, south, west)"
            ));
        }
    };
    if layer == "none" && index > 4 {
        return Err(
            "face buttons without a trigger are fixed (jump, interact, menu, cancel)".into(),
        );
    }
    Ok(180 + offset + index)
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Mode {
    pub name: String,
    pub label: String,
    /// Sent as Ctrl+Alt+Shift+<banner> on entering the mode. One-shot
    /// modes have none: they end after one key anyway.
    pub banner: Option<String>,
    /// One-shot mode: active for the next key only, or until this many ms.
    pub oneshot: Option<u32>,
    /// Unmapped keys type text.
    #[serde(default)]
    pub passthrough: bool,
    /// Modifiers added to this mode's bound keys.
    #[serde(default)]
    pub mods: Vec<Mod>,
    #[serde(default)]
    pub keys: BTreeMap<String, Action>,
}

/// Declared in WoW's canonical binding order (ALT-CTRL-SHIFT-key).
#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Mod {
    Alt,
    Ctrl,
    Shift,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum Action {
    Command(String),
    Switch(Switch),
    Button(Button),
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Switch {
    pub mode: String,
    pub send: Option<String>,
}

/// A spell or macro, either placed on an action button (bar + button) or
/// bound to the key directly. A bare bar + button is a slot you fill by hand.
#[derive(Debug, Deserialize, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Button {
    pub bar: Option<u8>,
    pub button: Option<u8>,
    pub spell: Option<String>,
    #[serde(rename = "macro")]
    pub macro_name: Option<String>,
    pub body: Option<String>,
}

/// A key plus modifiers, rendered for either side.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Chord {
    pub mods: Vec<Mod>,
    pub key: String,
}

impl Chord {
    pub fn new(mods: &[Mod], key: &str) -> Self {
        let mut mods = mods.to_vec();
        mods.sort();
        mods.dedup();
        Chord {
            mods,
            key: key.to_string(),
        }
    }

    pub fn banner(key: &str) -> Self {
        Chord::new(&[Mod::Alt, Mod::Ctrl, Mod::Shift], key)
    }

    /// For people, e.g. `Ctrl + Alt + I` (Steam's editor, docs).
    pub fn human(&self) -> String {
        let mut parts: Vec<&str> = [
            (Mod::Ctrl, "Ctrl"),
            (Mod::Alt, "Alt"),
            (Mod::Shift, "Shift"),
        ]
        .iter()
        .filter(|(m, _)| self.mods.contains(m))
        .map(|(_, name)| *name)
        .collect();
        let key = keys::wow_name(&self.key).expect("validated key");
        parts.push(&key);
        parts.join(" + ")
    }

    /// kanata syntax, e.g. `A-C-S-f9`.
    pub fn kanata(&self) -> String {
        let prefix: String = self
            .mods
            .iter()
            .map(|m| match m {
                Mod::Alt => "A-",
                Mod::Ctrl => "C-",
                Mod::Shift => "S-",
            })
            .collect();
        format!("{prefix}{}", self.key)
    }

    /// WoW binding string, e.g. `ALT-CTRL-SHIFT-F9`. Only valid after validation.
    pub fn wow(&self) -> String {
        let prefix: String = self
            .mods
            .iter()
            .map(|m| match m {
                Mod::Alt => "ALT-",
                Mod::Ctrl => "CTRL-",
                Mod::Shift => "SHIFT-",
            })
            .collect();
        let key = keys::wow_name(&self.key).expect("validated key");
        format!("{prefix}{key}")
    }
}

/// Commands the WowKeys addon implements itself, as `wowkeys:<name>`.
pub const ADDON_COMMANDS: &[&str] = &[
    "confirm", "vendor", "choose1", "choose2", "choose3", "choose4", "choose5", "choose6",
    "choose7", "choose8", "choose9",
];

impl Button {
    /// The WoW binding command for this key: the action button if placed,
    /// otherwise the spell or macro itself.
    pub fn command(&self) -> String {
        match (self.slot(), &self.spell, &self.macro_name) {
            (Some((command, _)), _, _) => command,
            (None, Some(spell), _) => format!("SPELL {spell}"),
            (None, _, Some(name)) => format!("MACRO {name}"),
            _ => unreachable!("validated button"),
        }
    }

    /// Binding command and action slot id, if placed on a bar.
    pub fn slot(&self) -> Option<(String, u16)> {
        let (bar, button) = (self.bar?, self.button?);
        let (command, base) = match bar {
            1 => ("ACTIONBUTTON", 0),
            2 => ("MULTIACTIONBAR1BUTTON", 60),
            3 => ("MULTIACTIONBAR2BUTTON", 48),
            4 => ("MULTIACTIONBAR3BUTTON", 24),
            5 => ("MULTIACTIONBAR4BUTTON", 36),
            6 => ("MULTIACTIONBAR5BUTTON", 144),
            7 => ("MULTIACTIONBAR6BUTTON", 156),
            8 => ("MULTIACTIONBAR7BUTTON", 168),
            _ => unreachable!("validated bar"),
        };
        Some((format!("{command}{button}"), base + u16::from(button)))
    }
}

impl Mode {
    /// Bound keys in grid order, for stable output.
    pub fn keys_in_order(&self) -> impl Iterator<Item = (&str, &Action)> {
        keys::GRID
            .iter()
            .flat_map(|row| row.iter())
            .filter_map(|k| self.keys.get(*k).map(|a| (*k, a)))
    }

    pub fn chord(&self, key: &str) -> Chord {
        Chord::new(&self.mods, key)
    }
}

pub fn parse(text: &str) -> Result<Layout, Vec<String>> {
    let layout: Layout = toml::from_str(text).map_err(|e| vec![e.to_string()])?;
    let errors = validate(&layout);
    if errors.is_empty() {
        Ok(layout)
    } else {
        Err(errors)
    }
}

fn validate(layout: &Layout) -> Vec<String> {
    let mut errors = Vec::new();
    if layout.modes.is_empty() {
        errors.push("layout needs at least one [[mode]]".into());
    }
    for key in &layout.os_hold {
        if !keys::is_key(key) {
            errors.push(format!("os_hold: unknown key `{key}`"));
        }
    }

    let mut names: HashMap<&str, &Mode> = HashMap::new();
    let mut banners = HashMap::new();
    for mode in &layout.modes {
        if names.insert(mode.name.as_str(), mode).is_some() {
            errors.push(format!("mode `{}` is defined twice", mode.name));
        }
        match (&mode.banner, mode.oneshot) {
            (None, None) => errors.push(format!("mode `{}` needs a banner", mode.name)),
            (Some(_), Some(_)) => errors.push(format!(
                "mode `{}`: one-shot modes have no banner",
                mode.name
            )),
            _ => {}
        }
        if mode.oneshot.is_some() && mode.passthrough {
            errors.push(format!(
                "mode `{}`: one-shot can't be passthrough",
                mode.name
            ));
        }
        let Some(banner) = &mode.banner else { continue };
        if !keys::is_function_key(banner) {
            errors.push(format!("mode `{}`: banner must be f1..f24", mode.name));
        }
        if let Some(other) = banners.insert(banner.as_str(), mode.name.as_str()) {
            errors.push(format!(
                "modes `{other}` and `{}` share banner {banner}",
                mode.name
            ));
        }
    }

    // WoW binding string -> (command, where), to catch two keys fighting over one chord.
    let mut wow_bindings: HashMap<String, (String, String)> = HashMap::new();
    // Action slot -> button, to catch two different things placed in one slot.
    let mut slots: HashMap<u16, (&Button, String)> = HashMap::new();
    // Macro name -> body, since WoW macros are looked up by name.
    let mut macros: HashMap<&str, (Option<&str>, String)> = HashMap::new();

    for mode in &layout.modes {
        for (key, action) in &mode.keys {
            let at = format!("{}.{key}", mode.name);
            if !keys::is_key(key) {
                errors.push(format!("{at}: unknown key (see layoutgen/src/keys.rs)"));
                continue;
            }
            let command = match action {
                Action::Switch(s) => {
                    match names.get(s.mode.as_str()) {
                        None => errors.push(format!("{at}: no mode named `{}`", s.mode)),
                        Some(target) if target.oneshot.is_some() && s.send.is_some() => {
                            errors.push(format!("{at}: can't send a key into a one-shot mode"))
                        }
                        _ => {}
                    }
                    if let Some(send) = &s.send
                        && !keys::is_key(send)
                    {
                        errors.push(format!("{at}: can't send unknown key `{send}`"));
                    }
                    continue;
                }
                Action::Command(c) => {
                    if let Some(name) = c.strip_prefix("wowkeys:")
                        && !ADDON_COMMANDS.contains(&name)
                    {
                        errors.push(format!(
                            "{at}: unknown addon command `{name}` (have: {})",
                            ADDON_COMMANDS.join(", ")
                        ));
                    }
                    c.clone()
                }
                Action::Button(b) => {
                    if let Err(e) = check_button(b) {
                        errors.push(format!("{at}: {e}"));
                        continue;
                    }
                    if let Some(name) = &b.macro_name {
                        match macros.get(name.as_str()) {
                            Some((body, other_at)) if *body != b.body.as_deref() => errors.push(
                                format!("{at}: macro `{name}` has a different body at {other_at}"),
                            ),
                            _ => {
                                macros.insert(name, (b.body.as_deref(), at.clone()));
                            }
                        }
                    }
                    if let Some((_, slot)) = b.slot()
                        && (b.spell.is_some() || b.macro_name.is_some())
                    {
                        match slots.get(&slot) {
                            Some((other, other_at)) if *other != b => errors.push(format!(
                                "{at}: that bar button already holds something else at {other_at}"
                            )),
                            _ => {
                                slots.insert(slot, (b, at.clone()));
                            }
                        }
                    }
                    b.command()
                }
            };
            if mode.passthrough {
                errors.push(format!("{at}: passthrough modes can only switch modes"));
                continue;
            }
            if keys::wow_name(key).is_none() {
                errors.push(format!("{at}: WoW can't bind this key on its own"));
                continue;
            }
            let chord = mode.chord(key).wow();
            match wow_bindings.get(&chord) {
                Some((other, other_at)) if *other != command => errors.push(format!(
                    "{at}: {chord} is already bound to {other} at {other_at}; give this mode `mods`"
                )),
                _ => {
                    wow_bindings.insert(chord, (command, at));
                }
            }
        }
    }
    if let Some(steam) = &layout.steam_layer {
        match names.get(steam.mode.as_str()) {
            None => errors.push(format!("steam_layer: no mode named `{}`", steam.mode)),
            Some(mode) if mode.banner.is_none() || mode.passthrough => errors.push(format!(
                "steam_layer: mode `{}` needs a banner and can't be passthrough",
                steam.mode
            )),
            Some(mode) => {
                for (input, key) in &steam.keys {
                    let at = format!("steam_layer.keys.{input}");
                    if !PAD_INPUTS.contains(&input.as_str()) {
                        errors.push(format!(
                            "{at}: unknown input (have: {})",
                            PAD_INPUTS.join(", ")
                        ));
                    }
                    match mode.keys.get(key) {
                        Some(Action::Command(_)) | Some(Action::Button(_)) => {}
                        Some(Action::Switch(_)) => {
                            errors.push(format!("{at}: `{key}` switches modes; pick a game action"))
                        }
                        None => errors.push(format!(
                            "{at}: mode `{}` has nothing on `{key}`",
                            steam.mode
                        )),
                    }
                }
            }
        }
    }

    for (layer, inputs) in &layout.controller {
        for (input, b) in inputs {
            let at = format!("controller.{layer}.{input}");
            if let Err(e) = pad_slot(layer, input) {
                errors.push(format!("{at}: {e}"));
            }
            // `{ macro = "Poly" }` may refer to a macro defined in a mode.
            let reference = b.macro_name.is_some() && b.body.is_none() && b.spell.is_none();
            if b.bar.is_some() || b.button.is_some() {
                errors.push(format!(
                    "{at}: no bar/button here; the input picks the slot"
                ));
            } else if reference {
                let name = b.macro_name.as_deref().unwrap_or_default();
                if !macros.contains_key(name) {
                    errors.push(format!("{at}: macro `{name}` isn't defined in any mode"));
                }
                continue;
            } else if let Err(e) = check_button(b) {
                errors.push(format!("{at}: {e}"));
            }
            if let Some(name) = &b.macro_name {
                match macros.get(name.as_str()) {
                    Some((body, other_at)) if *body != b.body.as_deref() => errors.push(format!(
                        "{at}: macro `{name}` has a different body at {other_at}"
                    )),
                    _ => {
                        macros.insert(name, (b.body.as_deref(), at.clone()));
                    }
                }
            }
        }
    }
    errors
}

fn check_button(b: &Button) -> Result<(), String> {
    match (b.bar, b.button) {
        (Some(bar), _) if !(1..=8).contains(&bar) => {
            return Err(format!("bar must be 1..8, got {bar}"));
        }
        (_, Some(button)) if !(1..=12).contains(&button) => {
            return Err(format!("button must be 1..12, got {button}"));
        }
        (Some(_), None) | (None, Some(_)) => return Err("give both bar and button".into()),
        (None, None) if b.spell.is_none() && b.macro_name.is_none() => {
            return Err("needs a spell, a macro, or a bar + button".into());
        }
        _ => {}
    }
    match (&b.spell, &b.macro_name, &b.body) {
        (Some(_), Some(_), _) => Err("pick spell or macro, not both".into()),
        (_, Some(_), None) => Err("macro needs a body".into()),
        (_, None, Some(_)) => Err("body without macro".into()),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn errors(text: &str) -> Vec<String> {
        parse(text).err().unwrap_or_default()
    }

    #[test]
    fn repo_layout_is_valid() {
        let text = include_str!("../../layout.toml");
        if let Err(e) = parse(text) {
            panic!("{e:#?}");
        }
    }

    #[test]
    fn chords_render_for_both_sides() {
        let c = Chord::banner("f9");
        assert_eq!(c.kanata(), "A-C-S-f9");
        assert_eq!(c.wow(), "ALT-CTRL-SHIFT-F9");
        let c = Chord::new(&[Mod::Shift, Mod::Ctrl], ";");
        assert_eq!(c.wow(), "CTRL-SHIFT-;");
    }

    #[test]
    fn slot_ids() {
        let b = |bar, button| Button {
            bar: Some(bar),
            button: Some(button),
            spell: None,
            macro_name: None,
            body: None,
        };
        assert_eq!(b(1, 1).slot(), Some(("ACTIONBUTTON1".into(), 1)));
        assert_eq!(b(2, 3).slot(), Some(("MULTIACTIONBAR1BUTTON3".into(), 63)));
        assert_eq!(b(2, 3).command(), "MULTIACTIONBAR1BUTTON3");
    }

    #[test]
    fn unplaced_buttons_bind_directly() {
        let b = Button {
            bar: None,
            button: None,
            spell: Some("Frost Armor".into()),
            macro_name: None,
            body: None,
        };
        assert_eq!(b.command(), "SPELL Frost Armor");
    }

    #[test]
    fn catches_collisions_between_modes() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            j = "JUMP"
            [[mode]]
            name = "b"
            label = "B"
            banner = "f10"
            [mode.keys]
            j = "SITORSTAND"
            "#,
        );
        assert!(e[0].contains("already bound"), "{e:?}");
    }

    #[test]
    fn catches_bad_references() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            caps = { mode = "nope" }
            nokey = "JUMP"
            j = { bar = 9, button = 1 }
            k = { bar = 1 }
            l = "wowkeys:dance"
            "#,
        );
        assert_eq!(e.len(), 5, "{e:?}");
    }

    #[test]
    fn oneshot_modes() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            ralt = { mode = "leader", send = "ret" }
            [[mode]]
            name = "leader"
            label = "LEADER"
            banner = "f10"
            oneshot = 1000
            "#,
        );
        assert_eq!(e.len(), 2, "{e:?}");
    }

    #[test]
    fn controller_slots_match_the_game() {
        // Pairs confirmed in game (test with a PlayStation pad).
        assert_eq!(pad_slot("rt", "north"), Ok(198)); // Fire Blast, RT+Triangle
        assert_eq!(pad_slot("rt", "east"), Ok(199)); // Fireball, RT+Circle
        assert_eq!(pad_slot("rt", "south"), Ok(200)); // Frostbolt, RT+Cross
        assert_eq!(pad_slot("none", "left"), Ok(181));
        assert_eq!(pad_slot("lt", "up"), Ok(186));
        assert_eq!(pad_slot("ltrt", "down"), Ok(204));
        assert!(pad_slot("none", "south").is_err());
    }

    #[test]
    fn controller_entries_are_checked() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            j = { macro = "M", body = "/sit" }
            [controller.none]
            south = { spell = "Jump" }
            [controller.rt]
            up = { macro = "M", body = "/dance" }
            down = { macro = "M" }
            left = { macro = "Nope" }
            sideways = { spell = "Blink" }
            "#,
        );
        assert_eq!(e.len(), 4, "{e:?}");
        assert!(
            e.iter().any(|m| m.contains("`Nope` isn't defined")),
            "{e:?}"
        );
    }

    #[test]
    fn steam_layer_is_checked() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            tab = { mode = "ui" }
            [[mode]]
            name = "ui"
            label = "UI"
            banner = "f10"
            mods = ["ctrl", "alt"]
            [mode.keys]
            i = "TOGGLECHARACTER0"
            tab = { mode = "a" }
            [steam_layer]
            mode = "ui"
            button = "Create"
            [steam_layer.keys]
            up = "i"
            down = "tab"
            left = "z"
            sideways = "i"
            "#,
        );
        assert_eq!(e.len(), 3, "{e:?}");
    }

    #[test]
    fn human_chords() {
        assert_eq!(
            Chord::new(&[Mod::Alt, Mod::Ctrl], "i").human(),
            "Ctrl + Alt + I"
        );
        assert_eq!(Chord::banner("f10").human(), "Ctrl + Alt + Shift + F10");
    }

    #[test]
    fn macro_names_are_unique() {
        let e = errors(
            r#"
            [[mode]]
            name = "a"
            label = "A"
            banner = "f9"
            [mode.keys]
            j = { macro = "M", body = "/sit" }
            k = { macro = "M", body = "/dance" }
            "#,
        );
        assert!(e[0].contains("different body"), "{e:?}");
    }
}
