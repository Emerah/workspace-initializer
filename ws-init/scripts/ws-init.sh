#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: ws-init.sh --path WORKSPACE_ROOT [--repo NAME] [--visibility private|public]
                  [--allowed-root PATH]...
USAGE
}

fail() {
  printf 'ws-init: validation failed: %s\n' "$1" >&2
  exit 1
}

handle_initialization_failure() {
  failure_status="$1"
  trap - ERR
  set +e

  printf '\nws-init: initialization failed\n' >&2
  printf 'Failed phase: %s\n' "$current_phase" >&2
  printf 'Completed phases: %s\n' "$completed_phases" >&2
  printf 'Manual recovery (no rollback was performed):\n' >&2

  if [[ "$current_phase" == "Managed file creation" ]]; then
    printf '  # Repair or complete the Managed files under %q, then run:\n' "$workspace_root" >&2
  fi
  if [[ "$current_phase" == "Staged content inspection" && "${staged_secret_count:-0}" -gt 0 ]]; then
    printf 'Obvious secrets remain staged:\n' >&2
    for staged_secret_path in "${staged_secret_paths[@]}"; do
      printf '  %s\n' "$staged_secret_path" >&2
      printf '  git -C %q rm --cached -- %q\n' "$workspace_root" "$staged_secret_path" >&2
    done
    printf '  # Review .gitignore and remove or ignore each secret before restaging.\n' >&2
    printf '  # After the staged content is safe, restage and continue initialization.\n' >&2
  fi

  if ((recovery_step <= 2)); then
    printf '  git -C %q init -b main\n' "$workspace_root" >&2
  fi
  if ((recovery_step <= 3)); then
    printf '  git -C %q add --all\n' "$workspace_root" >&2
  fi
  if ((recovery_step <= 4)); then
    printf '  git -C %q commit -m %q\n' "$workspace_root" "chore: initialize workspace" >&2
  fi
  if ((recovery_step <= 5)); then
    printf '  gh repo view %q >/dev/null 2>&1 || gh repo create %q %q\n' \
      "$github_login/$repository_name" "$github_login/$repository_name" "--$visibility" >&2
  fi
  if ((recovery_step <= 6)); then
    printf '  git -C %q remote get-url origin >/dev/null 2>&1 || git -C %q remote add origin %q\n' \
      "$workspace_root" "$workspace_root" "https://github.com/$github_login/$repository_name.git" >&2
  fi
  if ((recovery_step <= 7)); then
    printf '  git -C %q push -u origin main\n' "$workspace_root" >&2
  fi

  exit "$failure_status"
}

configure_initialization_phase() {
  local next_phase="$1"
  local next_recovery_step="$2"

  if [[ -n "$current_phase" ]]; then
    completed_phases="$completed_phases, $current_phase"
  fi
  current_phase="$next_phase"
  recovery_step="$next_recovery_step"
}

canonical_existing_directory() {
  (cd "$1" 2>/dev/null && pwd -P)
}

workspace_path=""
repository_name=""
visibility="private"
additional_allowed_roots=()
additional_allowed_root_count=0

while (($# > 0)); do
  case "$1" in
    --path|--repo|--visibility|--allowed-root)
      (($# >= 2)) || fail "$1 requires a value"
      argument="$1"
      value="$2"
      shift 2
      case "$argument" in
        --path) workspace_path="$value" ;;
        --repo) repository_name="$value" ;;
        --visibility) visibility="$value" ;;
        --allowed-root)
          additional_allowed_roots+=("$value")
          additional_allowed_root_count=$((additional_allowed_root_count + 1))
          ;;
      esac
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$workspace_path" ]] || fail "--path is required"

if [[ ( -e "$workspace_path" || -L "$workspace_path" ) && ! -d "$workspace_path" ]]; then
  fail "Workspace root must be a directory"
fi

if [[ -d "$workspace_path" ]]; then
  workspace_root="$(canonical_existing_directory "$workspace_path")" || fail "Workspace root is not accessible"
