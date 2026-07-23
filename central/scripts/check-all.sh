#!/bin/sh
set -u

case "${CHECK_READ_DATA_SUBSET:-}" in
  ''|CHANGE_ME*)
    echo "CHECK_READ_DATA_SUBSET 未配置" >&2
    exit 2
    ;;
esac

FAILED=0

while IFS= read -r HOST_NAME || [ -n "$HOST_NAME" ]; do
  case "$HOST_NAME" in
    ''|'#'*) continue ;;
  esac

  echo "===== 开始检查: $HOST_NAME ====="
  if /scripts/run-restic.sh "$HOST_NAME" check \
      --read-data-subset="$CHECK_READ_DATA_SUBSET"; then
    echo "===== 检查完成: $HOST_NAME ====="
  else
    echo "===== 检查失败，继续下一个仓库: $HOST_NAME =====" >&2
    FAILED=1
  fi
done < /config/hosts.txt

exit "$FAILED"
