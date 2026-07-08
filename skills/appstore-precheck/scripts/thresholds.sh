#!/usr/bin/env bash
# thresholds.sh — the single source of truth for the verdict thresholds.
# Sourced by verdict.sh and findings.sh so the two renderers can never diverge.
#
#   RED    >= RED_FAIL_MIN FAILs
#   YELLOW >= YELLOW_WARN_MIN WARNs (and no FAIL)
#   GREEN  otherwise

# shellcheck disable=SC2034  # consumed by the sourcing scripts, not here
RED_FAIL_MIN=1
# shellcheck disable=SC2034
YELLOW_WARN_MIN=5
