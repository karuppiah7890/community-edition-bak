#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# Note: This script supports only Linux(Debian/Ubuntu) and MacOS
# Following environment variables are expected to be exported before running the script.
# The script will fail if any of them is missing
# MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT - virtual and static IP for the management cluster's control plane nodes
# WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT - virtual and static IP for the management cluster's control plane nodes
# VSPHERE_SERVER - private IP of the vcenter server
# VSPHERE_SSH_AUTHORIZED_KEY - SSH public key to inject into control plane nodes and worker nodes for SSHing into them later
# VSPHERE_USERNAME - vcenter username
# VSPHERE_PASSWORD - vcenter password
# VSPHERE_DATACENTER - SDDC path
# VSPHERE_DATASTORE - Name of the vSphere datastore to deploy the Tanzu Kubernetes cluster as it appears in the vSphere inventory
# VSPHERE_FOLDER - name of an existing VM folder in which to place Tanzu Kubernetes Grid VMs
# VSPHERE_NETWORK - The network portgroup to assign each VM node
# VSPHERE_RESOURCE_POOL - Name of an existing resource pool in which to place this Tanzu Kubernetes cluster
# JUMPER_SSH_HOST_IP - public IP address to access the Jumper host for SSH
# JUMPER_SSH_USERNAME - username to access the Jumper host for SSH
# JUMPER_SSH_PRIVATE_KEY - private key to access to access the Jumper host for SSH
# JUMPER_SSH_KNOWN_HOSTS_ENTRY - entry to put in the SSH client machine's (from where script is run) known_hosts file

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TCE_REPO_PATH="${MY_DIR}"/../..

declare -a required_env_vars=("MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT"
"WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT"
"VSPHERE_SERVER"
"VSPHERE_SSH_AUTHORIZED_KEY"
"VSPHERE_USERNAME"
"VSPHERE_PASSWORD"
"VSPHERE_DATACENTER"
"VSPHERE_DATASTORE"
"VSPHERE_FOLDER"
"VSPHERE_NETWORK"
"VSPHERE_RESOURCE_POOL"
"JUMPER_SSH_HOST_IP"
"JUMPER_SSH_USERNAME"
"JUMPER_SSH_PRIVATE_KEY"
"JUMPER_SSH_KNOWN_HOSTS_ENTRY")

"${TCE_REPO_PATH}"/test/vsphere/check-required-env-vars.sh "${required_env_vars[@]}"

# shellcheck source=test/util/utils.sh
source "${TCE_REPO_PATH}"/test/util/utils.sh

# shellcheck source=test/vsphere/cleanup-utils.sh
source "${TCE_REPO_PATH}"/test/vsphere/cleanup-utils.sh

"${TCE_REPO_PATH}"/test/install-dependencies.sh || { error "Dependency installation failed!"; exit 1; }
"${TCE_REPO_PATH}"/test/fetch-and-install-tce-release.sh v0.7.0 || { error "TCE installation failed!"; exit 1; }

random_id="${RANDOM}"

export MANAGEMENT_CLUSTER_NAME="test-management-cluster-${random_id}"
export WORKLOAD_CLUSTER_NAME="test-workload-cluster-${random_id}"

# export PROXY_CONFIG_NAME="${MANAGEMENT_CLUSTER_NAME}-and-${WORKLOAD_CLUSTER_NAME}"

# "${TCE_REPO_PATH}"/test/vsphere/run-proxy-to-vcenter-server-and-control-plane.sh "${VSPHERE_SERVER}"/32 "${MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32 "${WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32

# trap '{ "${TCE_REPO_PATH}"/test/vsphere/stop-proxy-to-vcenter-server-and-control-plane.sh; }' EXIT

function cleanup_management_cluster {
    echo "Using govc to cleanup ${MANAGEMENT_CLUSTER_NAME} management cluster resources"
    govc_cleanup ${MANAGEMENT_CLUSTER_NAME} || error "MANAGEMENT CLUSTER CLEANUP USING GOVC FAILED! Please manually delete any ${MANAGEMENT_CLUSTER_NAME} management cluster resources using vCenter Web UI"
}

function cleanup_workload_cluster {
    error "Using govc to cleanup ${WORKLOAD_CLUSTER_NAME} workload cluster resources"
    govc_cleanup ${WORKLOAD_CLUSTER_NAME} || error "WORKLOAD CLUSTER CLEANUP USING GOVC FAILED! Please manually delete any ${WORKLOAD_CLUSTER_NAME} workload cluster resources using vCenter Web UI"
}

management_cluster_config_file="${TCE_REPO_PATH}"/test/vsphere/management-cluster-config.yaml

export VSPHERE_CONTROL_PLANE_ENDPOINT=${MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}
export CLUSTER_NAME=${MANAGEMENT_CLUSTER_NAME}

time tanzu management-cluster create ${MANAGEMENT_CLUSTER_NAME} --file "${management_cluster_config_file}" -v 10 || {
    error "MANAGEMENT CLUSTER CREATION FAILED!"
    cleanup_management_cluster
    exit 1
}

unset VSPHERE_CONTROL_PLANE_ENDPOINT
unset CLUSTER_NAME

"${TCE_REPO_PATH}"/test/docker/check-tce-cluster-creation.sh ${MANAGEMENT_CLUSTER_NAME}-admin@${MANAGEMENT_CLUSTER_NAME}

workload_cluster_config_file="${TCE_REPO_PATH}"/test/vsphere/workload-cluster-config.yaml

export VSPHERE_CONTROL_PLANE_ENDPOINT=${WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}
export CLUSTER_NAME=${WORKLOAD_CLUSTER_NAME}

time tanzu cluster create ${WORKLOAD_CLUSTER_NAME} --file "${workload_cluster_config_file}" -v 10 || {
    error "WORKLOAD CLUSTER CREATION FAILED!"
    cleanup_management_cluster
    cleanup_workload_cluster
    exit 1
}

unset VSPHERE_CONTROL_PLANE_ENDPOINT
unset CLUSTER_NAME

"${TCE_REPO_PATH}"/test/docker/check-tce-cluster-creation.sh ${WORKLOAD_CLUSTER_NAME}-admin@${WORKLOAD_CLUSTER_NAME}

echo "Cleaning up"

echo "Deleting workload cluster"
time tanzu cluster delete ${WORKLOAD_CLUSTER_NAME} -y || {
    error "WORKLOAD CLUSTER DELETION FAILED!"
    cleanup_management_cluster
    cleanup_workload_cluster
    exit 1
}

wait_iterations=120

for (( i = 1 ; i <= wait_iterations ; i++))
do
    echo "Waiting for workload cluster to get deleted..."
    num_of_clusters=$(tanzu cluster list -o json | jq 'length')
    if [[ "$num_of_clusters" != "0" ]]; then
        echo "Workload cluster ${WORKLOAD_CLUSTER_NAME} successfully deleted"
        break
    fi
    if [[ "${i}" == "${wait_iterations}" ]]; then
        echo "Timed out waiting for workload cluster ${WORKLOAD_CLUSTER_NAME} to get deleted"
        cleanup_management_cluster
        cleanup_workload_cluster
        exit 1
    fi
    sleep 5
done

echo "Deleting management cluster"
time tanzu management-cluster delete ${MANAGEMENT_CLUSTER_NAME} -y || {
    error "MANAGEMENT CLUSTER DELETION FAILED!"
    cleanup_management_cluster
    exit 1
}

