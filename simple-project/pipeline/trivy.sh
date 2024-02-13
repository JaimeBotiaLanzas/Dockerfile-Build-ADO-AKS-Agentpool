#!/bin/bash

set -e

env

echo "****************************************************"
echo "PROJECT_NAME: $PROJECT_NAME"
echo "REPO_NAME: $REPO_NAME"
echo "KANIKO_NAME: $KANIKO_NAME"
echo "PIPELINE_ID: $PIPELINE_ID"
echo "BRANCH_NAME: $BRANCH_NAME"
echo "SYSTEM_ACCESSTOKEN: $SYSTEM_ACCESSTOKEN"
echo "REPO_NAME: $REPO_NAME"
echo "WORKING_DIRECTORY: $WORKING_DIRECTORY"
echo "AZURE_CONTAINER_REGISTRY_NAME: $AZURE_CONTAINER_REGISTRY_NAME"
echo "IMAGE_NAME: $IMAGE_NAME"
echo "IMAGE_VERSION_GLOBAL: $IMAGE_VERSION_GLOBAL"
echo "****************************************************"


sleep 10

cat <<EOF | kubectl apply --force -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: trivy-$KANIKO_NAME-$PIPELINE_ID
  namespace: $KANIKO_NAMESPACE
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template: 
    spec:
      containers:
      - name: trivy
        image: aquasec/trivy:0.35.0
        args: 
          - "image"
          - "--ignore-unfixed"
          - "--severity"
          - "HIGH,CRITICAL"
          - "--vuln-type"
          - "library"
          - "$AZURE_CONTAINER_REGISTRY_NAME.azurecr.io/$IMAGE_NAME:$IMAGE_VERSION_GLOBAL"
          - "--timeout"
          - "10m"
        env:
          - name: TRIVY_USERNAME
            valueFrom:
              secretKeyRef:
                name: trivysecret
                key: TRIVY_USERNAME
          - name: TRIVY_PASSWORD
            valueFrom:
              secretKeyRef:
                name: trivysecret
                key: TRIVY_PASSWORD
          - name: TRIVY_AUTH_URL
            valueFrom:
              secretKeyRef:
                name: trivysecret
                key: TRIVY_AUTH_URL
      restartPolicy: Never
EOF


JOBUUID=$(kubectl get job trivy-$KANIKO_NAME-$PIPELINE_ID -n $KANIKO_NAMESPACE -o "jsonpath={.metadata.labels.controller-uid}")
PODNAME=$(kubectl get po -l controller-uid=$JOBUUID -o name)

echo "****************************"
echo "working on this pod $PODNAME"
echo "****************************"

sleep 4

if [ $(kubectl get  $PODNAME  -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') == "Failed" ]; then
exit 1;
fi
while [[ $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') != "Succeeded" && $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') != "Failed" ]]; do kubectl logs $PODNAME -n $KANIKO_NAMESPACE -f && sleep 3 ; done


if [ $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') == "Failed" ]; then
exit 1;
fi