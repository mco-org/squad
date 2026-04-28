use anyhow::{Context, Result};
use std::path::{Path, PathBuf};

pub struct Platform {
    pub name: &'static str,
    pub binary: &'static str,
    pub command_path: &'static str, // relative to home dir
    pub content: &'static str,
}

pub const DEFAULT_PROTOCOL_VERSION: i64 = 1;
pub const SUPPORTED_PROTOCOL_VERSION: i64 = 2;

pub const PLATFORMS: &[Platform] = &[
    Platform {
        name: "claude",
        binary: "claude",
        command_path: ".claude/commands/squad.md",
        content: SQUAD_MD_CONTENT,
    },
    Platform {
        name: "gemini",
        binary: "gemini",
        command_path: ".gemini/commands/squad.toml",
        content: SQUAD_TOML_CONTENT,
    },
    Platform {
        name: "codex",
        binary: "codex",
        command_path: ".codex/skills/squad/SKILL.md",
        content: SQUAD_CODEX_CONTENT,
    },
    Platform {
        name: "opencode",
        binary: "opencode",
        command_path: ".config/opencode/commands/squad.md",
        content: SQUAD_MD_CONTENT,
    },
];

/// Codex Skills format (uses $ARGUMENTS, placed in ~/.agents/skills/squad/SKILL.md)
pub const SQUAD_CODEX_CONTENT: &str = r#"---
name: squad
description: "Join squad multi-agent collaboration. Usage: $squad <role> [custom-id]"
---

You are joining a squad multi-agent collaboration team.

Your join arguments: $ARGUMENTS

**IMPORTANT:** Do NOT run `squad $ARGUMENTS` or treat the arguments as a CLI subcommand. Instead, follow the setup steps below.

## Phase 1: Setup (do this once)

1. Parse your join arguments above.

   **If arguments are empty or missing:**
   Run `squad roles` to list available roles, then ask the user which role they want to join as. Do NOT proceed until the user picks a role.

   **If arguments look like a role name** (1-2 words, e.g. "cto", "worker worker-2"):
   - First word is your role — this can be ANY string: "cto", "ceo", "manager", "reviewer", etc. It does NOT need to appear in `squad roles` (that list only shows predefined templates).
   - Optional second word is a custom agent ID
   - If no custom ID provided, use the role name as your ID
   - Examples: "manager" → id=manager, role=manager | "worker worker-2" → id=worker-2, role=worker | "cto" → id=cto, role=cto

   **If arguments look like natural language** (e.g. "加入团队，作为管理员", "join as tech lead and review PRs"):
   - Extract the intended role from the text. Pick a short English role name (e.g. "manager", "reviewer", "cto").
   - Use that as your role and ID.
   - If no role can be inferred, ask the user to clarify.

