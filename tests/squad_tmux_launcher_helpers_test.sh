#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
helpers="$repo_root/scripts/lib/squad-tmux-launcher-helpers.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/lib/node_modules/@anthropic-ai/claude-code"
cat >"$tmpdir/lib/node_modules/@anthropic-ai/claude-code/cli.js" <<'EOF'
#!/usr/bin/env node
console.log('stub')
EOF
chmod +x "$tmpdir/lib/node_modules/@anthropic-ai/claude-code/cli.js"
ln -s "../lib/node_modules/@anthropic-ai/claude-code/cli.js" "$tmpdir/bin/claude"

source "$helpers"

candidates="$(pane_command_candidates "$tmpdir/bin/claude")"

printf '%s\n' "$candidates" | grep -qx 'claude'
printf '%s\n' "$candidates" | grep -qx 'cli.js'
printf '%s\n' "$candidates" | grep -qx 'node'

(
  set +u
  before_nounset="$(set -o | awk '$1=="nounset" { print $2 }')"
  pane_command_candidates "$tmpdir/bin/claude" >/dev/null
  empty_source=()
  copy_array_or_empty copied_empty empty_source
  copy_array_or_empty copied_missing missing_source
  after_nounset="$(set -o | awk '$1=="nounset" { print $2 }')"
  test "$before_nounset" = "$after_nounset"
  test "${#copied_empty[@]}" -eq 0
  test "${#copied_missing[@]}" -eq 0
)

is_truthy true
! is_truthy false

slug="$(slugify_path_component 'feat/mcp-server-sdk-upgrade')"
test "$slug" = "feat-mcp-server-sdk-upgrade"

repo_dir="$tmpdir/repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -b main >/dev/null
repo_dir="$(cd "$repo_dir" && pwd -P)"
git -C "$repo_dir" config user.email "codex@example.com"
git -C "$repo_dir" config user.name "Codex"
echo "hello" >"$repo_dir/README.md"
git -C "$repo_dir" add README.md
git -C "$repo_dir" commit -m "init" >/dev/null

resolved_root="$(resolve_worktree_root "$repo_dir" ".worktrees")"
test "$resolved_root" = "$repo_dir/.worktrees"

requested_path="$(resolve_worktree_path "$repo_dir" ".worktrees" "mcp-upgrade")"
test "$requested_path" = "$repo_dir/.worktrees/mcp-upgrade"
test "$(repo_worktree_location_slug "$repo_dir")" != "$(basename "$repo_dir")"
! path_is_within "$repo_dir/.worktrees/../outside" "$repo_dir"

trust_capture=$' Accessing workspace:\n\n Quick safety check: Is this a project you created or one you trust?\n\n ❯ 1. Yes, I trust this folder\n   2. No, exit\n\n Enter to confirm · Esc to cancel\n'
ready_capture=$' Claude Code v2.1.87\n\n❯ \n'
pending_command_capture=$' Claude Code v2.1.87\n\n❯ /squad worker\n'
active_command_capture=$'❯ /squad worker\n\n⏺ Skill(/squad)\n  ⎿  Successfully loaded skill\n\n⏺ Bash(squad init)\n  ⎿  Running…\n'

pane_capture_has_workspace_trust_prompt "$trust_capture"
! pane_capture_has_workspace_trust_prompt "$ready_capture"
pane_capture_has_interactive_prompt "$ready_capture"
pane_capture_has_pending_command_input "$pending_command_capture" "/squad worker"
! pane_capture_has_pending_command_input "$ready_capture" "/squad worker"
! pane_capture_has_squad_command_activity "$pending_command_capture"
pane_capture_has_squad_command_activity "$active_command_capture"

! ensure_repo_local_worktree_ignored "$repo_dir" "$requested_path"
echo ".worktrees/" >>"$repo_dir/.gitignore"
ensure_repo_local_worktree_ignored "$repo_dir" "$requested_path"

created_path="$(ensure_git_worktree "$repo_dir" "$requested_path" "feat/mcp-upgrade" "HEAD" 0)"
test "$created_path" = "$requested_path"
test -d "$requested_path"
test "$(git -C "$requested_path" branch --show-current)" = "feat/mcp-upgrade"

reused_path="$(ensure_git_worktree "$repo_dir" "$repo_dir/.worktrees/other-path" "feat/mcp-upgrade" "HEAD" 0)"
test "$reused_path" = "$requested_path"

other_repo_dir="$tmpdir/other-repo"
mkdir -p "$other_repo_dir"
git -C "$tmpdir" init -b main other-repo >/dev/null
other_repo_dir="$(cd "$other_repo_dir" && pwd -P)"
git -C "$other_repo_dir" config user.email "codex@example.com"
git -C "$other_repo_dir" config user.name "Codex"
echo "world" >"$other_repo_dir/README.md"
git -C "$other_repo_dir" add README.md
git -C "$other_repo_dir" commit -m "init" >/dev/null

! ensure_git_worktree "$other_repo_dir" "$requested_path" "feat/mcp-upgrade" "HEAD" 0

planned_path="$(ensure_git_worktree "$repo_dir" "$repo_dir/.worktrees/dry-run-path" "feat/dry-run" "HEAD" 1)"
test "$planned_path" = "$repo_dir/.worktrees/dry-run-path"
test ! -d "$repo_dir/.worktrees/dry-run-path"

echo "PASS: helper functions cover command detection and worktree planning"
