#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/squad-tmux-launcher-helpers.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/squad-tmux-launch.sh <project-dir> [options]

Options:
  --task-file <path>      Use a specific task brief file
  --session-name <name>   Override tmux session name
  --workers <n>           Override worker pane count
  --worktree-branch <name> Enable worktree mode and use this branch name
  --worktree-path <name>  Override worktree leaf directory name
  --worktree-base <ref>   Base ref for new worktree branches (default: HEAD)
  --worktree-location <path> Override worktree parent directory
  --no-worktree           Disable worktree mode even if config enables it
  --no-setup              Skip `squad setup claude`
  --no-attach             Create/start session but do not attach
  --dry-run               Generate prompt/summary/map only; do not run squad/tmux/claude
  --reuse-session         Reuse an existing tmux session instead of failing
  -h, --help              Show this help

Task source priority:
  1. --task-file <path>
  2. <project-dir>/.squad/run-task.md
  3. task_discovery.plan_globs / spec_globs from .squad/launcher.yaml
     or the default docs/superpowers/plans/YYYY-MM-DD-*-implementation.md
     plus the newest matching spec

Project config:
  <project-dir>/.squad/launcher.yaml

Worktree config:
  <project-dir>/.squad/launcher.yaml -> workspace.worktree
  Default location when enabled without an explicit path:
    ~/.local/share/squad/worktrees/<repo-root-slug>

Generated files:
  <project-dir>/.squad/quickstart/generated-*.md
  <project-dir>/.squad/quickstart/<worktree-path>/generated-*.md   (when worktree mode is enabled)

Examples:
  scripts/squad-tmux-launch.sh /path/to/project
  scripts/squad-tmux-launch.sh /path/to/project --task-file /tmp/task.md
  scripts/squad-tmux-launch.sh /path/to/project --worktree-branch feat/my-task
  scripts/squad-tmux-launch.sh /path/to/project --dry-run --no-setup
  scripts/squad-tmux-launch.sh /path/to/project --reuse-session --session-name my-squad
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: missing required command: $cmd" >&2
    exit 1
  fi
}

normalize_session_name() {
  local value="$1"
  value="$(printf '%s' "$value" | tr ' /:@' '----')"
  value="${value//[^A-Za-z0-9._-]/-}"
  printf '%s' "${value:-squad-session}"
}

wait_for_pane_command() {
  local target="$1"
  local timeout_secs="$2"
  shift 2
  local expected_commands=("$@")
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local current
    current="$(tmux display-message -p -t "$target" "#{pane_current_command}")"

    local expected=""
    for expected in "${expected_commands[@]}"; do
      if [[ "$current" == "$expected" ]]; then
        return 0
      fi
    done

    if (( "$(date +%s)" - start_ts >= timeout_secs )); then
      echo "Error: pane $target did not start one of [${expected_commands[*]}] within ${timeout_secs}s (current: $current)" >&2
      return 1
    fi

    sleep 1
  done
}

wait_for_agent_count() {
  local workspace="$1"
  local expected_count="$2"
  local timeout_secs="$3"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local current_count
    current_count="$(
      (
        cd "$workspace"
        squad agents --json 2>/dev/null || true
      ) | awk 'NF { count += 1 } END { print count + 0 }'
    )"

    if (( current_count >= expected_count )); then
      return 0
    fi

    if (( "$(date +%s)" - start_ts >= timeout_secs )); then
      echo "Error: only ${current_count}/${expected_count} agents joined squad within ${timeout_secs}s" >&2
      return 1
    fi

    sleep 1
  done
}

send_tmux_text() {
  local target="$1"
  local text="$2"
  tmux load-buffer - <<<"$text"
  tmux paste-buffer -t "$target"
  tmux send-keys -t "$target" Enter
  tmux delete-buffer
}

