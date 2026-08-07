# Publishing plugins

This repo ships **one skill** with **native plugin manifests** for four hosts. Gemini CLI has no
plugin marketplace yet; use `gemini skills install` instead (see the README Quick start).

| Host | Manifest | Marketplace catalog |
|------|----------|---------------------|
| Claude Code | [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) | [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) |
| Cursor | [`.cursor-plugin/plugin.json`](../.cursor-plugin/plugin.json) | [`.cursor-plugin/marketplace.json`](../.cursor-plugin/marketplace.json) |
| OpenAI Codex | reads `.claude-plugin/plugin.json` (legacy-compatible) | [`.agents/plugins/marketplace.json`](../.agents/plugins/marketplace.json) and `.claude-plugin/marketplace.json` |
| Grok Build | [`.grok-plugin/plugin.json`](../.grok-plugin/plugin.json) (also accepts `.claude-plugin/`) | [`.grok-plugin/marketplace.json`](../.grok-plugin/marketplace.json) |

The plugin root is the **repository root**. Skills live under `skills/appstore-precheck/`; hooks under
`hooks/`. After changing manifests, run `npm run check-versions`, `claude plugin validate .`, and
`grok plugin validate .`.

---

## Claude Code — public marketplace

**Already wired.** Users install with:

```
/plugin marketplace add berkayturk/appstore-precheck
/plugin install appstore-precheck@appstore-precheck
```

### Maintainer checklist

1. Bump version in `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
   `.grok-plugin/plugin.json`, `.grok-plugin/marketplace.json` (`plugins[0].version`),
   `package.json`, and `skills/appstore-precheck/SKILL.md` (`metadata.version`).
2. Run `npm run check-versions`, `claude plugin validate .`, and `grok plugin validate .`.
3. Tag and push (`v1.x.y`). Claude Code marketplace tracks the GitHub repo; users pick up new
   versions on reinstall or marketplace refresh.

There is no separate Anthropic submission step for a GitHub-hosted marketplace beyond keeping the
repo public and the manifests valid.

---

## Cursor — official marketplace

### What users do today (GitHub marketplace)

Before the plugin is listed on [cursor.com/marketplace](https://cursor.com/marketplace), users can
import this repo as a **team or personal marketplace**:

1. Open **Cursor → Customize → Plugins**.
2. Choose **Import marketplace** (or **Add marketplace**).
3. Paste the GitHub repo URL: `https://github.com/berkayturk/appstore-precheck`
4. Cursor reads [`.cursor-plugin/marketplace.json`](../.cursor-plugin/marketplace.json) and lists
   `appstore-precheck`.
5. Install the plugin from the imported marketplace.

