#!/usr/bin/env bash
# Tag ECR repos that start with a prefix and currently have NO tags.
# Adds one or more tags provided on the command line.
#
# Requirements: awscli v2, jq
# IAM: ec2:DescribeRegions, ecr:DescribeRepositories, ecr:ListTagsForResource, ecr:TagResource

set -euo pipefail

PREFIX=""
REGION=""            # empty -> scan all regions
APPLY="false"        # dry-run by default
ONLY_UNTAGGED="true" # required by the task; leave true

# Arrays to collect tag structs
declare -a TAG_STRUCTS=()

usage() {
  cat <<EOF
Usage:
  tag_ecr_by_prefix.sh [--prefix PREFIX] [--region REGION] --tag KEY=VALUE [--tag KEY=VALUE ...] [--apply]

Options:
  --prefix PREFIX     Repository name prefix to match (default: github/)
  --region REGION     Single AWS region to scan (default: all regions)
  --tag KEY=VALUE     Tag pair to apply; repeat for multiple (e.g., --tag Team=CNP --tag Owner=Platform)
  --apply             Actually apply tags (default is dry-run)
  -h, --help          Show this help

Notes:
- Repositories are tagged ONLY if they currently have zero tags.
- Dry-run prints what would happen without making changes.
Examples:
  ./tag_ecr_by_prefix.sh --tag Team=CNP
  ./tag_ecr_by_prefix.sh --prefix github/org-foo/ --tag Team=CNP --tag CostCenter=123 --apply
  ./tag_ecr_by_prefix.sh --region eu-west-2 --prefix gitlab/ --tag Team=Core --tag Owner=DevEx
  AWS_PROFILE=aws-eng-platform-dev ./tag_ecr_by_prefix.sh --region eu-west-2 --prefix "quay/" --tag Team=my --tag Environment=dev --apply
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --tag)
      kv="${2:-}"; shift 2
      if [[ -z "$kv" || "$kv" != *=* ]]; then
        echo "Error: --tag requires KEY=VALUE" >&2; exit 2
      fi
      key="${kv%%=*}"
      val="${kv#*=}"
      if [[ -z "$key" ]]; then
        echo "Error: tag key cannot be empty" >&2; exit 2
      fi
      # Collect as AWS CLI "structure" args
      TAG_STRUCTS+=("Key=${key},Value=${val}")
      ;;
    --apply) APPLY="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ${#TAG_STRUCTS[@]} -eq 0 ]]; then
  echo "Error: at least one --tag KEY=VALUE is required." >&2
  usage; exit 2
fi

get_regions() {
  if [[ -n "$REGION" ]]; then
    echo "$REGION"
  else
    aws ec2 describe-regions --query "Regions[].RegionName" --output text
  fi
}

echo "Prefix: '$PREFIX'"
echo "Mode:   $([[ "$APPLY" == "true" ]] && echo APPLY || echo DRY-RUN)"
[[ -n "$REGION" ]] && echo "Region: $REGION" || echo "Region: ALL"

total_found=0
total_tagged=0

for region in $(get_regions); do
  echo "== Region: $region =="
  repos_json=$(aws ecr describe-repositories --region "$region" \
    --query "repositories[?starts_with(repositoryName, \`${PREFIX}\`)].{name:repositoryName,arn:repositoryArn}" \
    --output json)

  count=$(echo "$repos_json" | jq 'length')
  [[ "$count" -eq 0 ]] && { echo "  No repos matching prefix."; continue; }

  echo "$repos_json" | jq -cr '.[]' | while read -r repo; do
    name=$(echo "$repo" | jq -r .name)
    arn=$(echo "$repo" | jq -r .arn)

    tags_json=$(aws ecr list-tags-for-resource --region "$region" --resource-arn "$arn" --output json)
    tagcount=$(echo "$tags_json" | jq '.tags | length')

    if [[ "$ONLY_UNTAGGED" == "true" && "$tagcount" -ne 0 ]]; then
      # Skip repos that already have any tags at all
      continue
    fi

    echo "  Candidate: $name (current tags: $tagcount)";
    ((total_found++))

    if [[ "$APPLY" == "true" ]]; then
      # Pass one --tags followed by multiple "Key=...,Value=..." structures
      aws ecr tag-resource --region "$region" --resource-arn "$arn" --tags "${TAG_STRUCTS[@]}"
      echo "    Tagged: $name  ->  ${TAG_STRUCTS[*]}"
      ((total_tagged++))
    else
      echo "    [dry-run] Would tag: $name  ->  ${TAG_STRUCTS[*]}"
    fi
  done
done
