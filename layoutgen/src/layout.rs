//! layout.toml: types, parsing and validation.

use crate::keys;
use serde::Deserialize;
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Layout {
    #[serde(rename = "mode")]
    pub modes: Vec<Mode>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Mode {
    pub name: String,
    pub label: String,
    /// Sent as Ctrl+Alt+Shift+<banner> on entering the mode.
    pub banner: String,
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

#[derive(Debug, Deserialize, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Button {
    pub bar: u8,
    pub button: u8,
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

impl Button {
    /// WoW binding command and action slot id for this bar/button.
    pub fn target(&self) -> (String, u16) {
        let (command, base) = match self.bar {
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
        (
            format!("{command}{}", self.button),
            base + u16::from(self.button),
        )
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

    let mut names = HashMap::new();
    let mut banners = HashMap::new();
    for mode in &layout.modes {
        if names.insert(mode.name.as_str(), ()).is_some() {
            errors.push(format!("mode `{}` is defined twice", mode.name));
        }
        if !keys::is_function_key(&mode.banner) {
            errors.push(format!("mode `{}`: banner must be f1..f24", mode.name));
        }
        if let Some(other) = banners.insert(mode.banner.as_str(), mode.name.as_str()) {
            errors.push(format!(
                "modes `{other}` and `{}` share banner {}",
                mode.name, mode.banner
            ));
        }
    }

    // WoW binding string -> (command, where), to catch two keys fighting over one chord.
    let mut wow_bindings: HashMap<String, (String, String)> = HashMap::new();
    // Action slot -> button, to catch two different things placed in one slot.
    let mut slots: HashMap<u16, (&Button, String)> = HashMap::new();

    for mode in &layout.modes {
        for (key, action) in &mode.keys {
            let at = format!("{}.{key}", mode.name);
            if !keys::is_key(key) {
                errors.push(format!("{at}: unknown key (see layoutgen/src/keys.rs)"));
                continue;
            }
            let command = match action {
                Action::Switch(s) => {
                    if !names.contains_key(s.mode.as_str()) {
                        errors.push(format!("{at}: no mode named `{}`", s.mode));
                    }
                    if let Some(send) = &s.send
                        && !keys::is_key(send)
                    {
                        errors.push(format!("{at}: can't send unknown key `{send}`"));
                    }
                    continue;
                }
                Action::Command(c) => c.clone(),
                Action::Button(b) => {
                    if let Err(e) = check_button(b) {
                        errors.push(format!("{at}: {e}"));
                        continue;
                    }
                    let (command, slot) = b.target();
                    if b.spell.is_some() || b.macro_name.is_some() {
                        match slots.get(&slot) {
                            Some((other, other_at)) if *other != b => errors.push(format!(
                                "{at}: bar {} button {} already holds something else at {other_at}",
                                b.bar, b.button
                            )),
                            _ => {
                                slots.insert(slot, (b, at.clone()));
                            }
                        }
                    }
                    command
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
    if !(1..=8).contains(&b.bar) {
        return Err(format!("bar must be 1..8, got {}", b.bar));
    }
    if !(1..=12).contains(&b.button) {
        return Err(format!("button must be 1..12, got {}", b.button));
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
            bar,
            button,
            spell: None,
            macro_name: None,
            body: None,
        };
        assert_eq!(b(1, 1).target(), ("ACTIONBUTTON1".into(), 1));
        assert_eq!(b(2, 3).target(), ("MULTIACTIONBAR1BUTTON3".into(), 63));
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
            "#,
        );
        assert_eq!(e.len(), 3, "{e:?}");
    }
}
