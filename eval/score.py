#!/usr/bin/env python3
"""score.py — score a cached eval run and generate docs/llm-scorecard.md.

Offline only: re-parses the raw API responses cached by eval/run.sh — no
network, no key, no re-billing. Output is deterministic for a given run dir
(the only timestamp used is the manifest's run_date), so the --check staleness
gate mirrors scripts/scorecard.sh --check.

    score.py                 print the scorecard over all committed baselines
    score.py --write         write docs/llm-scorecard.md
    score.py --check         fail if the doc is stale or any Tier-A F1 < floor
    score.py --run DIR       score one specific run dir (single-run card)
    score.py --dataset DIR   dataset override (unit tests)

The committed card covers every baseline under eval/baseline/ (one section
per model run, newest first, plus a comparison table), so two models never
hide each other. Floor: LLM_F1_FLOOR env var (default 0.80), gating Tier-A F1
of every committed baseline — Tier B is advisory by design. With no committed
baseline the gate reports itself inactive and exits 0 (an absent measurement
is not a passing measurement, and must never be fabricated).
"""
import json
import os
import sys
import math
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from parse_verdict import parse_verdict  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = REPO / "eval" / "dataset"
BASELINE_DIR = REPO / "eval" / "baseline"
CARD = REPO / "docs" / "llm-scorecard.md"
DEFAULT_FLOOR = 0.80
DECISIONS = {'finding', 'pass', 'not-applicable'}


def all_baselines():
    """Every committed baseline run, newest first by the manifest's run_date
    (not by directory name: dirs are named <date>-<model>, so same-day runs
    of two models would otherwise sort by model name rather than recency)."""
    if not BASELINE_DIR.is_dir():
        return []
    runs = [d for d in BASELINE_DIR.iterdir()
            if d.is_dir() and (d / "manifest.json").is_file()]

    def run_date(d):
        try:
            manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
            return (manifest.get("run_date") or "", d.name)
        except (OSError, ValueError):
            return ("", d.name)

    return sorted(runs, key=run_date, reverse=True)


def load_cases(dataset_dir):
    return [json.loads(p.read_text(encoding="utf-8"))
            for p in sorted((dataset_dir / "cases").glob("*.json"))]


def cases_for_run(run_dir, dataset_dir):
    # Preserve historical labels/numbering. Never reinterpret an old cached response
    # against a newly numbered check or a newly edited expected label.
    if dataset_dir.resolve() == DEFAULT_DATASET.resolve():
        snapshot = run_dir / 'cases.json'
        if snapshot.is_file():
            return json.loads(snapshot.read_text())
        if run_dir.parent.resolve() == BASELINE_DIR.resolve():
            return json.loads((BASELINE_DIR / 'cases-v1.json').read_text())
    return load_cases(dataset_dir)


def majority(verdicts):
    """Require a strict majority; a mere plurality also counts as abstention."""
    counts = Counter(verdicts)
    top, top_n = counts.most_common(1)[0]
    if top_n <= len(verdicts) / 2:
        return "no-majority", False
    return top, len(counts) == 1


def score_case(case, run_dir):
    """Score one case against its cached repeats. Returns a result dict."""
    case_dir = run_dir / case["id"]
    reps = sorted(case_dir.glob("rep*.json"))
    verdicts = []
    for rep in reps:
        response = json.loads(rep.read_text(encoding="utf-8"))
        verdicts.append(parse_verdict(response)["verdict"])
    if not verdicts:
        return {**case, "predicted": "not-run", "unanimous": False, "repeats": []}
    predicted, unanimous = majority(verdicts)
    return {**case, "predicted": predicted, "unanimous": unanimous, "repeats": verdicts}


def confusion(results):
    """Binary confusion over scored cases: positive = 'finding'."""
    tp = fp = fn = tn = 0
    for r in results:
        if r['predicted'] not in DECISIONS or r['expected'] not in DECISIONS:
            continue  # Abstention is neither a clean bill of health nor a true negative.
        want_pos = r["expected"] == "finding"
        got_pos = r["predicted"] == "finding"
        if want_pos and got_pos:
            tp += 1
        elif not want_pos and got_pos:
            fp += 1
        elif want_pos and not got_pos:
            fn += 1
        else:
            tn += 1
    return tp, fp, fn, tn


def metrics(tp, fp, fn):
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall else 0.0
    return precision, recall, f1


def tier_row(name, results):
    tp, fp, fn, tn = confusion(results)
    precision, recall, f1 = metrics(tp, fp, fn)
    n = len(results)
    return (f"| {name} | {n} | {tp} | {fp} | {fn} | {tn} "
            f"| {precision:.2f} | {recall:.2f} | {f1:.2f} |")


