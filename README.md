# Azure DevOps Agent with Kaniko

This repository provides a guide to create an Azure DevOps agent using Kaniko. The agent builds and pushes images to an Azure Container Registry (ACR), and then deploys them to an Azure Kubernetes Service (AKS) cluster.

This work is largely based on the guide by Umut Ercan, with modifications to the Dockerfile and `start.sh` for the Azure DevOps Agent to resolve some issues. You can find Umut's original guide [here](https://medium.com/adessoturkey/azure-devops-agents-on-aks-with-kaniko-option-f672f900a177).

## Prerequisites

Open Aure  cloud shell and clone this repository:

```bash
git clone https://github.com/JaimeBotiaLanzas/Dockerfile-Build-ADO-AKS-Agentpool
cd Dockerfile-Build-ADO-AKS-Agentpool
```

## Step 1 Create RG and ACR

Create a resource group and an Azure Container Registry (ACR) using the following commands:

```bash
RG=aks-agent-rg && ACR=aksagentacr && AKS=aks-cluster && NS=azure-devops && SP=spforaks
az group create -n $RG -l uksouth
az acr create -n $ACR -g $RG --sku premium
```

## Step 2 Create kaniko ACR Token to push images in ACR

```bash
ACR_USER=kaniko-push
ACR_PASSWORD=$(az acr token create  -r $ACR -g $RG  -n $ACR_USER --scope-map _repositories_push --output json | jq -r .credentials.passwords[0].value)
```

## Step 3 Create AKS Cluster and SP
    
```bash
SPPW=$(az ad sp create-for-rbac --name $SP | jq -r .password)
SPID=$(az ad sp list --display-name $SP | jq -r .[].appId)
SUBSID=$(az account show | jq -r .id) && TENANTID=$(az account show | jq -r .homeTenantId) && SUBNAME=$(az account show | jq -r .name)
az role assignment create --assignee $SPID  --scope /subscriptions/$SUBSID --role Contributor

az aks create \
   -g $RG \
   -n $AKS \
   --generate-ssh-keys \
   --node-count 1 \
   --node-vm-size Standard_D2_v2 \
   --service-principal $SPID \
   --client-secret $SPPW \
   --attach-acr $ACR

az aks get-credentials --resource-group $RG  --name $AKS

kubectl get pods -A 

    NAMESPACE     NAME                                  READY   STATUS    RESTARTS   AGE
    kube-system   azure-ip-masq-agent-jzcvb             1/1     Running   0          2m2s
    kube-system   cloud-node-manager-xfpwq              1/1     Running   0          2m2s
    kube-system   coredns-789789675-hv6kz               1/1     Running   0          62s
    kube-system   coredns-789789675-mfjzv               1/1     Running   0          2m14s
    kube-system   coredns-autoscaler-649b947bbd-jcjn4   1/1     Running   0          2m14s
    kube-system   csi-azuredisk-node-qz68p              3/3     Running   0          2m2s
    kube-system   csi-azurefile-node-fgjxf              3/3     Running   0          2m2s
    kube-system   konnectivity-agent-59767bdd84-lnsrc   1/1     Running   0          2m14s
    kube-system   konnectivity-agent-59767bdd84-pmjsl   1/1     Running   0          2m14s
    kube-system   kube-proxy-hbx5m                      1/1     Running   0          2m2s
    kube-system   metrics-server-5bd48455f4-rrsht       1/2     Running   0          57s
    kube-system   metrics-server-5bd48455f4-z7glx       1/2     Running   0          57s
    kube-system   metrics-server-7557c5798-x7dpt        1/2     Running   0          2m13s
```	

## Step 4 Create Service Connection in Azure DevOps 

Go to Azure DevOps and create a new service connection with the following parameters:

```bash
echo -e "SPPW: $SPPW \nSPID: $SPID \nSUBSID: $SUBSID \nTENANTID: $TENANTID \nSUBNAME: $SUBNAME"
```

## Step 5 Create K8s ns and secret to push to ACR
    
```bash
kubectl create ns $NS
kubectl create secret generic registrysecret -n $NS --from-literal=dockerconfigjson="{\"auths\": {\"$ACR.azurecr.io\": {\"username\": \"$ACR_USER\",\"password\": \"$ACR_PASSWORD\"}}}"
```

#Step 6 Kaniko Test
#We go to a dir with a Dockerfile to build and we apply this command

