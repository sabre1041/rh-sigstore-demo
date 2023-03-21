#!/bin/bash
SCRIPT_BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

SECRETS_DIR="${SCRIPT_BASE_DIR}/bootstrap/base/secrets"
FULCIO_ROOT_CERT="${SECRETS_DIR}/fulcio-root.pem"
FULCIO_PRIVATE_KEY="${SECRETS_DIR}/file_ca_key.pem"
FULCIO_PUBLIC_KEY="${SECRETS_DIR}/file_ca_pub.pem"
PRIVATE_KEY_PASSWORD="fulcio"
HELM_SIGSTORE_REPO="https://sigstore.github.io/helm-charts"
SIGSTORE_NAMESPACE=sigstore

export FULCIO_SERVER_SECRET_NAME=fulcio-secret-rh

# Generate Keys - Source: https://github.com/lukehinds/sigstore-the-hard-way/blob/main/src/06-fulcio.md
if [ ! -f "${FULCIO_ROOT_CERT}" ]; then
    openssl ecparam -genkey -name prime256v1 -noout -out "${SECRETS_DIR}/unenc.key"
    openssl ec -in "${SECRETS_DIR}/unenc.key" -passout pass:${PRIVATE_KEY_PASSWORD} -out "${FULCIO_PRIVATE_KEY}" -des
    openssl ec -in "${SECRETS_DIR}/file_ca_key.pem" -passin pass:${PRIVATE_KEY_PASSWORD} -pubout -out "${FULCIO_PUBLIC_KEY}"
    openssl req -new -x509 -days 365 -passin pass:${PRIVATE_KEY_PASSWORD} -subj "/C=US/ST=North Carolina/L=Raleigh/O=Red Hat"  -extensions v3_ca -key "${FULCIO_PRIVATE_KEY}" -out "${FULCIO_ROOT_CERT}"
    rm "${SECRETS_DIR}/unenc.key"
    #echo "password=${PRIVATE_KEY_PASSWORD}" > "${SECRETS_DIR}/private_key_password.env"
fi

# Check if sigstore repository added
HELM_SIGSTORE_REPO_COUNT=$(helm repo list -o json | jq -r 'map(select(.name=="sigstore"))|length')

if [ "${HELM_SIGSTORE_REPO_COUNT}" != "1" ]; then
    helm repo add sigstore ${HELM_SIGSTORE_REPO}
fi

helm repo update

oc apply -k "${SCRIPT_BASE_DIR}/bootstrap/base"

echo "Waiting for Keycloak Operator to Start"
while [[ "$(oc get subscription.operators.coreos.com -n keycloak-system rhsso-operator -o jsonpath='{ .status.currentCSV}')" == "" ]]; do sleep 5; done
while [[ "$(oc get csv -n keycloak-system $(oc get subscription.operators.coreos.com -n keycloak-system rhsso-operator -o jsonpath='{ .status.currentCSV}') -o jsonpath='{ .status.phase}')" != "Succeeded" ]]; do sleep 5; done

oc apply -k "${SCRIPT_BASE_DIR}/apps/base/keycloak/"

export BASE_DOMAIN=$(oc get dns cluster -o jsonpath='{ .spec.baseDomain }')

# Wait for Keycloak realm to be ready
echo "Waiting for Keycloak sigstore realm to be ready"
while [[ "$(curl -k -s -o /dev/null -w ''%{http_code}'' https://keycloak-keycloak-system.apps.${BASE_DOMAIN}/auth/realms/sigstore/.well-known/openid-configuration)" != "200" ]]; do sleep 5; done

# Initialize Sigstore OpenShift Content
helm upgrade -i sigstore-openshift helm/charts/sigstore-openshift -n ${SIGSTORE_NAMESPACE} --create-namespace --set configs.fulcio.server.secret.name=${FULCIO_SERVER_SECRET_NAME} --set-file configs.fulcio.server.secret.root_cert=${FULCIO_ROOT_CERT} --set-file configs.fulcio.server.secret.private_key=${FULCIO_PRIVATE_KEY} --set-file configs.fulcio.server.secret.public_key=${FULCIO_PUBLIC_KEY} --set configs.fulcio.server.secret.password=${PRIVATE_KEY_PASSWORD}

envsubst < "${SCRIPT_BASE_DIR}/helm/values/values.yaml.tpl" > "${SCRIPT_BASE_DIR}/helm/values/values.yaml"

helm upgrade -i -n ${SIGSTORE_NAMESPACE} scaffolding sigstore/scaffold -f "${SCRIPT_BASE_DIR}/helm/values/values.yaml"

echo
echo "Sigstore URL's:"
echo
echo "Fulcio: https://fulcio.apps.$BASE_DOMAIN"
echo "Keycloak: https://keycloak-keycloak-system.apps.$BASE_DOMAIN"
echo "Rekor: https://rekor.apps.$BASE_DOMAIN"
echo "TUF: https://tuf.apps.$BASE_DOMAIN"
