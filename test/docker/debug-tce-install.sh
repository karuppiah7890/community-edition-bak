#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

print_green() {
    echo -e "\033[32mCustom Debug Script: ${@}\033[39m"
}

# Install kind

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Check if the kind bootstrap cluster is up and running

kind_cluster=""

while [ -z "${kind_cluster}" ]
do
    sleep 20;
    kind_cluster=$(kind get clusters -q)
done

print_green "Kind cluster is available: ${kind_cluster}"

# Check if the kind k8s cluster is up and running

got_kubeconfig="false"

while [ "${got_kubeconfig}" == "false" ]
do
    full_kubeconfig=$(kind get kubeconfig --name ${kind_cluster} || true)

    if [ -n "${full_kubeconfig}" ]; then
        kind get kubeconfig --name ${kind_cluster} > kind-cluster.kubeconfig
        got_kubeconfig="true"
    fi

    sleep 20;
done

print_green "Waiting for kind cluster nodes to be ready"

found_nodes="false"

export KUBECONFIG=kind-cluster.kubeconfig

while [ "${found_nodes}" == "false" ]
do
    number_of_nodes=$(kubectl get nodes -o json | jq '.items | length')

    if [ "${number_of_nodes}" != "0" ]; then
        found_nodes="true"
        kubectl wait --for=condition=ready node --all --timeout=240s
    fi

    sleep 20;
done

# "${MY_DIR}"/check-tce-cluster-creation.sh ${kind_cluster}

print_green "Kind bootstrap cluster info - "

kubectl cluster-info

print_green "Kind bootstrap cluster nodes info - "

kubectl get nodes

print_green "Kind bootstrap cluster pods info - "

kubectl get pods -A

print_system_resources() {
    print_green "Disk space available for Runner - "

    df -H

    print_green "RAM available for Runner - "

    free -g

    docker_engine_mem=$(docker system info -f "{{.MemTotal}}")

    print_green "RAM available for Docker Engine - ${docker_engine_mem}"

    docker_engine_cpu=$(docker system info -f "{{.NCPU}}")

    print_green "Number of CPUs available for Docker Engine - ${docker_engine_cpu}"
}

print_system_resources

# get all pods, filter out to get the providers and related pods - use "managers", check which are not ready, find issues in them by describing the pods

temp_dir=$(mktemp -d)
controller_pods_json_file="${temp_dir}/controller-pods.json"

while true
do
    all_ready="true"
    kubectl get pods -A \
    -o json \
    | jq '.items[] | select(.metadata.name | test("manager")) | { name: .metadata.name, namespace: .metadata.namespace }' \
    | jq -s > "${controller_pods_json_file}"

    jq -c '.[]' ${controller_pods_json_file} | while read controller_pod; do
        name=$(echo ${controller_pod} | jq .name -r)
        namespace=$(echo ${controller_pod} | jq .namespace -r)

        is_ready=$(kubectl get pod -n "${namespace}" "${name}" -o json | jq '.status.conditions[] | select(.type == "Ready") | .status' -r)

        if [[ "${is_ready}" == "False" ]]; then
            all_ready="false"
            kubectl describe pod -n "${namespace}" "${name}" | tail
        fi
    done

    if [[ "${all_ready}" == "true" ]]; then
        echo "All manager pods are ready"
    else
        echo "Some manager pods are not ready"
    fi

    sleep 20

    print_system_resources
done

