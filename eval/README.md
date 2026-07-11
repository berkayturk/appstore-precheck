# eval/ — LLM deep-review evaluation harness

Measures Pierre's Phase 4 deep review (28 semantic checks) against a labelled
dataset. Additive and opt-in: nothing here runs in the default scan path, and
nothing here changes the GREEN/YELLOW/RED verdict.

```
schema/case.schema.json   case schema (validated by validate.sh)
dataset/cases/*.json      one labelled case per file
dataset/fixtures/<id>/    minimal fixture each case points at
lib/                      build_request.py, parse_verdict.py, validate_case.py
run.sh                    call the API, cache raw responses (needs ANTHROPIC_API_KEY)
score.py                  offline scorer -> docs/llm-scorecard.md
baseline/<date>/          committed response caches CI scores against
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
