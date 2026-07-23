#!/bin/sh
set -eu

for VARIABLE_NAME in RESTIC_HOST RESTIC_REPOSITORY; do
  eval "VARIABLE_VALUE=\${$VARIABLE_NAME:-}"
  case "$VARIABLE_VALUE" in
    ''|CHANGE_ME*)
      echo "客户端参数未配置: $VARIABLE_NAME" >&2
      exit 2
      ;;
  esac
done

for REQUIRED_FILE in \
  /run/secrets/restic-rest-password \
  /run/secrets/repository-password \
  /config/excludes.txt; do
  if [ ! -r "$REQUIRED_FILE" ]; then
    echo "缺少或无法读取文件: $REQUIRED_FILE" >&2
    exit 2
  fi
done

export RESTIC_REST_USERNAME="$RESTIC_HOST"
export RESTIC_REST_PASSWORD
RESTIC_REST_PASSWORD=$(sed -n '1p' /run/secrets/restic-rest-password)
export RESTIC_PASSWORD_FILE=/run/secrets/repository-password

cd /backup
set -- backup \
  --host "$RESTIC_HOST" \
  --skip-if-unchanged \
  --iexclude-file=/config/excludes.txt \
  --verbose

SOURCE_COUNT=0
for SOURCE_PATH in /backup/*; do
  if [ ! -e "$SOURCE_PATH" ]; then
    continue
  fi

  SOURCE_NAME=${SOURCE_PATH#/backup/}
  set -- "$@" "$SOURCE_NAME"
  SOURCE_COUNT=$((SOURCE_COUNT + 1))
done

if [ "$SOURCE_COUNT" -eq 0 ]; then
  echo "/backup 下没有可用的备份源挂载" >&2
  exit 2
fi

restic "$@"
restic snapshots --host "$RESTIC_HOST" --latest 1
