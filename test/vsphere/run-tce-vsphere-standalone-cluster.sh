#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# Note: This script supports only Linux(Debian/Ubuntu) and MacOS
# Following environment variables are expected to be exported before running the script.
# The script will fail if any of them is missing
# VSPHERE_CONTROL_PLANE_ENDPOINT - virtual and static IP for the cluster's control plane nodes
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

declare -a required_env_vars=("VSPHERE_CONTROL_PLANE_ENDPOINT"
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

# shellcheck source=test/util/utils.sh
source "${MY_DIR}"/../util/utils.sh

# shellcheck source=test/vsphere/cleanup-utils.sh
source "${MY_DIR}"/cleanup-utils.sh

export CLUSTER_NAME="guest-cluster-${RANDOM}"
export PROXY_CONFIG_NAME=${CLUSTER_NAME}

"${MY_DIR}"/run-proxy-to-vcenter-server-and-control-plane.sh "${VSPHERE_SERVER}"/32 "${VSPHERE_CONTROL_PLANE_ENDPOINT}"/32

trap '{ "${MY_DIR}"/stop-proxy-to-vcenter-server-and-control-plane.sh; }' EXIT

cluster_config_file="${MY_DIR}"/standalone-cluster-config.yaml

# Cleanup function
function deletecluster {
    vsphere_cluster_name=$1

    if [[ -z "${vsphere_cluster_name}" ]]; then
        echo "Cluster name not passed to deletecluster function. Usage example: deletecluster standalone-cluster-1234"
        exit 1
    fi

    echo "Deleting standalone cluster"
    tanzu standalone-cluster delete ${vsphere_cluster_name} -y || {
        error "STANDALONE CLUSTER DELETION FAILED!"
        govc_cleanup ${vsphere_cluster_name}
        # Finally fail after cleanup because cluster delete command failed,
        # and cluster delete command is a subject under test (SUT) in the E2E test
        exit 1
    }
}

tanzu standalone-cluster create ${CLUSTER_NAME} --file "${cluster_config_file}" -v 10 || {
    error "STANDALONE CLUSTER CREATION FAILED!"
    # TODO: directly delete the management cluster with govc, that's better.
    # as creation failing can be very tricky to delete with tanzu management-cluster delete
    # command.
    deletecluster
    # Finally fail after cleanup because cluster create command failed,
    # and cluster create command is a subject under test (SUT) in the E2E test
    exit 1
}

"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${CLUSTER_NAME}-admin@${CLUSTER_NAME}

echo "Cleaning up"
deletecluster ${CLUSTER_NAME}
