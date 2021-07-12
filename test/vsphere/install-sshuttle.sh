#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

print_unable_to_install_sshuttle() {
    echo "Unable to automatically install sshuttle for this platform. Please install sshuttle."
}

BUILD_OS=$(uname -s)
export BUILD_OS

if [[ -z "$(command -v sshuttle)" ]]; then
    if [[ "$BUILD_OS" == "Linux" ]]; then
        distro_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)

        if [[ "${distro_id}" == "ubuntu" || "${distro_id}" == "debian" ]]; then
            sudo apt-get install sshuttle --yes
        else
            print_unable_to_install_sshuttle
            echo "Exiting..."
            exit 1
        fi
    elif [[ "$BUILD_OS" == "Darwin" ]]; then
        brew install sshuttle
    else
        print_unable_to_install_sshuttle
        echo "Exiting..."
        exit 1
    fi
fi
