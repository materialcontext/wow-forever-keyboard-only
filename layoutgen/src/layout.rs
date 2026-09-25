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
