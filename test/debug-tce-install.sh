#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

echo "DEBUGGING TCE install :D"

print_green() {
    echo -e "\033[32mCustom Debug Script: ${@}\033[39m"
}

# Install kind

BUILD_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ -z "$(command -v kind)" ]]; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-${BUILD_OS}-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

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
    number_of_nodes=$(kubectl get nodes -o json | jq '.items | length' || true)

    if [ "${number_of_nodes}" == "1" ]; then
        found_nodes="true"
        for i in 1 2 3
        do
            kubectl wait --for=condition=ready node --all --timeout=240s || true
            kubectl describe node | grep -i error || true
        done
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

docker_engine_mem=$(docker system info -f "{{.MemTotal}}")

print_green "Max RAM available for Docker Engine - ${docker_engine_mem}"

docker_engine_cpu=$(docker system info -f "{{.NCPU}}")

print_green "Max Number of CPUs available for Docker Engine - ${docker_engine_cpu}"

print_system_resources() {
    print_green "Disk space available for Runner - "

    df -H

    print_green "RAM available for Runner - "

    free -g

    docker_engine_resource_usage_stats=$(docker stats --no-stream)

    print_green "CPU and RAM available for Docker Engine - ${docker_engine_resource_usage_stats}"
}

print_system_resources

# get all pods, filter out to get the providers and related pods - use "managers", check which are not ready, find issues in them by describing the pods

temp_dir=$(mktemp -d)
all_pods_json_file="${temp_dir}/all-pods.json"

while true
do
    all_ready="true"
    kubectl get pods -A \
    -o json \
    | jq '.items[] | { name: .metadata.name, namespace: .metadata.namespace }' \
    | jq -s > "${all_pods_json_file}"

    jq -c '.[]' ${all_pods_json_file} | while read controller_pod; do
        name=$(echo ${controller_pod} | jq .name -r)
        namespace=$(echo ${controller_pod} | jq .namespace -r)

        # is_ready=$(kubectl get pod -n "${namespace}" "${name}" -o json | jq '.status.conditions[] | select(.type == "Ready") | .status' -r)

        # if [[ "${is_ready}" != "True" ]]; then
        #     # The below line is not change the value of `all_ready` to affect the
        #     # if statement that comes later. Maybe it's because the `all_ready` is used
        #     # in a nested block / context? Hmm. The definition is outside the if block and
        #     # outside the while loop over here
        #     all_ready="false"
        #     kubectl describe pod -n "${namespace}" "${name}" | tail
        #     kubectl logs -n "${namespace}" "${name}" || true
        # fi

        kubectl describe pod -n "${namespace}" "${name}" | tail || true
        kubectl logs -n "${namespace}" "${name}" || true
    done

    if [[ "${all_ready}" == "true" ]]; then
        echo "All manager pods are ready"
    else
        echo "Some manager pods are not ready"
    fi

    sleep 20

    print_system_resources
done

# Ideas for debugging -

# CLUSTER_PLAN=dev CLUSTER_NAME=my-cluster tanzu standalone-cluster create my-cluster -i docker -v 10 &> /tmp/standalone.log &
# pid=$!
# for ((i=1;i<=100;i++))
# do
# echo ""
# echo "#####"
# echo "standalone logs"
# echo "#####"
# echo ""
# cat /tmp/standalone.log
# bootstrapclustername=$(kind get clusters | grep tkg) || true
# if [[ -n $bootstrapclustername ]]; then
#     kind get kubeconfig --name $bootstrapclustername > /tmp/bootstrap.kubeconfig || true
#     echo ""
#     echo "#####"
#     echo "bootstrap resources"
#     echo "#####"
#     echo ""
#     kubectl --kubeconfig /tmp/bootstrap.kubeconfig get all,clusters,dockerclusters,machines,dockermachines,dockermachinetemplates,dockermachinepools,machinedeployments,machinehealthchecks,machinepools,machinesets -A || true
#     echo ""
#     echo "#####"
#     echo "bootstrap capd logs"
#     echo "#####"
#     echo ""
#     kubectl --kubeconfig /tmp/bootstrap.kubeconfig logs -l cluster.x-k8s.io/provider=infrastructure-docker -n capd-system -c manager || true
# fi
# container=$(docker ps | grep -e "my.*control" | awk '{ print $1}') || true
# if [[ -n $container ]]; then
#     echo ""
#     echo "#####"
#     echo "standalone cluster control plane containers"
#     echo "#####"
#     echo ""
#     docker exec $container /bin/bash -c "crictl --runtime-endpoint unix:////var/run/containerd/containerd.sock ps -a" || true
#     echo ""
#     echo "#####"
#     echo "standalone cluster control plane container logs"
#     echo "#####"
#     echo ""
#     docker exec $container /bin/bash -c "crictl --runtime-endpoint unix:////var/run/containerd/containerd.sock ps -a | grep -v CONTAINER | awk '{print $1}' | xargs -n1 crictl --runtime-endpoint unix:////var/run/containerd/containerd.sock logs -t" || true
#     echo "#####"
#     echo "kubelet logs"
#     echo "#####"
#     echo ""
#     docker exec $container /bin/bash -c "journalctl -xeu kubelet" || true
# fi
# sleep 5
# done
# kill $pid
