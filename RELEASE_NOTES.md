# rg-grep-compat v0.1.0

Initial Linux release of a GNU `grep` compatibility dispatcher with an optional, conservative ripgrep fast path.

## Highlights

- Fixes compatibility failures such as `grep -Eq` being interpreted by `rg` as an encoding argument.
- Default `strict` mode forwards arguments, output, and exit status to GNU grep without rewriting them.
- Optional `RG_GREP_MODE=fast` uses ripgrep only for a very narrow set of eligible quiet, single-file, ASCII literal searches; all other calls fall back to GNU grep.
- A user-local installer and uninstaller that do not modify `/usr/bin/grep`.
- Differential test suite covering 43 cases; passed on the release builder.
- Linux x86_64 static binary included as a separate release asset.

## Requirements

GNU grep remains a required dependency for GNU-compatible behavior. `fast` mode requires ripgrep. The `fast` path is not a proof of full semantic equivalence and may be slower for small files. This release does **not** turn ripgrep into a fully standalone, 100%-compatible GNU grep implementation.

## Install

Download the release archive or binary, and consult `README.md` / `README.zh-CN.md` for the user-local installation instructions. Do not replace your system `/usr/bin/grep`.