```bash	
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-test
  namespace: azure-devops
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 60
  template:
    spec:
      initContainers:
      - name: init-container
        image: alpine
        command: ["sh", "-c"]
        args: 
        - |
          while true; do sleep 1; if [ -f /workspace/Dockerfile ]; then break; fi done
        volumeMounts: 
        - name: local-volume
          mountPath: /workspace
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:v1.9.1
        args:
          - "--context=dir:///workspace/"
          - "--destination=$ACR.azurecr.io/test-image:v1"
        volumeMounts:
        - name: kaniko-secret
          mountPath: /kaniko/.docker
        - name: local-volume
          mountPath: /workspace
      restartPolicy: Never
      volumes:
      - name: kaniko-secret
        secret:
          secretName: registrysecret
          items:
            - key: dockerconfigjson
              path: config.json
      - name: local-volume
        emptyDir: {}
EOF
```	

We check the logs of the kaniko container

```bash	
JOBUUID=$(kubectl get job kaniko-test -n $NS -o "jsonpath={.metadata.labels.controller-uid}") && PODNAME=$(kubectl get po -n $NS -l controller-uid=$JOBUUID -o json | jq -r .items[0].metadata.name)
```	

We put the dockerfile on the volume of the initContainer 
    
```bash
kubectl cp -n $NS kaniko-test/Dockerfile $PODNAME:/workspace -c init-container
```

We check the logs of the kaniko container

```bash	

sleep 5 && kubectl logs -f -n $NS $PODNAME

    Defaulted container "kaniko" out of: kaniko, init-container (init)
    INFO[0000] Retrieving image manifest alpine             
    INFO[0000] Retrieving image alpine from registry index.docker.io 
    INFO[0000] Retrieving image manifest alpine             
    INFO[0000] Returning cached image manifest              
    INFO[0001] Built cross stage deps: map[]                
    INFO[0001] Retrieving image manifest alpine             
    INFO[0001] Returning cached image manifest              
    INFO[0001] Retrieving image manifest alpine             
    INFO[0001] Returning cached image manifest              
    INFO[0001] Executing 0 build triggers                   
    INFO[0001] Building stage 'alpine' [idx: '0', base-idx: '-1'] 
    INFO[0001] Skipping unpacking as no commands require it. 
    INFO[0001] Pushing image to .azurecr.io/test-image:v1 
    INFO[0002] Pushed .azurecr.io/test-image@sha256:4957f1b5c01b975584c1eb4f493c68c
```

## Step 7 Create our Azure DevOps agent image with Kaniko
To do that we change the name of the image to aks-agent-image and we change the destination of the image to our ACR
    
```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-agent
  namespace: azure-devops
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 60
  template:
    spec:
      initContainers:
      - name: init-container
        image: alpine
        command: ["sh", "-c"]
        args: 
        - |
          while true; do sleep 1; if [ -f /workspace/Dockerfile ]; then break; fi done
        volumeMounts: 
        - name: local-volume
          mountPath: /workspace
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:v1.9.1
        args:
          - "--context=dir:///workspace/"
          - "--destination=$ACR.azurecr.io/aks-agent-image:v1"
        volumeMounts:
        - name: kaniko-secret
          mountPath: /kaniko/.docker
        - name: local-volume
          mountPath: /workspace
      restartPolicy: Never
      volumes:
      - name: kaniko-secret
        secret:
          secretName: registrysecret
          items:
            - key: dockerconfigjson
              path: config.json
      - name: local-volume
        emptyDir: {}
EOF
```

We check the logs of the kaniko container after passing the Dockerfile and the start.sh to the initContainer

```bash
JOBUUID=$(kubectl get job kaniko-agent -n $NS -o "jsonpath={.metadata.labels.controller-uid}") && PODNAME=$(kubectl get po -n $NS -l controller-uid=$JOBUUID -o json | jq -r .items[0].metadata.name)
kubectl cp -n $NS azure-devops-agent/start.sh $PODNAME:/workspace -c init-container
kubectl cp -n $NS azure-devops-agent/Dockerfile $PODNAME:/workspace -c init-container

sleep 5 && kubectl logs -f -n $NS $PODNAME
```

## Step 8 Create Azure DevOps Agent using URL of Org, Pool Name and ADO PAT (PAT will be used to give permissions to agent so be careful with it)