load_launcher_config() {
  local config_path="$1"
  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  require_cmd ruby

  eval "$(
    ruby - "$config_path" <<'RUBY'
require "yaml"
require "shellwords"

file = ARGV[0]
data =
  if File.exist?(file)
    YAML.safe_load(
      File.read(file),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false,
    ) || {}
  else
    {}
  end

def lookup(hash, *keys)
  keys.reduce(hash) do |acc, key|
    break nil unless acc.is_a?(Hash)
    acc[key] || acc[key.to_sym]
  end
end

def emit_scalar(name, value)
  value = nil if value.respond_to?(:empty?) && value.empty?
  rendered = value.nil? ? "''" : Shellwords.escape(value.to_s)
  puts "#{name}=#{rendered}"
end

def emit_array(name, value)
  items = Array(value).compact.map(&:to_s)
  print "#{name}=("
  items.each do |item|
    print "#{Shellwords.escape(item)} "
  end
  puts ")"
end

emit_scalar("CFG_PROJECT_NAME", lookup(data, "project", "name"))
emit_scalar("CFG_SESSION_NAME", lookup(data, "project", "session_name"))
emit_scalar("CFG_CLAUDE_COMMAND", lookup(data, "runtime", "claude_command"))
emit_array("CFG_CLAUDE_ARGS", lookup(data, "runtime", "claude_args"))
emit_scalar("CFG_MANAGER_ROLE", lookup(data, "runtime", "manager_role"))
emit_scalar("CFG_WORKER_ROLE", lookup(data, "runtime", "worker_role"))
emit_scalar("CFG_INSPECTOR_ROLE", lookup(data, "runtime", "inspector_role"))
emit_scalar("CFG_WORKERS", lookup(data, "runtime", "workers"))
emit_array("CFG_INIT_ARGS", lookup(data, "workspace", "init_args"))
emit_scalar("CFG_WORKTREE_ENABLED", lookup(data, "workspace", "worktree", "enabled"))
emit_scalar("CFG_WORKTREE_LOCATION", lookup(data, "workspace", "worktree", "location"))
emit_scalar("CFG_WORKTREE_PATH", lookup(data, "workspace", "worktree", "path"))
emit_scalar("CFG_WORKTREE_BRANCH", lookup(data, "workspace", "worktree", "branch"))
emit_scalar("CFG_WORKTREE_BASE_REF", lookup(data, "workspace", "worktree", "base_ref"))
emit_array("CFG_TASK_DISCOVERY_PLAN_GLOBS", lookup(data, "task_discovery", "plan_globs"))
emit_array("CFG_TASK_DISCOVERY_SPEC_GLOBS", lookup(data, "task_discovery", "spec_globs"))
emit_scalar("CFG_TASK_DISCOVERY_PLAN_SUFFIX", lookup(data, "task_discovery", "plan_suffix"))
emit_scalar("CFG_TASK_DISCOVERY_SPEC_SUFFIX", lookup(data, "task_discovery", "spec_suffix"))
emit_array("CFG_FOCUS_FILES", lookup(data, "focus", "files"))
emit_array("CFG_FOCUS_DOCS", lookup(data, "focus", "docs"))
emit_array("CFG_CONSTRAINTS", lookup(data, "constraints"))
RUBY
  )"
}

latest_matching_doc() {
  local dir="$1"
  local pattern="$2"
  [[ -d "$dir" ]] || return 1

  find "$dir" -maxdepth 1 -type f -name "$pattern" | LC_ALL=C sort | tail -n 1
}

latest_matching_glob_patterns() {
  local root="$1"
  shift
  [[ -d "$root" ]] || return 1
  (( $# > 0 )) || return 1

  require_cmd ruby

  ruby - "$root" "$@" <<'RUBY'
root_arg = ARGV.shift
root = begin
  File.realpath(root_arg)
rescue StandardError
  File.expand_path(root_arg)
end
patterns = ARGV
matches = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_EXTGLOB) }
  .select do |path|
    next false unless File.file?(path)
    expanded = begin
      File.realpath(path)
    rescue StandardError
      File.expand_path(path)
    end
    expanded == root || expanded.start_with?(root + "/")
  end
  .uniq
  .sort_by { |path| [File.basename(path), path] }
puts matches.last if matches.any?
RUBY
}

all_matching_glob_patterns() {
  local root="$1"
  shift
  [[ -d "$root" ]] || return 1
  (( $# > 0 )) || return 1

  require_cmd ruby

  ruby - "$root" "$@" <<'RUBY'
root_arg = ARGV.shift
root = begin
  File.realpath(root_arg)
rescue StandardError
  File.expand_path(root_arg)
end
patterns = ARGV
matches = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_EXTGLOB) }
  .select do |path|
    next false unless File.file?(path)
    expanded = begin
      File.realpath(path)
    rescue StandardError
      File.expand_path(path)
    end
    expanded == root || expanded.start_with?(root + "/")
  end
  .uniq
  .sort_by { |path| [File.basename(path), path] }
puts matches
RUBY
}

