use squad::setup::{
    command_path, current_version, diagnose_templates_for_platforms, install_command,
    install_for_platform, is_installed, PLATFORMS, SQUAD_CODEX_CONTENT, SQUAD_MD_CONTENT,
    SQUAD_TOML_CONTENT,
};
use std::sync::{Mutex, OnceLock};
use tempfile::TempDir;

fn env_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

struct EnvGuard {
    home: Option<std::ffi::OsString>,
    userprofile: Option<std::ffi::OsString>,
    path: Option<std::ffi::OsString>,
    pathext: Option<std::ffi::OsString>,
}

impl EnvGuard {
    fn new() -> Self {
        Self {
            home: std::env::var_os("HOME"),
            userprofile: std::env::var_os("USERPROFILE"),
            path: std::env::var_os("PATH"),
            pathext: std::env::var_os("PATHEXT"),
        }
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        restore_env("HOME", &self.home);
        restore_env("USERPROFILE", &self.userprofile);
        restore_env("PATH", &self.path);
        restore_env("PATHEXT", &self.pathext);
    }
}

fn restore_env(key: &str, value: &Option<std::ffi::OsString>) {
    if let Some(value) = value {
        std::env::set_var(key, value);
    } else {
        std::env::remove_var(key);
    }
}

fn lock_env() -> std::sync::MutexGuard<'static, ()> {
    env_lock().lock().unwrap_or_else(|error| error.into_inner())
}

#[test]
fn test_platforms_defined() {
    assert!(PLATFORMS.len() >= 4);
    let names: Vec<&str> = PLATFORMS.iter().map(|p| p.name).collect();
    assert!(names.contains(&"claude"));
    assert!(names.contains(&"gemini"));
    assert!(names.contains(&"codex"));
    assert!(names.contains(&"opencode"));
}

#[test]
fn test_md_content_has_required_sections() {
    assert!(SQUAD_MD_CONTENT.contains("$ARGUMENTS"));
    assert!(SQUAD_MD_CONTENT.contains("squad join"));
    assert!(SQUAD_MD_CONTENT.contains("squad receive"));
    assert!(SQUAD_MD_CONTENT.contains("squad send"));
    assert!(SQUAD_MD_CONTENT.contains("squad agents"));
}

#[test]
fn test_toml_content_has_required_sections() {
    assert!(SQUAD_TOML_CONTENT.contains("{{args}}"));
    assert!(SQUAD_TOML_CONTENT.contains("squad join"));
    assert!(SQUAD_TOML_CONTENT.contains("squad receive"));
    assert!(SQUAD_TOML_CONTENT.contains("squad send"));
    assert!(SQUAD_TOML_CONTENT.contains("description"));
    assert!(SQUAD_TOML_CONTENT.contains("prompt"));
}

#[test]
fn test_codex_skill_frontmatter_is_valid_yaml() {
    let frontmatter = SQUAD_CODEX_CONTENT
        .strip_prefix("---\n")
        .and_then(|content| content.split_once("\n---"))
        .map(|(frontmatter, _)| frontmatter)
        .unwrap();

    serde_yaml::from_str::<serde_yaml::Value>(frontmatter).unwrap();
}

#[test]
fn test_installed_codex_skill_frontmatter_is_valid_yaml() {
    let _lock = lock_env();
    let _env = EnvGuard::new();
    let tmp = TempDir::new().unwrap();
    std::env::set_var("HOME", tmp.path());

    let codex = PLATFORMS
        .iter()
        .find(|platform| platform.name == "codex")
        .unwrap();
    let path = install_for_platform(codex).unwrap();
    let content = std::fs::read_to_string(path).unwrap();
    let frontmatter = content
        .strip_prefix("---\n")
        .and_then(|content| content.split_once("\n---"))
        .map(|(frontmatter, _)| frontmatter)
        .unwrap();

    let parsed = serde_yaml::from_str::<serde_yaml::Value>(frontmatter).unwrap();
    assert_eq!(parsed["name"], "squad");
    assert_eq!(parsed["squad-version"], current_version());
}

