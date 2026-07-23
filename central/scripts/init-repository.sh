#!/bin/sh
set -eu

RUN_RESTIC=${RUN_RESTIC:-/scripts/run-restic.sh}

HOST_NAME=${1:-}
if [ -z "$HOST_NAME" ]; then
  echo "用法: $0 <host>" >&2
  exit 2
fi

if "$RUN_RESTIC" "$HOST_NAME" cat config >/dev/null 2>&1; then
  echo "仓库已存在，跳过初始化: $HOST_NAME"
  exit 0
fi

echo "正在初始化仓库: $HOST_NAME"
if "$RUN_RESTIC" "$HOST_NAME" init; then
  echo "仓库初始化完成: $HOST_NAME"
  exit 0
fi

# 处理并发初始化或第一次探测时的瞬时错误：只要现在能读取配置，
# 仓库就已经可用，应当按幂等成功处理。
if "$RUN_RESTIC" "$HOST_NAME" cat config >/dev/null 2>&1; then
  echo "仓库已由其他操作完成初始化: $HOST_NAME"
  exit 0
fi

echo "仓库初始化失败: $HOST_NAME" >&2
exit 1
