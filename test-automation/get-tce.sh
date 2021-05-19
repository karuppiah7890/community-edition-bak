#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

# TODO: Use "make release" and install TCE, instead of using TCE GitHub releases

TCE_VERSION="v0.4.0"
TCE_RELEASE_TAR_BALL="tce-linux-amd64-${TCE_VERSION}.tar.gz"
TCE_RELEASE_DIR="tce-linux-amd64-${TCE_VERSION}"
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
INSTALLATION_DIR="${MY_DIR}/tce-installation"

mkdir -p "${INSTALLATION_DIR}"

curl -L https://github.com/gruntwork-io/fetch/releases/download/v0.4.2/fetch_linux_amd64 -o "${INSTALLATION_DIR}"/fetch

chmod +x "${INSTALLATION_DIR}"/fetch

"${INSTALLATION_DIR}"/fetch --repo "https://github.com/vmware-tanzu/tce" \
    --tag ${TCE_VERSION} \
    --release-asset ${TCE_RELEASE_TAR_BALL} \
    --progress \
    "${INSTALLATION_DIR}"

tar xzvf "${INSTALLATION_DIR}"/${TCE_RELEASE_TAR_BALL} --directory="${INSTALLATION_DIR}"

# TODO: change this to direct script invocation once
# https://github.com/vmware-tanzu/tce/pull/550 is released in a stable TCE version
cd "${INSTALLATION_DIR}"/${TCE_RELEASE_DIR}

./install.sh

# Revert back to original directory after installation
cd -
