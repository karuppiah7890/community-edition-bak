#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

function az_docker {
    docker run --user "$(id -u)":"$(id -g)" \
        --volume "${HOME}":/home/az \
        --env HOME=/home/az \
        --rm \
        mcr.microsoft.com/azure-cli az "$@"
}

function azure_login {
    az_docker login --service-principal --username "${AZURE_CLIENT_ID}" --password "${AZURE_CLIENT_SECRET}" \
        --tenant "${AZURE_TENANT_ID}" || {
        error "azure CLI LOGIN FAILED!"
        return 1
    }

    az_docker account set --subscription "${AZURE_SUBSCRIPTION_ID}" || {
        error "azure CLI SETTING ACCOUNT SUBSCRIPTION ID FAILED!"
        return 1
    }
}

function azure_cluster_cleanup {
    echo "Cleaning up ${CLUSTER_NAME} cluster resources using azure CLI"

    azure_login || {
        return 1
    }

    az_docker group delete --name "${AZURE_RESOURCE_GROUP}" --yes || {
        error "azure CLI RESOURCE GROUP DELETION FAILED!"
        return 1
    }
}

function accept_vm_image_terms {
    azure_login || {
        return 1
    }

    az_docker vm image terms accept --publisher "${VM_IMAGE_PUBLISHER}" --offer "${VM_IMAGE_OFFER}" \
        --plan "${VM_IMAGE_BILLING_PLAN_SKU}" --subscription "${AZURE_SUBSCRIPTION_ID}" || {
        error "azure CLI ACCEPT VM IMAGE TERMS FAILED!"
        return 1
    }
}
