---
name: paperclip-claude-sync
description: >
  Analyze both paperclip-claude (fork) and paperclipai/paperclip (upstream) to find
  upstream improvements that can be safely adopted without affecting fork customizations.
  First maps what the fork has customized and why, then analyzes upstream changes, then
  cross-references to find improvements that don't touch customized areas. Produces a
  detailed recommendation report. Never modifies fork files directly — all output goes
  to a separate workspace. Use this skill whenever the user wants to check what's new
  upstream, sync the fork, find adoptable improvements, or understand what the original
  repo has been doing. Triggers: "paperclip 업데이트", "upstream 싱크", "paperclip-claude
  최신화", "원본 변경사항 확인", "fork 동기화", "sync upstream", "check upstream changes",
  "update from upstream", "upstream에 뭐 바뀌었어", "원본에서 가져올 거 있어", "개선사항 확인",
  "what changed upstream", "포크 동기화", "업스트림 확인".
---

# Paperclip Claude Sync

Find upstream improvements that are safe to adopt in paperclip-claude — by analyzing both sides first.

## Execution Model

This skill runs as a **subagent in a separate session**. When triggered, spawn a new agent to perform the full analysis. The subagent does all the heavy lifting (fetch, diff, analysis, report generation) and returns the finished report. The parent session then presents it to the user.

### How to invoke

When this skill triggers, do the following:

1. **Spawn a subagent** using the Agent tool with this prompt structure:

   ```
   You are running the paperclip-claude-sync skill. Your job is to analyze the
   paperclip-claude fork and the paperclipai/paperclip upstream repo, then produce
   a sync report with improvement recommendations.

   Read the full skill instructions at: <skill-dir>/SKILL.md (the "Analysis Workflow" section)
   Read the helper script at: <skill-dir>/scripts/analyze_upstream.sh
   Read the report template at: <skill-dir>/assets/report-template.md

   Fork root: <$FORK_ROOT>
   Workspace: <$FORK_ROOT>/../paperclip-claude-sync-workspace/

   Execute Phases 1 through 5 of the Analysis Workflow. Save all outputs to the
   workspace directory. The final deliverable is sync-report.md in the workspace.

   CRITICAL: paperclip-claude is READ-ONLY. Never Write or Edit any file inside
   the fork directory. All output goes to the workspace only.
   ```

2. **Wait for the subagent to complete.** It will produce:
   - `paperclip-claude-sync-workspace/sync-report.md` — the full report
   - `paperclip-claude-sync-workspace/fork-customization-map.md` — fork analysis
   - `paperclip-claude-sync-workspace/classification.tsv` — file classifications
   - Various supporting files

3. **Read `sync-report.md`** and present the key findings to the user:
   - Fork customization summary (brief)
   - Upstream activity summary (brief)
   - Recommended improvements (full detail)
   - Do-Not-Touch list (if any)

4. **Phase 6 onward** (User Approval, Output Generation, Verification) happens in the parent session interactively with the user.

### Why a separate session

The analysis involves reading dozens of files across both repos, running git operations, and cross-referencing large diffs. Running this in a subagent:
- Keeps the parent conversation clean — the user sees the final report, not the analysis noise
- Protects the parent context window from being consumed by raw diffs and file reads
- Allows the analysis to run in the background if desired

---

## The Golden Rule

**paperclip-claude is read-only.** The subagent may `Read` any file in the fork for analysis, but must never `Write`, `Edit`, or delete any fork file. All output goes to the workspace directory. This applies to both the subagent and the parent session.

---

## Analysis Workflow (executed by the subagent)

### Phase 1: Preparation

1. **Identify paths.** `$FORK_ROOT` is the paperclip-claude directory. `$WORKSPACE` is the sibling workspace directory.

2. **Create workspace.** `mkdir -p $WORKSPACE`. If it exists from a prior run, clear it for a fresh analysis.

3. **Fetch upstream.**
   ```bash
   bash "<skill-dir>/scripts/analyze_upstream.sh" fetch "$FORK_ROOT"
   ```

4. **Find the merge-base.** The common ancestor between `HEAD` and `upstream/master`.

### Phase 2: Fork Analysis — Understand What Was Customized

Before looking at upstream, map out what paperclip-claude has changed from the original.

1. **Get the fork's diff from merge-base.**
   ```bash
   git diff --stat <merge-base> HEAD
   ```

2. **For each modified file, understand the customization.** Read the file and the diff to determine:
   - **What was changed**: Added features? Modified behavior? Config adjustments?
   - **Why it was changed**: Commit messages, inline comments, fork philosophy
   - **How deep the change is**: Surface-level (config values, UI text) vs structural (rewritten logic)

3. **Build the Fork Customization Map.** Save to `$WORKSPACE/fork-customization-map.md`:

   ```markdown
   ## Fork Customization Map

   ### Structural Changes (high-risk overlap zones)
   - `ui/src/pages/Settings.tsx` — Removed OpenClaw invites, added project path config
   - `server/src/services/billing.ts` — Stripped to Claude Code subscription-only

   ### Feature Additions (fork-only)
   - `skills/paperclip-claude-sync/` — Not in upstream
   - `.claude/skills/design-guide/` — Fork-specific design system

   ### Config / Branding Changes
   - `package.json` — Name changed to paperclip-claude

   ### Untouched Areas
   - `packages/db/` — No fork modifications
   - `packages/shared/` — No fork modifications
   - `cli/` — No fork modifications
   ```

