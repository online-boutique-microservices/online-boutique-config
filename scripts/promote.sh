#!/bin/bash
# ============================================================
# Promote Script — Copy image tags between environments
#
# Usage:
#   ./scripts/promote.sh dev staging
#   ./scripts/promote.sh staging prod
#
# This script:
# 1. Reads image tags from source environment kustomization.yaml
# 2. Updates target environment kustomization.yaml with same tags
# 3. Commits and pushes → ArgoCD auto-syncs the target env
# ============================================================

set -euo pipefail

# ─── Validate arguments ──────────────────────────────────

if [ $# -ne 2 ]; then
  echo "❌ Usage: $0 <source_env> <target_env>"
  echo "   Example: $0 dev staging"
  echo "   Example: $0 staging prod"
  exit 1
fi

SOURCE_ENV="$1"
TARGET_ENV="$2"
VALID_ENVS="dev staging prod"

for env in "$SOURCE_ENV" "$TARGET_ENV"; do
  if ! echo "$VALID_ENVS" | grep -qw "$env"; then
    echo "❌ Invalid environment: $env (must be one of: $VALID_ENVS)"
    exit 1
  fi
done

if [ "$SOURCE_ENV" == "$TARGET_ENV" ]; then
  echo "❌ Source and target environments cannot be the same"
  exit 1
fi

# ─── Ensure we're on main and up to date ─────────────────

echo "📥 Ensuring repo is up to date..."
git checkout main
git pull origin main

# ─── Read image tags from source ─────────────────────────

SOURCE_FILE="envs/${SOURCE_ENV}/kustomization.yaml"
TARGET_FILE="envs/${TARGET_ENV}/kustomization.yaml"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "❌ Source file not found: $SOURCE_FILE"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "📦 Promoting: ${SOURCE_ENV} → ${TARGET_ENV}"
echo "═══════════════════════════════════════════════"
echo ""

# Extract image entries from source
SERVICES=$(grep "name:" "$SOURCE_FILE" | grep -v "newName\|kustomize\|common\|online-boutique" | awk '{print $3}')
echo "🔍 Services found in ${SOURCE_ENV}:"
echo "$SERVICES" | while read svc; do echo "   - $svc"; done

# For each image, copy newName and newTag from source to target
echo ""
echo "📝 Updating image tags in ${TARGET_ENV}..."

# Use a Python one-liner to properly parse and update YAML
python3 << 'PYTHON_SCRIPT'
import yaml
import sys

source_file = "envs/SOURCE_ENV/kustomization.yaml".replace("SOURCE_ENV", "$SOURCE_ENV")
target_file = "envs/TARGET_ENV/kustomization.yaml".replace("TARGET_ENV", "$TARGET_ENV")

source_file = source_file.replace("$SOURCE_ENV", "${SOURCE_ENV}")
target_file = target_file.replace("$TARGET_ENV", "${TARGET_ENV}")
PYTHON_SCRIPT

# Simpler approach: use sed to copy newTag values
while IFS= read -r line; do
  if echo "$line" | grep -q "newTag:"; then
    TAG=$(echo "$line" | awk '{print $2}')
    # Find the corresponding service name (2 lines above newTag)
    break
  fi
done < "$SOURCE_FILE"

# Use kustomize to update tags properly
cd "envs/${TARGET_ENV}"

# Read each image entry from source and apply to target
grep -A2 "^  - name:" "../../${SOURCE_FILE}" | while read -r line; do
  if echo "$line" | grep -q "^  - name:"; then
    CURRENT_NAME=$(echo "$line" | awk '{print $3}')
  elif echo "$line" | grep -q "newName:"; then
    CURRENT_NEW_NAME=$(echo "$line" | awk '{print $2}')
  elif echo "$line" | grep -q "newTag:"; then
    CURRENT_TAG=$(echo "$line" | awk '{print $2}')
    if [ -n "$CURRENT_NAME" ] && [ -n "$CURRENT_NEW_NAME" ] && [ -n "$CURRENT_TAG" ]; then
      echo "   ✅ ${CURRENT_NAME} → ${CURRENT_TAG}"
      kustomize edit set image "${CURRENT_NAME}=${CURRENT_NEW_NAME}:${CURRENT_TAG}"
    fi
  fi
done

cd ../..

# ─── Commit and push ─────────────────────────────────────

echo ""
echo "📤 Committing changes..."

git add "envs/${TARGET_ENV}/"
if git diff --cached --quiet; then
  echo "ℹ️  No changes detected — ${TARGET_ENV} already has the same tags as ${SOURCE_ENV}"
  exit 0
fi

TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
git commit -m "promote(${TARGET_ENV}): from ${SOURCE_ENV} @ ${TIMESTAMP}

Promoted image tags from ${SOURCE_ENV} to ${TARGET_ENV}.
Timestamp: ${TIMESTAMP}"

git push origin main

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ Promotion complete: ${SOURCE_ENV} → ${TARGET_ENV}"
if [ "$TARGET_ENV" == "prod" ]; then
  echo ""
  echo "⚠️  PRODUCTION: Manual sync required!"
  echo "   Open ArgoCD UI → online-boutique-prod → Click 'Sync'"
fi
echo "═══════════════════════════════════════════════"