path_matches_glob_patterns() {
  local root="$1"
  local candidate="$2"
  shift 2
  (( $# > 0 )) || return 1
  [[ -d "$root" ]] || return 1

  require_cmd ruby

  ruby - "$root" "$candidate" "$@" <<'RUBY'
root = File.expand_path(ARGV.shift)
candidate = File.expand_path(ARGV.shift)
patterns = ARGV

begin
  relative = candidate.delete_prefix(root + "/")
  if relative == candidate || relative.empty?
    exit 1
  end

  matched = patterns.any? do |pattern|
    Dir.glob(File.join(root, pattern), File::FNM_EXTGLOB).any? do |path|
      File.expand_path(path) == candidate
    end
  end

  exit(matched ? 0 : 1)
rescue StandardError
  exit 1
end
RUBY
}

doc_topic_slug() {
  local file_path="$1"
  local suffix="$2"
  local name=""
  name="$(basename "$file_path")"

  if [[ -n "$suffix" && "$name" == *"$suffix" ]]; then
    name="${name%"$suffix"}"
  else
    name="${name%.md}"
  fi

  if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)$ ]]; then
    name="${BASH_REMATCH[1]}"
  fi

  [[ -n "$name" ]] || return 1
  printf '%s' "$name"
}

matching_spec_from_patterns() {
  local plan_file="$1"
  local topic_slug=""
  local root="$2"
  shift 2
  local -a patterns=("$@")
  local pattern=""
  local candidate=""
  local candidate_slug=""
  local latest=""

  topic_slug="$(doc_topic_slug "$plan_file" "$task_discovery_plan_suffix")" || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    candidate_slug="$(doc_topic_slug "$candidate" "$task_discovery_spec_suffix" || true)"
    if [[ -n "$candidate_slug" && "$candidate_slug" == "$topic_slug" ]]; then
      latest="$candidate"
    fi
  done < <(all_matching_glob_patterns "$root" "${patterns[@]}" 2>/dev/null || true)

  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  else
    return 1
  fi
}

