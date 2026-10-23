#!/usr/bin/env bash
# Auto-increment versionCode in pubspec.yaml, then build a Play Store release AAB.
# Run from frontend root: ./scripts/release_build.sh
#
# Supabase Cutover Release:
#   To build a cutover release with Supabase connectivity enabled, pass ENABLE_SUPABASE=1:
#     ENABLE_SUPABASE=1 ./scripts/release_build.sh
#   Requires SUPABASE_URL and SUPABASE_ANON_KEY to be set in .env or shell environment.
#   NEVER set SUPABASE_SERVICE_ROLE_KEY in client environment (build will fail).
#
# Optional:
#   --dry-run         Preview the next versionCode and build command without changing pubspec or building
#   --skip-increment  Build with the current versionCode (no pubspec change)
#   --allow-staging   Allow staging Supabase URL during build verification

set -euo pipefail

DRY_RUN=0
SKIP_INCREMENT=0
ALLOW_STAGING=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-increment) SKIP_INCREMENT=1 ;;
    --allow-staging) ALLOW_STAGING=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run] [--skip-increment] [--allow-staging]" >&2
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
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
      cat >&2 <<'EOF'
Missing FIREBASE_API_KEY_ANDROID.

Project root .env is missing (functions/.env is for Cloud Functions only).
Create it from the template, then set your Android Firebase API key:

  cp .env.example .env
  # Edit .env and set FIREBASE_API_KEY_ANDROID=<Android app API key from Firebase Console>

Re-run: ./scripts/release_build.sh
EOF
    else
      cat >&2 <<'EOF'
Missing FIREBASE_API_KEY_ANDROID.

Set FIREBASE_API_KEY_ANDROID in project root .env (not functions/.env), or export it in your shell.

Re-run: ./scripts/release_build.sh
EOF
    fi
    exit 1
  fi

  DART_DEFINES+=(--dart-define=FIREBASE_API_KEY_ANDROID="$FIREBASE_API_KEY_ANDROID")

  if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    DART_DEFINES+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
  fi
  if [[ -n "${RECAPTCHA_SITE_KEY:-}" ]]; then
    DART_DEFINES+=(--dart-define=RECAPTCHA_SITE_KEY="$RECAPTCHA_SITE_KEY")
  fi

  # Guard: SUPABASE_SERVICE_ROLE_KEY must NEVER be present in client release build environment
  if [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    echo "SECURITY ERROR: SUPABASE_SERVICE_ROLE_KEY detected in environment. Service role keys must NEVER be present during client builds." >&2
    exit 1
  fi

  # Never pass USE_SUPABASE_AUTH. Inject Supabase compile-time config only when
  # ENABLE_SUPABASE=1 is set explicitly for this release.
  if [[ "${ENABLE_SUPABASE:-}" == "1" ]]; then
    echo "WARNING: ENABLE_SUPABASE=1 — injecting SUPABASE_URL and SUPABASE_ANON_KEY dart-defines into this release build." >&2
    if [[ -z "${SUPABASE_URL:-}" ]]; then
      echo "Missing required environment variable: SUPABASE_URL (required when ENABLE_SUPABASE=1)" >&2
      exit 1
    fi
    if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
      echo "Missing required environment variable: SUPABASE_ANON_KEY (required when ENABLE_SUPABASE=1)" >&2
      exit 1
    fi
    DART_DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
    DART_DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
  fi
}

validate_production_build_config() {
  local validator="$SCRIPT_DIR/verify_production_build_config.js"
  if [[ ! -f "$validator" ]]; then
    validator="$PROJECT_ROOT/../backend/scripts/verify_production_build_config.js"
  fi
  if [[ -f "$validator" ]]; then
    local validator_args=("$validator" "--client-only")
    if [[ "$ALLOW_STAGING" -eq 1 || "${ALLOW_STAGING_BUILD:-}" == "true" ]]; then
      validator_args+=("--allow-staging")
    fi
    if [[ -n "${SUPABASE_URL:-}" ]]; then
      validator_args+=("--supabase-url=$SUPABASE_URL")
    fi
    if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
      validator_args+=("--supabase-anon-key=$SUPABASE_ANON_KEY")
    fi
    node "${validator_args[@]}"
  fi
}

cd "$PROJECT_ROOT"
import_dotenv "$PROJECT_ROOT/.env"
build_dart_defines
validate_production_build_config
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
