#!/usr/bin/env bash
set -e

# Run kube-bench as a Kubernetes Job and print the result on stdout
# All informational messages in this script are printed to stderr

JOB="kube-bench"
ROLEBINDING="kube-bench-psp"
IMAGE="aquasec/kube-bench:0.0.34"

function log() {
  echo "[$(date)] $1" >&2
}

log "Applying the job manifest"
kubectl create rolebinding ${ROLEBINDING} --clusterrole=eks:podsecuritypolicy:privileged --serviceaccount=default:default --namespace=default >&2
kubectl apply -f - >&2 <<MANIFEST
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: kube-bench
        image: ${IMAGE}
        command: ["kube-bench", "--version", "1.13-json"]
        volumeMounts:
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
        - name: etc-systemd
          mountPath: /etc/systemd
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
      restartPolicy: Never
      volumes:
      - name: var-lib-kubelet
        hostPath:
          path: "/var/lib/kubelet"
      - name: etc-systemd
        hostPath:
          path: "/etc/systemd"
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
      - name: usr-bin
        hostPath:
          path: "/usr/bin"
MANIFEST

while [ "$(kubectl get job ${JOB} --no-headers -o custom-columns=:status.succeeded)" != "1" ]
do
  log "Waiting for job to complete..." >&2 && sleep 1
done

log "Job completed, outputting results to stdout"
kubectl logs job/"${JOB}"

log "Clean up: deleting the job"
kubectl delete job ${JOB} >&2
kubectl delete rolebinding ${ROLEBINDING} >&2