else
  workspace_parent="$(dirname "$workspace_path")"
  canonical_parent="$(canonical_existing_directory "$workspace_parent")" || fail "the Workspace root's immediate parent must exist"
  workspace_root="$canonical_parent/$(basename "$workspace_path")"
fi

workspace_name="$(basename "$workspace_root")"

canonical_home="$(canonical_existing_directory "$HOME")" || fail "user home is not accessible"
home_parent="$(dirname "$canonical_home")"
case "$workspace_root" in
  /|"$canonical_home"|"$home_parent") fail "forbidden broad Workspace root: $workspace_root" ;;
esac

canonical_allowed_roots=()
for default_allowed_root in "$HOME/Desktop" "$HOME/Developer" "$HOME/Documents"; do
  [[ -d "$default_allowed_root" ]] || continue
  canonical_default_allowed_root="$(canonical_existing_directory "$default_allowed_root")" || continue
  canonical_allowed_roots+=("$canonical_default_allowed_root")
done

if ((additional_allowed_root_count > 0)); then
  for additional_allowed_root in "${additional_allowed_roots[@]}"; do
    [[ -d "$additional_allowed_root" ]] || fail "Allowed root must exist: $additional_allowed_root"
    canonical_additional_root="$(canonical_existing_directory "$additional_allowed_root")" || fail "Allowed root is not accessible: $additional_allowed_root"
    case "$canonical_additional_root" in
      /|"$canonical_home"|"$home_parent") fail "forbidden broad Allowed root: $additional_allowed_root" ;;
    esac
    canonical_allowed_roots+=("$canonical_additional_root")
  done
fi

