<p align="center">
  <img src="assets/social-preview.png" width="840" alt="appstore-precheck, a French critic reviews your build before Apple does">
</p>

<p align="center">
  <a href="https://github.com/berkayturk/appstore-precheck/actions/workflows/ci.yml"><img src="https://github.com/berkayturk/appstore-precheck/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS-lightgrey.svg" alt="Platform: iOS">
  <img src="https://img.shields.io/badge/Agent%20Skill-open%20standard-1F6FEB.svg" alt="Agent Skill">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20·%20Codex%20·%20Cursor%20·%20Gemini-2563EB.svg" alt="Works with Claude Code, Codex, Cursor, Gemini">
</p>

<p align="center"><strong>Catch App Store rejections before a reviewer does.</strong></p>

---

`appstore-precheck` is a read-only, pre-submission gate for iOS apps. It statically scans the most
common rejection vectors, runs Apple's own metadata linter, watches the App Store Review Guidelines
for drift, and finishes with an adversarial review pass, then hands you a single **GREEN / YELLOW /
RED** verdict. It never edits your code.

It ships as a portable [Agent Skill](https://agentskills.io): the same `SKILL.md` runs natively in
Claude Code, OpenAI Codex, Cursor, and Gemini CLI. The scanner is plain Bash, so you can also run it
by hand or wire it into CI.

## Meet Pierre

<img src="assets/mascot.png" align="right" width="124" alt="Pierre, the French app reviewer">

Your verdict is delivered by **Pierre**, a French critic who has seen ten thousand rejections and is
impressed by none of them. He reviews your build harder than Apple would, in private. A GREEN from
Pierre means Apple will wave you through.

- 🔴 **RED**: *"Non. Restore Purchases, absent. Guideline 3.1.2. Suivant."*
- 🟡 **YELLOW**: *"A few small uglinesses. I would not reject. But I noticed."*
- 🟢 **GREEN**: *"Hmf. I find nothing. Acceptable. Do not make me regret this."*

The verdict line is in Pierre's voice. The breakdown beneath it, every `file:line` and fix, stays
plain and surgical.

## What it checks

20 rejection vectors across code, fastlane metadata, screenshots, `PrivacyInfo.xcprivacy`, and the paywall:

| Guideline | Check |
|-----------|-------|
| **5.1.1(v)** | Privacy Manifest ↔ Required Reason API parity |
| **5.1.1** | A non-empty purpose string for every sensitive framework |
| **5.1.2** | ATT usage ↔ `NSUserTrackingUsageDescription` |
| **2.3.10** | No other-platform / competitor names in metadata |
| **2.3.1** | Metadata length limits (name, subtitle, keywords, promo, description) |
| **2.3.7** | Localized metadata parity across every locale |
| **2.3.3** | At least one screenshot per locale |
| **3.1.2** | Trial & auto-renew subscription disclosures |
| **3.1.2** | Restore Purchases + Terms (EULA) + Privacy Policy on the paywall |
| **2.5.1** | No private / banned APIs |
| **4.0** | Minimum functionality (real navigation) |
| **4.8** | Sign in with Apple offered when a third-party social login is used |
| **3.1.1(a)** | External purchase link entitlement + disclosure, when external purchase APIs are used |
| **5.1.5** | Sensitive-API justification *(opt-in)* |
| **5.1.2** | Tracking / IDFA SDK (AdMob, AppLovin, AppsFlyer, Adjust, …) shipped without an ATT prompt |
| **encryption** | `ITSAppUsesNonExemptEncryption` set, so App Store Connect skips the export-compliance question |
| **2.3** | A working support URL and a privacy URL in fastlane metadata (no placeholders) |
| **5.1.1** | Analytics SDK present ↔ `PrivacyInfo.xcprivacy` declares collected data / tracking domains |
| **2.1** | No placeholder / dummy copy (lorem ipsum, TODO, `example.com`) in store metadata |

Paywall checks are skipped automatically when no in-app-purchase signals are present.

## Quick start

**Claude Code**: install as a plugin:

```
/plugin marketplace add berkayturk/appstore-precheck
/plugin install appstore-precheck@appstore-precheck
```

**Run instantly with npx** (no clone, no install):

```bash
npx appstore-precheck            # scans the current directory, prints the verdict
npx appstore-precheck --fail-on YELLOW
```

It runs the static scan over the current directory and exits non-zero on RED (or on YELLOW with
`--fail-on YELLOW`). Read-only, like everything else here.

**Codex, Cursor, Gemini, Claude**: clone, then run the installer from inside your iOS project:

```bash
git clone https://github.com/berkayturk/appstore-precheck.git
/path/to/appstore-precheck/install.sh        # → ./.claude/skills and ./.agents/skills
```

**Standalone**: the scanner is just Bash:

```bash
bash skills/appstore-precheck/scripts/scan.sh
```

**CI**: drop the static scan into a workflow with the bundled composite action. It fails the
job on a RED verdict; set `fail-on: YELLOW` to be stricter:

```yaml
- uses: berkayturk/appstore-precheck@v1.0.0
  with:
    working-directory: .   # optional
    fail-on: RED           # optional (RED | YELLOW)
```

## How it works

| Phase | Step |
|-------|------|
| **0** | **Guideline drift**: diff the live App Store Review Guidelines against a tracked baseline. Never blocks. |
| **1** | **Static scan**: `scan.sh` over the 20 vectors above. |
| **2** | **`fastlane precheck`**: Apple's own metadata rule engine. |
| **3** | **Adversarial review**: Pierre role-plays a skeptical reviewer and drafts realistic rejection notices. |
| **4** | **Verdict**: GREEN / YELLOW / RED, and a `.precheck-pass` token the upload guard gates on. |

## Demo

<p align="center">
  <img src="assets/demo.gif" width="760" alt="appstore-precheck running: a clean app passes GREEN, an app with rejection vectors is blocked RED">
</p>

A clean app passes **GREEN**; an app with rejection vectors is blocked **RED**. The verdict and
counts are deterministic ([`verdict.sh`](skills/appstore-precheck/scripts/verdict.sh)).

## Example

```
🔴 Pierre: "Non. Three faults. Apple would have found one. Suivant."

RED: 3 FAIL
• 3.1.2 Restore Purchases missing    SubscriptionView.swift:14 → add restorePurchases()
• 2.3.10 "Android" in metadata        en-US/description.txt:1 → remove the reference
• 5.1.1(v) FileTimestamp undeclared   PrivacyInfo.xcprivacy → declare the reason
Submission blocked.
```

See [`examples/`](examples/) for full [GREEN](examples/green-pass.md) and [RED](examples/red-reject.md) runs,
plus real [Phase 0 drift-check](examples/drift-check.md) and [Phase 2 `fastlane precheck`](examples/fastlane-precheck.md) results.

## Output

| State | Meaning | Token | Upload guard |
|-------|---------|-------|--------------|
| 🟢 **GREEN** | 0 FAIL, ≤2 WARN | written (60 min) | allowed |
| 🟡 **YELLOW** | 0 FAIL, 3+ WARN | not written | blocked; needs confirmation |
| 🔴 **RED** | ≥1 FAIL | removed | blocked; shows the FAIL list |

## Configuration

Zero config for a standard fastlane + Xcode layout. The scanner auto-detects your source directory,
fastlane metadata, screenshots, String Catalog, paywall view, and locales. Override any of it with a
`.appstore-precheck.json` at your repo root (copy
[`config.example.json`](skills/appstore-precheck/config.example.json)).

## Cross-tool support

`SKILL.md` follows the [Agent Skills open standard](https://agentskills.io), with no per-tool conversion.
Hosts differ only in the directory they scan:

| Host | Reads from |
|------|-----------|
| Claude Code | `.claude/skills/` · `~/.claude/skills/` |
| OpenAI Codex | `.agents/skills/` · `~/.agents/skills/` |
| Cursor | `.agents/skills/`, `.cursor/skills/`, also `.claude/skills/` |
| Gemini CLI | `.agents/skills/`, `.gemini/skills/` |

A root [`AGENTS.md`](AGENTS.md) covers hosts that read always-on context instead of on-demand skills.
[`docs/cross-tool-verification.md`](docs/cross-tool-verification.md) records real per-host runs
(all four hosts verified end-to-end: Claude Code, Codex, Gemini, and Cursor), and
[`docs/field-tests.md`](docs/field-tests.md) records dogfooding the scanner against real
App Store apps (DuckDuckGo, Pocket Casts, Wikipedia).

## Requirements

`bash`, `git`, `grep`, `find` · `jq` (config + String Catalog checks) · `python3` (exact Unicode
length counts) · `fastlane` + an App Store Connect API key for Phase 2 only.

**Secrets**: the ASC API key is read from your environment at runtime and deleted immediately after
`fastlane precheck`. Never commit it; `.gitignore` blocks `*asc-key*.json` and `.env`.

## Uninstall

```bash
/plugin uninstall appstore-precheck@appstore-precheck                        # Claude Code plugin
rm -rf .claude/skills/appstore-precheck .agents/skills/appstore-precheck     # manual install
rm -f .precheck-pass                                                         # runtime token
```

## Development

```bash
npm run lint            # bash -n on every script
npm run check-versions  # plugin.json / package.json / SKILL.md in lockstep
npm test                # run scan.sh against fixture projects and assert
claude plugin validate .
```

CI runs ShellCheck, JSON validation, the version-consistency guard, and the fixture tests on every push.

## Disclaimer

This is a static heuristic tool. A GREEN result **lowers but does not eliminate** rejection risk;
Apple's guidelines change frequently and reviewer decisions are judgment calls. It performs no runtime
crash testing; always do a final manual review before you submit. Not affiliated with Apple.

## Star History

<a href="https://star-history.com/#berkayturk/appstore-precheck&Date">
  <img src="https://api.star-history.com/svg?repos=berkayturk/appstore-precheck&type=Date" alt="Star History Chart" width="600">
</a>

## License

[MIT](LICENSE) © Berkay Turk