latest_matching_spec_for_plan() {
  local plan_file="$1"
  local root="$2"

  if (( ${#task_discovery_spec_globs[@]} > 0 )); then
    matching_spec_from_patterns "$plan_file" "$root" "${task_discovery_spec_globs[@]}"
    return
  fi

  local specs_dir="$root/docs/superpowers/specs"
  local topic_slug=""
  topic_slug="$(doc_topic_slug "$plan_file" "$task_discovery_plan_suffix")" || return 1
  latest_matching_doc "$specs_dir" "????-??-??-${topic_slug}${task_discovery_spec_suffix}"
}

looks_like_plan_file() {
  local file_path="$1"
  local base_name
  base_name="$(basename "$file_path")"
  [[ -n "$task_discovery_plan_suffix" && "$base_name" == *"$task_discovery_plan_suffix" ]]
}

resolve_discovery_candidate() {
  local root="$1"

  if (( ${#task_discovery_plan_globs[@]} > 0 )); then
    latest_matching_glob_patterns "$root" "${task_discovery_plan_globs[@]}"
  else
    latest_matching_doc "$root/docs/superpowers/plans" "????-??-??-*${task_discovery_plan_suffix}"
  fi
}

discovery_root_for_plan_file() {
  local plan_file="$1"
  local project_dir="$2"
  local repo_root="$3"

  if (( ${#task_discovery_plan_globs[@]} > 0 )); then
    if path_matches_glob_patterns "$project_dir" "$plan_file" "${task_discovery_plan_globs[@]}"; then
      printf '%s\n' "$project_dir"
      return 0
    fi
    return 1
  fi

  if [[ "$plan_file" == "$project_dir"/docs/superpowers/plans/*"$task_discovery_plan_suffix" ]]; then
    printf '%s\n' "$project_dir"
    return 0
  fi

  if [[ -n "$repo_root" && "$repo_root" != "$project_dir" ]] && [[ "$plan_file" == "$repo_root"/docs/superpowers/plans/*"$task_discovery_plan_suffix" ]]; then
    printf '%s\n' "$repo_root"
    return 0
  fi

  return 1
}

resolve_task_sources() {
  local project_dir="$1"
  local task_override="$2"
  local default_task_file="$3"
  local repo_root="$4"
  local candidate=""
  local root=""
  local -a search_roots=()

  task_source_kind="task-brief"
  task_source_path=""
  task_supporting_spec_path=""
  task_source_root=""

  if [[ -n "$task_override" ]]; then
    task_source_path="$task_override"
    if [[ ! -f "$task_source_path" ]]; then
      echo "Error: task brief not found: $task_source_path" >&2
      echo "Provide --task-file <path> or create $default_task_file" >&2
      exit 1
    fi
  elif [[ -f "$default_task_file" ]]; then
    task_source_path="$default_task_file"
  else
    search_roots=("$project_dir")
    if (( ${#task_discovery_plan_globs[@]} == 0 )) && [[ -n "$repo_root" && "$repo_root" != "$project_dir" ]]; then
      search_roots+=("$repo_root")
    fi

    for root in "${search_roots[@]}"; do
      candidate="$(resolve_discovery_candidate "$root" || true)"
      if [[ -n "$candidate" ]]; then
        task_source_kind="superpowers-plan"
        task_source_path="$candidate"
        task_source_root="$root"
        task_supporting_spec_path="$(latest_matching_spec_for_plan "$candidate" "$root" || true)"
        break
      fi
    done

    if [[ -z "$task_source_path" ]]; then
      echo "Error: task brief not found: $default_task_file" >&2
      echo "Provide --task-file <path>, create $default_task_file, or configure task_discovery.plan_globs in $launcher_config" >&2
      exit 1
    fi
  fi

  if [[ "$task_source_kind" == "task-brief" ]] && looks_like_plan_file "$task_source_path"; then
    task_source_kind="superpowers-plan"
    task_source_root="$(discovery_root_for_plan_file "$task_source_path" "$project_dir" "$repo_root" || true)"
    if [[ -z "$task_source_root" ]]; then
      task_source_root="$project_dir"
    fi
    task_supporting_spec_path="$(latest_matching_spec_for_plan "$task_source_path" "$task_source_root" || true)"
  fi
}

build_manager_prompt() {
  local output_path="$1"
  local project_name="$2"
  local workspace_dir="$3"
  local task_file="$4"

  {
    echo "# Squad Manager Prompt"
    echo
    echo "Coordinate the current squad collaboration run using the project context below and the task brief that follows."
    echo
    echo "## Project Context"
    echo "- Project: \`$project_name\`"
    echo "- Config root: \`$source_project_dir\`"
    echo "- Workspace root: \`$workspace_dir\`"
    echo "- Session: \`$session_name\`"
    echo "- Worker count: \`$workers\`"
    echo "- Manager role: \`$manager_role\`"
    echo "- Worker role base: \`$worker_role\`"
    echo "- Inspector role: \`$inspector_role\`"
    echo

    if (( worktree_enabled == 1 )); then
      echo "## Worktree"
      echo "- Enabled: \`true\`"
      echo "- Repo root: \`$git_repo_root\`"
      echo "- Worktree root: \`$worktree_root\`"
      echo "- Branch: \`$worktree_branch\`"
      echo "- Base ref: \`$worktree_base_ref\`"
      echo
    fi

    if (( ${#focus_files[@]} > 0 )); then
      echo "## Focus Files"
      for item in "${focus_files[@]}"; do
        echo "- \`$item\`"
      done
      echo
    fi

    if (( ${#focus_docs[@]} > 0 )); then
      echo "## Focus Docs"
      for item in "${focus_docs[@]}"; do
        echo "- \`$item\`"
      done
      echo
    fi

    if (( ${#constraints[@]} > 0 )); then
      echo "## Constraints"
      for item in "${constraints[@]}"; do
        echo "- $item"
      done
      echo
    fi

    echo "## Input Sources"
    echo "- Primary task source: \`$task_source_path\`"
    if [[ "$task_source_kind" == "superpowers-plan" ]]; then
      echo "- Primary type: \`implementation-plan\`"
      if [[ -n "$task_supporting_spec_path" ]]; then
        echo "- Supporting spec: \`$task_supporting_spec_path\`"
      fi
      if [[ -n "$task_source_root" ]]; then
        echo "- Source root: \`$task_source_root\`"
      fi
    else
      echo "- Primary type: \`task-brief\`"
    fi
    echo

    cat <<'EOF'
## Execution Principles
- Start with read-only analysis and build a baseline before assigning work.
- Prefer `squad task create / ack / complete` when state tracking matters.
- The manager coordinates, delegates, reviews, and closes the loop; avoid taking the main implementation work personally.
- Each task must include a goal, touched files, behavior constraints, and acceptance criteria.
- Every completed worker task should be reviewed by the inspector.
- Do not validate only the happy path; cover failures, fallback behavior, recovery, and regressions.
- If worktree mode is enabled, all code changes, tests, and commits must happen in `Workspace root`.
EOF
    echo
    if [[ "$task_source_kind" == "superpowers-plan" ]]; then
      echo "## Implementation Plan"
      echo
      cat "$task_file"
      if [[ -n "$task_supporting_spec_path" ]]; then
        echo
        echo "## Supporting Spec"
        echo
        cat "$task_supporting_spec_path"
      fi
    else
      echo "## Task Brief"
      echo
      cat "$task_file"
    fi
  } >"$output_path"
}

build_inspector_prompt() {
  local output_path="$1"
  local project_name="$2"
  local workspace_dir="$3"
  local task_file="$4"
  local inspector_source="$5"

  {
    echo "# Squad Inspector Prompt"
    echo
    echo "Review the current squad output as the inspector, prioritizing bugs, regressions, documentation drift, and missing tests."
    echo
    echo "## Project Context"
    echo "- Project: \`$project_name\`"
    echo "- Config root: \`$source_project_dir\`"
    echo "- Workspace root: \`$workspace_dir\`"
    echo "- Session: \`$session_name\`"
    echo "- Manager role: \`$manager_role\`"
    echo "- Inspector role: \`$inspector_role\`"
    echo

    if (( worktree_enabled == 1 )); then
      echo "## Worktree"
      echo "- Repo root: \`$git_repo_root\`"
      echo "- Worktree root: \`$worktree_root\`"
      echo "- Branch: \`$worktree_branch\`"
      echo
    fi

    if (( ${#focus_files[@]} > 0 )); then
      echo "## Focus Files"
      for item in "${focus_files[@]}"; do
        echo "- \`$item\`"
      done
      echo
    fi

    if (( ${#constraints[@]} > 0 )); then
      echo "## Constraints"
      for item in "${constraints[@]}"; do
        echo "- $item"
      done
      echo
    fi

    cat <<'EOF'
## Review Principles
- Findings first. Order them by severity.
- Prioritise behavioral regressions, broken assumptions, and missing tests.
- Check README and docs against the actual implementation when relevant.
- If there are no blocking findings, say so explicitly and note residual risks.

EOF

    if [[ -f "$inspector_source" ]]; then
      echo "## Inspector Brief"
      echo
      cat "$inspector_source"
      echo
    fi

    if [[ "$task_source_kind" == "superpowers-plan" ]]; then
      echo "## Implementation Plan"
      echo
      cat "$task_file"
      if [[ -n "$task_supporting_spec_path" ]]; then
        echo
        echo "## Supporting Spec"
        echo
        cat "$task_supporting_spec_path"
      fi
    else
      echo "## Task Brief"
      echo
      cat "$task_file"
    fi

    if [[ ! -f "$inspector_source" ]]; then
      cat <<'EOF'
## Review Checklist
Use the task material above to confirm:
- the implementation satisfies the goal rather than only making tests pass
- no behavior regressions or compatibility breaks were introduced
- README, configuration guidance, and diagnostics still match the implementation
- tests genuinely cover the change objective
EOF
    fi
  } >"$output_path"
}

build_run_summary() {
  local output_path="$1"
  {
    echo "# Squad Run Summary"
    echo
    echo "- Project: \`$project_name\`"
    echo "- Config root: \`$source_project_dir\`"
    echo "- Workspace root: \`$workspace_dir\`"
    echo "- Session: \`$session_name\`"
    echo "- Task file: \`$task_file\`"
    echo "- Task source kind: \`$task_source_kind\`"
    echo "- Task source path: \`$task_source_path\`"
    echo "- Supporting spec path: \`$task_supporting_spec_path\`"
    echo "- Task source root: \`$task_source_root\`"
    echo "- Inspector prompt source: \`$inspector_prompt_source\`"
    echo "- Launcher config: \`$launcher_config\`"
    echo "- Claude launch: \`$claude_launch_command\`"
    echo "- Workers: \`$workers\`"
    echo "- Dry run: \`$dry_run\`"
    echo "- No setup: \`$no_setup\`"
    echo "- No attach: \`$no_attach\`"
    echo "- Reuse session: \`$reuse_session\`"
    echo "- Worktree enabled: \`$worktree_enabled\`"
    echo "- Git repo root: \`$git_repo_root\`"
    echo "- Worktree root: \`$worktree_root\`"
    echo "- Worktree branch: \`$worktree_branch\`"
    echo "- Worktree base ref: \`$worktree_base_ref\`"
    echo "- Worktree config root: \`$source_project_dir\`"
    echo
    echo "Generated files:"
    echo "- \`$prompt_file\`"
    echo "- \`$inspector_prompt_file\`"
    echo "- \`$summary_file\`"
    echo "- \`$terminal_map_file\`"
  } >"$output_path"
}

build_terminal_map() {
  local output_path="$1"
  {
    echo "# Terminal Map"
    echo
    echo "- tmux session: \`$session_name\`"
    echo "- workspace: \`$workspace_dir\`"
    echo
    echo "| Pane | Role | Command |"
    echo "| --- | --- | --- |"
    for i in "${!pane_labels[@]}"; do
      echo "| $i | \`${pane_labels[$i]}\` | \`${pane_commands[$i]}\` |"
    done
  } >"$output_path"
}

no_setup=0
no_attach=0
dry_run=0
reuse_session=0
no_worktree=0
task_file_override=""
session_name_override=""
workers_override=""
worktree_branch_override=""
worktree_path_override=""
worktree_base_ref_override=""
worktree_location_override=""
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file)
      task_file_override="${2:-}"
      [[ -n "$task_file_override" ]] || { echo "Error: --task-file requires a path" >&2; exit 1; }
      shift 2
      ;;
    --session-name)
      session_name_override="${2:-}"
      [[ -n "$session_name_override" ]] || { echo "Error: --session-name requires a value" >&2; exit 1; }
      shift 2
      ;;
    --workers)
      workers_override="${2:-}"
      [[ -n "$workers_override" ]] || { echo "Error: --workers requires a value" >&2; exit 1; }
      shift 2
      ;;
    --worktree-branch)
      worktree_branch_override="${2:-}"
      [[ -n "$worktree_branch_override" ]] || { echo "Error: --worktree-branch requires a value" >&2; exit 1; }
      shift 2
      ;;
    --worktree-path)
      worktree_path_override="${2:-}"
      [[ -n "$worktree_path_override" ]] || { echo "Error: --worktree-path requires a value" >&2; exit 1; }
      shift 2
      ;;
    --worktree-base)
      worktree_base_ref_override="${2:-}"
      [[ -n "$worktree_base_ref_override" ]] || { echo "Error: --worktree-base requires a value" >&2; exit 1; }
      shift 2
      ;;
    --worktree-location)
      worktree_location_override="${2:-}"
      [[ -n "$worktree_location_override" ]] || { echo "Error: --worktree-location requires a value" >&2; exit 1; }
      shift 2
      ;;
    --no-worktree)
      no_worktree=1
      shift
      ;;
    --no-setup)
      no_setup=1
      shift
      ;;
    --no-attach)
      no_attach=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --reuse-session)
      reuse_session=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if (( ${#positional[@]} < 1 )); then
  usage >&2
  exit 1
fi

project_dir="${positional[0]}"
if [[ ! -d "$project_dir" ]]; then
  echo "Error: project directory does not exist: $project_dir" >&2
  exit 1
fi

cd "$project_dir"
project_dir="$(pwd -P)"
source_project_dir="$project_dir"

launcher_config="$project_dir/.squad/launcher.yaml"
default_task_file="$project_dir/.squad/run-task.md"
detected_repo_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
CFG_PROJECT_NAME=""
CFG_SESSION_NAME=""
CFG_CLAUDE_COMMAND=""
CFG_CLAUDE_ARGS=()
CFG_MANAGER_ROLE=""
CFG_WORKER_ROLE=""
CFG_INSPECTOR_ROLE=""
CFG_WORKERS=""
CFG_INIT_ARGS=()
CFG_WORKTREE_ENABLED=""
CFG_WORKTREE_LOCATION=""
CFG_WORKTREE_PATH=""
CFG_WORKTREE_BRANCH=""
CFG_WORKTREE_BASE_REF=""
CFG_TASK_DISCOVERY_PLAN_GLOBS=()
CFG_TASK_DISCOVERY_SPEC_GLOBS=()
CFG_TASK_DISCOVERY_PLAN_SUFFIX=""
CFG_TASK_DISCOVERY_SPEC_SUFFIX=""
CFG_FOCUS_FILES=()
CFG_FOCUS_DOCS=()
CFG_CONSTRAINTS=()

load_launcher_config "$launcher_config"

project_name="${CFG_PROJECT_NAME:-$(basename "$project_dir")}"
session_name="${session_name_override:-${CFG_SESSION_NAME:-${project_name}-squad}}"
session_name="$(normalize_session_name "$session_name")"
claude_command="${CFG_CLAUDE_COMMAND:-claude}"
if [[ "$claude_command" == "~" ]]; then
  claude_command="$HOME"
elif [[ "${claude_command:0:2}" == "~/" ]]; then
  claude_command="$HOME/${claude_command:2}"
fi
manager_role="${CFG_MANAGER_ROLE:-manager}"
worker_role="${CFG_WORKER_ROLE:-worker}"
inspector_role="${CFG_INSPECTOR_ROLE:-inspector}"
workers="${workers_override:-${CFG_WORKERS:-2}}"
worktree_enabled=0
if is_truthy "${CFG_WORKTREE_ENABLED:-}"; then
  worktree_enabled=1
fi
if [[ -n "$worktree_branch_override" || -n "$worktree_path_override" || -n "$worktree_base_ref_override" || -n "$worktree_location_override" ]]; then
  worktree_enabled=1
fi
if (( no_worktree == 1 )); then
  worktree_enabled=0
fi

if ! [[ "$workers" =~ ^[0-9]+$ ]] || (( workers < 1 )); then
  echo "Error: --workers must be an integer >= 1 (got: $workers)" >&2
  exit 1
fi

copy_array_or_empty claude_args CFG_CLAUDE_ARGS
copy_array_or_empty init_args CFG_INIT_ARGS
copy_array_or_empty task_discovery_plan_globs CFG_TASK_DISCOVERY_PLAN_GLOBS
copy_array_or_empty task_discovery_spec_globs CFG_TASK_DISCOVERY_SPEC_GLOBS
copy_array_or_empty focus_files CFG_FOCUS_FILES
copy_array_or_empty focus_docs CFG_FOCUS_DOCS
copy_array_or_empty constraints CFG_CONSTRAINTS
task_discovery_plan_suffix="${CFG_TASK_DISCOVERY_PLAN_SUFFIX:--implementation.md}"
task_discovery_spec_suffix="${CFG_TASK_DISCOVERY_SPEC_SUFFIX:--design.md}"

task_file=""
task_source_kind=""
task_source_path=""
task_supporting_spec_path=""
task_source_root=""

resolve_task_sources "$project_dir" "$task_file_override" "$default_task_file" "$detected_repo_root"
task_file="$task_source_path"

if (( ${#init_args[@]} == 0 )); then
  init_args=(--refresh-roles)
fi

git_repo_root=""
project_relative_path=""
worktree_location=""
worktree_branch=""
worktree_path=""
worktree_base_ref=""
worktree_root=""
workspace_dir="$source_project_dir"

if (( worktree_enabled == 1 )); then
  require_cmd git
  git_repo_root="$(git -C "$source_project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$git_repo_root" ]]; then
    echo "Error: worktree mode requires a git repository: $source_project_dir" >&2
    exit 1
  fi

  if [[ "$source_project_dir" == "$git_repo_root" ]]; then
    project_relative_path=""
  else
    project_relative_path="${source_project_dir#$git_repo_root/}"
  fi

  default_worktree_location="~/.local/share/squad/worktrees/$(repo_worktree_location_slug "$git_repo_root")"
  worktree_location="${worktree_location_override:-${CFG_WORKTREE_LOCATION:-$default_worktree_location}}"
  worktree_branch="${worktree_branch_override:-${CFG_WORKTREE_BRANCH:-}}"
  worktree_base_ref="${worktree_base_ref_override:-${CFG_WORKTREE_BASE_REF:-HEAD}}"
  worktree_path="${worktree_path_override:-${CFG_WORKTREE_PATH:-}}"

  if [[ -z "$worktree_branch" ]]; then
    echo "Error: worktree mode requires a branch name via workspace.worktree.branch or --worktree-branch" >&2
    exit 1
  fi

  if [[ -z "$worktree_path" ]]; then
    worktree_path="$(slugify_path_component "$worktree_branch")"
  fi

  requested_worktree_root="$(resolve_worktree_path "$git_repo_root" "$worktree_location" "$worktree_path")"
  ensure_repo_local_worktree_ignored "$git_repo_root" "$requested_worktree_root"
  worktree_root="$(ensure_git_worktree "$git_repo_root" "$requested_worktree_root" "$worktree_branch" "$worktree_base_ref" "$dry_run")"

  if [[ -n "$project_relative_path" ]]; then
    workspace_dir="$worktree_root/$project_relative_path"
  else
    workspace_dir="$worktree_root"
  fi
else
  git_repo_root="$(git -C "$source_project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
fi

if (( dry_run == 0 )) && [[ ! -d "$workspace_dir" ]]; then
  echo "Error: workspace directory does not exist: $workspace_dir" >&2
  exit 1
fi

quickstart_dir="$source_project_dir/.squad/quickstart"
if (( worktree_enabled == 1 )); then
  quickstart_dir="$quickstart_dir/$(slugify_path_component "$worktree_path")"
fi
mkdir -p "$quickstart_dir"

claude_launch_command="$(shell_join "$claude_command")"
if (( ${#claude_args[@]} > 0 )); then
  claude_launch_command="$(shell_join "$claude_command" "${claude_args[@]}")"
fi
inspector_prompt_source="$source_project_dir/.squad/prompts/inspector.md"

prompt_file="$quickstart_dir/generated-manager.prompt.md"
inspector_prompt_file="$quickstart_dir/generated-inspector.prompt.md"
summary_file="$quickstart_dir/generated-run-summary.md"
terminal_map_file="$quickstart_dir/generated-terminal-map.md"

pane_labels=("$manager_role")
pane_commands=("/squad $manager_role")
for ((i = 1; i <= workers; i++)); do
  if (( i == 1 )); then
    pane_labels+=("$worker_role")
    pane_commands+=("/squad $worker_role")
  else
    pane_labels+=("${worker_role}-${i}")
    pane_commands+=("/squad $worker_role ${worker_role}-${i}")
  fi
done
pane_labels+=("$inspector_role")
pane_commands+=("/squad $inspector_role")

build_manager_prompt "$prompt_file" "$project_name" "$workspace_dir" "$task_file"
build_inspector_prompt "$inspector_prompt_file" "$project_name" "$workspace_dir" "$task_file" "$inspector_prompt_source"
build_run_summary "$summary_file"
build_terminal_map "$terminal_map_file"

if (( dry_run == 1 )); then
  echo "Dry run complete."
  echo "Config root: $source_project_dir"
  echo "Workspace root: $workspace_dir"
  echo "Manager prompt: $prompt_file"
  echo "Inspector prompt: $inspector_prompt_file"
  echo "Run summary: $summary_file"
  echo "Terminal map: $terminal_map_file"
  exit 0
fi

require_cmd squad
require_cmd "$claude_command"
require_cmd tmux

if (( no_setup == 0 )); then
  echo "[1/6] Refreshing Claude /squad command"
  squad setup claude
else
  echo "[1/6] Skipping squad setup claude (--no-setup)"
fi

echo "[2/6] Initializing squad workspace"
(
  cd "$workspace_dir"
  squad init "${init_args[@]}"
)

if tmux has-session -t "$session_name" 2>/dev/null; then
  if (( reuse_session == 0 )); then
    echo "Error: tmux session already exists: $session_name" >&2
    echo "Use --reuse-session or run: tmux kill-session -t \"$session_name\"" >&2
    exit 1
  fi

  echo "[3/6] Reusing existing tmux session: $session_name"
  echo "Generated prompt: $prompt_file"
  if (( no_attach == 0 )); then
    if [[ -n "${TMUX:-}" ]]; then
      tmux switch-client -t "$session_name"
    else
      tmux attach -t "$session_name"
    fi
  fi
  exit 0
fi

echo "[3/6] Creating tmux session"
start_cmd="cd $(shell_escape "$workspace_dir") && exec $claude_launch_command"
tmux new-session -d -s "$session_name" -n squad "$start_cmd"
for ((i = 1; i < ${#pane_labels[@]}; i++)); do
  tmux split-window -t "$session_name":0 "$start_cmd"
done
tmux select-layout -t "$session_name":0 tiled

for i in "${!pane_labels[@]}"; do
  tmux select-pane -t "$session_name":0."$i" -T "${pane_labels[$i]}"
done

pane_command_aliases=()
while IFS= read -r alias; do
  pane_command_aliases+=("$alias")
done < <(pane_command_candidates "$claude_command")
for i in "${!pane_labels[@]}"; do
  wait_for_pane_command "$session_name":0."$i" 30 "${pane_command_aliases[@]}"
done

echo "[4/6] Sending squad commands"
for i in "${!pane_commands[@]}"; do
  send_tmux_text "$session_name":0."$i" "${pane_commands[$i]}"
done

echo "[5/6] Waiting for agents to join squad"
wait_for_agent_count "$workspace_dir" "${#pane_commands[@]}" 90

echo "[6/6] Sending manager and inspector prompts"
send_tmux_text "$session_name":0.0 "$(cat "$prompt_file")"
send_tmux_text "$session_name":0."$((${#pane_labels[@]} - 1))" "$(cat "$inspector_prompt_file")"

echo "Ready."
echo "Config root: $source_project_dir"
echo "Workspace root: $workspace_dir"
echo "tmux session: $session_name"
echo "Manager prompt: $prompt_file"
echo "Inspector prompt: $inspector_prompt_file"
echo "Run summary: $summary_file"
echo "Terminal map: $terminal_map_file"

if (( no_attach == 0 )); then
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$session_name"
  else
    tmux attach -t "$session_name"
  fi
fi
