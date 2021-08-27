#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e

required_env_vars=( "${@}" )

for env_var in "${required_env_vars[@]}"
do
    if [ -z "$(printenv "${env_var}")" ]; then
        echo "Environment variable ${env_var} is empty! It's a required environment variable, please set it"
        exit 1
    fi
done
