#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# Note: This script supports only Linux(Debian/Ubuntu) and MacOS
# Following environment variables are expected to be exported before running the script
# VSPHERE_CONTROL_PLANE_ENDPOINT - virtual and static IP for the cluster's control plane nodes
# VSPHERE_SERVER - private IP of the vcenter server
# VSPHERE_SSH_AUTHORIZED_KEY - SSH public key to inject into control plane nodes and worker nodes for SSHing into them later
# VSPHERE_USERNAME - vcenter username
# VSPHERE_PASSWORD - Base64 encoded vcenter password
# VSPHERE_DATACENTER - SDDC path
# VSPHERE_DATASTORE - Name of the vSphere datastore to deploy the Tanzu Kubernetes cluster as it appears in the vSphere inventory
# VSPHERE_FOLDER - name of an existing VM folder in which to place Tanzu Kubernetes Grid VMs
# VSPHERE_NETWORK - The network portgroup to assign each VM node
# VSPHERE_RESOURCE_POOL - Name of an existing resource pool in which to place this Tanzu Kubernetes cluster
# JUMPER_SSH_HOST_IP - public IP address to access the Jumper host for SSH
# JUMPER_SSH_USERNAME - username to access the Jumper host for SSH
# JUMPER_SSH_PRIVATE_KEY - private key to access to access the Jumper host for SSH

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
"JUMPER_SSH_PRIVATE_KEY")

for env_var in "${required_env_vars[@]}"
do
    if [ -z "${env_var}" ]; then
        echo "Environment variable ${env_var} is empty! It's a required environment variable, please set it"
        exit 1
    fi
done

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

"${MY_DIR}"/../install-dependencies.sh
"${MY_DIR}"/../build-tce.sh
"${MY_DIR}"/install-sshuttle.sh

guest_cluster_name="guest-cluster-${RANDOM}"

export CLUSTER_NAME="$guest_cluster_name"

jumper_ssh_host_name=vmc-jumper-${guest_cluster_name}
jumper_ssh_private_key_location=~/.ssh/jumper_private_key

ssh_config_file_template="${MY_DIR}"/ssh-config-template

ssh_config_file=~/.ssh/config

mkdir -p "$(dirname ${ssh_config_file})"
touch ${ssh_config_file}

envsubst < "${ssh_config_file_template}" >> ${ssh_config_file}

mkdir -p "$(dirname ${jumper_ssh_private_key_location})"
touch ${jumper_ssh_private_key_location}

rm -rfv ${jumper_ssh_private_key_location}
printenv 'JUMPER_SSH_PRIVATE_KEY' > ${jumper_ssh_private_key_location}
chmod 400 ${jumper_ssh_private_key_location}

sshuttle --daemon -vvvvvvvv --remote ${jumper_ssh_host_name} "${VSPHERE_SERVER}"/32 "${VSPHERE_CONTROL_PLANE_ENDPOINT}"/32

trap '{ kill $(cat ./sshuttle.pid); }' EXIT

cluster_config_file_template="${MY_DIR}"/standalone-cluster-template.yaml

vsphere_temp_dir=$(mktemp -d)

cluster_config_file="${vsphere_temp_dir}"/standalone-cluster.yaml

envsubst < "${cluster_config_file_template}" > "${cluster_config_file}"

tanzu standalone-cluster create ${guest_cluster_name} --file "${cluster_config_file}" -v 10 || failed="true"

# TODO: Move check script from docker to the parent directory to be used commonly :)
"${MY_DIR}"/../docker/check-tce-cluster-creation.sh ${guest_cluster_name}-admin@${guest_cluster_name}

tanzu standalone-cluster delete ${guest_cluster_name} -y
