//! Physical keys: the kanata defsrc grid and each key's WoW binding name.

/// ANSI QWERTY, one entry per defsrc row. Every layer is rendered on this grid.
pub const GRID: &[&[&str]] = &[
    &["esc"],
    &[
        "grv", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "bspc",
    ],
    &[
        "tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\",
    ],
    &[
        "caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "ret",
    ],
    &[
        "lsft", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "rsft",
    ],
    &["lctl", "lmet", "lalt", "spc", "ralt", "rmet", "rctl"],
];

pub fn is_key(name: &str) -> bool {
    GRID.iter().flat_map(|row| row.iter()).any(|k| *k == name)
}

/// WoW's name for a key in binding strings, or None if WoW can't bind it alone.
/// Letters are uppercase; punctuation is the literal character (as in WoW's
/// default `bind - ACTIONBUTTON11`).
pub fn wow_name(key: &str) -> Option<String> {
    let named = match key {
        "esc" => "ESCAPE",
        "bspc" => "BACKSPACE",
        "tab" => "TAB",
        "caps" => "CAPSLOCK",
        "ret" => "ENTER",
        "spc" => "SPACE",
        "grv" => "`",
        k if is_function_key(k) => return Some(k.to_uppercase()),
        k if k.chars().count() == 1 && is_key(k) => return Some(k.to_uppercase()),
        _ => return None,
    };
    Some(named.to_string())
}

/// A name for the key that is safe inside a kanata alias name.
pub fn alias_safe(key: &str) -> &str {
    match key {
        ";" => "scln",
        "'" => "apos",
        "," => "comm",
        "." => "dot",
        "/" => "slsh",
        "-" => "min",
        "=" => "eql",
        "[" => "lbrc",
        "]" => "rbrc",
        "\\" => "bksl",
        k => k,
    }
}

/// f1..f24: not on the grid, but valid for banner chords.
pub fn is_function_key(key: &str) -> bool {
    key.strip_prefix('f')
        .and_then(|n| n.parse::<u8>().ok())
        .is_some_and(|n| (1..=24).contains(&n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wow_names() {
        assert_eq!(wow_name("j").as_deref(), Some("J"));
        assert_eq!(wow_name(";").as_deref(), Some(";"));
        assert_eq!(wow_name("spc").as_deref(), Some("SPACE"));
        assert_eq!(wow_name("f12").as_deref(), Some("F12"));
        assert_eq!(wow_name("lsft"), None);
        assert_eq!(wow_name("f25"), None);
    }
}
