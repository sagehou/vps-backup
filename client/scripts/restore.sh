#!/bin/sh
set -eu

usage() {
  cat >&2 <<'EOF'
用法:
  /scripts/restore.sh <snapshot-id|latest> <快照内绝对路径>

示例:
  /scripts/restore.sh latest /backup/data/www
  /scripts/restore.sh 0123456789abcdef /backup/etc/nginx

恢复内容会写入 /restore 下新建的独立目录，不会覆盖备份源。
EOF
  exit 2
}

[ "$#" -eq 2 ] || usage

SNAPSHOT_ID=$1
SNAPSHOT_PATH=$2

case "$SNAPSHOT_ID" in
  latest) ;;
  *[!a-fA-F0-9]*|'')
    echo "非法快照 ID：只能使用 latest 或十六进制快照 ID" >&2
    exit 2
    ;;
esac

case "$SNAPSHOT_PATH" in
  /*) ;;
  *)
    echo "快照路径必须是以 / 开头的绝对路径" >&2
    exit 2
    ;;
esac

case "/$SNAPSHOT_PATH/" in
  */../*|*/./*)
    echo "快照路径不能包含 . 或 .. 路径组件" >&2
    exit 2
    ;;
esac

if [ ! -d /restore ] || [ ! -w /restore ]; then
  echo "/restore 不存在或不可写；请检查 Compose 的恢复目录挂载及权限" >&2
  exit 2
fi

if [ ! -x /scripts/restic-command.sh ]; then
  echo "缺少可执行认证入口 /scripts/restic-command.sh" >&2
  exit 2
fi

RESTORE_DIR=$(mktemp -d /restore/restic-restore.XXXXXX)
echo "快照: $SNAPSHOT_ID"
echo "恢复路径: $SNAPSHOT_PATH"
echo "恢复目标: $RESTORE_DIR"
echo "开始恢复到隔离目录；不会覆盖在线数据。"

if /scripts/restic-command.sh restore "$SNAPSHOT_ID" \
  --target "$RESTORE_DIR" \
  --include "$SNAPSHOT_PATH"; then
  echo "恢复完成。"
  echo "容器内路径: $RESTORE_DIR"
  echo "宿主机路径: /data/restic-client/restore/${RESTORE_DIR##*/}"
else
  RESULT=$?
  echo "恢复失败，临时目录保留以便排查: $RESTORE_DIR" >&2
  exit "$RESULT"
fi