workspace_is_allowed="no"
for canonical_allowed_root in "${canonical_allowed_roots[@]}"; do
  case "$workspace_root" in
    "$canonical_allowed_root"/*) workspace_is_allowed="yes" ;;
  esac
done
[[ "$workspace_is_allowed" == "yes" ]] || fail "Workspace root must be a strict descendant of an Allowed root"

ancestor_directory="$(dirname "$workspace_root")"
while :; do
  [[ ! -e "$ancestor_directory/.git" ]] || fail "Workspace root is inside an ancestor Git worktree"
  [[ "$ancestor_directory" != "/" ]] || break
  ancestor_directory="$(dirname "$ancestor_directory")"
done

[[ "$(uname -s)" == "Darwin" ]] || fail "version 1 supports macOS only"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is required"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated"

[[ ! -e "$workspace_root/.git" && ! -L "$workspace_root/.git" ]] || fail "Workspace root already contains Git metadata"

[[ "$visibility" == "private" || "$visibility" == "public" ]] || fail "--visibility must be private or public"
[[ -n "$repository_name" ]] || repository_name="$workspace_name"
[[ "$repository_name" =~ ^[A-Za-z0-9._-]{1,100}$ && "$repository_name" != "." && "$repository_name" != ".." ]] || \
  fail "--repo must be a valid GitHub repository name"

for managed_file in .gitignore README.md LICENSE.md; do
  if [[ -L "$workspace_root/$managed_file" || ( -e "$workspace_root/$managed_file" && ! -f "$workspace_root/$managed_file" ) ]]; then
    fail "Invalid Managed file path: $managed_file"
  fi
done

github_login="$(gh api user --jq .login)" || fail "could not determine the authenticated GitHub login"
[[ -n "$github_login" && "$github_login" != "null" ]] || fail "could not determine the authenticated GitHub login"

repository_lookup_output=""
if repository_lookup_output="$(gh api "repos/$github_login/$repository_name" 2>&1)"; then
  fail "GitHub repository already exists: $github_login/$repository_name"
elif [[ "$repository_lookup_output" != *"(HTTP 404)"* ]]; then
  fail "could not confirm GitHub repository availability: $github_login/$repository_name"
fi

if [[ ! -e "$workspace_root/LICENSE.md" ]]; then
  github_display_name="$(gh api user --jq .name)" || fail "could not determine the GitHub display name"
  if [[ -z "$github_display_name" || "$github_display_name" == "null" ]]; then
    github_display_name="$github_login"
  fi

  license_template="$(gh api licenses/mit --jq .body)" || fail "could not fetch GitHub's MIT license template"
  [[ -n "$license_template" ]] || fail "GitHub returned an empty MIT license template"
fi

completed_phases="validation"
current_phase=""
recovery_step=1
configure_initialization_phase "Managed file creation" 2
trap 'handle_initialization_failure "$?"' ERR
mkdir -p "$workspace_root"

if [[ ! -e "$workspace_root/.gitignore" ]]; then
  cat > "$workspace_root/.gitignore" <<'GITIGNORE'
# General build output
build/
dist/
out/

# Swift and Swift Package Manager
.build/
.swiftpm/
Packages/

# Xcode
DerivedData/
*.xcuserstate
xcuserdata/

# VS Code
.vscode/

# Node
node_modules/
.npm/
.yarn/
coverage/

# macOS
.DS_Store
.AppleDouble

# Caches and logs
.cache/
*.log
logs/

# Private generated files
.env
.env.*
*.local
.tmp/
GITIGNORE
fi

if [[ ! -e "$workspace_root/README.md" ]]; then
  printf '# %s\n' "$workspace_name" > "$workspace_root/README.md"
fi

if [[ ! -e "$workspace_root/LICENSE.md" ]]; then
  creation_year="$(date +%Y)"
  license_text="${license_template//\[year\]/$creation_year}"
  license_text="${license_text//\[fullname\]/$github_display_name}"
  printf '%s\n' "$license_text" > "$workspace_root/LICENSE.md"
fi
configure_initialization_phase "Git initialization" 2
git -C "$workspace_root" init -b main

configure_initialization_phase "Git staging" 3
git -C "$workspace_root" add --all

configure_initialization_phase "Staged content inspection" 3
staged_file_list="$(mktemp "${TMPDIR:-/tmp}/ws-init-staged.XXXXXX")"
staged_blob_file="$(mktemp "${TMPDIR:-/tmp}/ws-init-blob.XXXXXX")"
trap 'rm -f "$staged_file_list" "$staged_blob_file"' EXIT
git -C "$workspace_root" diff --cached --name-only --diff-filter=ACMR -z > "$staged_file_list"

staged_secret_paths=()
staged_secret_count=0
while IFS= read -r -d '' staged_file; do
  staged_file_is_secret="no"
  case "$staged_file" in
    *.pem|*.key|id_rsa|*/id_rsa|id_dsa|*/id_dsa|id_ecdsa|*/id_ecdsa|id_ed25519|*/id_ed25519|credentials|*/credentials|credentials.*|*/credentials.*|secrets.*|*/secrets.*)
      staged_file_is_secret="yes"
      ;;
  esac
  git -C "$workspace_root" show ":./$staged_file" > "$staged_blob_file"
  if grep -Eiq -- '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----|(AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|GH_TOKEN|API_KEY|SECRET_KEY|PRIVATE_KEY)[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}' "$staged_blob_file"; then
    staged_file_is_secret="yes"
  fi

  if [[ "$staged_file_is_secret" == "yes" ]]; then
    staged_secret_paths+=("$staged_file")
    staged_secret_count=$((staged_secret_count + 1))
  fi
done < "$staged_file_list"

if ((staged_secret_count > 0)); then
  handle_initialization_failure 1
fi

printf 'Staged files:\n'
git -C "$workspace_root" diff --cached --name-only

configure_initialization_phase "Initial commit" 4
git -C "$workspace_root" commit -m "chore: initialize workspace"

configure_initialization_phase "GitHub repository creation" 5
gh repo create "$github_login/$repository_name" "--$visibility"

configure_initialization_phase "origin remote configuration" 6
git -C "$workspace_root" remote add origin "https://github.com/$github_login/$repository_name.git"

configure_initialization_phase "Initial push" 7
git -C "$workspace_root" push -u origin main
configure_initialization_phase "" 8

printf 'Workspace synchronized: %s/%s\n' "$github_login" "$repository_name"
