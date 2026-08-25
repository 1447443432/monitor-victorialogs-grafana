#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BASE_REGISTRY_USERNAME:-}" && -n "${BASE_REGISTRY_PASSWORD:-}" ]]; then
  echo "========== base registry login =========="
  echo "[INFO] logging in to base registry..."
  if [[ "$BASE_IMAGE" != */* ]]; then
    base_registry="docker.io"
  else
    base_registry="${BASE_IMAGE%%/*}"
    if [[ "$base_registry" != *.* && "$base_registry" != *:* && "$base_registry" != "localhost" ]]; then
      base_registry="docker.io"
    fi
  fi
  printf '%s' "$BASE_REGISTRY_PASSWORD" | docker login "$base_registry" --username "$BASE_REGISTRY_USERNAME" --password-stdin >/dev/null
  echo "[OK] base registry login"
fi

if [[ "$PUSH_ALIYUN" == true ]]; then
  echo "========== Aliyun registry login =========="
  echo "[INFO] logging in to Aliyun registry..."
  printf '%s' "$ALIYUN_PASSWORD" | docker login "$ALIYUN_REGISTRY" --username "$ALIYUN_USERNAME" --password-stdin >/dev/null
  echo "[OK] Aliyun registry login"
fi

builder="image-make-${ARCHITECTURE}"
if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
  docker buildx create --name "$builder" --driver docker-container --use >/dev/null
else
  docker buildx use "$builder"
fi

echo "========== docker build =========="
echo "[INFO] docker build running..."
build_log="build-${ARCHITECTURE}.log"
if ! docker buildx build --builder "$builder" \
  --platform "$PLATFORM" \
  --build-arg TARGETARCH="$ARCHITECTURE" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg ALPINE_MIRROR="$ALPINE_MIRROR" \
  --build-arg ALPINE_VERSION="$ALPINE_VERSION" \
  --file "$DOCKERFILE" \
  --tag "$TARGET_IMAGE" \
  --load "$BUILD_CONTEXT" >"$build_log" 2>&1; then
  echo "[ERROR] docker build failed"
  tail -n 200 "$build_log"
  exit 1
fi
echo "[OK] docker build"

aliyun_image="$ALIYUN_IMAGE_OVERRIDE"
if [[ "$PUSH_ALIYUN" == true ]]; then
  echo "========== docker push =========="
  echo "[INFO] pushing $aliyun_image..."
  docker tag "$TARGET_IMAGE" "$aliyun_image"
  push_log="push-${ARCHITECTURE}.log"
  if ! docker push "$aliyun_image" >"$push_log" 2>&1; then
    echo "[ERROR] docker push failed"
    tail -n 100 "$push_log"
    exit 1
  fi
  echo "[OK] docker push"
fi

image_name="${TARGET_IMAGE##*/}"
image_name="${image_name%%@*}"
image_name="${image_name%%:*}"
if [[ "$RELEASE_ENABLED" == true ]]; then
  echo "========== image package =========="
  echo "[INFO] saving local image..."
  mkdir -p release-assets
  archive="release-assets/${image_name}_${RELEASE_TAG}.tar.gz"
  docker save "$TARGET_IMAGE" | gzip -9 > "$archive"
  sha256sum "$archive" > "$archive.sha256"
  echo "[OK] image package: $archive"
fi

echo "========== build result =========="
echo "BUILD SUCCESS"
echo "image=$TARGET_IMAGE"
echo "arch=$ARCHITECTURE"

{
  echo "## Build $ARCHITECTURE summary"
  echo
  echo "| Item | Value |"
  echo "|---|---|"
  echo "| Architecture | \`$ARCHITECTURE\` |"
  echo "| Platform | \`$PLATFORM\` |"
  echo "| Runner | \`$RUNNER\` |"
  echo "| Base image | \`$BASE_IMAGE\` |"
  echo "| Local image | \`$TARGET_IMAGE\` |"
  if [[ "$PUSH_ALIYUN" == true ]]; then
    echo "| Aliyun push | enabled: \`$aliyun_image\` |"
  else
    echo "| Aliyun push | skipped: registry credentials or destination are missing |"
  fi
  echo "| Release package | \`${image_name}_${RELEASE_TAG}.tar.gz\` |"
} >> "$GITHUB_STEP_SUMMARY"