def run_stats(run_dir, dataset_dir):
    """Everything one run contributes to the card: results and summary numbers."""
    manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
    cases = cases_for_run(run_dir, dataset_dir)
    results = [score_case(c, run_dir) for c in cases]
    unlabeled = [r for r in results if not r["label_confirmed"]]
    not_run = [r for r in results if r["label_confirmed"] and r["predicted"] == "not-run"]
    attempted = [r for r in results if r['label_confirmed'] and r['predicted'] != 'not-run']
    abstained = [r for r in attempted if r['predicted'] not in DECISIONS]
    answerable = [r for r in attempted if r['expected'] in DECISIONS]
    scored = [r for r in attempted if r['predicted'] in DECISIONS and r['expected'] in DECISIONS]
    tier_a = [r for r in scored if r["tier"] == "A"]
    tier_b = [r for r in scored if r["tier"] == "B"]
    _, b_fp, _, b_tn = confusion(tier_b)
    _, _, f1_a = metrics(*confusion(tier_a)[:3])
    unanimous = sum(1 for r in scored if r["unanimous"])
    return {
        "manifest": manifest, "results": results, "unlabeled": unlabeled,
        "not_run": not_run, "scored": scored, "tier_a": tier_a, "tier_b": tier_b,
        "f1_a": f1_a, "b_fp": b_fp, "b_tn": b_tn,
        "b_fp_rate": b_fp / (b_fp + b_tn) if b_fp + b_tn else 0.0,
        "unanimous": unanimous,
        "consistency": unanimous / len(scored) if scored else 0.0,
        'abstained': abstained, 'attempted': attempted,
        'coverage': len(scored) / len(answerable) if answerable else 0.0,
        'expected_abstentions': [r for r in attempted if r['expected'] == 'insufficient_evidence'],
    }


def _header():
    return [
        "# appstore-precheck — LLM Deep-Review Scorecard",
        "",
        "_Generated by `eval/score.py`. Do not edit by hand._",
        "",
        "## Methodology",
        "",
        "The current catalog has 31 semantic checks (Tier B: 4, 5, 7, 10, 15, 29, 30, 31).",
        "Historical baselines retain their original 28-check identities and labels.",
        "New runs snapshot cases; historical cases are pinned in `eval/baseline/cases-v1.json`.",
        "Pierre is measured against the labelled dataset in `eval/dataset/`:",
        "minimal, human-labelled fixtures, one target check per case. `eval/run.sh`",
        "calls the pinned model once per case per repeat and caches raw responses;",
        "this scorer re-parses those caches offline. The scored verdict per case is",
        "the majority vote across repeats; consistency is the share of cases where",
        "all repeats agreed. Positive class = REVIEW-FINDING. Cases whose label a",
        "human has not confirmed are counted as UNLABELED and excluded from every",
        "headline metric. Live URL fetches are substituted by pre-fetched contents",
        "embedded in the case (a deliberate determinism trade-off).",
        "Abstentions are excluded from binary metrics and reported separately with decision coverage.",
        "The F1 gate also requires at least 95% decision coverage among attempted answerable labeled cases.",
        "",
    ]


