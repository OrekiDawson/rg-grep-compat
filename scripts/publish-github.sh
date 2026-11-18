#!/usr/bin/env bash
# Publish the v0.1.0 binary to an EXISTING GitHub repository after its source is on main.
# Requires the GitHub CLI and an authenticated repository owner.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo="${1:-OrekiDawson/rg-grep-compat}"
version="v0.1.0"
asset="dist/rg-grep-compat-linux-x86_64-static"
command -v gh >/dev/null || { echo "Missing GitHub CLI (gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first" >&2; exit 1; }
gh repo view "$repo" >/dev/null || { echo "Repository not accessible: $repo" >&2; exit 1; }
[[ -f "$asset" ]] || { echo "Missing asset: $asset" >&2; exit 1; }
if gh release view "$version" --repo "$repo" >/dev/null 2>&1; then
  echo "Release $version already exists; refusing to overwrite it" >&2
  exit 1
fi
# gh creates the tag pointing at main if the tag does not already exist.
gh release create "$version" "$asset" \
  --repo "$repo" --target main --title "rg-grep-compat $version" \
  --notes-file RELEASE_NOTES.md
printf 'Release created: https://github.com/%s/releases/tag/%s\n' "$repo" "$version"
