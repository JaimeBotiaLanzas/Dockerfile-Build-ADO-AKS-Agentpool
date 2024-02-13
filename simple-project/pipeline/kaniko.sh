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


cat <<EOF | kubectl apply --force -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-$KANIKO_NAME-$PIPELINE_ID
  namespace: $KANIKO_NAMESPACE
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      initContainers:
      - name: git-clone
        image: alpine:3.17.0
        command: ["sh", "-c"]
        args: 
        - |
          apk add --no-cache git
          echo "****************************************************"
          echo "working on this branch $BRANCH_NAME"
          echo $PIPELINE_ID
          echo "****************************************************"
          git clone https://:$SYSTEM_ACCESSTOKEN@dev.azure.com/jbotialanzas9393/$PROJECT_NAME/_git/$REPO_NAME --branch=$BRANCH_NAME /workspace
          echo "***************************"
          echo "/workspace folder:"
          ls -al /workspace
          echo "******************************************************"
          echo "/workspace/$WORKING_DIRECTORY folder:"
          echo "******************************************************"
          ls -al /workspace/$WORKING_DIRECTORY
        volumeMounts: 
        - name: git-volume
          mountPath: /workspace
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:v1.9.1
        args:
          - "--context=dir:///workspace/$WORKING_DIRECTORY"
          - "--cache=true"
          - "--destination=$AZURE_CONTAINER_REGISTRY_NAME.azurecr.io/$IMAGE_NAME:$IMAGE_VERSION_GLOBAL"
        volumeMounts:
        - name: kaniko-secret
          mountPath: /kaniko/.docker
        - name: git-volume
          mountPath: /workspace
      restartPolicy: Never
      volumes:
      - name: kaniko-secret
        secret:
          secretName: registrysecret
          items:
            - key: dockerconfigjson
              path: config.json
      - name: git-volume
        emptyDir: {}
EOF


JOBUUID=$(kubectl get job kaniko-$KANIKO_NAME-$PIPELINE_ID -n $KANIKO_NAMESPACE -o "jsonpath={.metadata.labels.controller-uid}")
PODNAME=$(kubectl get po -l controller-uid=$JOBUUID -o name)

echo "****************************"
echo "working on this pod $PODNAME"
echo "****************************"

while [[ $(kubectl get  $PODNAME  -n $KANIKO_NAMESPACE -o jsonpath='{..initContainerStatuses..state..reason}') = "PodInitializing"  ]]; do echo "Cloning repository to init container (PodInitializing)" && sleep 2 ; done
while [[ $(kubectl get  $PODNAME  -n $KANIKO_NAMESPACE -o jsonpath='{..initContainerStatuses..state..reason}') != "Completed"  ]]; do kubectl logs $PODNAME -c git-clone -n $KANIKO_NAMESPACE -f && sleep 2 ; done
sleep 4


if [ $(kubectl get  $PODNAME  -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') == "Failed" ]; then
exit 1;
fi
while [[ $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') != "Succeeded" && $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') != "Failed" ]]; do kubectl logs $PODNAME -n $KANIKO_NAMESPACE -f && sleep 3 ; done


if [ $(kubectl get  $PODNAME -n $KANIKO_NAMESPACE -o jsonpath='{..status.phase}') == "Failed" ]; then
exit 1;
fi