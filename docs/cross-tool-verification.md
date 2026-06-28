# Cross-tool runtime verification

`appstore-precheck` ships one `SKILL.md` (the open [Agent Skills](https://agentskills.io) standard)
that every supported host reads natively. They differ only in the directory they scan.
`install.sh` vendors the skill into both `.claude/skills/` and `.agents/skills/`, covering all hosts.

This document records **real runs** verifying, per host, that the skill is discovered, triggers on
a submission-intent prompt, and actually executes `scripts/scan.sh`.

## Method

A throwaway project was created from the `sample-app` fixture (which carries known violations:
an "Android / Google Play" metadata mention and a paywall view missing Restore / Terms / Privacy).
The skill was installed with `./install.sh all`, then each host was driven headlessly with a
submission-intent prompt and observed for (a) skill discovery, (b) a `scan.sh` invocation, and
(c) a faithful GREEN/YELLOW/RED verdict.

Expected scanner output for this fixture:

```
FAIL: 2.3.10 Other-platform mention — banned reference in metadata
FAIL: 3.1.2 Restore Purchases — not found in …/SubscriptionView.swift
FAIL: 3.1.2 Terms of Use (EULA) link — not found in …/SubscriptionView.swift
FAIL: 3.1.2 Privacy Policy link — not found in …/SubscriptionView.swift
WARN: 2.3.3 Screenshots — en-US has only 1 image(s)
→ RED (4 FAIL): no .precheck-pass token
```

## Results

| Host | Installed | Skill dir | Discovered | `scan.sh` ran | Verdict | Status |
|------|-----------|-----------|------------|---------------|---------|--------|
| **Claude Code** | ✅ | `.claude/skills/` | ✅ | ✅ `bash .claude/skills/appstore-precheck/scripts/scan.sh` | RED | **Verified** |
| **Codex CLI** | ✅ | `.agents/skills/` | ✅ | ✅ | RED (faithful, Pierre one-liner) | **Verified** |
| **Gemini CLI** | ✅ | `.agents/skills/`, `.gemini/skills/` | ✅ `gemini skills list` → `appstore-precheck [Enabled]` | ✅ | RED (faithful, Pierre one-liner) | **Verified** |
| **Cursor** | ✅ | `.agents/skills/`, `.cursor/skills/`, also `.claude/skills/` | ✅ | ✅ | RED (faithful, Pierre one-liner) | **Verified** |

### Claude Code: verified

`claude -p` run from the project. The model loaded the project skill and invoked the scanner; the
`stream-json` transcript shows the exact tool call:

```
bash .claude/skills/appstore-precheck/scripts/scan.sh
```

It returned a **RED** verdict and withheld the `.precheck-pass` token, as required. (Note: keep the
prompt aligned with the SKILL.md output contract; a loose prompt let the model embellish beyond
the scanner's lines; a contract-aligned prompt produced the verbatim `scan.sh` output.)

### Codex CLI: verified

`codex exec --full-auto` (ChatGPT auth) run from the project. Codex discovered the skill under
`.agents/skills/`, ran the scanner, and produced a faithful presentation: one Pierre line
(*"Non. Four faults. This one is not ready for the velvet rope."*), the verbatim FAIL/WARN list,
`file:line` fixes, the non-blocking drift-check note, the `fastlane precheck` note (skipped, no ASC
creds in that throwaway project), and the manual checklist. Verdict: **RED**, no token. This is the
reference example of the intended layered-voice behavior.

### Gemini CLI: verified

`gemini 0.34.0` with `gemini-api-key` auth (key supplied via `~/.gemini/.env`). `install.sh`
places the skill under `.agents/skills/`, and `gemini skills list` reports it as
`appstore-precheck [Enabled]`. A headless `gemini -y -p "…"` run discovered the skill, executed the
scanner, and returned a faithful **RED** verdict: one Pierre line (*"Non. 4 faults. Apple would
have found fewer. Suivant."*) followed by the verbatim FAIL/WARN lines and the deterministic counts
(`fail=4 warn=1 pass=8`), token withheld.

> Note: the default Gemini Pro model was intermittently returning HTTP 503 ("high demand"); the run
> succeeded on `gemini-2.5-flash` (`gemini -m gemini-2.5-flash …`). That is a transient Google-side
> capacity issue, not a skill-wiring problem; auth and skill discovery worked regardless.

### Cursor: verified

Verified via `cursor-agent` (Cursor's headless CLI; `cursor-agent login` for auth). `install.sh`
populates `.agents/skills/` and `.claude/skills/` (and a mirrored `.cursor/skills/`), all of which
Cursor reads. A headless `cursor-agent -p --force "…"` run discovered the skill, executed the
scanner, and returned a faithful **RED** verdict: Pierre one-liner (*"Non. Quatre faults. Apple
would have found fewer. Suivant."*), the verbatim scan output, and the deterministic counts
(`fail=4 warn=1 pass=8`), token withheld.

## Conclusion

The single `SKILL.md` is genuinely portable: **all four hosts are verified end-to-end, namely
Claude Code, Codex CLI, Gemini CLI, and Cursor** (skill discovered → `scan.sh` executed → faithful
GREEN/YELLOW/RED verdict, Pierre voice in presentation only). One `SKILL.md`, no per-tool
conversion.
