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
LAUNCH=0

EXTRA_DEFINES=()

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-increment) SKIP_INCREMENT=1 ;;
    --allow-staging) ALLOW_STAGING=1 ;;
    --launch)
      LAUNCH=1
      export ENABLE_SUPABASE=1
      export USE_SUPABASE_DB_DOCTOR_PATIENT="true"
      if [[ -z "${SUPABASE_URL:-}" ]]; then
        export SUPABASE_URL="https://rnltknemwnjrjxthtull.supabase.co"
      fi
      if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
        export SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJubHRrbmVtd25qcmp4dGh0dWxsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NjM3MjIsImV4cCI6MjEwNjUzOTcyMn0.d4bALRDReFuGSNKpxz0iOTyHpaE95Tlpd3DfDxvzvAY"
      fi
      echo "LAUNCH PROFILE ACTIVE: Building release with Supabase primary database enabled." >&2
      ;;
    --dart-define=*) EXTRA_DEFINES+=("$arg") ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run] [--skip-increment] [--allow-staging] [--launch]" >&2
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
    if [[ ! -f "$PROJECT_ROOT/.env" && ! -f "$PROJECT_ROOT/../.env" ]]; then
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
    if [[ "$LAUNCH" == "1" || "${USE_SUPABASE_DB_DOCTOR_PATIENT:-}" == "true" ]]; then
      DART_DEFINES+=(--dart-define=USE_SUPABASE_DB_DOCTOR_PATIENT=true)
    fi
  fi

  local all_defines=("${DART_DEFINES[@]}" "${EXTRA_DEFINES[@]}")

  # Guard: APP_CHECK_DEBUG_TOKEN or any *DEBUG_TOKEN* must NEVER be passed as a --dart-define in release builds
  for define in "${all_defines[@]}"; do
    if [[ "$define" =~ [Dd][Ee][Bb][Uu][Gg]_[Tt][Oo][Kk][Ee][Nn] ]]; then
      echo "SECURITY ERROR: Debug token would be passed as a --dart-define in release build ($define). Debug tokens must NEVER be passed to release builds." >&2
      exit 1
    fi
  done

  # Strict allowlist: confirm only intended keys reach dart-defines
  local allowed_keys=("FIREBASE_API_KEY_ANDROID" "GOOGLE_MAPS_API_KEY" "RECAPTCHA_SITE_KEY" "SUPABASE_URL" "SUPABASE_ANON_KEY" "USE_SUPABASE_DB_DOCTOR_PATIENT")
  for define in "${all_defines[@]}"; do
    local key="${define#--dart-define=}"
    key="${key%%=*}"
    local found=0
    for allowed in "${allowed_keys[@]}"; do
      if [[ "$key" == "$allowed" ]]; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "SECURITY ERROR: Unintended dart-define key '$key' detected. Only allowlisted keys (${allowed_keys[*]}) may reach release builds." >&2
      exit 1
    fi
  done

  local intended_keys=()
  for define in "${DART_DEFINES[@]}"; do
    local key="${define#--dart-define=}"
    key="${key%%=*}"
    intended_keys+=("$key")
  done
  echo "Configured Dart define keys: ${intended_keys[*]}"
}

validate_production_build_config() {
  # Only validate API endpoint when Supabase/Gateway connectivity is enabled or targeting production
  if [[ "${ENABLE_SUPABASE:-}" != "1" && "${APP_ENV:-}" != "production" ]]; then
    return 0
  fi

  local staging_url="${STAGING_SUPABASE_URL:-https://rnltknemwnjrjxthtull.supabase.co}"
  local prod_endpoint="${PROD_GATEWAY_URL:-${SUPABASE_URL:-}}"

  if [[ "$ALLOW_STAGING" -ne 1 && "${ALLOW_STAGING_BUILD:-}" != "true" ]]; then
    if [[ -z "$prod_endpoint" ]]; then
      echo "FAIL-FAST SECURITY GATE: Production release build requires a dedicated production API endpoint (PROD_GATEWAY_URL). None configured. Release build aborted." >&2
      exit 1
    fi
    if [[ "$prod_endpoint" == "$staging_url" || "$prod_endpoint" =~ rnltknemwnjrjxthtull ]]; then
      echo "FAIL-FAST SECURITY GATE: Production release build detected STAGING endpoint ($prod_endpoint). Production build must point to dedicated production access layer and differ from staging. Pass --allow-staging if building a staging artifact." >&2
      exit 1
    fi
  fi

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
if [[ ! -f "$PROJECT_ROOT/.env" && -f "$PROJECT_ROOT/../.env" ]]; then
  import_dotenv "$PROJECT_ROOT/../.env"
fi
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

BUILD_CMD=(flutter build appbundle --release "${DART_DEFINES[@]}" "${EXTRA_DEFINES[@]}")
MASKED_CMD=()
for item in "${BUILD_CMD[@]}"; do
  if [[ "$item" =~ ^--dart-define=([^=]+)=.*$ ]]; then
    MASKED_CMD+=("--dart-define=${BASH_REMATCH[1]}=***")
  else
    MASKED_CMD+=("$item")
  fi
done
printf 'Build command: %q ' "${MASKED_CMD[@]}"
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
