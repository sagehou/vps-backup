#!/bin/sh
set -u

for VARIABLE_NAME in KEEP_LAST KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY KEEP_YEARLY KEEP_WITHIN; do
  eval "VARIABLE_VALUE=\${$VARIABLE_NAME:-}"
  case "$VARIABLE_VALUE" in
    ''|CHANGE_ME*)
      echo "保留参数未配置: $VARIABLE_NAME" >&2
      exit 2
      ;;
  esac
done

FAILED=0

while IFS= read -r HOST_NAME || [ -n "$HOST_NAME" ]; do
  case "$HOST_NAME" in
    ''|'#'*) continue ;;
  esac

  echo "===== 开始维护: $HOST_NAME ====="
  if /scripts/run-restic.sh "$HOST_NAME" forget \
      --keep-last "$KEEP_LAST" \
      --keep-daily "$KEEP_DAILY" \
      --keep-weekly "$KEEP_WEEKLY" \
      --keep-monthly "$KEEP_MONTHLY" \
      --keep-yearly "$KEEP_YEARLY" \
      --keep-within "$KEEP_WITHIN" \
      --group-by host,paths \
      --prune; then
    echo "===== 维护完成: $HOST_NAME ====="
  else
    echo "===== 维护失败，继续下一个仓库: $HOST_NAME =====" >&2
    FAILED=1
  fi
done < /config/hosts.txt

exit "$FAILED"
