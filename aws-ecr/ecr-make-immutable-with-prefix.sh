#!/usr/bin/env bash
set -euo pipefail

# Converts all ECR repos whose name starts with prefixes such as "github/" AND are currently MUTABLE to IMMUTABLE.
# Works across all regions by default. Requires: awscli v2 with ECR permissions.
#
# Usage:
#   ./ecr-make-immutable.sh                 # all regions, default profile
#   AWS_PROFILE=prod ./ecr-make-immutable.sh
#   REGIONS="eu-west-2" ./ecr-make-immutable.sh
#
# Safety:
#   Set DRY_RUN=false to actually apply changes. Default is DRY_RUN=true (preview only).
#
# Full Example:
#   DRY_RUN=true REGIONS="eu-west-2" AWS_PROFILE=aws-eng-platform-dev ./ecr-make-immutable-with-prefix.sh github/ quay/

DRY_RUN="${DRY_RUN:-true}"
PROFILE_OPT="${AWS_PROFILE:+--profile $AWS_PROFILE}"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <prefix1> [prefix2 ...]"
  exit 1
fi
PREFIXES=("$@")

# Regions to process: space-separated in $REGIONS or all opt-in-not-required regions
if [[ -n "${REGIONS:-}" ]]; then
  REG_LIST=$REGIONS
else
  REG_LIST=$(aws ec2 describe-regions $PROFILE_OPT --all-regions \
    --query "Regions[].RegionName" --output text)
fi

changed_any=false

for region in $REG_LIST; do
  echo "== Region: $region =="
  # List repo names that start with github/ and are currently MUTABLE

  repos=$(aws ecr describe-repositories \
      $PROFILE_OPT --region "$region" \
      --query "repositories[?imageTagMutability=='MUTABLE'].repositoryName" \
      --output text | tr '\t' '\n' | sed '/^$/d')

  match_repos=()
  for repo in $repos; do
    for prefix in "${PREFIXES[@]}"; do
      if [[ "$repo" == "$prefix"* ]]; then
        match_repos+=("$repo")
        break
      fi
    done
  done

  if [[ ${#match_repos[@]} -eq 0 ]]; then
    echo "No matching MUTABLE repos in $region."
    continue
  fi

  echo "Found ${#match_repos[@]} repo(s):"
  for r in "${match_repos[@]}"; do
    echo "  - $r"
  done

  for repo in "${match_repos[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY RUN] Would set $repo to IMMUTABLE in $region"
    else
      echo "Setting $repo to IMMUTABLE in $region..."
      aws ecr put-image-tag-mutability \
        $PROFILE_OPT --region "$region" \
        --repository-name "$repo" \
        --image-tag-mutability IMMUTABLE >/dev/null
      echo "  Done."
      changed_any=true
    fi
  done
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN=true (no changes made). Re-run with DRY_RUN=false to apply."
else
  if [[ "$changed_any" == "true" ]]; then
    echo "All matching repos have been set to IMMUTABLE."
  else
    echo "No changes were necessary."
  fi
fi
