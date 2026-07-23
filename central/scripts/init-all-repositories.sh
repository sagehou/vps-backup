#!/bin/sh
set -u

HOSTS_FILE=${HOSTS_FILE:-/config/hosts.txt}
INIT_REPOSITORY=${INIT_REPOSITORY:-/scripts/init-repository.sh}

if [ ! -r "$HOSTS_FILE" ]; then
  echo "主机清单不存在或无法读取: $HOSTS_FILE" >&2
  exit 2
fi

TOTAL=0
SUCCEEDED=0
FAILED=0

while IFS= read -r HOST_NAME || [ -n "$HOST_NAME" ]; do
  case "$HOST_NAME" in
    ''|'#'*) continue ;;
  esac

  TOTAL=$((TOTAL + 1))
  echo "===== 处理仓库: $HOST_NAME ====="

  # 子初始化不得继承 hosts.txt 的 stdin，否则第一个子进程可能吞掉
  # 剩余主机清单，表现为批量任务只执行一个仓库。
  if "$INIT_REPOSITORY" "$HOST_NAME" </dev/null; then
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "===== 初始化失败，继续下一个仓库: $HOST_NAME =====" >&2
  fi
done < "$HOSTS_FILE"

echo "批量初始化完成: 总计=$TOTAL 成功或已存在=$SUCCEEDED 失败=$FAILED"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
