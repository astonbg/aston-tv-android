# Contributing to Aston TV

## Roles and integration
GitHub is the shared record for ChatGPT/Codex and Claude Code. There is no automatic agent-to-agent bridge configured by these files. Launch each tool separately in its own checkout.

ChatGPT/Codex normally handles Android, player lifecycle, gateway/API contracts, tests and builds. Claude normally handles TV 7.1 design, touch UX and cross-review. These are proposed roles; an issue's explicit claim controls ownership. astonbg is the human integrator. Tools are not GitHub users and are not assigned fictitious accounts.

## Start without conflicts
1. Fetch origin and inspect status, remote branches, open issues and PRs. Preserve any existing local changes.
2. Read AGENTS.md and the roadmap. Resolve issue #1 before new overlapping platform implementation; codex/iphone-recovery already contains substantial work.
3. Post an issue claim with the fields below; re-read for competing claims. One issue has one implementation writer at a time.
4. Create a unique branch from the agreed base SHA in a separate worktree or clone. Never share a working directory between concurrent agents.
5. Push only your branch and open a draft PR early. A reviewer reports findings; the branch owner applies fixes.
6. Fetch before pushing. If the remote branch changed unexpectedly, stop dependent edits and arrange a handoff. Never use force to win a race.
7. Integrator merges reviewed PRs sequentially, then dependent branches merge the latest origin/main and rerun affected checks. Do not rebase a published/shared branch.
8. Release the issue claim with a handoff, including unresolved work.

Example commands after claiming issue 2 (choose a unique destination and branch if these already exist):

```sh
git fetch origin
git status --short
git worktree add ../aston-codex-fullscreen -b codex/2-fullscreen origin/main
git -C ../aston-codex-fullscreen status --short --branch
```

Claude uses another checkout and branch, for example claude/3-tv71-design. Use the agreed baseline SHA instead of origin/main if issue #1 specifies one. Do not reuse codex/iphone-recovery as a new agent's workspace.

Claim template:

```text
Status: CLAIMED
Tool/session: <human-readable unique session>
Issue: #<number>
Branch: <unique branch>
Base SHA: <commit>
Owned files: <explicit paths>
Dependencies / overlapping claims: <links or none>
Next handoff: <deliverable>
```

Claims are advisory, not a distributed lock. For simultaneous claims the integrator chooses a writer; other sessions may continue read-only review. Stale claims require contact/handoff, not unilateral takeover.

## Build commands grounded in current main
Android prerequisites: JDK 17, Gradle 8.10.2 and Android SDK platform 35/build-tools 35.0.0; set your local SDK path through your environment or untracked local.properties. No Gradle wrapper is checked into the inspected main; do not suggest ./gradlew until a wrapper is deliberately added.

```sh
# Root Java Android target:
gradle --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest
# Separate Kotlin Mobile 7.1 target, run from repository root:
gradle -p mobile71 --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest
```

Outputs are app/build/outputs/apk/debug/app-debug.apk and mobile71/app/build/outputs/apk/debug/app-debug.apk respectively. Test tasks on main may report NO-SOURCE; this is not regression coverage. Run instrumentation on a configured emulator/device when the selected baseline includes tests.

iOS requires macOS, Xcode and XcodeGen. Match the existing target; these commands build unsigned device bundles, not installable signed distribution:

```sh
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/AstonTV.xcodeproj -scheme AstonTV -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodegen generate --spec ios-mobile5/project.yml
xcodebuild -project ios-mobile5/AstonMobile5.xcodeproj -scheme AstonMobile5 -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

For release packaging/icon generation use the relevant workflow. Re-check commands and package IDs after recovery integration. Do not run live gateway tests merely because a build can reach the network.

## Review and merge
PRs need an issue, owner, scoped diff, exact base/test SHA, relevant test evidence and known limitations. User-facing layout changes need before/after evidence for portrait and landscape. Cross-review should check playback, state, security and both platform implications.

Branch protection and required checks must be configured in GitHub; Markdown does not enforce them. Their configuration has not been verified or changed by this setup. Issue #6 tracks PR checks, protection and removal of the existing APK bot's direct main push. Do not enable a required check until it exists and succeeds on the intended PRs. Do not auto-merge.

No generated APK/IPA, secrets or credentials in new source commits. Upload test binaries as workflow artifacts with SHA, version, package ID and signing type. Existing tracked releases are historical and are not proof of a current build.

## Instruction references
AGENTS.md follows the [OpenAI repository instruction convention](https://learn.chatgpt.com/docs/agent-configuration/agents-md). CLAUDE.md imports the shared rules using [Claude Code's documented file imports](https://code.claude.com/docs/en/memory#import-additional-files).
