#!/bin/bash
set -euo pipefail

ENV_NAME=$1
VERSION=$2
IMAGE="${IMAGE:-hello-pipeline}"

case "$ENV_NAME" in
  staging) PORT=8081 ;;
  prod)    PORT=8080 ;;
  *) echo "Môi trường không hợp lệ: $ENV_NAME (dùng staging hoặc prod)"; exit 1 ;;
esac

NAME="hello-$ENV_NAME"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --env-file "env/$ENV_NAME.env" -p "$PORT:3000" "$IMAGE:$VERSION"

echo "Đang kiểm tra (smoke test) $ENV_NAME ..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://localhost:$PORT/health" >/dev/null; then
    echo "Triển khai thành công lên $ENV_NAME:"
    curl -fsS "http://localhost:$PORT/"
    exit 0
  fi
  sleep 1
done

echo "Smoke test thất bại!"
docker logs "$NAME"
exit 1