**Team admins (Teams / Enterprise):** Dashboard → **Settings → Plugins → Import** under Team
Marketplaces, paste the same repo URL, review parsed plugins, save. See
[Cursor team marketplace docs](https://cursor.com/docs/plugins).

### Submit to the public Cursor Marketplace (maintainer)

1. Ensure [`.cursor-plugin/plugin.json`](../.cursor-plugin/plugin.json) and
   [`.cursor-plugin/marketplace.json`](../.cursor-plugin/marketplace.json) are valid.
2. Skills must live at `skills/<name>/SKILL.md` with `name` + `description` frontmatter (already true).
3. Optional: commit a logo under `assets/` and reference it in `plugin.json` (`logo` field).
4. Go to [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish).
5. Submit the **GitHub repository URL**. Cursor manually reviews every listing.
6. After approval, users find the plugin under **Customize → Plugins** without importing a repo.

### Local testing (maintainer)

Copy (do not symlink) the repo into `~/.cursor/plugins/local/appstore-precheck` and reload the
window. Cursor rejects symlinks whose target is outside `~/.cursor/plugins/local/`.

---

## OpenAI Codex — plugin marketplace

Codex reads plugin manifests from `.codex-plugin/plugin.json` or, for this repo,
**`.claude-plugin/plugin.json`** (legacy-compatible). Marketplace catalogs are read from:

- `.agents/plugins/marketplace.json` (native)
- `.claude-plugin/marketplace.json` (legacy-compatible)

### What users do today

```bash
codex plugin marketplace add berkayturk/appstore-precheck
codex plugin add appstore-precheck@appstore-precheck
```

Or interactively: run `codex`, then `/plugins`, pick the **appstore-precheck** marketplace tab, and
install.

To refresh after a repo update:

```bash
codex plugin marketplace upgrade appstore-precheck
```

### Submit to the public Codex Plugin Directory (maintainer)

OpenAI’s docs state that **self-serve publishing to the official Plugin Directory is coming soon**
([Build plugins](https://developers.openai.com/codex/plugins/build)). There is **no public submit
form** like Cursor’s marketplace publish page today.

**What you can do now:**

1. **GitHub repo marketplace (public, link-based)** — users run:

   ```bash
   codex plugin marketplace add berkayturk/appstore-precheck
   ```

   Then run `codex`, type `/plugins`, open the **appstore-precheck** marketplace tab, and install
   the plugin. (On Codex CLI 0.125.x there is no `codex plugin add` subcommand yet.)

2. **Codex app — workspace share (team, not public):** install the plugin locally, then
   **Plugins → Created by you → Share** with workspace members. They see it under **Shared with you**.

3. **Prep for official directory:** keep `.claude-plugin/plugin.json` `interface` metadata current
   (`displayName`, `shortDescription`, `logo`, `websiteURL`). This repo already includes those fields.

When self-serve public publishing opens, expect a flow similar to Cursor: manifest review + listing in
the **Curated by OpenAI** tab inside Codex **Plugins**.

**Not recommended for this skill repo:** the Apps SDK app-submission path (build a ChatGPT app →
OpenAI creates a Codex plugin). That is for full apps with connectors, not a skill-only package.

---

## Grok Build — plugin marketplace

Grok Build reads [`.grok-plugin/marketplace.json`](../.grok-plugin/marketplace.json) and
[`.grok-plugin/plugin.json`](../.grok-plugin/plugin.json). It also accepts the
`.claude-plugin/` equivalents, so this repo remains dual-readable.

### What users do today

```bash
grok plugin marketplace add berkayturk/appstore-precheck
grok plugin install appstore-precheck --trust
```

This installs from GitHub `main` (see [why the index uses a URL source](#why-the-index-uses-a-url-source)).

Direct install (no marketplace step):

```bash
grok plugin install berkayturk/appstore-precheck --trust
# or a local clone:
grok plugin install /path/to/appstore-precheck --trust
```

Validate locally:

```bash
grok plugin validate .
grok plugin details appstore-precheck
```

Plugins stay off until enabled; after install, `grok plugin enable appstore-precheck` (or `Space`
in the Plugins tab). The upload-guard hook auto-wires when the plugin is trusted (`--trust`);
Grok sets `GROK_PLUGIN_ROOT` and the `CLAUDE_PLUGIN_ROOT` alias used by `hooks/hooks.json`.
Grok's hook payload is camelCase (`.toolInput`) where Claude's is snake_case (`.tool_input`) —
`hooks/fastlane-guard.sh` reads both, and `tests/test-guard.sh` covers both envelopes. A guard that
reads only one of them fails **open** on the other host.

### Why the index uses a URL source

Grok's marketplace scanner rejects a self-referential local source: `"source": "./"` (and `"."`,
and `{"type": "local", "path": "."}`) fail with *marketplace path is empty*, and a local source may
not contain parent components. The plugin root here **is** the repository root, so the entry uses
the URL form pointing at this repo. Claude Code and Cursor keep `"./"` — their scanners accept it.

Two consequences worth knowing:

- **The marketplace flow always installs GitHub `main`**, even when the source was added from a
  local clone (`grok plugin marketplace add .`). Anyone testing an unmerged branch must use the
  direct path install (`grok plugin install /path/to/appstore-precheck --trust`), which does
  install the working tree.
- **The entry is not `sha`-pinned**, so installs are not reproducible and deployments that set
  `[marketplace] require_sha = true` (or `GROK_MARKETPLACE_REQUIRE_SHA=1`) refuse it. Pinning is a
  post-merge step: the release commit's sha does not exist until the release lands on `main`. To
  pin, after the release commit is on `main` add its full sha as `plugins[0].source.sha` and push
  that as a follow-up commit — see the release checklist in [`MAINTENANCE.md`](../MAINTENANCE.md).

### Official xAI catalog (optional)

To list this plugin in the [built-in Grok marketplace](https://github.com/xai-org/plugin-marketplace),
open a PR there with a remote plugin entry pointing at this repo (pinned `sha` recommended). The
self-hosted marketplace above works without that listing.

---

## Gemini CLI — skills install (no plugin marketplace)

Gemini has **no** `gemini plugin install` marketplace today. Native one-liner install:

```bash
gemini skills install https://github.com/berkayturk/appstore-precheck.git \
  --path skills/appstore-precheck --scope workspace
```

Use `--scope user` for a global install under `~/.gemini/skills/`. Verify with `gemini skills list`.

Fallback: [`install.sh`](../install.sh) copies the skill into `.agents/skills/` (also read by Gemini).

---

## Version bumps across manifests

When releasing, keep these in lockstep (enforced by `npm run check-versions`):

- `.claude-plugin/plugin.json` → `version`
- `.cursor-plugin/plugin.json` → `version`
- `.grok-plugin/plugin.json` → `version`
- `.grok-plugin/marketplace.json` → `plugins[0].version`
- `package.json` → `version`
- `skills/appstore-precheck/SKILL.md` → `metadata.version`

Codex does not require a separate `.codex-plugin/plugin.json` in this repo because it consumes the
Claude-compatible manifest at `.claude-plugin/plugin.json`.
