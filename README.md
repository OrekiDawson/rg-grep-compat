# rg-grep-compat

A **GNU grep compatibility dispatcher** for Linux. It preserves GNU grep's CLI behavior in **strict mode** (the default) and optionally uses ripgrep for a narrow, verified set of queries.

> [!IMPORTANT]
> ripgrep is not a drop-in, 100%-compatible GNU grep replacement. This project obtains exact GNU behavior by *delegating to a real GNU grep binary*. Without GNU grep installed, a 100% compatibility guarantee is not possible. `fast` mode has a conservative optimization, but filesystem races and different implementations mean literal 100% equivalence cannot be promised for that mode.

## What it solves

Replacing `grep` with `rg` through a symlink breaks scripts such as `grep -Eq PATTERN`: `rg -E` is an encoding flag, not GNU grep's extended-regexp flag. This dispatcher forwards such commands to GNU grep unchanged. It **never modifies `/usr/bin/grep`**.

## Requirements

- Linux x86_64 (other Linux architectures can build from source)
- A C11 compiler (`gcc` or `clang`) and `make` for source builds
- GNU grep at `/usr/bin/grep` or `/bin/grep`
- ripgrep at `/usr/bin/rg` or `/bin/rg` for the optional `fast` mode

## Build and test

```bash
make
make test
```

## Install in your home directory (no sudo)

```bash
make install-user
unalias grep 2>/dev/null || true  # zsh / bash aliases can override binaries
export PATH="$HOME/.local/share/rg-grep-compat/bin:$PATH"
command -v grep
# Expect ~/.local/share/rg-grep-compat/bin/grep
```

Add only the `export PATH=...` line to your `~/.zshrc` if you want this permanently. The installer intentionally doesn't edit your shell files.

By default, `grep` **always delegates to GNU grep**. To opt into limited ripgrep acceleration:

```bash
export RG_GREP_MODE=fast
export RG_GREP_TRACE=1    # optional diagnostic output; disable in normal scripts
printf 'hello\n' > /tmp/rg-grep-sample.txt
grep -Fq 'hello' /tmp/rg-grep-sample.txt
# [rg-grep-compat] ripgrep (safe fixed-literal quiet fast path)

printf '0.170.0\n' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
# Falls back to GNU grep, and succeeds (exit code 0)
```

`fast` mode recognizes only **quiet (`-q`) searches with one small, regular ASCII file and a simple literal pattern**. It supports `-F`/`-E` where equivalent. The file must not be a symlink or contain NUL/high-bit bytes. It falls back to GNU grep for stdin, binary data, Unicode, recursive searches, context printing, advanced regex, errors, and any unrecognized flags. This preflight costs extra I/O; `fast` mode is not guaranteed to outperform native GNU grep for small files. Performance depends on real workloads.

## Environment variables

| Name | Default | Purpose |
| --- | --- | --- |
| `RG_GREP_MODE` | `strict` | `strict` / `fast` / `audit` |
| `RG_GREP_TRACE` | unset | Set to `1` for backend selection messages on stderr |
| `RG_GREP_GNU_PATH` | `/usr/bin/grep` then `/bin/grep` | Optional **absolute** GNU grep executable path |
| `RG_GREP_RG_PATH` | `/usr/bin/rg` then `/bin/rg` | Optional **absolute** ripgrep executable path |

`audit` runs ripgrep for eligible queries, but GNU grep remains authoritative for final output and exit status. Traces can reveal the eligible paths. `RG_GREP_TRACE` should stay disabled in production to avoid changing stderr.

## Uninstall

```bash
make uninstall-user
hash -r   # for bash, or 'rehash' in zsh
```

If you permanently changed PATH in `~/.zshrc`, remove that line. The installer/uninstaller never modifies system files.

## Security and scope

- No `sudo`, no execution of shell command strings, no auto-downloads.
- The real GNU grep path is resolved independently of PATH and checked against the dispatcher executable to prevent direct recursion.
- Unknown flags are **never** rewritten into an approximate ripgrep equivalent.
- This is an initial conservative implementation, not a full GNU grep parser, regex translator, or a guarantee of faster searches.
- Tests check both exit codes and exact stdout/stderr against GNU grep.

License: MIT. See `LICENSE`.