#[test]
fn test_command_path_falls_back_to_userprofile_when_home_is_missing() {
    let _lock = lock_env();
    let _env = EnvGuard::new();
    let tmp = TempDir::new().unwrap();
    std::env::remove_var("HOME");
    std::env::set_var("USERPROFILE", tmp.path());

    let platform = PLATFORMS
        .iter()
        .find(|platform| platform.name == "codex")
        .unwrap();
    let path = command_path(platform).unwrap();

    assert_eq!(path, tmp.path().join(platform.command_path));
}

#[test]
fn test_is_installed_detects_windows_command_wrappers() {
    let _lock = lock_env();
    let _env = EnvGuard::new();
    let tmp = TempDir::new().unwrap();
    let wrapper = tmp.path().join("codex.cmd");
    std::fs::write(&wrapper, "@echo off\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&wrapper).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&wrapper, permissions).unwrap();
    }
    std::env::set_var("PATH", tmp.path());
    std::env::set_var("PATHEXT", ".COM;.EXE;.BAT;.CMD");

    assert!(is_installed("codex"));
}

#[cfg(unix)]
#[test]
fn test_is_installed_requires_executable_bit_on_unix_even_with_pathext() {
    let _lock = lock_env();
    let _env = EnvGuard::new();
    let tmp = TempDir::new().unwrap();
    let wrapper = tmp.path().join("codex.cmd");
    std::fs::write(&wrapper, "@echo off\n").unwrap();
    std::env::set_var("PATH", tmp.path());
    std::env::set_var("PATHEXT", ".COM;.EXE;.BAT;.CMD");

    assert!(!is_installed("codex"));
}

#[test]
fn test_install_command_creates_file() {
    let tmp = TempDir::new().unwrap();
    let cmd_dir = tmp.path().join("commands");
    let cmd_path = cmd_dir.join("squad.md");

    install_command(&cmd_path, SQUAD_MD_CONTENT).unwrap();

    assert!(cmd_path.exists());
    let content = std::fs::read_to_string(&cmd_path).unwrap();
    assert!(content.contains("squad join"));
}

#[test]
fn test_install_command_creates_parent_dirs() {
    let tmp = TempDir::new().unwrap();
    let deep_path = tmp.path().join("a").join("b").join("c").join("squad.md");

    install_command(&deep_path, SQUAD_MD_CONTENT).unwrap();

    assert!(deep_path.exists());
}

#[test]
fn test_md_content_has_session_conflict_instruction() {
    assert!(SQUAD_MD_CONTENT.contains("Session replaced"));
}

#[test]
fn test_install_command_overwrites_existing() {
    let tmp = TempDir::new().unwrap();
    let cmd_dir = tmp.path().join("commands");
    std::fs::create_dir_all(&cmd_dir).unwrap();
    let cmd_path = cmd_dir.join("squad.md");
    std::fs::write(&cmd_path, "old content").unwrap();

    install_command(&cmd_path, SQUAD_MD_CONTENT).unwrap();

    let content = std::fs::read_to_string(&cmd_path).unwrap();
    assert!(content.contains("squad join")); // new content, not "old content"
}

#[test]
fn test_md_content_has_two_phase_structure() {
    assert!(SQUAD_MD_CONTENT.contains("Phase 1"));
    assert!(SQUAD_MD_CONTENT.contains("Phase 2"));
    assert!(SQUAD_MD_CONTENT.contains("Enter Receive Mode"));
}

#[test]
fn test_md_content_has_actual_id_instruction() {
    assert!(SQUAD_MD_CONTENT.contains("Joined as"));
}

