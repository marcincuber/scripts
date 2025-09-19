#!/bin/bash

api_key=""
domain_name=""
profile_name=""
api_key_endpoint="https://${api_key}@api.detectify.com"

domain_token=$(curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/domains/ \
  | jq -r --arg domain_name "${domain_name}" '.[] | select(.name == $domain_name) | .token ')

profile_token=$(curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/profiles/${domain_token}/ \
  | jq -r --arg profile_name "${profile_name}" '.[] | select(.name == $profile_name) | .token ')

high=$(curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/findings/${profile_token}/?severity=high \
  | jq -r '.[] | "Issue: \(.title), Score: \(.score[].score)"')

medium=$(curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/findings/${profile_token}/?severity=medium \
  | jq -r '.[] | "Issue: \(.title), Score: \(.score[].score)"')

low=$(curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/findings/${profile_token}/?severity=low \
  | jq -r '.[] | "Issue: \(.title), Score: \(.score[].score)"')

echo
echo "Findings for profile: ${profile_name}"
echo "High Severity issues:"
echo "${high}"
echo
echo "Medium Severity issues:"
echo "${medium}"
echo
echo "Low Severity issues:"
echo "${low}"
echo
echo "Latest report highlights:"

curl -s -H "Accept:application/json" ${api_key_endpoint}/rest/v2/reports/${profile_token}/latest/ \
  | jq 'with_entries(select([.key] | inside(["url", "created", "cvss", "high_level_findings", "medium_level_findings", "low_level_findings"])))'

# curl -X POST -H "Accept:application/json" ${api_key_endpoint}/rest/v2/scans/${profile_token}/

STATUS=

curl -H "Accept:application/json" ${api_key_endpoint}/rest/v2/scans/${profile_token}/ | jq .
