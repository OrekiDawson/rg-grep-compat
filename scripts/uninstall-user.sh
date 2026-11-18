#!/usr/bin/env bash
set -euo pipefail
rm -f "$HOME/.local/share/rg-grep-compat/bin/grep" "$HOME/.local/bin/rg-grep-compat"
rmdir "$HOME/.local/share/rg-grep-compat/bin" "$HOME/.local/share/rg-grep-compat" 2>/dev/null || true
rm -f "$HOME/.local/libexec/rg-grep-compat/rg-grep-compat"
rmdir "$HOME/.local/libexec/rg-grep-compat" 2>/dev/null || true
printf '已移除用户级 rg-grep-compat 文件。未修改 ~/.zshrc。\n'
