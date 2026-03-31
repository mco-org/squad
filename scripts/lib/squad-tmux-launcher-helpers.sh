#!/usr/bin/env bash

shell_escape() {
  printf '%q' "$1"
}

shell_join() {
  local joined=""
  local item=""
  for item in "$@"; do
    if [[ -n "$joined" ]]; then
      joined+=" "
    fi
    joined+="$(shell_escape "$item")"
  done
  printf '%s' "$joined"
}

pane_command_candidates() {
  local command_name="$1"
  local resolved=""
  local current=""
  local target=""
  local shebang=""
  local interpreter=""
  local candidates=()

  add_candidate() {
    local candidate="$1"
    local existing=""
    local found=0
    [[ -n "$candidate" ]] || return 0
    if (( ${#candidates[@]} > 0 )); then
      for existing in "${candidates[@]}"; do
        if [[ "$existing" == "$candidate" ]]; then
          found=1
          break
        fi
      done
    fi
    if (( found == 1 )); then
      return 0
    fi
    candidates+=("$candidate")
  }

  add_candidate "$(basename "$command_name")"

  if command -v "$command_name" >/dev/null 2>&1; then
    resolved="$(command -v "$command_name")"
  elif [[ -e "$command_name" ]]; then
    resolved="$command_name"
  fi

  if [[ -n "$resolved" ]]; then
    add_candidate "$(basename "$resolved")"
    current="$resolved"
    while [[ -L "$current" ]]; do
      target="$(readlink "$current")"
      if [[ "$target" == /* ]]; then
        current="$target"
      else
        current="$(dirname "$current")/$target"
      fi
    done
    add_candidate "$(basename "$current")"

    if [[ -f "$current" ]]; then
      IFS= read -r shebang <"$current" || true
      if [[ "$shebang" == "#!"* ]]; then
        shebang="${shebang#\#!}"
        shebang="${shebang#"${shebang%%[![:space:]]*}"}"
        if [[ "$shebang" == */env\ * ]]; then
          interpreter="${shebang##*/env }"
          interpreter="${interpreter%% *}"
        else
          interpreter="${shebang%% *}"
          interpreter="$(basename "$interpreter")"
        fi
        add_candidate "$interpreter"
      fi
    fi
  fi

  if (( ${#candidates[@]} > 0 )); then
    printf '%s\n' "${candidates[@]}"
  fi
}

is_truthy() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

slugify_path_component() {
  local value="$1"
  value="$(printf '%s' "$value" | tr ' /:@' '----')"
  value="${value//[^A-Za-z0-9._-]/-}"
  printf '%s' "${value:-worktree}"
}

copy_array_or_empty() {
  local target_name="$1"
  local source_name="$2"

  eval "$target_name=()"
  if ! declare -p "$source_name" >/dev/null 2>&1; then
    return 0
  fi

  eval 'if ((${#'"$source_name"'[@]} > 0)); then '"$target_name"'=("${'"$source_name"'[@]}"); fi'
}

repo_worktree_location_slug() {
  local repo_root="$1"
  local normalized="${repo_root#/}"
  printf '%s' "$(slugify_path_component "$normalized")"
}

expand_path_from_base() {
  local path="$1"
  local base_dir="$2"

  if [[ "$path" == "~" ]]; then
    path="$HOME"
  elif [[ "${path:0:2}" == "~/" ]]; then
    path="$HOME/${path:2}"
  elif [[ "$path" != /* ]]; then
    path="$base_dir/$path"
  fi

  printf '%s' "$path"
}

resolve_worktree_root() {
  local repo_root="$1"
  local location="$2"
  expand_path_from_base "${location:-.worktrees}" "$repo_root"
}

resolve_worktree_path() {
  local repo_root="$1"
  local location="$2"
  local leaf_name="$3"
  local root=""
  root="$(resolve_worktree_root "$repo_root" "$location")"
  if [[ -n "$leaf_name" ]]; then
    printf '%s/%s' "$root" "$leaf_name"
  else
    printf '%s' "$root"
  fi
}

path_is_within() {
  local path="$1"
  local base="$2"
  case "$path" in
    */../*|*/./*|../*|./*|*/..|*/.)
      return 1
      ;;
  esac
  [[ "$path" == "$base" || "$path" == "$base"/* ]]
}

ensure_repo_local_worktree_ignored() {
  local repo_root="$1"
  local path="$2"
  local rel_path=""

  if ! path_is_within "$path" "$repo_root"; then
    return 0
  fi

  if [[ "$path" == "$repo_root" ]]; then
    echo "Error: worktree path cannot be the repository root: $path" >&2
    return 1
  fi

  rel_path="${path#$repo_root/}"
  if git -C "$repo_root" check-ignore -q "$rel_path"; then
    return 0
  fi

  echo "Error: repo-local worktree path is not ignored by git: $rel_path" >&2
  echo "Add an ignore rule for that path or use a worktree location outside the repository." >&2
  return 1
}

find_worktree_path_for_branch() {
  local repo_root="$1"
  local branch_name="$2"
  local line=""
  local current_path=""
  local current_branch=""

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        current_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        if [[ "$current_branch" == "$branch_name" ]]; then
          printf '%s\n' "$current_path"
          return 0
        fi
        ;;
    esac
  done < <(git -C "$repo_root" worktree list --porcelain)

  return 1
}

ensure_git_worktree() {
  local repo_root="$1"
  local requested_path="$2"
  local branch_name="$3"
  local base_ref="$4"
  local dry_run="${5:-0}"
  local existing_branch_path=""
  local current_branch=""
  local requested_common_dir=""
  local repo_common_dir=""

  if [[ -z "$branch_name" ]]; then
    echo "Error: worktree branch name is required" >&2
    return 1
  fi

  existing_branch_path="$(find_worktree_path_for_branch "$repo_root" "$branch_name" || true)"
  if [[ -n "$existing_branch_path" ]]; then
    printf '%s\n' "$existing_branch_path"
    return 0
  fi

  if [[ -f "$requested_path/.git" || -d "$requested_path/.git" ]]; then
    requested_common_dir="$(git -C "$requested_path" rev-parse --git-common-dir 2>/dev/null || true)"
    repo_common_dir="$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$requested_common_dir" && "$requested_common_dir" != /* ]]; then
      requested_common_dir="$requested_path/$requested_common_dir"
    fi
    if [[ -n "$repo_common_dir" && "$repo_common_dir" != /* ]]; then
      repo_common_dir="$repo_root/$repo_common_dir"
    fi
    if [[ -n "$requested_common_dir" && -n "$repo_common_dir" && "$requested_common_dir" != "$repo_common_dir" ]]; then
      echo "Error: requested worktree path belongs to a different repository: $requested_path" >&2
      return 1
    fi

    current_branch="$(git -C "$requested_path" branch --show-current 2>/dev/null || true)"
    if [[ -n "$current_branch" && "$current_branch" != "$branch_name" ]]; then
      echo "Error: requested worktree path already exists on branch '$current_branch': $requested_path" >&2
      return 1
    fi
    printf '%s\n' "$requested_path"
    return 0
  fi

  if [[ -e "$requested_path" && ! -d "$requested_path" ]]; then
    echo "Error: requested worktree path exists and is not a directory: $requested_path" >&2
    return 1
  fi

  if [[ -d "$requested_path" ]]; then
    if [[ -n "$(find "$requested_path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      echo "Error: requested worktree path exists and is not an empty git worktree: $requested_path" >&2
      return 1
    fi
  fi

  if (( dry_run == 1 )); then
    printf '%s\n' "$requested_path"
    return 0
  fi

  mkdir -p "$(dirname "$requested_path")"

  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
    git -C "$repo_root" worktree add "$requested_path" "$branch_name" >/dev/null
  else
    git -C "$repo_root" worktree add "$requested_path" -b "$branch_name" "${base_ref:-HEAD}" >/dev/null
  fi

  printf '%s\n' "$requested_path"
}