#[test]
fn test_templates_enter_receive_mode_after_setup() {
    // Templates should mandate entering receive mode immediately after setup
    assert!(SQUAD_MD_CONTENT.contains("Immediately after setup"));
    assert!(SQUAD_TOML_CONTENT.contains("Immediately after setup"));
    // Templates should use --wait without explicit timeout (let platform control the cycle)
    assert!(SQUAD_MD_CONTENT.contains("receive <your-id> --wait`"));
    assert!(SQUAD_TOML_CONTENT.contains("receive <your-id> --wait`"));
}

#[test]
fn test_templates_mention_task_commands() {
    assert!(SQUAD_MD_CONTENT.contains("squad task"));
    assert!(SQUAD_TOML_CONTENT.contains("squad task"));
    assert!(SQUAD_MD_CONTENT.contains("squad send"));
    assert!(SQUAD_TOML_CONTENT.contains("squad send"));
}

#[test]
fn test_toml_content_has_two_phase_structure() {
    assert!(SQUAD_TOML_CONTENT.contains("Phase 1"));
    assert!(SQUAD_TOML_CONTENT.contains("Phase 2"));
    assert!(SQUAD_TOML_CONTENT.contains("Enter Receive Mode"));
}

#[test]
fn test_setup_templates_do_not_auto_clean_without_user_confirmation() {
    assert!(!SQUAD_MD_CONTENT.contains("run `squad clean` then `squad init`"));
    assert!(!SQUAD_TOML_CONTENT.contains("run `squad clean` then `squad init`"));
    assert!(SQUAD_MD_CONTENT.contains("ask the user"));
    assert!(SQUAD_TOML_CONTENT.contains("ask the user"));
}

#[test]
fn test_template_diagnostics_report_missing_outdated_and_markerless_templates_in_platform_order() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    let claude = PLATFORMS
        .iter()
        .find(|platform| platform.name == "claude")
        .unwrap();
    let codex = PLATFORMS
        .iter()
        .find(|platform| platform.name == "codex")
        .unwrap();
    let gemini = PLATFORMS
        .iter()
        .find(|platform| platform.name == "gemini")
        .unwrap();

    let codex_path = home.join(codex.command_path);
    install_command(&codex_path, "plain content without marker").unwrap();

    let gemini_path = home.join(gemini.command_path);
    install_command(
        &gemini_path,
        "# squad-version: 0.0.1\ndescription = \"old\"",
    )
    .unwrap();

    let diagnostics = diagnose_templates_for_platforms(&[gemini, claude, codex], home).unwrap();

    assert_eq!(
        diagnostics,
        vec![
            "WARN: slash template claude is missing; run squad init or squad setup".to_string(),
            "WARN: slash template codex is missing squad-version marker; run squad init or squad setup"
                .to_string(),
            format!(
                "WARN: slash template gemini is outdated (installed=0.0.1, current={}); run squad init or squad setup",
                current_version()
            ),
        ]
    );
}

#[test]
fn test_template_diagnostics_report_ok_when_no_supported_binaries_are_installed() {
    let tmp = TempDir::new().unwrap();

    let diagnostics = diagnose_templates_for_platforms(&[], tmp.path()).unwrap();

    assert_eq!(
        diagnostics,
        vec!["OK: no installed slash templates detected".to_string()]
    );
}

#[test]
fn test_template_diagnostics_report_ok_when_all_templates_are_current() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    let claude = PLATFORMS
        .iter()
        .find(|platform| platform.name == "claude")
        .unwrap();
    let gemini = PLATFORMS
        .iter()
        .find(|platform| platform.name == "gemini")
        .unwrap();

    let claude_path = home.join(claude.command_path);
    install_command(
        &claude_path,
        &format!("# squad-version: {}\nclaude template", current_version()),
    )
    .unwrap();

    let gemini_path = home.join(gemini.command_path);
    install_command(
        &gemini_path,
        &format!("# squad-version: {}\ngemini template", current_version()),
    )
    .unwrap();

    let diagnostics = diagnose_templates_for_platforms(&[gemini, claude], home).unwrap();

    assert_eq!(
        diagnostics,
        vec!["OK: slash templates are current".to_string()]
    );
}
