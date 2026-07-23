#!/bin/sh
set -eu

HOST_NAME=${1:-}
if [ -z "$HOST_NAME" ]; then
  echo "用法: $0 <host> <restic 参数...>" >&2
  exit 2
fi
shift

case "$HOST_NAME" in
  *[!a-z0-9-]*|'')
    echo "非法主机名: $HOST_NAME" >&2
    exit 2
    ;;
esac

if ! grep -Fxq "$HOST_NAME" /config/hosts.txt; then
  echo "主机不在 /config/hosts.txt 中: $HOST_NAME" >&2
  exit 2
fi

REPOSITORY_FILE="/config/repositories/${HOST_NAME}.repository-url"
PASSWORD_FILE="/run/repository-passwords/${HOST_NAME}.repository-password"
ADMIN_PASSWORD_FILE=/run/secrets/admin.http-password

for REQUIRED_FILE in "$REPOSITORY_FILE" "$PASSWORD_FILE" "$ADMIN_PASSWORD_FILE"; do
  if [ ! -r "$REQUIRED_FILE" ]; then
    echo "缺少或无法读取文件: $REQUIRED_FILE" >&2
    exit 2
  fi
done

export RESTIC_REPOSITORY
RESTIC_REPOSITORY=$(sed -n '1p' "$REPOSITORY_FILE")
export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
export RESTIC_REST_USERNAME="${RESTIC_ADMIN_USERNAME:?RESTIC_ADMIN_USERNAME 未设置}"
export RESTIC_REST_PASSWORD
RESTIC_REST_PASSWORD=$(sed -n '1p' "$ADMIN_PASSWORD_FILE")

exec restic "$@"