def run_body(stats, h):
    """Card body for one run. `h` is the section heading prefix ('##' or '###')."""
    manifest, results, scored = stats["manifest"], stats["results"], stats["scored"]
    prompt_sha = manifest.get("prompt_sha256")
    lines = [
        f"{h} Run manifest",
        "",
        "| field | value |", "|---|---|",
        f"| model | `{manifest['model']}` |",
        f"| generation params | max_tokens={manifest['max_tokens']}, "
        f"thinking={manifest['thinking']}, effort={manifest['effort']} |",
        f"| repeats per case | {manifest['repeat']} |",
        f"| run date | {manifest['run_date']} |",
        f"| dataset sha256 | `{manifest['dataset_sha256'][:16]}…` |",
        f"| prompt sha256 | `{prompt_sha[:16]}…` |" if prompt_sha
        else "| prompt sha256 | not recorded (run predates the prompt fingerprint) |",
        f"| cases | {len(scored)} scored, {len(stats['unlabeled'])} UNLABELED, "
        f"{len(stats['not_run'])} not run |",
        f"| abstentions | {len(stats['abstained'])}/{len(stats['attempted'])} attempted labeled cases |",
        f"| decision coverage (answerable cases) | {stats['coverage']:.2%} |",
        f"| expected abstentions correct | {sum(r['predicted'] == 'insufficient_evidence' for r in stats['expected_abstentions'])}/{len(stats['expected_abstentions'])} |",
        "",
        f"{h} Per-tier metrics",
        "",
        "| tier | cases | TP | FP | FN | TN | precision | recall | F1 |",
        "|---|---|---|---|---|---|---|---|---|",
        tier_row("A (high-confidence)", stats["tier_a"]),
        tier_row("B (heuristic)", stats["tier_b"]),
        tier_row("all", scored),
        "",
        f"**Tier-B false-positive rate:** {stats['b_fp_rate']:.2f} "
        f"({stats['b_fp']} FP over {stats['b_fp'] + stats['b_tn']} clean Tier-B case(s))",
        "",
        f"**Consistency:** {stats['unanimous']}/{len(scored)} case(s) unanimous across "
        f"{manifest['repeat']} repeats"
        f" ({stats['consistency']:.2f})" if scored else "**Consistency:** n/a",
        "",
        f"{h} Per-check breakdown",
        "",
        "| check | tier | guideline | case | expected | predicted (majority) | repeats | unanimous |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for r in results:
        status = ("UNLABELED" if not r["label_confirmed"] else r["predicted"])
        reps = "/".join(r["repeats"]) if r["repeats"] else "—"
        lines.append(
            f"| {r['check_id']} | {r['tier']} | {r['guideline']} | {r['id']} "
            f"| {r['expected']} | {status} | {reps} "
            f"| {'yes' if r['unanimous'] else 'no'} |")
    disagreements = [r for r in scored if not r["unanimous"]]
    if disagreements:
        lines += ["", "Non-unanimous cases (majority used for scoring): "
                  + ", ".join(f"`{r['id']}`" for r in disagreements)]
    return lines


def telemetry(run_dir, cases):
    latencies, costs, briers, confidence_pairs = [], [], [], []
    unknown_cost = 0
    for case in cases:
        for path in (run_dir / case['id']).glob('rep*.json'):
            body = json.loads(path.read_text())
            if body.get('provider') != 'typesafe':
                continue
            r = body.get('result', {})
            latency = r.get('latency_ms')
            if r.get('request_attempted') and isinstance(latency, (float, int)) and math.isfinite(latency):
                latencies.append(latency)
            cost = r.get('estimated_cost_usd')
            if cost is None:
                unknown_cost += 1
            else:
                costs.append(cost)
            answer = r.get('response', {}).get('answers', {}).get('outcome', {})
            probabilities = answer.get('probabilities', {})
            if case['label_confirmed'] and case['expected'] in DECISIONS and 'finding' in probabilities:
                briers.append((probabilities['finding'] - (case['expected'] == 'finding')) ** 2)
                predicted = answer.get('choice', '').replace('_', '-')
                confidence_pairs.append((max(probabilities.values()), predicted == case['expected']))
    if not latencies:
        return []
    def percentile(p):
        return sorted(latencies)[max(0, math.ceil(len(latencies) * p) - 1)]
    lines = ['', '### TypeSafe telemetry', '',
             f"Measured request latency: p50 {percentile(.5):.1f} ms; p95 {percentile(.95):.1f} ms.",
             f"Estimated Jev input cost: ${sum(costs):.6f}; {unknown_cost} request(s) with unknown cost.",
             'Cost excludes host/Pierre escalation. Repeated cases are correlated observations.']
    if briers:
        lines.append(f"Finding-probability Brier score: {sum(briers)/len(briers):.4f} over {len(briers)} labeled responses.")
        lines += ['', '| Selected probability band | Responses | Exact outcome accuracy |', '|---|---|---|']
        for low, high in ((0, .5), (.5, .8), (.8, .9), (.9, 1.01)):
            group = [ok for p, ok in confidence_pairs if low <= p < high]
            accuracy = f'{sum(group)/len(group):.2%}' if group else 'n/a'
            lines.append(f'| {low:.1f}–{min(high,1):.1f} | {len(group)} | {accuracy} |')
    return lines


def render(run_dir, dataset_dir):
    """Single-run card (--run DIR)."""
    lines = _header()
    lines += run_body(run_stats(run_dir, dataset_dir), "##")
    lines += telemetry(run_dir, cases_for_run(run_dir, dataset_dir))
    lines += ["", _honesty()]
    return "\n".join(lines) + "\n"


def render_all(runs, dataset_dir):
    """Committed card: every baseline, newest first, behind a comparison table."""
    lines = _header()
    if not runs:
        lines += [
            "## Results",
            "",
            "_No committed baseline run yet. Run `eval/run.sh --baseline` (needs",
            "`ANTHROPIC_API_KEY`), review the cached responses, and commit",
            "`eval/baseline/<date>-<model>/`. Until then the CI Tier-A F1 floor is inactive._",
            "",
            _honesty(),
        ]
        return "\n".join(lines) + "\n"

    stats = [run_stats(r, dataset_dir) for r in runs]
    lines += [
        "## Model comparison",
        "",
        "All committed baselines, newest first. Full per-run details follow.",
        "",
        "| model | run date | cases scored | Tier-A F1 | Tier-B FP rate | consistency |",
        "|---|---|---|---|---|---|",
    ]
    for s in stats:
        m = s["manifest"]
        lines.append(
            f"| `{m['model']}` | {m['run_date']} | {len(s['scored'])} "
            f"| {s['f1_a']:.2f} ({len(s['tier_a'])} case(s)) "
            f"| {s['b_fp_rate']:.2f} ({s['b_fp']}/{s['b_fp'] + s['b_tn']}) "
            f"| {s['consistency']:.2f} ({s['unanimous']}/{len(s['scored'])}) |")
    lines.append("")
    for run, s in zip(runs, stats):
        m = s["manifest"]
        lines += [f"## `{m['model']}` — {m['run_date'][:10]}", ""]
        lines += run_body(s, "###")
        lines += telemetry(run, cases_for_run(run, dataset_dir))
        lines.append("")
    lines.append(_honesty())
    return "\n".join(lines) + "\n"


def _honesty():
    return (
        "## Honesty\n"
        "\n"
        "These numbers measure fidelity to this project's own human labels on\n"
        "synthetic minimal fixtures — **not agreement with Apple's actual review\n"
        "decisions**, and not behavior on full-size real projects. Each case\n"
        "isolates one check, so cross-check interference is unmeasured. Tier B is\n"
        "heuristic by design; its false-positive rate is reported precisely because\n"
        "it is expected to be the weakest surface. Counts are shown next to every\n"
        "rate so small samples stay visible. See also `docs/scorecard.md` for the\n"
        "static-scanner measurements."
    )


def tier_a_f1(run_dir, dataset_dir):
    cases = cases_for_run(run_dir, dataset_dir)
    scored = [r for c in cases if c["label_confirmed"]
              for r in [score_case(c, run_dir)]
              if r["predicted"] in DECISIONS and r['expected'] in DECISIONS and r["tier"] == "A"]
    tp, fp, fn, _ = confusion(scored)
    _, _, f1 = metrics(tp, fp, fn)
    return f1, len(scored)


def main(argv):
    run_dir = None
    dataset_dir = DEFAULT_DATASET
    write = check = False
    args = argv[1:]
    while args:
        arg = args.pop(0)
        if arg == "--run":
            run_dir = Path(args.pop(0))
        elif arg == "--dataset":
            dataset_dir = Path(args.pop(0))
        elif arg == "--write":
            write = True
        elif arg == "--check":
            check = True
        else:
            print(f"score.py: unknown arg '{arg}'", file=sys.stderr)
            return 64
    if run_dir is not None:
        if not (run_dir / "manifest.json").is_file():
            print(f"score.py: no manifest.json in {run_dir}", file=sys.stderr)
            return 1
        card = render(run_dir, dataset_dir)
        runs = [run_dir]
    else:
        runs = all_baselines()
        card = render_all(runs, dataset_dir)

    if check:
        if not CARD.is_file() or CARD.read_text(encoding="utf-8") != card:
            print("score.py: docs/llm-scorecard.md is stale — run eval/score.py --write",
                  file=sys.stderr)
            return 1
        if not runs:
            print("score.py: up to date (no baseline yet — Tier-A F1 floor inactive)")
            return 0
        floor = float(os.environ.get("LLM_F1_FLOOR", DEFAULT_FLOOR))
        failed = False
        for run in runs:
            model = json.loads((run / "manifest.json").read_text(encoding="utf-8"))["model"]
            f1, n = tier_a_f1(run, dataset_dir)
            stats = run_stats(run, dataset_dir)
            if stats['coverage'] < .95 or n == 0:
                print(f"score.py: {model}: insufficient decision coverage or no Tier-A observations", file=sys.stderr)
                failed = True
            if f1 < floor:
                print(f"score.py: {model}: Tier-A F1 {f1:.2f} (over {n} case(s)) "
                      f"below floor {floor:.2f}", file=sys.stderr)
                failed = True
            else:
                print(f"score.py: {model}: Tier-A F1 {f1:.2f} over {n} case(s) >= {floor:.2f}")
        if failed:
            return 1
        print(f"score.py: up to date ({len(runs)} baseline(s) at or above the floor)")
        return 0

    if write:
        CARD.write_text(card, encoding="utf-8")
        print(f"score.py: wrote {CARD}")
    else:
        sys.stdout.write(card)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
