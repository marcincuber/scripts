#####
# Description: check if scanned image returned any CRITIAL findings
# Execute: ./ecr-scan-script.sh REPO_NAME IMAGE_TAG
#####

REPO_NAME=${1}
IMAGE_TAG=${2}

if aws --region eu-west-1 ecr wait image-scan-complete --repository-name ${REPO_NAME} --image-id imageTag=${IMAGE_TAG}
then
	CRITICAL_ISSUE_COUNT=$(aws --region eu-west-1 ecr describe-image-scan-findings --repository-name ${REPO_NAME} --image-id imageTag=${IMAGE_TAG} --query 'imageScanFindings.findingSeverityCounts.CRITICAL')
	if [[ "${CRITICAL_ISSUE_COUNT}" -gt 0 ]]
	then
		echo "Critical issues detected. Failing to fix..."
		exit 1
	fi
	echo "All good amigo, we can scan new image later."
else
	echo "Scan did not finish"
	exit 1
fi