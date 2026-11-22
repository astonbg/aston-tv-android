# Starting and handing off work

These prompts use GitHub as shared context; no live ChatGPT-to-Claude connection is implied. Start from a branch containing this setup (or from main once it is merged). The setup branch is codex/collaboration-setup-20261122. Each implementation session creates its own branch after reading the current issue claim.

## Claude Code starting prompt
Work on astonbg/aston-tv-android. Read CLAUDE.md, AGENTS.md, CONTRIBUTING.md and docs/mobile-roadmap.md from the collaboration setup. Inspect open issues/PRs and remote heads before editing. Start with issue #3: claim it with your unique session, branch, base SHA and owned files. Use your own checkout and claude/3-tv71-design branch, based on the current agreed baseline. First deliver docs/design/tv71-mobile.md and a TV 7.1 reference inventory. Preserve existing codex/iphone-recovery work. Do not edit Android player/API/workflow files, push to main or another agent's branch. If original LG/TV6 assets are missing, report the missing input and complete the specification parts supported by repository evidence. Open a draft PR with findings, evidence and questions for the platform owner. Do not claim implementation or review you have not performed.

## ChatGPT/Codex starting prompt
Read AGENTS.md, CONTRIBUTING.md and docs/mobile-roadmap.md. Claim issue #1 in a separate checkout and unique codex/1-mobile-baseline branch. Re-fetch main and codex/iphone-recovery, inspect their divergence, tests and package IDs, and propose the canonical Android/iOS baseline with a scoped integration plan. Preserve both branches. Coordinate with Claude's issue #3 file claim. Then claim issue #6 separately to eliminate CI pushes to main and establish reliable APK validation before tackling issue #2. Report actual evidence and never force-push or merge without the integrator.

## Handoff format
- Issue and status: CLAIMED / REVIEW / BLOCKED / RELEASED
- Writer/session:
- Branch and exact last commit:
- Owned/changed files:
- Completed behavior or document:
- Tests actually run with results:
- Artifact/screenshots:
- Dependencies / missing references:
- Reviewer findings:
- Next action and proposed owner:

The receiving session re-reads the issue, acknowledges the handoff and verifies the branch head before writing. A session ending does not silently transfer its branch to another writer.
