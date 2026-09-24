//! layoutgen: layout.toml -> kanata/wow.kbd + addon/WowKeys/Layout.lua.
//!
//! Run from the repo root:
//!   cargo run            regenerate
//!   cargo run -- --check exit 1 if generated files are stale

mod addon;
mod kanata;
mod keys;
mod layout;

use std::path::Path;
use std::process::ExitCode;
use std::{env, fs};

const LAYOUT: &str = "layout.toml";

fn main() -> ExitCode {
    let check = env::args().any(|a| a == "--check");

    let text = match fs::read_to_string(LAYOUT) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("can't read {LAYOUT} (run from the repo root): {e}");
            return ExitCode::FAILURE;
        }
    };
    let layout = match layout::parse(&text) {
        Ok(l) => l,
        Err(errors) => {
            for e in errors {
                eprintln!("{LAYOUT}: {e}");
            }
            return ExitCode::FAILURE;
        }
    };

    let outputs = [
        ("kanata/wow.kbd", kanata::render(&layout)),
        ("addon/WowKeys/Layout.lua", addon::render(&layout)),
    ];

    let mut ok = true;
    for (path, content) in outputs {
        let current = fs::read_to_string(path).unwrap_or_default();
        if current == content {
            continue;
        }
        if check {
            eprintln!("{path} is stale; run `cargo run`");
            ok = false;
        } else if let Err(e) = write(path, &content) {
            eprintln!("can't write {path}: {e}");
            ok = false;
        } else {
            println!("wrote {path}");
        }
    }
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn write(path: &str, content: &str) -> std::io::Result<()> {
    if let Some(dir) = Path::new(path).parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(path, content)
}
