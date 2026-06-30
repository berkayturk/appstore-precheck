# AGENTS.md

Cross-tool instructions for any coding agent working in or consuming this repository.
This file follows the [agents.md](https://agents.md) convention and is read by Codex, Cursor,
Gemini CLI, GitHub Copilot, and others as always-on context.

## What this repo is

`appstore-precheck` is a single **Agent Skill** (open standard: [agentskills.io](https://agentskills.io))
that runs a read-only, pre-submission check for an iOS app before App Store review. The skill
lives at [`skills/appstore-precheck/`](skills/appstore-precheck/); its scanner,
[`scripts/scan.sh`](skills/appstore-precheck/scripts/scan.sh), is portable Bash and can be run by
any agent or by hand. Phase 4 adds Pierre's 22-check semantic deep review (see
[`references/pierre-deep-review.md`](skills/appstore-precheck/references/pierre-deep-review.md)).

## Using the skill in your project

The same `SKILL.md` is consumed natively by Claude Code, Claude API/apps, OpenAI Codex, Cursor,
and Gemini CLI, with no per-tool conversion. They differ only in which directory they scan:

| Host | Skill directory it scans |
|------|--------------------------|
| Claude Code | `.claude/skills/<name>/` (project), `~/.claude/skills/` (user) |
| OpenAI Codex | `.agents/skills/<name>/` (project), `~/.agents/skills/` (user) |
| Cursor | `.agents/skills/`, `.cursor/skills/`, also reads `.claude/skills/` |
| Gemini CLI | `.agents/skills/`, `.gemini/skills/` |

Run `./install.sh` to copy the skill into both `.claude/skills/` and `.agents/skills/` of the
current project (covers every host above), or `./install.sh <host> <project|user>` for a single
host. Claude Code users can instead install it as a plugin (see the README).

## The hard rule

**Before any App Store submission, run the precheck and do not upload without a GREEN result.**

```bash
bash skills/appstore-precheck/scripts/scan.sh   # or .agents/skills/appstore-precheck/scripts/scan.sh once installed
```

Then follow [`references/methodology.md`](skills/appstore-precheck/references/methodology.md).
A FAIL means submission is blocked; 5+ WARN means get explicit human confirmation first.
Phase 4 `REVIEW-FINDING` lines are advisory — they do not block the token.

## Contributing to this repo

- `scripts/scan.sh` is the engine; keep it portable POSIX-ish Bash, forward-slash paths only.
- Keep `SKILL.md` under 500 lines; push detail into `references/`.
- After changing the scanner or manifests, run `npm test` (or `bash tests/run.sh`) and
  `claude plugin validate .`.
- Do not commit secrets. The App Store Connect API key is provided at runtime via env and
  deleted immediately after use; `.gitignore` blocks `*asc-key*.json` and `.env`.
