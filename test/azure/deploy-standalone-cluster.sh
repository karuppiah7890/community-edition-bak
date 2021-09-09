#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This script tests TCE Standalone cluster in Azure.
# It builds TCE, spins up a standalone cluster in Azure, 
# installs the default packages,
# and cleans the environment.
# Note: This script supports only Linux(Debian) and MacOS
# Following environment variables need to be exported before running the script
# AZURE_TENANT_ID
# AZURE_SUBSCRIPTION_ID
# AZURE_CLIENT_ID
# AZURE_CLIENT_SECRET
# AZURE_SSH_PUBLIC_KEY_B64
# Azure location is set to australiacentral using AZURE_LOCATION
# The best way to run this is by calling `make azure-standalone-cluster-e2e-test`
# from the root of the TCE repository.

set -e
set -x

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TCE_REPO_PATH="${MY_DIR}"/../..

"${TCE_REPO_PATH}"/azure/check-required-env-vars.sh

# shellcheck source=test/util/utils.sh
source "${TCE_REPO_PATH}"/test/util/utils.sh
"${TCE_REPO_PATH}"/test/install-dependencies.sh || { error "Dependency installation failed!"; exit 1; }
"${TCE_REPO_PATH}"/test/build-tce.sh || { error "TCE installation failed!"; exit 1; }

export CLUSTER_NAME="test${RANDOM}"
echo "Setting CLUSTER_NAME to ${CLUSTER_NAME}..."

function az_docker {
    docker run --user $(id -u):$(id -g) \
        --volume ${HOME}:/home/az \
        --env HOME=/home/az \
        --rm --interactive --tty \
        mcr.microsoft.com/azure-cli "$@"
}

function azure_cluster_cleanup {
    echo "Cleaning up ${CLUSTER} cluster resources using azure CLI"

    az_docker login --service-principal --username "${AZURE_CLIENT_ID}" --password "${AZURE_CLIENT_SECRET}" \
        --tenant "${AZURE_TENANT_ID}"

    az_docker account set --subscription "${AZURE_SUBSCRIPTION_ID}"

    az_docker group delete --name "${name}" --yes
}

function delete_cluster {
    echo "Deleting standalone cluster"
    tanzu standalone-cluster delete ${CLUSTER_NAME} -y
}

function create_standalone_cluster {
    echo "Bootstrapping TCE standalone cluster on AWS..."
    tanzu standalone-cluster create "${CLUSTER_NAME}" -f "${TCE_REPO_PATH}"/test/aws/cluster-config.yaml || { 
        error "STANDALONE CLUSTER CREATION FAILED!";
        delete_kind_cluster;
        aws-nuke-tear-down "${CLUSTER_NAME}";
        exit 1;
    }
    kubectl config get-contexts "${CLUSTER_NAME}"-admin@"${CLUSTER_NAME}" || { 
        error "CONTEXT NOT PRESENT IN KUBECONFIG FOR STANDALONE CLUSTER!";
        delete_cluster;
        exit 1;
    }

    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=300s || { error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"; delete_cluster; exit 1; }
}

create_standalone_cluster

echo "Installing packages on TCE..."
"${TCE_REPO_PATH}"/test/add-tce-package-repo.sh || { error "PACKAGE REPOSITORY INSTALLATION FAILED!"; delete_cluster; exit 1; }
tanzu package available list || { error "UNEXPECTED FAILURE OCCURRED!"; delete_cluster; exit 1; }

echo "Cleaning up..."
delete_cluster || {
    error "STANDALONE CLUSTER DELETION FAILED!";
    azure_cluster_cleanup;
    exit 1
}
