# Additional guideline runtime checks

No real simulator run was performed for the D stream. The synthetic observations and
shimmed lifecycle tests establish code behavior; they do not establish behavior of
ControlDopamine or another shipped app. The integration handoff records the actual
local app discovery and, if an existing simulator build is available, its run.

Run on a prebuilt app, never build from this runner:

```bash
bash skills/appstore-precheck/scripts/dynamic-run.sh \
  --app /absolute/path/Existing.app --repo /absolute/path/project \
  --repeats 3 --out /private/tmp/precheck-guidelines
bash skills/appstore-precheck/scripts/dynamic.sh \
  --transcript /private/tmp/precheck-guidelines/transcript.txt \
  --target simulator --build-config debug
```

Inspect `run.json` and its `guideline_observations` directory. Each accepted new
observation needs three separate fresh owned-device repeats. App PID mismatch,
unavailable OS ownership/class, inaccessible semantics, unavailable entry geometry,
missing exact action labels, or untriggered flows must remain SKIP.

CPU sampling waits 20 seconds after each successful launch. Only exact safe labels
are tapped, before demo login. D13/D14 provide positive observations only; absent
recording indicators or missing MusicKit authorization prompts are inconclusive and
are deliberately never defect findings. D17 does not infer Always authorization.

Sequential actions abstain once the screen differs from the initial app context; the
collector does not reset navigation or reuse earlier directory facts on a new screen.
A launch-time location advisory states only that the OS prompt preceded user action.
It makes no claim about missing context or request justification in any language.
