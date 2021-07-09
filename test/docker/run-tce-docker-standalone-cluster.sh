#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# "${MY_DIR}"/../install-dependencies.sh
# "${MY_DIR}"/../build-tce.sh

sudo sysctl net/netfilter/nf_conntrack_max=131072

"${MY_DIR}"/install-jq.sh
"${MY_DIR}"/get-tce.sh

echo "Running debug script in the background..."

"${MY_DIR}"/debug-tce-install.sh &

guest_cluster_name="guest-cluster-${RANDOM}"

CLUSTER_PLAN=dev CLUSTER_NAME="$guest_cluster_name" tanzu standalone-cluster create ${guest_cluster_name} -i docker -v 10

"${MY_DIR}"/check-tce-cluster-creation.sh ${guest_cluster_name}-admin@${guest_cluster_name}
