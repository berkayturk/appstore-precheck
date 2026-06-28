# Example: Phase 2 `fastlane precheck`

Apple's own metadata rule engine, wrapped by Phase 2. This is **real output** from running the
verbatim SKILL.md Phase 2 command against a live App Store Connect app (bundle id genericized
here as `com.example.app`). `Result: true` → the Phase 2 line is PASS.

## Command (verbatim from SKILL.md)

The ASC API key JSON is built from your environment at runtime, used, then deleted. It is never
committed. Example builder (env var names vary per project):

```bash
# 1. Build the key JSON from your ASC credentials (kept out of version control)
jq -n --arg kid "$ASC_KEY_ID" --arg iss "$ASC_ISSUER_ID" \
      --rawfile key "$ASC_P8_PATH" \
      '{key_id:$kid, issuer_id:$iss, key:$key, in_house:false}' > /tmp/asc-key.json

# 2. Run Apple's rule engine (the verbatim SKILL.md Phase 2 command)
fastlane run precheck \
  app_identifier:"com.example.app" \
  api_key_path:"/tmp/asc-key.json" \
  include_in_app_purchases:false \
  default_rule_level:":error"

# 3. Delete the secret immediately
rm -f /tmp/asc-key.json
```

## Output

```
[12:16:33]: Creating authorization token for App Store Connect API
[12:16:33]: Checking app for precheck rule violations
[12:16:39]: ✅  Passed: No negative  sentiment
[12:16:39]: ✅  Passed: No placeholder text
[12:16:39]: ✅  Passed: No mentioning  competitors
[12:16:39]: ✅  Passed: No future functionality promises
[12:16:39]: ✅  Passed: No words indicating test content
[12:16:39]: ✅  Passed: No curse words
[12:16:39]: ✅  Passed: No words indicating your IAP is free
[12:16:39]: ✅  Passed: Incorrect, or missing copyright date
[12:16:50]: ✅  Passed: No broken urls
[12:16:50]: precheck 👮‍♀️ 👮  finished without detecting any potential problems 🛫
[12:16:50]: Result: true
```

## Interpreting the result

- **`Result: true`** → Phase 2 is **PASS**. Apple's rule engine found no metadata violations.
- **Any violation line** (e.g. a competitor mention, a broken URL, placeholder text) → Phase 2 is
  **FAIL**; precheck prints the offending rule and `Result: false`. Fix the metadata and re-run.

`include_in_app_purchases:false` is set because the IAP disclosure checks are already covered by
Phase 1 (§8–10), and the IAP metadata endpoint has API-key limitations. Phase 1's static scan and
Phase 2's Apple-side check are complementary, not redundant.
