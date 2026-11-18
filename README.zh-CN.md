# rg-grep-compat：让 rg 与 GNU grep 安全共存

**目标**：提供一个可以命名为 `grep` 的原生 Linux 命令入口，避免 `rg` 选项与 GNU grep 选项不兼容导致脚本报错，例如 Codex 安装脚本的 `grep -Eq`。

**重要边界**：**仅靠 ripgrep 本体无法实现 GNU grep 的 100% 行为兼容**。本项目采用“双执行器”：严格模式直接执行 GNU grep，才能获得真正的 GNU 语义；可选加速模式仅把经过保守检查的简单查询交给 `rg`。因此它仍然**依赖系统 GNU grep**，不是独立替代它的实现。

## Kubuntu 快速安装

需要系统安装 `gcc`、`make`、`grep`、`ripgrep`。安装缺少的编译工具（可选）：

```bash
sudo apt install build-essential ripgrep grep
```

在解压的项目目录执行：

```bash
make
make test
make install-user
```

**只在当前终端启用**：

```zsh
unalias grep 2>/dev/null || true
export PATH="$HOME/.local/share/rg-grep-compat/bin:$PATH"
rehash
command -v grep
```

应返回 `~/.local/share/rg-grep-compat/bin/grep`。如果你在 `~/.zshrc` 内写过 `alias grep='rg'`、`alias grep='rg --...'`，要注释掉它们，否则别名仍会抢先接管交互输入。别名通常不传递给 `curl ... | sh` 这种子 Shell，但 PATH 内的错误替身会影响它们。

现在可以再检查导致你之前报错的命令：

```bash
printf '%s\n' 0.170.0 | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
echo $?  # 预期：0
```

**默认严格兼容**：所有调用直接委托 GNU grep，语义由真实 GNU grep 保证。

**可选让安全子集使用 rg**：

```bash
export RG_GREP_MODE=fast
export RG_GREP_TRACE=1   # 调试时开启，正式使用建议关闭
printf 'hello world\n' > /tmp/rg-grep-test.txt
grep -Fq hello /tmp/rg-grep-test.txt
```

可看到 `[rg-grep-compat] ripgrep...`。`grep -Eq` 若包含复杂正则，会自动交给 GNU grep。`fast` 模式目前只覆盖单个小型 ASCII 普通文件上的 `-q` 简单字面量搜索，**并不保证比 GNU grep 更快**；输入预扫描也有开销。

## 为什么不直接 `alias grep=rg`？

因为两者同名选项的语义不同：`grep -E` 是扩展正则；`rg -E` 是指定字符编码。递归搜索、文件过滤、二进制处理、基本正则 BRE、错误输出等也有大量差异。简单别名不能提供兼容性。

## 安全性

- 不需要 root 权限，不修改 `/usr/bin/grep`、`/bin/grep`。
- 安装器不会自动修改 `~/.zshrc`。
- 采用绝对路径调用 GNU grep，避免 PATH 递归进入兼容层。
- 默认严格模式可以直接运行系统安装脚本；不要用此工具替换系统级 grep 包。

## 卸载

```bash
make uninstall-user
rehash
```

如曾在 `~/.zshrc` 中加入 PATH，手动删除对应一行即可。

## 测试与边界

`make test` 会对比 GNU grep 和本程序的退出码、标准输出和标准错误。当前覆盖常规参数、固定字符串、BRE/ERE、二进制、Unicode、递归、错误输出、文件缺失和少量加速路径。

**严格模式的 100% 一致性来自直接调用 GNU grep，不代表 rg 已经实现了所有 GNU grep 语义**。开启 `fast` 后，在文件被其他进程同时修改等竞态环境下无法承诺绝对一致。

使用 MIT License，详见 `LICENSE`。