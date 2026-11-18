#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-$(pwd)/build/rg-grep-compat}"
[[ -x "$BIN" ]] || { echo "Missing executable: $BIN" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'hello world\nsecond line\nhello again\n' > "$TMP/basic.txt"
printf 'alpha\r\nbeta\r\n' > "$TMP/crlf.txt"
printf 'before\000HELLO\nafter\n' > "$TMP/binary.dat"
printf 'caf\303\251\n' > "$TMP/utf8.txt"
printf 'hidden content\n' > "$TMP/.hidden"
printf 'abc\nabc\nxyz\n' > "$TMP/repeated.txt"
printf 'xx\377\nyy\n' > "$TMP/invalid-utf8.txt"
: > "$TMP/empty.txt"
ln -s "$TMP/basic.txt" "$TMP/link.txt"
mkdir -p "$TMP/nested"
printf 'nested hello\n' > "$TMP/nested/a.txt"
# Deliberately exceed fast-path size limit.
head -c 4300000 /dev/zero | tr '\0' 'a' > "$TMP/large.txt"

PASSED=0
FAILED=0
case_test() {
  local name="$1" mode="$2"; shift 2
  local expected=$? actual=$?
  set +e
  env PATH=/usr/bin:/bin grep "$@" < /dev/null > "$TMP/expected.out" 2> "$TMP/expected.err"
  expected=$?
  RG_GREP_MODE="$mode" "$BIN" "$@" < /dev/null > "$TMP/actual.out" 2> "$TMP/actual.err"
  actual=$?
  set -e
  if [[ "$expected" -eq "$actual" ]] && cmp -s "$TMP/expected.out" "$TMP/actual.out" && cmp -s "$TMP/expected.err" "$TMP/actual.err"; then
    PASSED=$((PASSED+1))
  else
    echo "FAIL: $name (mode=$mode, exit GNU=$expected compat=$actual)" >&2
    diff -u "$TMP/expected.out" "$TMP/actual.out" || true
    diff -u "$TMP/expected.err" "$TMP/actual.err" || true
    FAILED=$((FAILED+1))
  fi
}

# GNU-fidelity mode: broad argument and output compatibility.
case_test 'basic' strict hello "$TMP/basic.txt"
case_test 'numbered' strict -n hello "$TMP/basic.txt"
case_test 'invert' strict -v hello "$TMP/basic.txt"
case_test 'extended' strict -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$TMP/basic.txt"
case_test 'basic regex' strict -G '^h.*d$' "$TMP/basic.txt"
case_test 'fixed' strict -F 'hello' "$TMP/basic.txt"
case_test 'fixed quiet' strict -Fq 'hello' "$TMP/basic.txt"
case_test 'missing match' strict -Fq 'not-there' "$TMP/basic.txt"
case_test 'line count' strict -c 'hello' "$TMP/basic.txt"
case_test 'only match' strict -o 'hello' "$TMP/basic.txt"
case_test 'recursive' strict -r 'hello' "$TMP/nested"
case_test 'with null data' strict -a 'HELLO' "$TMP/binary.dat"
case_test 'null separated' strict -z 'hello' "$TMP/basic.txt"
case_test 'multiple patterns' strict -e hello -e second "$TMP/basic.txt"
case_test 'case insensitive' strict -i hello "$TMP/basic.txt"
case_test 'max count' strict -m 1 hello "$TMP/basic.txt"
case_test 'missing file' strict hello "$TMP/non-existent.txt"
case_test 'invalid expression' strict -E '[' "$TMP/basic.txt"
case_test 'unicode text' strict 'café' "$TMP/utf8.txt"
case_test 'version' strict --version
case_test 'empty file' strict -q '' "$TMP/empty.txt"

# Fast mode: safe cases use rg, everything else must transparently fallback.
case_test 'rg match fixed' fast -Fq hello "$TMP/basic.txt"
case_test 'rg no match fixed' fast -qF absent "$TMP/basic.txt"
case_test 'rg match extended literal' fast -Eq hello "$TMP/basic.txt"
case_test 'rg no match extended literal' fast -qE absent "$TMP/basic.txt"
case_test 'rg pattern option' fast --quiet --fixed-strings --regexp=hello "$TMP/basic.txt"
case_test 'rg pattern attached' fast -Fqehello "$TMP/basic.txt"
case_test 'rg empty pattern on nonempty file' fast -Fq '' "$TMP/basic.txt"
case_test 'rg empty pattern on empty file' fast -Fq '' "$TMP/empty.txt"
case_test 'rg CRLF' fast -Fq alpha "$TMP/crlf.txt"
case_test 'rg symlink fallback' fast -Fq hello "$TMP/link.txt"
case_test 'rg binary fallback' fast -Fq HELLO "$TMP/binary.dat"
case_test 'rg UTF-8 fallback' fast -Fq café "$TMP/utf8.txt"
case_test 'rg large file fallback' fast -Fq hello "$TMP/large.txt"
case_test 'rg regex fallback' fast -Eq '^hello.*$' "$TMP/basic.txt"
case_test 'rg invalid regex fallback' fast -Eq '[' "$TMP/basic.txt"
case_test 'rg recursive fallback' fast -rq hello "$TMP/nested"
case_test 'rg stdin fallback' fast -Fq hello -
case_test 'rg missing file fallback' fast -Fq hello "$TMP/non-existent.txt"
case_test 'rg error output' fast -F hello "$TMP/basic.txt"
case_test 'rg pattern with slash' fast -Fq /tmp "$TMP/basic.txt"
case_test 'rg audit' audit -Fq hello "$TMP/basic.txt"

# Verify actual selection on a known-safe case (opt-in tracing only).
RG_GREP_TRACE=1 RG_GREP_MODE=fast "$BIN" -Fq hello "$TMP/basic.txt" 2> "$TMP/trace"
if /usr/bin/grep -q 'ripgrep (safe fixed-literal' "$TMP/trace"; then
  PASSED=$((PASSED+1))
else
  echo 'FAIL: fast mode did not select rg' >&2
  FAILED=$((FAILED+1))
fi

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
