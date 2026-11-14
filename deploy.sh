#!/bin/bash
set -euo pipefail

ENV_NAME=$1
VERSION=$2

# Project configuration (modify this block when adapting to another project)
APP_NAME="${APP_NAME:-hello-pipeline}"
IMAGE="${IMAGE:-$APP_NAME}"
APP_PORT=3000
HEALTH_ENDPOINT="/health"

# Validate environment and assign host port
case "$ENV_NAME" in
  staging) HOST_PORT=8081 ;;
  prod)    HOST_PORT=8080 ;;
  *) echo "Invalid environment: $ENV_NAME (use staging or prod)"; exit 1 ;;
esac

NAME="$APP_NAME-$ENV_NAME"

# Stop and remove existing container if running
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Run new container with environment configuration
docker run -d --name "$NAME" --env-file "env/$ENV_NAME.env" -p "$HOST_PORT:$APP_PORT" "$IMAGE:$VERSION"

# Run smoke test
echo "Running smoke test on $ENV_NAME ..."
for i in {1..10}; do
  if curl -fsS "http://localhost:$HOST_PORT$HEALTH_ENDPOINT" >/dev/null; then
    echo "Successfully deployed to $ENV_NAME!"
    exit 0
  fi
  sleep 1
done

# Smoke test failed
echo "Smoke test failed!"
docker logs "$NAME"
exit 1