### Phase 3: Upstream Analysis — Understand What Changed

1. **Run the diff script.**
   ```bash
   bash "<skill-dir>/scripts/analyze_upstream.sh" diff "$FORK_ROOT"
   ```

2. **Read upstream commit log.** Group commits by theme:
   - PR merge commits (patterns like "Merge pull request #NNN")
   - Feature prefixes (feat:, fix:, chore:)
   - Issue references (PAP-XXXX, PAPA-XX)

3. **For significant changes, read the actual code.** Don't just trust commit messages:
   - `git show upstream/master:<filepath>` — upstream version
   - `git show <merge-base>:<filepath>` — base version
   - Understand what the change actually does

4. **Build Upstream Changes Summary** grouped by theme.

### Phase 4: Cross-Analysis — Find Safe Improvements

Cross-reference each upstream change against the Fork Customization Map:

| Upstream Change | Fork Status | Verdict |
|----------------|-------------|---------|
| Change in untouched area | Fork never modified | **Safe to adopt** |
| Change in config-only area | Fork changed surface values | **Review needed** |
| Change in structurally customized area | Fork rewrote logic | **Conflict** |
| New file added upstream | Doesn't exist in fork | **Safe to adopt** |
| File deleted upstream | Fork still uses it | **Review needed** |

Assess **value** with the fork's identity in mind. paperclip-claude is a **Claude Code-only** fork — it stripped multi-provider/billing logic and focuses on Claude Code as the sole adapter. Use this context when ranking:

- **High value — prioritize these**:
  - Claude Code adapter improvements (`packages/adapters/claude-local/`) — this IS the fork's runtime
  - Claude Code skill system changes (`skills/`, company-skills service) — core workflow
  - Security fixes and auth improvements — always relevant
  - Bug fixes in areas the fork uses (heartbeat, issues, inbox, agents)
  - DB migrations and schema changes — fork shares the same data model
  - Shared package updates (`packages/shared/`) — types, validators, constants used everywhere

- **Medium value — recommend if safe**:
  - UI improvements in non-customized areas — better UX for fork users too
  - Test additions — more coverage is always good
  - DX improvements (dev tooling, docs, CI)
  - New features that work independently of removed systems

- **Low value — mention but don't push**:
  - Multi-adapter features (Codex, other providers) — fork removed these
  - Billing/subscription features — fork has its own model
  - Features only relevant to self-hosted/enterprise setups the fork doesn't target

- **Also recommend if generally useful**: upstream changes that aren't Claude Code-specific but improve stability, performance, or code quality in shared infrastructure (server core, DB layer, shared utils). These benefit any fork regardless of specialization.

### Phase 5: Generate Report

Generate `$WORKSPACE/sync-report.md` using the template in `assets/report-template.md`. The report must contain:

#### 1. Fork Customization Summary
Overview of what paperclip-claude customized and the fork philosophy.

#### 2. Upstream Activity Summary
Readable briefing of what the original repo has been doing — not a file list.

#### 3. Recommended Improvements (the main section)
Grouped by theme:

```markdown
### [Theme Name] — [Adopt / Consider / Skip]
**Priority**: High / Medium / Low
**Impact area**: Which parts of the codebase
**Files**: N files (classification)

**What upstream did**: Plain-language explanation
**Why it matters**: User/developer impact
**Fork safety**: Why this doesn't affect customizations
**Adoption notes**: Migration steps, things to test

**Files included**:
- `path/to/file.ts` (Safe) — summary
```

#### 4. Do-Not-Touch List
Upstream changes overlapping with fork customizations:
- What upstream changed
- What the fork customized
- Why adopting would break things

#### 5. Upstream Commit Log
Raw log for reference.

---

## Post-Report Phases (executed in parent session)

### Phase 6: User Approval

Present the report and walk through recommendations:
- **Approve** theme/item — include in output
- **Skip** theme/item — exclude
- **Ask for detail** — show actual diff or upstream code

No files generated until approval completes.

### Phase 7: Produce Approved Output

For each approved item:
- Copy upstream file to `$WORKSPACE/approved/<relative-path>`
- Generate patch at `$WORKSPACE/patches/<relative-path>.patch`

```
paperclip-claude-sync-workspace/
├── sync-report.md              # Full analysis report
├── fork-customization-map.md   # Fork analysis
├── approved/                   # Ready-to-apply files
└── patches/                    # Unified diff patches
```

### Phase 8: Verification

1. **List produced files** with summaries.
2. **Verify fork integrity** — `git status --porcelain` must show no modifications to existing fork files.
3. **Application instructions**:
   ```bash
   cp -r paperclip-claude-sync-workspace/approved/* .
   # or
   git apply paperclip-claude-sync-workspace/patches/**/*.patch
   ```

---

## Edge Cases

- **New upstream files**: Always Safe.
- **Deleted upstream files**: Flag in report with dependency analysis.
- **Binary files**: Manual review only.
- **No changes**: Report "in sync" and exit.
- **100+ files**: Summarize by directory first.
- **Unclear customization**: Default to Review, not Safe.

## What This Skill Does NOT Do

- Run `git merge` or `git rebase`
- Push, pull, or create branches
- Resolve conflicts — only reports them
- Modify any file in the fork, ever

## Scripts

`scripts/analyze_upstream.sh` — subcommands: `fetch`, `diff`, `verify`

## Assets

`assets/report-template.md` — Markdown template for the sync report
