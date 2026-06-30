# Cross-tool runtime verification

`appstore-precheck` ships one `SKILL.md` (the open [Agent Skills](https://agentskills.io) standard)
that every supported host reads natively. Hosts differ in **which directory they scan** and **how
they install** the skill (native plugin vs `install.sh` vs `gemini skills install`).

This document records **real runs** verifying, per host, that the skill is discovered, triggers on
a submission-intent prompt, and actually executes `scripts/scan.sh`.

## Method (skill via `install.sh`)

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

## Results (skill runtime)

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

---

## Plugin install verification (v1.5.x)

Native plugin manifests ship at the repo root. These checks confirm **discovery and packaging**, not
a second full agent run per host.

| Host | Install path | Manifest smoke check | Status |
|------|--------------|----------------------|--------|
| **Claude Code** | `/plugin marketplace add berkayturk/appstore-precheck` + `/plugin install …` | `claude plugin validate .` passes | **Verified** |
| **Cursor** | Customize → Plugins → Import marketplace → repo URL | `.cursor-plugin/plugin.json` + `marketplace.json`; skill at `skills/appstore-precheck/SKILL.md` | **Manifest verified** (IDE install: user / marketplace review) |
| **Codex** | `codex plugin marketplace add berkayturk/appstore-precheck` → `/plugins` | `.agents/plugins/marketplace.json` + `.claude-plugin/plugin.json`; marketplace add succeeds on CLI 0.125.x | **Manifest verified** (install via `/plugins` TUI) |
| **Gemini CLI** | `gemini skills install https://github.com/berkayturk/appstore-precheck.git --path skills/appstore-precheck` | `gemini skills list` → `appstore-precheck [Enabled]` after local install test | **Verified** |

Notes:

- **Codex CLI 0.125.x** exposes `codex plugin marketplace {add,upgrade,remove}` only; plugin install
  and uninstall happen in the **`/plugins`** interactive browser (no `codex plugin add/remove`).
- **Cursor** public listing is pending marketplace review; until then, users import the GitHub repo
  as a marketplace (repo URL, not `github.com/marketplace/actions/…`).
- **GitHub Actions** distribution is separate: [Marketplace action](https://github.com/marketplace/actions/appstore-precheck)
  (`uses: berkayturk/appstore-precheck@v1`).

---

## Conclusion

The single `SKILL.md` is genuinely portable: **all four hosts are verified end-to-end for skill
runtime**, namely Claude Code, Codex CLI, Gemini CLI, and Cursor (skill discovered → `scan.sh`
executed → faithful GREEN/YELLOW/RED verdict, Pierre voice in presentation only). Native **plugin
manifests** for Claude Code, Cursor, and Codex are validated; Gemini uses **`gemini skills install`**
(no plugin marketplace). One `SKILL.md`, no per-tool conversion.
