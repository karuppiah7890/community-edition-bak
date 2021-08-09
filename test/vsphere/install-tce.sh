#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# TODO: Use "make release" and install TCE, instead of using TCE GitHub releases

TCE_VERSION="v0.7.0-rc.1-karuppiah"
TCE_RELEASE_TAR_BALL="tce-linux-amd64-v0.7.0-dev.1.tar.gz"
TCE_RELEASE_DIR="tce-linux-amd64-v0.7.0-dev.1"
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
INSTALLATION_DIR="${MY_DIR}/tce-installation"

mkdir -p "${INSTALLATION_DIR}"

curl -L https://github.com/gruntwork-io/fetch/releases/download/v0.4.2/fetch_linux_amd64 -o "${INSTALLATION_DIR}"/fetch

chmod +x "${INSTALLATION_DIR}"/fetch

"${INSTALLATION_DIR}"/fetch --repo "https://github.com/karuppiah7890/tce" \
    --tag ${TCE_VERSION} \
    --release-asset ${TCE_RELEASE_TAR_BALL} \
    --progress \
    --github-oauth-token ${GH_ACCESS_TOKEN} \
    "${INSTALLATION_DIR}"

tar xzvf "${INSTALLATION_DIR}"/${TCE_RELEASE_TAR_BALL} --directory="${INSTALLATION_DIR}"

./"${INSTALLATION_DIR}"/${TCE_RELEASE_DIR}/install.sh
