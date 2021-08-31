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

"${MY_DIR}"/../install-dependencies.sh
"${MY_DIR}"/../build-tce.sh

# shellcheck source=test/utils.sh
source "${MY_DIR}"/../utils.sh

# shellcheck source=test/vsphere/cleanup-utils.sh
source "${MY_DIR}"/cleanup-utils.sh

random_id="${RANDOM}"

management_cluster_name="management-cluster-${random_id}"
workload_cluster_name="workload-cluster-${random_id}"

# TODO: get rid of this env var name - `CLUSTER_NAME`
# and delete it completely and see if the automation works!! :)
# Cluster creation should work without CLUSTER_NAME in the yaml and in env vars
# It will work with `create`'s name argument!
export CLUSTER_NAME="${management_cluster_name}"
export PROXY_CONFIG_NAME="${management_cluster_name}-and-${workload_cluster_name}"

"${MY_DIR}"/run-proxy-to-vcenter-server-and-control-plane.sh "${VSPHERE_SERVER}"/32 "${MANAGEMENT_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32 "${WORKLOAD_CLUSTER_VSPHERE_CONTROL_PLANE_ENDPOINT}"/32

trap '{ "${MY_DIR}"/stop-proxy-to-vcenter-server-and-control-plane.sh; }' EXIT

function delete_management_cluster {
    vsphere_cluster_name=$1

    if [[ -z "${vsphere_cluster_name}" ]]; then
        echo "Cluster name not passed to delete_management_cluster function. Usage example: delete_management_cluster management-cluster-1234"
        exit 1
    fi

    echo "Deleting management cluster"
    tanzu management-cluster delete ${vsphere_cluster_name} -y || {
        # TODO: let's mention cluster name in the error?
        error "MANAGEMENT CLUSTER DELETION FAILED!! Using govc to cleanup cluster resources"
        govc_cleanup ${vsphere_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${CLUSTER_NAME} management cluster resources using vCenter Web UI"
        # Finally fail after cleanup because cluster delete command failed,
        # and cluster delete command is a subject under test (SUT) in the E2E test
        exit 1
    }
}

function delete_workload_cluster {
    vsphere_cluster_name=$1

    if [[ -z "${vsphere_cluster_name}" ]]; then
        echo "Cluster name not passed to delete_workload_cluster function. Usage example: delete_workload_cluster workload-cluster-1234"
        exit 1
    fi

    echo "Deleting workload cluster"
    tanzu cluster delete ${vsphere_cluster_name} -y || {
        # TODO: let's mention cluster name in the error?
        error "WORKLOAD CLUSTER DELETION FAILED!! Using govc to cleanup cluster resources"
        govc_cleanup ${vsphere_cluster_name} || error "GOVC CLEANUP FAILED!! Please manually delete any ${vsphere_cluster_name} workload cluster resources using vCenter Web UI"
        # Finally fail after cleanup because cluster delete command failed,
        # and cluster delete command is a subject under test (SUT) in the E2E test
        exit 1
    }
}

management_cluster_config_file="${MY_DIR}"/management-cluster-config.yaml

tanzu management-cluster create ${CLUSTER_NAME} --file "${management_cluster_config_file}" -v 10 || {
    error "MANAGEMENT CLUSTER CREATION FAILED!"
    govc_cleanup ${CLUSTER_NAME} || error "GOVC CLEANUP FAILED!! Please manually delete any ${CLUSTER_NAME} management cluster resources using vCenter Web UI"
    # Finally fail after cleanup because cluster create command failed,
    # and cluster create command is a subject under test (SUT) in the E2E test
    exit 1
}

"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${CLUSTER_NAME}-admin@${CLUSTER_NAME}

export CLUSTER_NAME="${workload_cluster_name}"

workload_cluster_config_file="${MY_DIR}"/workload-cluster-config.yaml

tanzu cluster create ${CLUSTER_NAME} --file "${workload_cluster_config_file}" -v 10 || {
    error "WORKLOAD CLUSTER CREATION FAILED!"
    govc_cleanup ${CLUSTER_NAME} || error "GOVC CLEANUP FAILED!! Please manually delete any ${CLUSTER_NAME} workload cluster resources using vCenter Web UI"

    delete_management_cluster ${management_cluster_name} || error "MANAGEMENT CLUSTER DELETION FAILED!"

    exit 1
}

"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${CLUSTER_NAME}-admin@${CLUSTER_NAME}

echo "Cleaning up"

delete_workload_cluster ${workload_cluster_name} || {
    error "WORKLOAD CLUSTER DELETION FAILED!"

    delete_management_cluster ${management_cluster_name} || error "MANAGEMENT CLUSTER DELETION FAILED!"

    exit 1
}

delete_management_cluster ${management_cluster_name}
