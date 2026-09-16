#!/usr/bin/env bash
# Auto-increment versionCode in pubspec.yaml, then build a Play Store release AAB.
# Run from project root: ./scripts/release_build.sh
#
# Optional:
#   --dry-run         Preview the next versionCode and build command without changing pubspec or building
#   --skip-increment  Build with the current versionCode (no pubspec change)

set -euo pipefail

DRY_RUN=0
SKIP_INCREMENT=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-increment) SKIP_INCREMENT=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run] [--skip-increment]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"

import_dotenv() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local name="${BASH_REMATCH[1]// /}"
      local value="${BASH_REMATCH[2]}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      export "$name=$value"
    fi
  done < "$env_file"
}

read_version() {
  local line
  line="$(grep -E '^version:[[:space:]]*[^[:space:]+]+\+[0-9]+[[:space:]]*$' "$PUBSPEC" | head -n 1)"
  [[ -n "$line" ]] || { echo "Could not parse version line in pubspec.yaml." >&2; exit 1; }

  VERSION_NAME="${line#version:}"
  VERSION_NAME="${VERSION_NAME%%+*}"
  VERSION_NAME="${VERSION_NAME// /}"
  VERSION_CODE="${line##*+}"
  VERSION_CODE="${VERSION_CODE// /}"
}

write_version_code() {
  local new_code="$1"
  local tmp
  tmp="$(mktemp)"
  sed -E "s/^version:[[:space:]]*[^[:space:]+]+\\+[0-9]+[[:space:]]*$/version: ${VERSION_NAME}+${new_code}/" \
    "$PUBSPEC" > "$tmp"
  mv "$tmp" "$PUBSPEC"
  VERSION_CODE="$new_code"
}

build_dart_defines() {
  DART_DEFINES=()

  if [[ -z "${FIREBASE_API_KEY_ANDROID:-}" ]]; then
    cat >&2 <<'EOF'
Missing FIREBASE_API_KEY_ANDROID.

Set it in .env (copy from .env.example) or in your shell, then re-run:
  ./scripts/release_build.sh
EOF
    exit 1
  fi

  DART_DEFINES+=(--dart-define=FIREBASE_API_KEY_ANDROID="$FIREBASE_API_KEY_ANDROID")

  if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    DART_DEFINES+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
  fi
  if [[ -n "${RECAPTCHA_SITE_KEY:-}" ]]; then
    DART_DEFINES+=(--dart-define=RECAPTCHA_SITE_KEY="$RECAPTCHA_SITE_KEY")
  fi
}

cd "$PROJECT_ROOT"
import_dotenv "$PROJECT_ROOT/.env"
build_dart_defines
read_version

CURRENT_VERSION_CODE="$VERSION_CODE"
TARGET_VERSION_CODE="$VERSION_CODE"
if [[ "$SKIP_INCREMENT" -eq 0 ]]; then
  TARGET_VERSION_CODE=$((VERSION_CODE + 1))
fi

echo '=========================================='
echo ' Medibond Android release build'
echo '=========================================='

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Current pubspec.yaml version: ${VERSION_NAME}+${CURRENT_VERSION_CODE}"
  if [[ "$SKIP_INCREMENT" -eq 1 ]]; then
    echo 'Dry run - would build without changing versionCode.'
  else
    echo "Dry run - next versionCode would be: ${TARGET_VERSION_CODE}"
  fi
elif [[ "$SKIP_INCREMENT" -eq 1 ]]; then
  echo "Using existing version: ${VERSION_NAME}+${TARGET_VERSION_CODE}"
else
  write_version_code "$TARGET_VERSION_CODE"
  echo "Updated pubspec.yaml -> version: ${VERSION_NAME}+${TARGET_VERSION_CODE}"
fi

BUILD_CMD=(flutter build appbundle --release "${DART_DEFINES[@]}")
printf 'Build command: %q ' "${BUILD_CMD[@]}"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo 'Dry run only - pubspec.yaml unchanged and no build executed.'
  echo "Next versionCode for Play Console upload: ${TARGET_VERSION_CODE}"
  exit 0
fi

echo
echo 'Building release app bundle...'
"${BUILD_CMD[@]}"

AAB_PATH="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
echo
echo 'Release build complete.'
echo "  versionName:  ${VERSION_NAME}"
echo "  versionCode:  ${TARGET_VERSION_CODE}"
echo "  AAB output:   ${AAB_PATH}"
echo
echo "Upload to Play Console using versionCode ${TARGET_VERSION_CODE}."
