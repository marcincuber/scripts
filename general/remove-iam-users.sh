#!/usr/bin/env bash

function main() {
  for profile in $(aws-okta list | awk '{print $1}' | grep -E "okta.*prod")
  do
    echo "---"
    creds=$(aws-okta exec "${profile}" -- sh -c set | grep \^AWS)

    AWS_ACCESS_KEY_ID=$(echo "${creds}" | grep \^AWS_ACCESS_KEY_ID=)
    AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | grep \^AWS_SECRET_ACCESS_KEY=)
    AWS_SECURITY_TOKEN=$(echo "${creds}" | grep \^AWS_SECURITY_TOKEN=)
    AWS_SESSION_TOKEN=$(echo "${creds}" | grep \^AWS_SESSION_TOKEN=)

    export ${AWS_ACCESS_KEY_ID}
    export ${AWS_SECRET_ACCESS_KEY}
    export ${AWS_SECURITY_TOKEN}
    export ${AWS_SESSION_TOKEN}

    aws iam delete-login-profile --user-name marcin.cuber@news.co.uk
    groups=$(aws iam list-groups-for-user --user-name marcin.cuber@news.co.uk --query 'Groups[].GroupName' --output text);

    for group in ${groups}
    do
      aws iam remove-user-from-group --group-name ${group} --user-name marcin.cuber@news.co.uk
    done

    aws iam delete-user --user-name marcin.cuber@news.co.uk
  done
}

main
