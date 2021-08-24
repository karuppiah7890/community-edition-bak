set -e
set -x

BUILD_OS=$(uname -s)

# Helper functions
function error {
    printf '\E[31m'; echo "$@"; printf '\E[0m'
}

# Make sure docker is installed
echo "Checking for Docker..."
if [[ -z "$(command -v docker)" ]]; then
    echo "Installing Docker..."
    if [[ "$BUILD_OS" == "Linux" ]]; then
        distro_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
        sudo apt-get update > /dev/null
        sudo apt-get remove docker docker-engine docker.io containerd runc || true
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release > /dev/null 2>&1
        curl -fsSL https://download.docker.com/linux/${distro_id}/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \
            "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${distro_id} \
            $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt update > /dev/null
        sudo apt install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1
        sudo service docker start
        sleep 30s

        if [[ $(id -u) -ne 0 ]]; then
            sudo usermod -aG docker "$(whoami)"
        fi
    elif [[ "$(BUILD_OS)" == "Darwin" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        brew cask install docker
    fi
else
    echo "Found Docker!"
fi

echo "Verifying Docker..."
if ! sudo docker run hello-world > /dev/null; then
    error "Unable to verify docker functionality, make sure docker is installed correctly"
    exit 1
else
    echo "Verified Docker functionality successfully!"
fi