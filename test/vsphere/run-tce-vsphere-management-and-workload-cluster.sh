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

"${MY_DIR}"/check-required-env-vars.sh "${required_env_vars[@]}"

# "${MY_DIR}"/../install-dependencies.sh
# "${MY_DIR}"/../build-tce.sh

# shellcheck source=test/utils.sh
source "${MY_DIR}"/../utils.sh

# shellcheck source=test/vsphere/cleanup-utils.sh
source "${MY_DIR}"/cleanup-utils.sh

random_id="${RANDOM}"

management_cluster_name="management-cluster-${random_id}"
workload_cluster_name="workload-cluster-${random_id}"

export PROXY_CONFIG_NAME="${management_cluster_name}-and-${workload_cluster_name}"

"${MY_DIR}"/run-proxy-to-vcenter-server-and-control-plane.sh "${VSPHERE_SERVER}"/32 "${MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32 "${WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32

trap '{ "${MY_DIR}"/stop-proxy-to-vcenter-server-and-control-plane.sh; }' EXIT

management_cluster_config_file="${MY_DIR}"/management-cluster-config.yaml

export VSPHERE_CONTROL_PLANE_ENDPOINT=${MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}

time tanzu management-cluster create ${management_cluster_name} --file "${management_cluster_config_file}" -v 10 || {
    error "MANAGEMENT CLUSTER CREATION FAILED! Using govc to cleanup ${management_cluster_name} management cluster resources"
    govc_cleanup ${management_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${management_cluster_name} management cluster resources using vCenter Web UI"

    exit 1
}

"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${management_cluster_name}-admin@${management_cluster_name}

workload_cluster_config_file="${MY_DIR}"/workload-cluster-config.yaml

export VSPHERE_CONTROL_PLANE_ENDPOINT=${WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}

time tanzu cluster create ${workload_cluster_name} --file "${workload_cluster_config_file}" -v 10 || {
    error "WORKLOAD CLUSTER CREATION FAILED!"

    echo "Using govc to cleanup ${management_cluster_name} management cluster resources"
    govc_cleanup ${management_cluster_name} || error "MANAGEMENT CLUSTER DELETION FAILED! GOVC CLEANUP FAILED!! Please manually delete any ${management_cluster_name} management cluster resources using vCenter Web UI"

    error "Using govc to cleanup ${workload_cluster_name} workload cluster resources"
    govc_cleanup ${workload_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${workload_cluster_name} workload cluster resources using vCenter Web UI"

    exit 1
}

"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${workload_cluster_name}-admin@${workload_cluster_name}

echo "Cleaning up"

echo "Deleting workload cluster"
time tanzu cluster delete ${workload_cluster_name} -y || {
    error "WORKLOAD CLUSTER DELETION FAILED!!"

    echo "Using govc to cleanup ${management_cluster_name} management cluster resources"
    govc_cleanup ${management_cluster_name} || error "MANAGEMENT CLUSTER DELETION FAILED! GOVC CLEANUP FAILED!! Please manually delete any ${management_cluster_name} management cluster resources using vCenter Web UI"

    error "Using govc to cleanup ${workload_cluster_name} workload cluster resources"
    govc_cleanup ${workload_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${workload_cluster_name} workload cluster resources using vCenter Web UI"

    exit 1
}

for (( i = 1 ; i <= 120 ; i++))
do
    echo "Waiting for workload cluster to get deleted..."
    num_of_clusters=$(tanzu cluster list -o json | jq 'length')
    if [[ "$num_of_clusters" != "0" ]]; then
        echo "Workload cluster ${workload_cluster_name} successfully deleted"
        break
    fi
    if [[ "$i" == 120 ]]; then
        echo "Timed out waiting for workload cluster ${workload_cluster_name} to get deleted"

        echo "Using govc to cleanup ${management_cluster_name} management cluster resources"
        govc_cleanup ${management_cluster_name} || error "MANAGEMENT CLUSTER DELETION FAILED! GOVC CLEANUP FAILED!! Please manually delete any ${management_cluster_name} management cluster resources using vCenter Web UI"

        error "Using govc to cleanup ${workload_cluster_name} workload cluster resources"
        govc_cleanup ${workload_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${workload_cluster_name} workload cluster resources using vCenter Web UI"

        exit 1
    fi
    sleep 5
done

echo "Deleting management cluster"
time tanzu management-cluster delete ${management_cluster_name} -y || {
    error "MANAGEMENT CLUSTER DELETION FAILED!! Using govc to cleanup ${management_cluster_name} management cluster resources"
    govc_cleanup ${management_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${management_cluster_name} management cluster resources using vCenter Web UI"

    exit 1
}

