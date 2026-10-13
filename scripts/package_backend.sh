#!/usr/bin/env bash
set -euo pipefail
seftly_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$seftly_root/backend"
npm run build
npm run lint
npm test
npm audit --audit-level=high
seftly_release="$(git rev-parse --short HEAD)-working-tree"
mkdir -p "$seftly_root/release_artifacts"
seftly_stage="$(mktemp -d "$seftly_root/release_artifacts/backend-stage.XXXXXX")"
trap 'rm -rf "$seftly_stage"' EXIT
seftly_dir="$seftly_stage/backend-$seftly_release"
mkdir -p "$seftly_dir"
cp -R dist "$seftly_dir/dist"
cp package.json package-lock.json .env.example "$seftly_dir/"
printf '%s\n' "$seftly_release" > "$seftly_dir/REVISION"
# An operator must supply the host's existing private environment separately.
COPYFILE_DISABLE=1 tar -czf "$seftly_root/release_artifacts/backend-$seftly_release.tgz" -C "$seftly_stage" "backend-$seftly_release"
# Preserve earlier generated staging rather than merging stale dist files.
if [ -d "$seftly_root/release_artifacts/backend-$seftly_release" ]; then
  mv "$seftly_root/release_artifacts/backend-$seftly_release" "$seftly_root/release_artifacts/backend-previous-${seftly_stage##*/}"
fi
mv "$seftly_dir" "$seftly_root/release_artifacts/"
printf 'Prepared %s\n' "$seftly_root/release_artifacts/backend-$seftly_release.tgz"
