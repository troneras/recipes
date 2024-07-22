#!/bin/bash
## Do not modify this file. You will lose the ability to install and auto-update!

set -e # Exit immediately if a command exits with a non-zero status
## $1 could be empty, so we need to disable this check
#set -u # Treat unset variables as an error and exit
set -o pipefail # Cause a pipeline to return the status of the last command that exited with a non-zero status

VERSION="0.0.1"
DOCKER_VERSION="26.0"

# CDN="https://cdn.coollabs.io/coolify"
OS_TYPE=$(grep -w "ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')

# Check if the OS is manjaro, if so, change it to arch
if [ "$OS_TYPE" = "manjaro" ] || [ "$OS_TYPE" = "manjaro-arm" ]; then
    OS_TYPE="arch"
fi

# Check if the OS is popOS, if so, change it to ubuntu
if [ "$OS_TYPE" = "pop" ]; then
    OS_TYPE="ubuntu"
fi

# Check if the OS is linuxmint, if so, change it to ubuntu
if [ "$OS_TYPE" = "linuxmint" ]; then
    OS_TYPE="ubuntu"
fi

#Check if the OS is zorin, if so, change it to ubuntu
if [ "$OS_TYPE" = "zorin" ]; then
    OS_TYPE="ubuntu"
fi

if [ "$OS_TYPE" = "arch" ] || [ "$OS_TYPE" = "archarm" ]; then
    OS_VERSION="rolling"
else
    OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
fi

# Install xargs on Amazon Linux 2023 - lol
if [ "$OS_TYPE" = 'amzn' ]; then
    dnf install -y findutils >/dev/null
fi

# LATEST_VERSION=$(curl --silent $CDN/versions.json | grep -i version | xargs | awk '{print $2}' | tr -d ',')
DATE=$(date +"%Y%m%d-%H%M%S")

if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi

case "$OS_TYPE" in
arch | ubuntu | debian | raspbian | centos | fedora | rhel | ol | rocky | sles | opensuse-leap | opensuse-tumbleweed | almalinux | amzn) ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
    exit
    ;;
esac

# # Overwrite LATEST_VERSION if user pass a version number
# if [ "$1" != "" ]; then
#     LATEST_VERSION=$1
#     LATEST_VERSION="${LATEST_VERSION,,}"
#     LATEST_VERSION="${LATEST_VERSION#v}"
# fi

# echo -e "-------------"
# echo -e "Welcome to Coolify v4 beta installer!"
# echo -e "This script will install everything for you."
# echo -e "(Source code: https://github.com/coollabsio/coolify/blob/main/scripts/install.sh )\n"
# echo -e "-------------"

echo "OS: $OS_TYPE $OS_VERSION"
# echo "Coolify version: $LATEST_VERSION"

echo -e "-------------"
echo "Installing required packages..."

case "$OS_TYPE" in
arch)
    pacman -Sy --noconfirm --needed curl wget git jq >/dev/null || true
    ;;
ubuntu | debian | raspbian)
    apt update -y >/dev/null
    apt install -y curl wget git jq >/dev/null
    ;;
centos | fedora | rhel | ol | rocky | almalinux | amzn)
    if [ "$OS_TYPE" = "amzn" ]; then
        dnf install -y wget git jq >/dev/null
    else
        if ! command -v dnf >/dev/null; then
            yum install -y dnf >/dev/null
        fi
        dnf install -y curl wget git jq >/dev/null
    fi
    ;;
sles | opensuse-leap | opensuse-tumbleweed)
    zypper refresh >/dev/null
    zypper install -y curl wget git jq >/dev/null
    ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
    exit
    ;;
esac

# Detect OpenSSH server
SSH_DETECTED=false
if [ -x "$(command -v systemctl)" ]; then
    if systemctl status sshd >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
    if systemctl status ssh >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
elif [ -x "$(command -v service)" ]; then
    if service sshd status >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
    if service ssh status >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
fi
if [ "$SSH_DETECTED" = "false" ]; then
    echo "###############################################################################"
    echo "WARNING: Could not detect if OpenSSH server is installed and running - this does not mean that it is not installed, just that we could not detect it."
    echo -e "Please make sure it is set, otherwise Coolify cannot connect to the host system. \n"
    echo "###############################################################################"
fi

# Detect SSH PermitRootLogin
SSH_PERMIT_ROOT_LOGIN=false
SSH_PERMIT_ROOT_LOGIN_CONFIG=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}') || SSH_PERMIT_ROOT_LOGIN_CONFIG="N/A (commented out or not found at all)"
if [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "prohibit-password" ] || [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "yes" ] || [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "without-password" ]; then
    echo "PermitRootLogin is enabled."
    SSH_PERMIT_ROOT_LOGIN=true
fi

if [ "$SSH_PERMIT_ROOT_LOGIN" != "true" ]; then
    echo "###############################################################################"
    echo "WARNING: PermitRootLogin is not enabled in /etc/ssh/sshd_config."
    echo -e "It is set to $SSH_PERMIT_ROOT_LOGIN_CONFIG. Should be prohibit-password, yes or without-password.\n"
    echo -e "Please make sure it is set, otherwise Coolify cannot connect to the host system. \n"
    echo "###############################################################################"
fi

# Detect if docker is installed via snap
if [ -x "$(command -v snap)" ]; then
    if snap list | grep -q docker; then
        echo "Docker is installed via snap."
        echo "Please note that Coolify does not support Docker installed via snap."
        echo "Please remove Docker with snap (snap remove docker) and reexecute this script."
        exit 1
    fi
fi

if ! [ -x "$(command -v docker)" ]; then
    set +e
    curl https://get.docker.com | sh -s -- --version ${DOCKER_VERSION}
    if [ -x "$(command -v docker)" ]; then
        echo "Docker installed successfully."
    else
        echo "Docker installation failed with official script."
        echo "Maybe your OS is not supported?"
        echo "Please visit https://docs.docker.com/engine/install/ and install Docker manually to continue."
        exit 1
    fi
    set -e
fi

echo -e "-------------"
echo -e "Check Docker Configuration..."
mkdir -p /etc/docker
# shellcheck disable=SC2015
test -s /etc/docker/daemon.json && cp /etc/docker/daemon.json /etc/docker/daemon.json.original-"$DATE" || cat >/etc/docker/daemon.json <<EOL
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL
cat >/etc/docker/daemon.json.coolify <<EOL
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL
TEMP_FILE=$(mktemp)
if ! jq -s '.[0] * .[1]' /etc/docker/daemon.json /etc/docker/daemon.json.coolify >"$TEMP_FILE"; then
    echo "Error merging JSON files"
    exit 1
fi
mv "$TEMP_FILE" /etc/docker/daemon.json

if [ -s /etc/docker/daemon.json.original-"$DATE" ]; then
    DIFF=$(diff <(jq --sort-keys . /etc/docker/daemon.json) <(jq --sort-keys . /etc/docker/daemon.json.original-"$DATE"))
    if [ "$DIFF" != "" ]; then
        echo "Docker configuration updated, restart docker daemon..."
        systemctl restart docker
    else
        echo "Docker configuration is up to date."
    fi
else
    echo "Docker configuration updated, restart docker daemon..."
    systemctl restart docker
fi

echo -e "-------------"
