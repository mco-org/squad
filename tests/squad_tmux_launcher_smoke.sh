#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
launcher="$repo_root/scripts/squad-tmux-launch.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

project_dir="$tmpdir/project"
mkdir -p "$project_dir/.squad/prompts"
git -C "$tmpdir" init -b main project >/dev/null
project_dir="$(cd "$project_dir" && pwd -P)"
git -C "$project_dir" config user.email "codex@example.com"
git -C "$project_dir" config user.name "Codex"
echo "demo" >"$project_dir/README.seed"
git -C "$project_dir" add README.seed
git -C "$project_dir" commit -m "seed" >/dev/null
echo ".worktrees/" >"$project_dir/.gitignore"

cat >"$project_dir/.squad/launcher.yaml" <<'EOF'
project:
  name: demo-project
  session_name: demo-project-squad

runtime:
  claude_command: claude
  claude_args:
    - --dangerously-skip-permissions
  manager_role: manager
  worker_role: worker
  inspector_role: inspector
  workers: 2

workspace:
  init_args:
    - --refresh-roles
  worktree:
    enabled: true
    location: .worktrees
    branch: feat/feishu-claude-support
    path: feishu-claude-support
    base_ref: HEAD

focus:
  files:
    - src/app/main.ts
    - src/platforms/feishuPlatform.js
  docs:
    - README.md

constraints:
  - Keep Codex runtime behavior unchanged
  - Keep config backwards compatible
EOF

cat >"$project_dir/.squad/run-task.md" <<'EOF'
# Task
Improve Feishu support for Claude Code.

## Goals
- Stabilize the basic Claude path under Feishu
- Improve streaming and status feedback
- Tighten agent/runtime selection and recovery

## Acceptance
- Generate the manager prompt
- Generate the terminal mapping
- Keep dry-run free of tmux side effects
EOF

cat >"$project_dir/.squad/prompts/inspector.md" <<'EOF'
# Inspector Task
Focus on whether the README, path handling, and Claude install compatibility stay aligned with the implementation.
EOF

bash "$launcher" "$project_dir" --dry-run --no-setup --no-attach

quickstart_dir="$project_dir/.squad/quickstart/feishu-claude-support"
prompt_file="$quickstart_dir/generated-manager.prompt.md"
inspector_prompt_file="$quickstart_dir/generated-inspector.prompt.md"
summary_file="$quickstart_dir/generated-run-summary.md"
map_file="$quickstart_dir/generated-terminal-map.md"

test -f "$prompt_file"
test -f "$inspector_prompt_file"
test -f "$summary_file"
test -f "$map_file"

grep -q "Improve Feishu support for Claude Code" "$prompt_file"
grep -q "README, path handling, and Claude install compatibility" "$inspector_prompt_file"
grep -q "Improve Feishu support for Claude Code" "$inspector_prompt_file"
grep -q "src/platforms/feishuPlatform.js" "$prompt_file"
grep -q "Keep Codex runtime behavior unchanged" "$prompt_file"
grep -q "demo-project-squad" "$summary_file"
grep -q "claude --dangerously-skip-permissions" "$summary_file"
grep -q "generated-inspector.prompt.md" "$summary_file"
grep -q "feat/feishu-claude-support" "$summary_file"
grep -q ".worktrees/feishu-claude-support" "$summary_file"
grep -q "Workspace root" "$prompt_file"
grep -q "Worktree" "$prompt_file"
grep -q "manager" "$map_file"
grep -q "worker-2" "$map_file"
grep -q "inspector" "$map_file"

same_name_roots=()
for org in org-a org-b; do
  repo_dir="$tmpdir/$org/demo"
  mkdir -p "$repo_dir/.squad"
  git -C "$tmpdir/$org" init -b main demo >/dev/null
  git -C "$repo_dir" config user.email "codex@example.com"
  git -C "$repo_dir" config user.name "Codex"
  echo "seed" >"$repo_dir/README.md"
  git -C "$repo_dir" add README.md
  git -C "$repo_dir" commit -m "seed" >/dev/null

  cat >"$repo_dir/.squad/launcher.yaml" <<'EOF'
workspace:
  worktree:
    enabled: true
    branch: feat/smoke
EOF

  cat >"$repo_dir/.squad/run-task.md" <<'EOF'
# Task
Minimal task brief
EOF

  output="$(HOME="$tmpdir/home" bash "$launcher" "$repo_dir" --dry-run --no-setup --no-attach)"
  same_name_roots+=("$(printf '%s\n' "$output" | awk -F': ' '/^Workspace root: /{print $2; exit}')")
  test -f "$repo_dir/.squad/quickstart/feat-smoke/generated-manager.prompt.md"
done

