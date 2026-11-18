#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-$(pwd)/build/rg-grep-compat}"
[[ -x "$BIN" ]] || { echo "请先 make" >&2; exit 1; }
DEST="$HOME/.local/libexec/rg-grep-compat"
SHIM="$HOME/.local/share/rg-grep-compat/bin"
mkdir -p "$DEST" "$SHIM" "$HOME/.local/bin"
install -m 0755 "$BIN" "$DEST/rg-grep-compat"
ln -sfn "$DEST/rg-grep-compat" "$SHIM/grep"
ln -sfn "$DEST/rg-grep-compat" "$HOME/.local/bin/rg-grep-compat"
printf '安装完成（未修改系统文件或 shell 配置）。\n\n'
printf '仅当前终端启用：\n  unalias grep 2>/dev/null || true\n  export PATH="%s:$PATH"\n\n' "$SHIM"
printf '严格兼容（默认）：grep --version\n'
printf '可选安全 rg 加速：export RG_GREP_MODE=fast\n'
printf '观察选用的后端：export RG_GREP_TRACE=1\n'
