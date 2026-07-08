#!/usr/bin/env bash
# update-brew-formula.sh — keep the Homebrew tap (berkayturk/homebrew-tap) in
# lockstep with the npm release.
#
#   bash scripts/update-brew-formula.sh            # update the tap to package.json's version
#   bash scripts/update-brew-formula.sh --check    # verify only (used by CI): the tap formula
#                                                  # must match the latest version on npm
#
# The apply mode runs AFTER `npm publish`: it downloads the published tarball,
# computes its sha256, rewrites Formula/appstore-precheck.rb in a fresh clone of
# the tap, and pushes the bump. It refuses to run if the tarball is not on npm
# yet, so it can never point the formula at a version nobody can install.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_REPO="berkayturk/homebrew-tap"
FORMULA_PATH="Formula/appstore-precheck.rb"
REGISTRY_BASE="https://registry.npmjs.org/appstore-precheck"

fail() { echo "update-brew-formula: $*" >&2; exit 1; }

pkg_version() {
  sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$REPO_ROOT/package.json" | head -1
}

formula_version() {
  # Extract the version from the formula's tarball url line.
  sed -n 's|.*appstore-precheck-\([0-9][0-9.]*\)\.tgz.*|\1|p' "$1" | head -1
}

npm_latest() {
  curl -fsSL "$REGISTRY_BASE" | sed -n 's/.*"latest":"\([^"]*\)".*/\1/p' | head -1
}

check_mode() {
  local latest formula_file live_version
  latest="$(npm_latest)"
  [[ -n "$latest" ]] || fail "could not read the latest version from the npm registry"

  formula_file="$(mktemp)"
  # expand now: the local is out of scope when EXIT fires
  # shellcheck disable=SC2064
  trap "rm -f '$formula_file'" EXIT
  curl -fsSL "https://raw.githubusercontent.com/$TAP_REPO/main/$FORMULA_PATH" -o "$formula_file" \
    || fail "could not fetch $FORMULA_PATH from $TAP_REPO"
  live_version="$(formula_version "$formula_file")"
  [[ -n "$live_version" ]] || fail "could not parse a version out of the tap formula"

  if [[ "$live_version" != "$latest" ]]; then
    fail "tap formula is at $live_version but npm latest is $latest — run: bash scripts/update-brew-formula.sh"
  fi
  echo "OK: tap formula ($live_version) matches npm latest ($latest)"
}

apply_mode() {
  local version tarball_url tmp sha clone_dir
  version="$(pkg_version)"
  [[ -n "$version" ]] || fail "could not read the version from package.json"
  tarball_url="$REGISTRY_BASE/-/appstore-precheck-$version.tgz"

  tmp="$(mktemp -d)"
  # expand now: the local is out of scope when EXIT fires
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  echo "Fetching $tarball_url ..."
  curl -fsSL "$tarball_url" -o "$tmp/pkg.tgz" \
    || fail "version $version is not on npm yet — run 'npm publish' first"
  sha="$(shasum -a 256 "$tmp/pkg.tgz" | cut -d' ' -f1)"
  echo "sha256: $sha"

  clone_dir="$tmp/tap"
  git clone --quiet --depth 1 "https://github.com/$TAP_REPO.git" "$clone_dir"

  if [[ "$(formula_version "$clone_dir/$FORMULA_PATH")" == "$version" ]]; then
    echo "OK: tap formula is already at $version — nothing to do"
    return 0
  fi

  sed -i '' \
    -e "s|url \".*\"|url \"$tarball_url\"|" \
    -e "s|sha256 \".*\"|sha256 \"$sha\"|" \
    "$clone_dir/$FORMULA_PATH" 2>/dev/null \
  || sed -i \
    -e "s|url \".*\"|url \"$tarball_url\"|" \
    -e "s|sha256 \".*\"|sha256 \"$sha\"|" \
    "$clone_dir/$FORMULA_PATH"

  git -C "$clone_dir" add "$FORMULA_PATH"
  git -C "$clone_dir" commit --quiet -m "appstore-precheck $version"
  git -C "$clone_dir" push --quiet
  echo "OK: pushed appstore-precheck $version to $TAP_REPO"
}

case "${1:-}" in
  --check) check_mode ;;
  "")      apply_mode ;;
  *)       fail "unknown option: $1 (usage: update-brew-formula.sh [--check])" ;;
esac