case "${same_name_roots[0]}" in
  "$tmpdir/home/.local/share/squad/worktrees/"*) ;;
  *)
    echo "Expected worktree path to expand under HOME, got: ${same_name_roots[0]}" >&2
    exit 1
    ;;
esac

case "${same_name_roots[1]}" in
  "$tmpdir/home/.local/share/squad/worktrees/"*) ;;
  *)
    echo "Expected worktree path to expand under HOME, got: ${same_name_roots[1]}" >&2
    exit 1
    ;;
esac

test "${same_name_roots[0]}" != "${same_name_roots[1]}"

tilde_repo="$tmpdir/tilde-repo"
mkdir -p "$tilde_repo/.squad"
git -C "$tmpdir" init -b main tilde-repo >/dev/null
git -C "$tilde_repo" config user.email "codex@example.com"
git -C "$tilde_repo" config user.name "Codex"
echo "tilde" >"$tilde_repo/README.md"
git -C "$tilde_repo" add README.md
git -C "$tilde_repo" commit -m "seed" >/dev/null

cat >"$tilde_repo/.squad/launcher.yaml" <<'EOF'
runtime:
  claude_command: ~/bin/claude
  claude_args:
    - --dangerously-skip-permissions
EOF

cat >"$tilde_repo/.squad/run-task.md" <<'EOF'
# Task
Check tilde command expansion
EOF

HOME="$tmpdir/home" bash "$launcher" "$tilde_repo" --dry-run --no-setup --no-attach >/dev/null
grep -q "$tmpdir/home/bin/claude --dangerously-skip-permissions" "$tilde_repo/.squad/quickstart/generated-run-summary.md"

superpowers_repo="$tmpdir/superpowers-repo"
mkdir -p "$superpowers_repo/.squad" "$superpowers_repo/docs/superpowers/specs" "$superpowers_repo/docs/superpowers/plans"
git -C "$tmpdir" init -b main superpowers-repo >/dev/null
git -C "$superpowers_repo" config user.email "codex@example.com"
git -C "$superpowers_repo" config user.name "Codex"
echo "superpowers" >"$superpowers_repo/README.md"
git -C "$superpowers_repo" add README.md
git -C "$superpowers_repo" commit -m "seed" >/dev/null

cat >"$superpowers_repo/.squad/launcher.yaml" <<'EOF'
project:
  name: superpowers-demo
EOF

cat >"$superpowers_repo/docs/superpowers/specs/2026-03-29-older-flow-design.md" <<'EOF'
# Older Flow Design
This should not be selected.
EOF

cat >"$superpowers_repo/docs/superpowers/plans/2026-03-29-older-flow-implementation.md" <<'EOF'
# Older Flow Implementation Plan
This should not be selected.
EOF

cat >"$superpowers_repo/docs/superpowers/specs/2026-03-30-minimal-qr-connect-surface-design.md" <<'EOF'
# Minimal QR Connect Surface Design

## Goal
Finish the remaining product-facing QR connection path.
EOF

cat >"$superpowers_repo/docs/superpowers/plans/2026-03-30-minimal-qr-connect-surface-implementation.md" <<'EOF'
# Minimal QR Connect Surface Implementation Plan

## Task 1
Implement the QR connect surface.
EOF

bash "$launcher" "$superpowers_repo" --dry-run --no-setup --no-attach >/dev/null

superpowers_prompt="$superpowers_repo/.squad/quickstart/generated-manager.prompt.md"
superpowers_inspector_prompt="$superpowers_repo/.squad/quickstart/generated-inspector.prompt.md"
superpowers_summary="$superpowers_repo/.squad/quickstart/generated-run-summary.md"

test -f "$superpowers_prompt"
test -f "$superpowers_inspector_prompt"
test -f "$superpowers_summary"
grep -q "Minimal QR Connect Surface Implementation Plan" "$superpowers_prompt"
grep -q "Minimal QR Connect Surface Design" "$superpowers_prompt"
grep -q "Finish the remaining product-facing QR connection path" "$superpowers_prompt"
grep -q "Minimal QR Connect Surface Implementation Plan" "$superpowers_inspector_prompt"
grep -q "docs/superpowers/plans/2026-03-30-minimal-qr-connect-surface-implementation.md" "$superpowers_summary"
grep -q "docs/superpowers/specs/2026-03-30-minimal-qr-connect-surface-design.md" "$superpowers_summary"

custom_discovery_repo="$tmpdir/custom-discovery-repo"
mkdir -p "$custom_discovery_repo/.squad" "$custom_discovery_repo/workitems/plans" "$custom_discovery_repo/workitems/specifications"
git -C "$tmpdir" init -b main custom-discovery-repo >/dev/null
git -C "$custom_discovery_repo" config user.email "codex@example.com"
git -C "$custom_discovery_repo" config user.name "Codex"
echo "custom" >"$custom_discovery_repo/README.md"
git -C "$custom_discovery_repo" add README.md
git -C "$custom_discovery_repo" commit -m "seed" >/dev/null

