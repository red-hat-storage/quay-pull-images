#!/bin/bash

# Source: openshift-qe
# http://git.app.eng.bos.redhat.com/git/openshift-misc.git/plain/jenkins/v4-image-test/app_registry_tools/

NAMESPACE=${1:-aosqe4}

function getQuayToken()
{
echo "###get Quay Token"
    if [[ $REFRESH == true || ! -f quay.token ]]; then
        echo -n "Login Quay.io"
        echo -n "Quay Username: "
        read USERNAME
        echo -n "Quay Password: "
        read -s PASSWORD

        Quay_Token=$(curl -s -H "Content-Type: application/json" -XPOST https://quay.io/cnr/api/v1/users/login -d ' { "user": { "username": "'"${USERNAME}"'", "password": "'"${PASSWORD}"'" } }' |jq -r '.token')
        echo "$Quay_Token" > quay.token
    else
        Quay_Token=$(cat quay.token)
    fi

}

function updateCluster()
{
echo "# disable redhat-operators.yaml"
echo "
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata:
  name: cluster
spec:
  disableAllDefaultSources: false
  sources:
  - disabled: true
    name: redhat-operators" | oc apply -f -

echo "###Create&Update QE OperatorSource"

echo "apiVersion: v1
kind: Secret
metadata:
  name: qesecret
  namespace: openshift-marketplace
type: Opaque
stringData:
    token: ${Quay_Token}"| oc apply -f -

echo "apiVersion: operators.coreos.com/v1
kind: OperatorSource
metadata:
  name: qe-app-registry
  namespace: openshift-marketplace
spec:
  type: appregistry     
  endpoint: https://quay.io/cnr
  registryNamespace: ${NAMESPACE}
  authorizationToken:
    secretName: qesecret"| oc apply -f -
}

getQuayToken
#updateCluster
