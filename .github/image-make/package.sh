#!/usr/bin/env bash
set -euo pipefail

if [[ "$PACKAGE_MODE" == pull-release ]]; then
  echo "========== Aliyun registry login =========="
  echo "[INFO] logging in to Aliyun registry..."
  printf '%s' "$ALIYUN_PASSWORD" | docker login "$ALIYUN_REGISTRY" --username "$ALIYUN_USERNAME" --password-stdin >/dev/null
  echo "[OK] Aliyun registry login"
  package_image="$ALIYUN_IMAGE"
  echo "========== docker pull =========="
  echo "[INFO] pulling $package_image..."
  pull_log="pull-${ARCHITECTURE}.log"
  if ! docker pull --platform "linux/${ARCHITECTURE}" "$package_image" >"$pull_log" 2>&1; then
    echo "[ERROR] docker pull failed"
    tail -n 100 "$pull_log"
    exit 1
  fi
  echo "[OK] docker pull"
  echo "========== package platform check =========="
  actual="$(docker image inspect "$package_image" --format '{{.Architecture}}')"
  test "$actual" = "$ARCHITECTURE"
  echo "[OK] platform: $actual"
  mkdir -p release-assets
  image_name="${TARGET_IMAGE##*/}"
  image_name="${image_name%%@*}"
  image_name="${image_name%%:*}"
  archive="release-assets/${image_name}_${RELEASE_TAG}.tar.gz"
  docker save "$package_image" | gzip -9 > "$archive"
  sha256sum "$archive" > "$archive.sha256"
  echo "[OK] image package: $archive"
else
  echo "========== package artifact check =========="
  image_name="${TARGET_IMAGE##*/}"
  image_name="${image_name%%@*}"
  image_name="${image_name%%:*}"
  archive="release-assets/${image_name}_${RELEASE_TAG}.tar.gz"
  test -f "$archive"
  test -f "$archive.sha256"
  echo "[OK] build artifact: $archive"
fi

echo "========== package result =========="
echo "PACKAGE SUCCESS"

{
  echo "## Package $ARCHITECTURE summary"
  echo
  echo "- **Mode:** \`$PACKAGE_MODE\`"
  if [[ "$PACKAGE_MODE" == pull-release ]]; then
    echo "- **Source image:** \`$package_image\`"
  else
    echo "- **Source:** build job artifact \`release-$ARCHITECTURE\`"
  fi
  echo "- **Platform check:** \`linux/$ARCHITECTURE\`"
  image_name="${TARGET_IMAGE##*/}"
  image_name="${image_name%%@*}"
  image_name="${image_name%%:*}"
  echo "- **Archive:** \`${image_name}_${RELEASE_TAG}.tar.gz\`"
} >> "$GITHUB_STEP_SUMMARY"
