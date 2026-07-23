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

export RESTIC_REST_USERNAME="$RESTIC_HOST"
export RESTIC_REST_PASSWORD
RESTIC_REST_PASSWORD=$(sed -n '1p' /run/secrets/restic-rest-password)
export RESTIC_PASSWORD_FILE=/run/secrets/repository-password

exec restic "$@"
