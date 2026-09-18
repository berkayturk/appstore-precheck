# eval/ — LLM deep-review evaluation harness

Measures Pierre's Phase 4 deep review (31 semantic checks) against a labelled
dataset. Additive and opt-in: nothing here runs in the default scan path, and
nothing here changes the GREEN/YELLOW/RED verdict.

```
schema/case.schema.json   case schema (validated by validate.sh)
dataset/cases/*.json      one labelled case per file
dataset/fixtures/<id>/    minimal fixture each case points at
lib/                      build_request.py, parse_verdict.py, validate_case.py
run.sh                    call the API, cache raw responses (needs ANTHROPIC_API_KEY)
score.py                  offline scorer -> docs/llm-scorecard.md
baseline/<date>-<model>/  committed response caches CI scores against
runs/                     local runs (gitignored)
```

Typical flow:

```sh
bash eval/validate.sh                       # dataset sanity
ANTHROPIC_API_KEY=... bash eval/run.sh --baseline   # one paid run, cached
python3 eval/score.py --write               # regenerate docs/llm-scorecard.md
python3 eval/score.py --check               # what CI enforces (offline)
```

Full documentation and the honesty caveats live in the repo README's
`## Eval` section and in the generated `docs/llm-scorecard.md`.

Optional TypeSafe provider:

```sh
bash eval/run.sh --provider typesafe --cases 'check18-*' --dry-run
# Paid run; requires TYPESAFE_API_KEY:
bash eval/run.sh --provider typesafe --out eval/runs/jev-pilot
python3 eval/score.py --run eval/runs/jev-pilot
```

Check identities now use `check_key` from the versioned review catalog. Historical
baseline labels/numbering stay in `baseline/cases-v1.json`; new runs snapshot `cases.json`.
Case IDs are durable cache identities: the historical `check28-*` filenames now target
`rating-manipulation` (current display number 29). Do not rename old caches or reinterpret
their answers as developer-identity reviews. New fixtures need independent human label
confirmation. Abstentions have separate counts/coverage and are never true negatives.
See [the TypeSafe guide](../skills/appstore-precheck/references/typesafe.md).
