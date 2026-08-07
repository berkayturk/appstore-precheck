# Agent portability

`appstore-precheck` is one **Agent Skill** (the open [agentskills.io](https://agentskills.io)
standard): a single [`SKILL.md`](../skills/appstore-precheck/SKILL.md) plus its scripts and
references. The same skill runs natively across hosts, with **no per-tool conversion**.
Hosts differ only in *which directory they scan* and *how they surface the skill*.

## Who reads what

| Host | Skill directory | Notes |
|------|-----------------|-------|
| **Claude Code** | `.claude/skills/<name>/` (project), `~/.claude/skills/` (user) | Native plugin: `.claude-plugin/` + marketplace; upload-guard hook via `hooks/hooks.json`. |
| **OpenAI Codex** | `.agents/skills/<name>/` (project), `~/.agents/skills/` (user) | Native plugin: reads `.claude-plugin/plugin.json` + `.agents/plugins/marketplace.json`. |
| **Cursor** | `.agents/skills/`, `.cursor/skills/`, also `.claude/skills/` | Native plugin: `.cursor-plugin/` + marketplace; or `install.sh`. |
| **Gemini CLI** | `.agents/skills/`, `.gemini/skills/` | No plugin marketplace; `gemini skills install … --path skills/appstore-precheck`. |
| **Grok Build** | `.grok/skills/`, also `.agents/skills/` and `.claude/skills/` (compat) | Native plugin: `.grok-plugin/` marketplace + plugin; also accepts `.claude-plugin/` equivalents. Hooks get `GROK_PLUGIN_ROOT` (and `CLAUDE_PLUGIN_ROOT` alias). |

[`install.sh`](../install.sh) vendors the skill into `.claude/skills/`, `.agents/skills/`, and
`.grok/skills/` as a fallback. Plugin install paths per host are in the README and
[`publishing-plugins.md`](publishing-plugins.md). A root
[`AGENTS.md`](../AGENTS.md) additionally serves hosts that read always-on context instead of
on-demand skills.

## Why it's portable

- **The engine is plain Bash.** [`scan.sh`](../skills/appstore-precheck/scripts/scan.sh) and
  [`verdict.sh`](../skills/appstore-precheck/scripts/verdict.sh) have no host dependency. Any
  agent can run them, and so can a human in CI or a pre-commit hook.
- **The output is machine-faithful.** `FAIL:` / `WARN:` / `PASS:` lines mean the same thing to
  every host; the Pierre presentation voice is applied only when a human reads the verdict.
- **Detection is convention-over-configuration.** A standard fastlane + Xcode layout needs zero
  config; `.appstore-precheck.json` overrides anything that isn't auto-detected, identically on
  every host.

## Verified

Live, per-host runs (skill discovered → `scan.sh` executed → faithful verdict) are recorded in
[cross-tool-verification.md](cross-tool-verification.md): **Claude Code, Codex CLI, Gemini CLI, and
Cursor** are verified end-to-end. **Grok Build** plugin validate + install (skills + hooks inventory)
is verified; a full headless skill-runtime transcript can be added the same way as the other hosts.