cat >"$custom_discovery_repo/.squad/launcher.yaml" <<'EOF'
project:
  name: custom-discovery-demo

task_discovery:
  plan_globs:
    - workitems/plans/*-plan.md
  spec_globs:
    - workitems/specifications/*-spec.md
  plan_suffix: -plan.md
  spec_suffix: -spec.md
EOF

cat >"$custom_discovery_repo/workitems/specifications/2026-03-29-older-flow-spec.md" <<'EOF'
# Older Flow Spec
Do not select this spec.
EOF

cat >"$custom_discovery_repo/workitems/plans/2026-03-29-older-flow-plan.md" <<'EOF'
# Older Flow Plan
Do not select this plan.
EOF

cat >"$custom_discovery_repo/workitems/specifications/2026-03-31-remote-control-gateway-spec.md" <<'EOF'
# Remote Control Gateway Spec

## Goal
Keep arbitrary discovery layouts configurable.
EOF

cat >"$custom_discovery_repo/workitems/plans/2026-03-31-remote-control-gateway-plan.md" <<'EOF'
# Remote Control Gateway Plan

## Task 1
Support configurable plan/spec discovery.
EOF

bash "$launcher" "$custom_discovery_repo" --dry-run --no-setup --no-attach >/dev/null

custom_prompt="$custom_discovery_repo/.squad/quickstart/generated-manager.prompt.md"
custom_inspector_prompt="$custom_discovery_repo/.squad/quickstart/generated-inspector.prompt.md"
custom_summary="$custom_discovery_repo/.squad/quickstart/generated-run-summary.md"

test -f "$custom_prompt"
test -f "$custom_inspector_prompt"
test -f "$custom_summary"
grep -q "Remote Control Gateway Plan" "$custom_prompt"
grep -q "Remote Control Gateway Spec" "$custom_prompt"
grep -q "Keep arbitrary discovery layouts configurable" "$custom_prompt"
grep -q "Remote Control Gateway Plan" "$custom_inspector_prompt"
grep -q "workitems/plans/2026-03-31-remote-control-gateway-plan.md" "$custom_summary"
grep -q "workitems/specifications/2026-03-31-remote-control-gateway-spec.md" "$custom_summary"

custom_sort_repo="$tmpdir/custom-sort-repo"
mkdir -p "$custom_sort_repo/.squad" "$custom_sort_repo/a/plans" "$custom_sort_repo/z/plans" "$custom_sort_repo/a/specs" "$custom_sort_repo/z/specs"
git -C "$tmpdir" init -b main custom-sort-repo >/dev/null
git -C "$custom_sort_repo" config user.email "codex@example.com"
git -C "$custom_sort_repo" config user.name "Codex"
echo "sort" >"$custom_sort_repo/README.md"
git -C "$custom_sort_repo" add README.md
git -C "$custom_sort_repo" commit -m "seed" >/dev/null

cat >"$custom_sort_repo/.squad/launcher.yaml" <<'EOF'
task_discovery:
  plan_globs:
    - a/plans/*-plan.md
    - z/plans/*-plan.md
  spec_globs:
    - a/specs/*-spec.md
    - z/specs/*-spec.md
  plan_suffix: -plan.md
  spec_suffix: -spec.md
EOF

cat >"$custom_sort_repo/a/plans/2026-04-01-newer-plan.md" <<'EOF'
# Newer Plan
EOF

cat >"$custom_sort_repo/a/specs/2026-04-01-newer-spec.md" <<'EOF'
# Newer Spec
EOF

cat >"$custom_sort_repo/z/plans/2026-03-01-older-plan.md" <<'EOF'
# Older Plan
EOF

cat >"$custom_sort_repo/z/specs/2026-03-01-older-spec.md" <<'EOF'
# Older Spec
EOF

bash "$launcher" "$custom_sort_repo" --dry-run --no-setup --no-attach >/dev/null

custom_sort_prompt="$custom_sort_repo/.squad/quickstart/generated-manager.prompt.md"
custom_sort_summary="$custom_sort_repo/.squad/quickstart/generated-run-summary.md"

grep -q "Newer Plan" "$custom_sort_prompt"
grep -q "Newer Spec" "$custom_sort_prompt"
grep -q "a/plans/2026-04-01-newer-plan.md" "$custom_sort_summary"
grep -q "a/specs/2026-04-01-newer-spec.md" "$custom_sort_summary"

subproject_repo="$tmpdir/subproject-repo"
mkdir -p "$subproject_repo/subproj/.squad" "$subproject_repo/workitems/plans"
git -C "$tmpdir" init -b main subproject-repo >/dev/null
git -C "$subproject_repo" config user.email "codex@example.com"
git -C "$subproject_repo" config user.name "Codex"
echo "subproject" >"$subproject_repo/README.md"
git -C "$subproject_repo" add README.md
git -C "$subproject_repo" commit -m "seed" >/dev/null

cat >"$subproject_repo/subproj/.squad/launcher.yaml" <<'EOF'
project:
  name: subproj

task_discovery:
  plan_globs:
    - workitems/plans/*-plan.md
  spec_globs:
    - workitems/specifications/*-spec.md
  plan_suffix: -plan.md
  spec_suffix: -spec.md
EOF

cat >"$subproject_repo/workitems/plans/2026-04-01-root-plan.md" <<'EOF'
# Root Plan
EOF

set +e
subproject_output="$(bash "$launcher" "$subproject_repo/subproj" --dry-run --no-setup --no-attach 2>&1)"
subproject_status=$?
set -e

if (( subproject_status == 0 )); then
  echo "Expected custom discovery to stay within subproject config root" >&2
  exit 1
fi

printf '%s\n' "$subproject_output" | grep -q "configure task_discovery.plan_globs"
if printf '%s\n' "$subproject_output" | grep -q "Root Plan"; then
  echo "Unexpectedly selected repo-root plan for subproject launcher config" >&2
  exit 1
fi

taskfile_repo="$tmpdir/taskfile-repo"
mkdir -p "$taskfile_repo/subproj/.squad" "$taskfile_repo/subproj/workitems/plans" "$taskfile_repo/subproj/workitems/specifications"
git -C "$tmpdir" init -b main taskfile-repo >/dev/null
git -C "$taskfile_repo" config user.email "codex@example.com"
git -C "$taskfile_repo" config user.name "Codex"
echo "taskfile" >"$taskfile_repo/README.md"
git -C "$taskfile_repo" add README.md
git -C "$taskfile_repo" commit -m "seed" >/dev/null

cat >"$taskfile_repo/subproj/.squad/launcher.yaml" <<'EOF'
task_discovery:
  plan_globs:
    - workitems/plans/*-plan.md
  spec_globs:
    - workitems/specifications/*-spec.md
  plan_suffix: -plan.md
  spec_suffix: -spec.md
EOF

cat >"$taskfile_repo/subproj/workitems/plans/2026-04-01-demo-plan.md" <<'EOF'
# Demo Plan
EOF

cat >"$taskfile_repo/subproj/workitems/specifications/2026-04-01-demo-spec.md" <<'EOF'
# Demo Spec
EOF

bash "$launcher" "$taskfile_repo/subproj" --task-file "$taskfile_repo/subproj/workitems/plans/2026-04-01-demo-plan.md" --dry-run --no-setup --no-attach >/dev/null

taskfile_prompt="$taskfile_repo/subproj/.squad/quickstart/generated-manager.prompt.md"
taskfile_summary="$taskfile_repo/subproj/.squad/quickstart/generated-run-summary.md"

grep -q "Demo Plan" "$taskfile_prompt"
grep -q "Demo Spec" "$taskfile_prompt"
grep -q "subproj/workitems/specifications/2026-04-01-demo-spec.md" "$taskfile_summary"

escape_repo="$tmpdir/escape-repo"
mkdir -p "$escape_repo/.squad" "$tmpdir/outside-docs/plans"
git -C "$tmpdir" init -b main escape-repo >/dev/null
git -C "$escape_repo" config user.email "codex@example.com"
git -C "$escape_repo" config user.name "Codex"
echo "escape" >"$escape_repo/README.md"
git -C "$escape_repo" add README.md
git -C "$escape_repo" commit -m "seed" >/dev/null

cat >"$escape_repo/.squad/launcher.yaml" <<'EOF'
task_discovery:
  plan_globs:
    - ../outside-docs/plans/*-plan.md
  plan_suffix: -plan.md
EOF

cat >"$tmpdir/outside-docs/plans/2026-04-01-escaped-plan.md" <<'EOF'
# Escaped Plan
EOF

set +e
escape_output="$(bash "$launcher" "$escape_repo" --dry-run --no-setup --no-attach 2>&1)"
escape_rc=$?
set -e

if (( escape_rc == 0 )); then
  echo "Expected task discovery globs to stay within project-dir" >&2
  exit 1
fi

printf '%s\n' "$escape_output" | grep -q "configure task_discovery.plan_globs"
if [[ -f "$escape_repo/.squad/quickstart/generated-manager.prompt.md" ]]; then
  if grep -q "Escaped Plan" "$escape_repo/.squad/quickstart/generated-manager.prompt.md"; then
    echo "Unexpectedly selected escaped plan outside project-dir" >&2
    exit 1
  fi
fi

echo "PASS: generic launcher dry-run generated expected files"
