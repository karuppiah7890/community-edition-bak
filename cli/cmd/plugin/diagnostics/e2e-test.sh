#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TANZU_DIAGNOSTICS_BIN=${MY_DIR}/tanzu-diagnostics-e2e

echo "Entering ${MY_DIR} directory to build tanzu diagnostics plugin"
pushd "${MY_DIR}"

go build -o "${TANZU_DIAGNOSTICS_BIN}" -v

echo "Finished building tanzu diagnostics plugin. Leaving ${MY_DIR}"
popd

CLUSTER_NAME_SUFFIX=${RANDOM}
CLUSTER_NAME="e2e-diagnostics-${CLUSTER_NAME_SUFFIX}"
CLUSTER_KUBE_CONTEXT="kind-${CLUSTER_NAME}"
CLUSTER_KUBECONFIG="${CLUSTER_NAME}.kubeconfig"
NEW_CLUSTER_KUBE_CONTEXT="${CLUSTER_NAME}-admin@${CLUSTER_NAME}"

echo "Creating a kind cluster for the E2E test"

KUBECONFIG=${CLUSTER_KUBECONFIG} kind create cluster --name ${CLUSTER_NAME} || {
    echo "Error creating kind cluster!"
    exit 1
}

# The context rename is required for workload cluster diagnostics data collection to work
# as it expects the context name to be in a particular format based on cluster name
# and --workload-cluster-context flag is not supported for now.
KUBECONFIG=${CLUSTER_KUBECONFIG} kubectl config rename-context ${CLUSTER_KUBE_CONTEXT} ${NEW_CLUSTER_KUBE_CONTEXT} || {
    echo "Error renaming kube context!"
    exit 1
}

KUBECONFIG=${CLUSTER_KUBECONFIG} "${TANZU_DIAGNOSTICS_BIN}" collect --bootstrap-cluster-name ${CLUSTER_NAME} \
    --management-cluster-kubeconfig "${CLUSTER_KUBECONFIG}" \
    --management-cluster-context ${NEW_CLUSTER_KUBE_CONTEXT} \
    --management-cluster-name ${CLUSTER_NAME} \
    --workload-cluster-standalone \
    --workload-cluster-infra docker \
    --workload-cluster-name ${CLUSTER_NAME} || {
        echo "Error running tanzu diagnostics collect command!"
        exit 1
    }

echo "Checking if the diagnostics tar balls for the different clusters have been created"

EXPECTED_BOOTSTRAP_CLUSTER_DIAGNOSTICS="bootstrap.${CLUSTER_NAME}.diagnostics.tar.gz"
EXPECTED_MANAGEMENT_CLUSTER_DIAGNOSTICS="management-cluster.${CLUSTER_NAME}.diagnostics.tar.gz"
EXPECTED_WORKLOAD_CLUSTER_DIAGNOSTICS="workload-cluster.${CLUSTER_NAME}.diagnostics.tar.gz"

errors=0

if [ ! -f "$EXPECTED_BOOTSTRAP_CLUSTER_DIAGNOSTICS" ]; then
    echo "$EXPECTED_BOOTSTRAP_CLUSTER_DIAGNOSTICS does not exist. Expected bootstrap cluster diagnostics tar ball to be present"
    ((errors=errors+1))
fi

if [ ! -f "$EXPECTED_MANAGEMENT_CLUSTER_DIAGNOSTICS" ]; then
    echo "$EXPECTED_MANAGEMENT_CLUSTER_DIAGNOSTICS does not exist. Expected management cluster diagnostics tar ball to be present"
    ((errors=errors+1))
fi

if [ ! -f "$EXPECTED_WORKLOAD_CLUSTER_DIAGNOSTICS" ]; then
    echo "$EXPECTED_WORKLOAD_CLUSTER_DIAGNOSTICS does not exist. Expected workload cluster diagnostics tar ball to be present"
    ((errors=errors+1))
fi

if [[ ${errors} -gt 0 ]]; then
    echo "Total E2E errors in tanzu diagnostics plugin: ${errors}"
fi

echo "Cleaning up"

# kind delete cluster --name ${CLUSTER_NAME} || {
#     echo "Failed deleting kind cluster. Please delete it manually"
# }

# rm -fv ${CLUSTER_KUBECONFIG}

if [[ ${errors} -gt 0 ]]; then
    exit 1
fi
