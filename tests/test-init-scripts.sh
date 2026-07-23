#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${TMPDIR:-$ROOT_DIR/tests/.tmp}/vps-backup-tests"
mkdir -p "$TMP_ROOT"
TMP_DIR=$(mktemp -d "$TMP_ROOT/init.XXXXXX")
case "$TMP_DIR" in
  "$TMP_ROOT"/*) ;;
  *) echo "FAIL: 临时目录不在预期工作区内: $TMP_DIR" >&2; exit 1 ;;
esac
trap 'case "$TMP_DIR" in "$TMP_ROOT"/*) rm -rf -- "$TMP_DIR" ;; esac' EXIT HUP INT TERM

CALL_LOG="$TMP_DIR/calls.log"
export CALL_LOG

cat > "$TMP_DIR/fake-run-restic.sh" <<'EOF'
#!/bin/sh
set -eu

HOST_NAME=$1
COMMAND=$2
printf '%s %s\n' "$HOST_NAME" "$COMMAND" >> "$CALL_LOG"

# 主动读取 stdin，复现 docker compose exec 吞掉外层 hosts.txt 的行为。
cat >/dev/null

case "$HOST_NAME:$COMMAND" in
  existing:cat) exit 0 ;;
  new-one:cat|after-bad:cat) exit 1 ;;
  new-one:init|after-bad:init) exit 0 ;;
  bad:cat|bad:init) exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP_DIR/fake-run-restic.sh"

cat > "$TMP_DIR/hosts.txt" <<'EOF'
existing
new-one
bad
after-bad
EOF

set +e
HOSTS_FILE="$TMP_DIR/hosts.txt" \
INIT_REPOSITORY="$ROOT_DIR/central/scripts/init-repository.sh" \
RUN_RESTIC="$TMP_DIR/fake-run-restic.sh" \
  "$ROOT_DIR/central/scripts/init-all-repositories.sh" \
  >"$TMP_DIR/stdout.log" 2>"$TMP_DIR/stderr.log"
STATUS=$?
set -e

if [ "$STATUS" -ne 1 ]; then
  echo "FAIL: 有一个仓库失败时，批量脚本应返回 1，实际为 $STATUS" >&2
  exit 1
fi

if grep -Fq 'existing init' "$CALL_LOG"; then
  echo "FAIL: 已存在仓库不应再次 init" >&2
  exit 1
fi

for EXPECTED_CALL in 'new-one init' 'bad init' 'after-bad init'; do
  if ! grep -Fq "$EXPECTED_CALL" "$CALL_LOG"; then
    echo "FAIL: 缺少调用 $EXPECTED_CALL" >&2
    exit 1
  fi
done

if ! grep -Fq '总计=4' "$TMP_DIR/stdout.log"; then
  echo "FAIL: 子进程吞 stdin 后仍应处理全部 4 台主机" >&2
  exit 1
fi

echo "init script regression test OK"
