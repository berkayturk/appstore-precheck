#!/usr/bin/env bash
# tests/_assert.sh — shared assertion helpers for the test suite.
# Source this, run assertions, then `exit $fails`. Each helper increments $fails on
# mismatch and prints an "ok:" / "FAIL:" line. Helpers operate on values you pass in
# (no globals beyond the $fails counter), so each test file stays self-contained.

fails=0

assert_eq() { # assert_eq <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then
    echo "  ok: $3"
  else
    echo "  FAIL: $3 (got '$1', want '$2')"; fails=$((fails + 1))
  fi
}

assert_contains() { # assert_contains <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then
    echo "  ok: $3"
  else
    echo "  FAIL: $3 — expected to find: $2"; fails=$((fails + 1))
  fi
}

assert_absent() { # assert_absent <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then
    echo "  FAIL: $3 — did not expect: $2"; fails=$((fails + 1))
  else
    echo "  ok: $3"
  fi
}

assert_not_empty() { # assert_not_empty <value> <label>
  if [[ -n "$1" ]]; then
    echo "  ok: $2"
  else
    echo "  FAIL: $2 (got empty value)"; fails=$((fails + 1))
  fi
}

assert_gt() { # assert_gt <actual> <threshold> <label>
  if (( $1 > $2 )); then
    echo "  ok: $3"
  else
    echo "  FAIL: $3 (got '$1', want > '$2')"; fails=$((fails + 1))
  fi
}

section() { echo "== $1 =="; }