```bash
AZP_URL=https://dev.azure.com/jbotialanzas9393 && AZP_POOL=testpool && AZP_TOKEN=''
```

Now we create a pool with this command

```bash
curl -u :$AZP_TOKEN   -H "Content-Type: application/json"  -d '{"name": "testpool","autoProvision": true}' -X POST https://dev.azure.com/jbotialanzas9393/_apis/distributedtask/pools?api-version=7.0
```
We create the AKS secret

```bash
kubectl create secret generic azdevops \
        --namespace $NS \
        --from-literal=AZP_URL=$AZP_URL \
        --from-literal=AZP_TOKEN=$AZP_TOKEN \
        --from-literal=AZP_POOL=$AZP_POOL
```

We create the agent with this commands

```bash

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: $NS
  name: azure-agent
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $NS
  name: azure-agent-role
rules:
- apiGroups: [""]
  resources: ["pods","pods/log"]
  verbs: ["get", "watch", "list","create","patch","update","delete"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create","patch","update","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: azure-agent-role-binding
  namespace: $NS
subjects:
- kind: ServiceAccount
  name: azure-agent
  namespace: $NS
roleRef:
  kind: Role
  name: azure-agent-role
  apiGroup: rbac.authorization.k8s.io
EOF
```	

We create the deployment with this command

```bash

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azdevops-deployment
  namespace: $NS
  labels:
    app: azdevops-agent
spec:
  replicas: 1 
  selector:
    matchLabels:
      app: azdevops-agent
  template:
    metadata:
      labels:
        app: azdevops-agent
    spec:
      containers:
      - name: kubepodcreation
        image: $ACR.azurecr.io/aks-agent-image:v1
        env:
          - name: AZP_URL
            valueFrom:
              secretKeyRef:
                name: azdevops
                key: AZP_URL
          - name: AZP_TOKEN
            valueFrom:
              secretKeyRef:
                name: azdevops
                key: AZP_TOKEN
          - name: AZP_POOL
            valueFrom:
              secretKeyRef:
                name: azdevops
                key: AZP_POOL
          - name: AZP_AGENT_NAME
            valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.name  
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1024Mi"
            cpu: "750m"
      serviceAccountName: azure-agent
EOF
```

We check the logs of the agent

```bash

kubectl get pods -n $NS

kubectl logs -n $NS <podname>
```

#We go to the Azure DevOps and we set the parameters in the pipeline and execute it

```bash

trigger:
- none


#Global variables
variables:
- name: BRANCH_NAME
  value: $[replace(variables['Build.SourceBranch'], 'refs/heads/', '')]
- name: PIPELINE_ID
  value: $[replace(variables['Build.BuildNumber'], '.', '-')]
- name: IMAGE_VERSION_GLOBAL
  value: $(Build.BuildNumber)
- name: PROJECT_NAME
  value: aks-agent
- name: REPO_NAME
  value: aks-agent
- name: AZURE_CONTAINER_REGISTRY_NAME
  value: 'aksagentacr'
- name: KANIKO_NAMESPACE
  value: azure-devops
- name: APP_IMAGE_NAME
  value: 'simple-project'

stages:
- stage: FrontendBuild
  displayName: FrontendBuild
  pool: testpool
  dependsOn: []
  variables:      
    IMAGE_NAME: "$(APP_IMAGE_NAME)-test"
    WORKING_DIRECTORY: "$(APP_IMAGE_NAME)/application"
    KANIKO_NAME: "$(APP_IMAGE_NAME)"
  jobs:
  - job:
    steps:
    - task: AzureCLI@1
      displayName: '${{ variables.WORKING_DIRECTORY }}-building'
      env:
        SYSTEM_ACCESSTOKEN: $(System.AccessToken)
      inputs:
        azureSubscription: 'kaniko-test' #Introduce your service connection here
        scriptPath: '$(Build.SourcesDirectory)/simple-project/pipeline/kaniko.sh'
```	


## Step 9 Create a deployment to test the image that has been uploaded to the ACR

```bash

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-deployment
  namespace: $NS
  labels:
    app: node-deployment
spec:
  replicas: 1 
  selector:
    matchLabels:
      app: node-deployment
  template:
    metadata:
      labels:
        app: node-deployment
    spec:
      containers:
      - name: container_test
        image: $ACR.azurecr.io/image_name:tag
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1024Mi"
            cpu: "750m"
EOF
```