2. Run `squad init` (safe to run — won't overwrite existing workspace).

3. **Clean up stale agents from previous sessions:**
   Run `squad agents` and check the output.
   - If ALL agents show "stale" (no active agents), tell the user stale squad state was detected and ask the user whether they want to reset squad state with `squad clean` followed by `squad init`. Do NOT clean automatically.
   - If some agents are active (a team is already running), skip cleanup and proceed.

4. Run `squad join <id> --role <role> --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__` to register yourself.
   - Read the output line that says "Joined as ..." — that confirms your actual agent ID.
   - If the ID was taken, squad auto-assigns a suffixed ID (e.g. worker-2). Use that ID for all commands.
   - If role instructions are printed (=== Role Instructions ===), follow them.
   - If no predefined template exists, interpret the role using your own knowledge.

5. Run `squad agents` to see who else is on the team.

6. **If any squad command returns "Session replaced":** another terminal took your ID. Re-join with a different ID (e.g. `squad join worker-2 --role worker --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__`).

## Phase 2: Enter Receive Mode (MANDATORY)

**Immediately after setup, run `squad receive <your-id> --wait` to start listening for messages.** Do NOT wait for the user to tell you — enter receive mode now.

After receiving a message:
1. Execute the task or respond as appropriate for your role.
2. Report results using `squad send` or `squad task` commands.
3. Run `squad receive <your-id> --wait` again to wait for the next message.

If receive times out with no messages, run it again immediately.

Other useful commands:
- `squad send <your-id> <to> "<message>"` — send a message (use @all to broadcast)
- `squad task create <your-id> <to> --title "<title>"` — create a structured task
- `squad agents` — see who is online
- `squad pending` — check all unread messages
- `squad history` — view message history
"#;

/// Markdown format for Claude Code, OpenCode (uses $ARGUMENTS)
pub const SQUAD_MD_CONTENT: &str = r#"---
description: Join squad multi-agent collaboration. Usage: /squad <role> [custom-id]
---

You are joining a squad multi-agent collaboration team.

Your join arguments: $ARGUMENTS

**IMPORTANT:** Do NOT run `squad $ARGUMENTS` or treat the arguments as a CLI subcommand. Instead, follow the setup steps below.

## Phase 1: Setup (do this once)

1. Parse your join arguments above.

   **If arguments are empty or missing:**
   Run `squad roles` to list available roles, then ask the user which role they want to join as. Do NOT proceed until the user picks a role.

   **If arguments look like a role name** (1-2 words, e.g. "cto", "worker worker-2"):
   - First word is your role — this can be ANY string: "cto", "ceo", "manager", "reviewer", etc. It does NOT need to appear in `squad roles` (that list only shows predefined templates).
   - Optional second word is a custom agent ID
   - If no custom ID provided, use the role name as your ID
   - Examples: "manager" → id=manager, role=manager | "worker worker-2" → id=worker-2, role=worker | "cto" → id=cto, role=cto

   **If arguments look like natural language** (e.g. "加入团队，作为管理员", "join as tech lead and review PRs"):
   - Extract the intended role from the text. Pick a short English role name (e.g. "manager", "reviewer", "cto").
   - Use that as your role and ID.
   - If no role can be inferred, ask the user to clarify.

2. Run `squad init` (safe to run — won't overwrite existing workspace).

3. **Clean up stale agents from previous sessions:**
   Run `squad agents` and check the output.
   - If ALL agents show "stale" (no active agents), tell the user stale squad state was detected and ask the user whether they want to reset squad state with `squad clean` followed by `squad init`. Do NOT clean automatically.
   - If some agents are active (a team is already running), skip cleanup and proceed.

4. Run `squad join <id> --role <role> --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__` to register yourself.
   - Read the output line that says "Joined as ..." — that confirms your actual agent ID.
   - If the ID was taken, squad auto-assigns a suffixed ID (e.g. worker-2). Use that ID for all commands.
   - If role instructions are printed (=== Role Instructions ===), follow them.
   - If no predefined template exists, interpret the role using your own knowledge.

5. Run `squad agents` to see who else is on the team.

6. **If any squad command returns "Session replaced":** another terminal took your ID. Re-join with a different ID (e.g. `squad join worker-2 --role worker --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__`).

## Phase 2: Enter Receive Mode (MANDATORY)

**Immediately after setup, run `squad receive <your-id> --wait` to start listening for messages.** Do NOT wait for the user to tell you — enter receive mode now.

After receiving a message:
1. Execute the task or respond as appropriate for your role.
2. Report results using `squad send` or `squad task` commands.
3. Run `squad receive <your-id> --wait` again to wait for the next message.

If receive times out with no messages, run it again immediately.

Other useful commands:
- `squad send <your-id> <to> "<message>"` — send a message (use @all to broadcast)
- `squad task create <your-id> <to> --title "<title>"` — create a structured task
- `squad agents` — see who is online
- `squad pending` — check all unread messages
- `squad history` — view message history
"#;

/// TOML format for Gemini CLI (uses {{args}})
pub const SQUAD_TOML_CONTENT: &str = r#"description = "Join squad multi-agent collaboration. Usage: /squad <role> [custom-id]"

prompt = """
The user's input: {{args}}

You are joining a squad multi-agent collaboration team.

## Phase 1: Setup (do this once)

1. Parse the arguments above.

   **If arguments are empty or missing:**
   Run `squad roles` to list available roles, then ask the user which role they want to join as. Do NOT proceed until the user picks a role.

   **If arguments are provided:**
   - First word is the role — this can be ANY string, including custom roles like "cto", "ceo", "reviewer". It does NOT need to appear in `squad roles` (that list only shows predefined templates).
   - Optional second word is a custom agent ID
   - If no custom ID provided, use the role name as your ID
   - Examples: "manager" → id=manager, role=manager | "worker worker-2" → id=worker-2, role=worker | "cto" → id=cto, role=cto

2. Run `squad init` (safe to run — won't overwrite existing workspace).

3. **Clean up stale agents from previous sessions:**
   Run `squad agents` and check the output.
   - If ALL agents show "stale" (no active agents), tell the user stale squad state was detected and ask the user whether they want to reset squad state with `squad clean` followed by `squad init`. Do NOT clean automatically.
   - If some agents are active (a team is already running), skip cleanup and proceed.

4. Run `squad join <id> --role <role> --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__` to register yourself.
   - Read the output line that says "Joined as ..." — that confirms your actual agent ID.
   - If the ID was taken, squad auto-assigns a suffixed ID (e.g. worker-2). Use that ID for all commands.
   - If role instructions are printed (=== Role Instructions ===), follow them.
   - If no predefined template exists, interpret the role using your own knowledge.

5. Run `squad agents` to see who else is on the team.

6. **If any squad command returns "Session replaced":** another terminal took your ID. Re-join with a different ID (e.g. `squad join worker-2 --role worker --client __SQUAD_CLIENT__ --protocol-version __SQUAD_PROTOCOL_VERSION__`).

## Phase 2: Enter Receive Mode (MANDATORY)

**Immediately after setup, run `squad receive <your-id> --wait` to start listening for messages.** Do NOT wait for the user to tell you — enter receive mode now.

After receiving a message:
1. Execute the task or respond as appropriate for your role.
2. Report results using `squad send` or `squad task` commands.
3. Run `squad receive <your-id> --wait` again to wait for the next message.

If receive times out with no messages, run it again immediately.

Other useful commands:
- `squad send <your-id> <to> "<message>"` — send a message (use @all to broadcast)
- `squad task create <your-id> <to> --title "<title>"` — create a structured task
- `squad agents` — see who is online
- `squad pending` — check all unread messages
- `squad history` — view message history
"""
"#;

/// The version marker prefix used in generated slash command files.
const VERSION_MARKER: &str = "squad-version:";

/// Get the current binary version.
pub fn current_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Extract the squad-version from an installed slash command file.
fn extract_version(content: &str) -> Option<&str> {
    for line in content.lines() {
        let trimmed = line.trim().trim_start_matches('#').trim();
        if let Some(rest) = trimmed.strip_prefix(VERSION_MARKER) {
            return Some(rest.trim());
        }
    }
    None
}

/// Diagnose slash template health for a set of installed platforms.
/// Returns a list of OK/WARN lines sorted by platform name within each class.
pub fn diagnose_templates_for_platforms(
    platforms: &[&Platform],
    home: &Path,
) -> Result<Vec<String>> {
    if platforms.is_empty() {
        return Ok(vec!["OK: no installed slash templates detected".to_string()]);
    }
    let version = current_version();
    let mut warnings: Vec<(String, String)> = Vec::new();
    for platform in platforms {
        let path = home.join(platform.command_path);
        if !path.exists() {
            warnings.push((
                platform.name.to_string(),
                format!(
                    "WARN: slash template {} is missing; run squad init or squad setup",
                    platform.name
                ),
            ));
            continue;
        }
        let content = std::fs::read_to_string(&path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        match extract_version(&content) {
            None => {
                warnings.push((
                    platform.name.to_string(),
                    format!(
                        "WARN: slash template {} is missing squad-version marker; run squad init or squad setup",
                        platform.name
                    ),
                ));
            }
            Some(v) if v != version => {
                warnings.push((
                    platform.name.to_string(),
                    format!(
                        "WARN: slash template {} is outdated (installed={}, current={}); run squad init or squad setup",
                        platform.name, v, version
                    ),
                ));
            }
            Some(_) => {}
        }
    }
    if warnings.is_empty() {
        Ok(vec!["OK: slash templates are current".to_string()])
    } else {
        warnings.sort_by(|a, b| a.0.cmp(&b.0));
        Ok(warnings.into_iter().map(|(_, msg)| msg).collect())
    }
}

/// Check installed slash commands and update any that are outdated, missing version markers,
/// or missing entirely (for detected platforms).
/// Returns list of (platform_name, path) for updated/installed files.
pub fn check_and_update_commands() -> Vec<(String, PathBuf)> {
    let version = current_version();
    let mut updated = Vec::new();
    for platform in PLATFORMS {
        if !is_installed(platform.binary) {
            continue;
        }
        let path = match command_path(platform) {
            Ok(p) => p,
            Err(_) => continue,
        };
        let needs_update = if path.exists() {
            let current = std::fs::read_to_string(&path).unwrap_or_default();
            match extract_version(&current) {
                Some(v) => v != version,
                None => true,
            }
        } else {
            true // file missing = needs install
        };
        if needs_update {
            let content = versioned_content(&command_content(platform), version);
            if install_command(&path, &content).is_ok() {
                updated.push((platform.name.to_string(), path));
            }
        }
    }
    updated
}

/// Remove all installed slash command files.
/// Returns list of (platform_name, path) for removed files.
pub fn cleanup_commands() -> Vec<(String, PathBuf)> {
    let mut removed = Vec::new();
    for platform in PLATFORMS {
        let path = match command_path(platform) {
            Ok(p) => p,
            Err(_) => continue,
        };
        if path.exists() && std::fs::remove_file(&path).is_ok() {
            removed.push((platform.name.to_string(), path));
        }
    }
    removed
}

/// Insert a version marker into template content.
fn versioned_content(content: &str, version: &str) -> String {
    // For markdown: insert squad-version into frontmatter
    if let Some(rest) = content.strip_prefix("---") {
        if let Some(end) = rest.find("---") {
            return format!(
                "---{}squad-version: {}\n{}",
                &rest[..end],
                version,
                &rest[end..]
            );
        }
    }
    // For TOML: prepend as comment
    format!("# squad-version: {}\n{}", version, content)
}

pub fn command_content(platform: &Platform) -> String {
    platform
        .content
        .replace("__SQUAD_CLIENT__", platform.name)
        .replace(
            "__SQUAD_PROTOCOL_VERSION__",
            &SUPPORTED_PROTOCOL_VERSION.to_string(),
        )
}

/// Check if a binary exists in PATH.
pub fn is_installed(binary: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    let candidates = command_candidates(binary);
    for dir in std::env::split_paths(&path) {
        for candidate in &candidates {
            if is_command_file(&dir.join(candidate)) {
                return true;
            }
        }
    }
    false
}

fn command_candidates(binary: &str) -> Vec<String> {
    let mut candidates = vec![binary.to_string()];
    if Path::new(binary).extension().is_some() {
        return candidates;
    }
    let Some(pathext) = std::env::var_os("PATHEXT") else {
        return candidates;
    };
    for ext in pathext.to_string_lossy().split(';') {
        if ext.is_empty() {
            continue;
        }
        let normalized = if ext.starts_with('.') {
            ext.to_string()
        } else {
            format!(".{ext}")
        };
        candidates.push(format!("{binary}{normalized}"));
        let lowercase = normalized.to_ascii_lowercase();
        if lowercase != normalized {
            candidates.push(format!("{binary}{lowercase}"));
        }
    }
    candidates
}

fn is_command_file(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    if cfg!(windows) {
        return true;
    }
    is_executable(path)
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

/// Detect which platforms are installed.
pub fn detect_platforms() -> Vec<&'static Platform> {
    PLATFORMS
        .iter()
        .filter(|p| is_installed(p.binary))
        .collect()
}

/// Get the full path for a platform's command file.
pub fn command_path(platform: &Platform) -> Result<PathBuf> {
    let home = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .context("HOME or USERPROFILE not set")?;
    Ok(PathBuf::from(home).join(platform.command_path))
}

/// Install the squad command file for a platform.
pub fn install_command(path: &Path, content: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    std::fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Install for a specific platform (with version marker).
pub fn install_for_platform(platform: &Platform) -> Result<PathBuf> {
    let path = command_path(platform)?;
    let content = versioned_content(&command_content(platform), current_version());
    install_command(&path, &content)?;
    Ok(path)
}

/// Run setup: detect platforms and install.
pub fn run_setup() -> Vec<(String, PathBuf, Result<()>)> {
    let mut results = Vec::new();
    for platform in PLATFORMS {
        if !is_installed(platform.binary) {
            continue;
        }
        match install_for_platform(platform) {
            Ok(path) => results.push((platform.name.to_string(), path, Ok(()))),
            Err(e) => results.push((platform.name.to_string(), PathBuf::new(), Err(e))),
        }
    }
    results
}
