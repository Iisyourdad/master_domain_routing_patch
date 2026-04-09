#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/coollabsio/coolify.git}"
BASE_REF="${BASE_REF:-upstream/next}"

CONTAINER="${CONTAINER:-coolify}"
DEST_DIR="${DEST_DIR:-/var/www/html}"
PATCHES_FILE="${PATCHES_FILE:-patches.txt}"
RESTART_CONTAINER="${RESTART_CONTAINER:-true}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/apply-patches.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "==> Using temporary workspace: $WORKDIR"
echo "==> Upstream:          $UPSTREAM_URL"
echo "==> Base ref:          $BASE_REF"
echo "==> Container:         $CONTAINER"
echo "==> Dest dir:          $DEST_DIR"
echo "==> Patches file:      $PATCHES_FILE"
echo "==> Restart container: $RESTART_CONTAINER"
echo

docker inspect "$CONTAINER" >/dev/null 2>&1 || {
  echo "Container not found: $CONTAINER"
  exit 1
}

[ -f "$PATCHES_FILE" ] || {
  echo "Patches file not found: $PATCHES_FILE"
  exit 1
}

apply_changed_files() {
  local repo_dir="$1"
  local compare_ref="$2"
  local label="$3"

  local safe_label
  safe_label="$(echo "$label" | sed 's#[^A-Za-z0-9._-]#_#g')"
  local files_dir="$WORKDIR/files_$safe_label"

  rm -rf "$files_dir"
  mkdir -p "$files_dir"

  cd "$repo_dir"

  echo "==> Finding changed files for $label"
  local changed_files
  changed_files="$(git diff --name-only "$BASE_REF...$compare_ref")"

  if [ -z "$changed_files" ]; then
    echo "==> No changed files found for $label, skipping"
    echo
    return 0
  fi

  printf '%s\n' "$changed_files"
  echo

  echo "==> Preparing changed files"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    mkdir -p "$files_dir/$(dirname "$f")"
    cp --parents "$f" "$files_dir/"
  done <<< "$changed_files"

  echo "==> Applying files into container"
  find "$files_dir" -type f | while read -r local_file; do
    rel_path="${local_file#$files_dir/}"
    container_file="$DEST_DIR/$rel_path"
    container_parent="$(dirname "$container_file")"

    echo "==> Processing $rel_path"
    docker exec "$CONTAINER" sh -lc "mkdir -p '$container_parent' && rm -f '$container_file'"
    docker cp "$local_file" "$CONTAINER:$container_file"
  done

  echo "==> Finished: $label"
  echo
}

apply_branch_url() {
  local owner="$1"
  local repo="$2"
  local branch="$3"

  local fork_url="https://github.com/${owner}/${repo}.git"
  local safe_branch
  safe_branch="$(echo "$branch" | sed 's#[^A-Za-z0-9._-]#_#g')"
  local repo_dir="$WORKDIR/repo_branch_$safe_branch"

  echo "=================================================="
  echo "==> Applying branch URL"
  echo "==> Repo:   $fork_url"
  echo "==> Branch: $branch"
  echo "=================================================="

  rm -rf "$repo_dir"
  git clone --quiet "$fork_url" "$repo_dir"
  cd "$repo_dir"

  git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
  git fetch --prune origin
  git fetch --prune upstream

  git checkout -B "$branch" "origin/$branch"

  apply_changed_files "$repo_dir" "$branch" "branch-$branch"
}

apply_pr_url() {
  local owner="$1"
  local repo="$2"
  local pr_number="$3"

  local fork_url="https://github.com/${owner}/${repo}.git"
  local repo_dir="$WORKDIR/repo_pr_${pr_number}"
  local pr_ref="pr-${pr_number}"

  echo "=================================================="
  echo "==> Applying PR URL"
  echo "==> Repo: $fork_url"
  echo "==> PR:   #$pr_number"
  echo "=================================================="

  rm -rf "$repo_dir"
  git clone --quiet "$fork_url" "$repo_dir"
  cd "$repo_dir"

  git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
  git fetch --prune origin
  git fetch --prune upstream

  git fetch origin "pull/${pr_number}/head:refs/remotes/origin/${pr_ref}"

  apply_changed_files "$repo_dir" "origin/${pr_ref}" "pr-${pr_number}"
}

echo "==> Reading patch list"
while IFS= read -r line || [ -n "$line" ]; do
  line="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  [ -z "$line" ] && continue
  [[ "$line" =~ ^# ]] && continue

  if [[ "$line" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/(.+)$ ]]; then
    apply_branch_url "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    continue
  fi

  if [[ "$line" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)$ ]]; then
    apply_pr_url "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    continue
  fi

  echo "Invalid entry in $PATCHES_FILE:"
  echo "  $line"
  echo
  echo "Supported formats:"
  echo "  https://github.com/<owner>/<repo>/tree/<branch>"
  echo "  https://github.com/<owner>/<repo>/pull/<number>"
  exit 1
done < "$PATCHES_FILE"

if [ "$RESTART_CONTAINER" = "true" ]; then
  echo "==> Restarting container: $CONTAINER"
  docker restart "$CONTAINER"
  echo
fi

echo "==> Done"
echo "All patches from $PATCHES_FILE were applied."