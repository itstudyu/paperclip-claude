#!/usr/bin/env bash
# analyze_upstream.sh — Git operations for paperclip-claude-sync skill
# Usage:
#   analyze_upstream.sh fetch <fork-root>
#   analyze_upstream.sh diff  <fork-root> [upstream-branch]
#   analyze_upstream.sh verify <fork-root>
#
# All output goes to paperclip-claude-sync-workspace/ (sibling of fork-root).
# This script NEVER modifies files in <fork-root>.

set -euo pipefail

CMD="${1:-}"
FORK_ROOT="${2:-$(pwd)}"
UPSTREAM_BRANCH="${3:-upstream/master}"

WORKSPACE="$(dirname "$FORK_ROOT")/paperclip-claude-sync-workspace"

die() { echo "ERROR: $*" >&2; exit 1; }

# ── fetch ──────────────────────────────────────────────────────────────
cmd_fetch() {
  cd "$FORK_ROOT"

  # upstream リモートが無ければ追加
  if ! git remote get-url upstream &>/dev/null; then
    echo "Adding upstream remote..."
    git remote add upstream https://github.com/paperclipai/paperclip.git
  fi

  echo "Fetching upstream..."
  git fetch upstream --no-tags --quiet
  echo "Upstream fetched successfully."
  echo "Latest upstream/main: $(git rev-parse --short upstream/main)"
  echo "Current HEAD:         $(git rev-parse --short HEAD)"
}

# ── diff ───────────────────────────────────────────────────────────────
cmd_diff() {
  cd "$FORK_ROOT"
  mkdir -p "$WORKSPACE"

  local merge_base
  merge_base=$(git merge-base HEAD "$UPSTREAM_BRANCH") || die "Cannot find merge-base between HEAD and $UPSTREAM_BRANCH"

  echo "Merge base: $(git rev-parse --short "$merge_base")"
  echo "Upstream:   $(git rev-parse --short "$UPSTREAM_BRANCH")"
  echo "Fork HEAD:  $(git rev-parse --short HEAD)"
  echo ""

  # upstream で変更されたファイル一覧
  local upstream_changes="$WORKSPACE/upstream-changes.txt"
  git diff --name-status "$merge_base" "$UPSTREAM_BRANCH" > "$upstream_changes"

  # fork で変更されたファイル一覧
  local fork_changes="$WORKSPACE/fork-changes.txt"
  git diff --name-status "$merge_base" HEAD > "$fork_changes"

  # 分類結果の出力
  local classification="$WORKSPACE/classification.tsv"
  echo -e "FILE\tUPSTREAM_STATUS\tFORK_STATUS\tCATEGORY" > "$classification"

  # upstream 変更ファイルを1つずつ分類
  while IFS=$'\t' read -r status filepath; do
    # filepath が空の場合はスキップ (rename の場合など)
    [[ -z "$filepath" ]] && continue

    # fork での変更状態を確認
    local fork_status
    fork_status=$(awk -F'\t' -v f="$filepath" '$NF == f {print $1}' "$fork_changes" 2>/dev/null || echo "")

    if [[ -z "$fork_status" ]]; then
      # fork は未修正 → Safe
      echo -e "${filepath}\t${status}\t-\tSafe" >> "$classification"
    else
      # fork も修正している → 重複チェック
      # upstream と fork の変更行範囲を比較
      local upstream_lines fork_lines overlap
      upstream_lines=$(git diff "$merge_base" "$UPSTREAM_BRANCH" -- "$filepath" 2>/dev/null | grep -c '^[+-]' || echo "0")
      fork_lines=$(git diff "$merge_base" HEAD -- "$filepath" 2>/dev/null | grep -c '^[+-]' || echo "0")

      # 行範囲の重複を簡易チェック (diff3 ベース)
      if git merge-tree "$merge_base" HEAD "$UPSTREAM_BRANCH" -- "$filepath" 2>/dev/null | grep -q '<<<<<<<'; then
        echo -e "${filepath}\t${status}\t${fork_status}\tConflict" >> "$classification"
      else
        echo -e "${filepath}\t${status}\t${fork_status}\tReview" >> "$classification"
      fi
    fi
  done < "$upstream_changes"

  # サマリー出力
  local safe_count review_count conflict_count
  safe_count=$(grep -c "Safe$" "$classification" 2>/dev/null || true)
  review_count=$(grep -c "Review$" "$classification" 2>/dev/null || true)
  conflict_count=$(grep -c "Conflict$" "$classification" 2>/dev/null || true)
  safe_count=${safe_count:-0}
  review_count=${review_count:-0}
  conflict_count=${conflict_count:-0}

  echo "=== Classification Summary ==="
  echo "Safe:     $safe_count files"
  echo "Review:   $review_count files"
  echo "Conflict: $conflict_count files"
  echo "Total:    $(( safe_count + review_count + conflict_count )) files"
  echo ""
  echo "Details:  $classification"
  echo "Upstream: $upstream_changes"
  echo "Fork:     $fork_changes"

  # コミットログも保存
  git log --oneline "$merge_base..$UPSTREAM_BRANCH" > "$WORKSPACE/upstream-commits.txt"
  echo "Commits:  $WORKSPACE/upstream-commits.txt"
}

# ── verify ─────────────────────────────────────────────────────────────
cmd_verify() {
  cd "$FORK_ROOT"
  local status
  status=$(git status --porcelain)

  if [[ -z "$status" ]]; then
    echo "VERIFIED: Fork working tree is clean. No files were modified."
    exit 0
  else
    echo "WARNING: Fork working tree has uncommitted changes:"
    echo "$status"
    exit 1
  fi
}

# ── dispatch ───────────────────────────────────────────────────────────
case "$CMD" in
  fetch)  cmd_fetch ;;
  diff)   cmd_diff ;;
  verify) cmd_verify ;;
  *)      die "Unknown command: $CMD. Usage: $0 {fetch|diff|verify} <fork-root> [upstream-branch]" ;;
esac
