###########################################
##### INSTALLATION SCRIPT - RUN ONCE ######
###########################################
#!/bin/sh

# Usage:
# Phase 1 (on internet-connected machine): ./installation.sh download
# Phase 2 (on offline target machine):     ./installation.sh install
# aws s3api put-object --bucket s3://arn:aws:s3:us-east-1:034362039150:accesspoint/tmp --key offline.zip --body offline.zip      

download_packages() {
    echo "=== PHASE 1: Downloading packages for offline installation ==="

    # Create directory for offline packages
    mkdir -p ./offline-packages
    cd ./offline-packages

    echo "Downloading APT packages..."
    PACKAGES="docker.io unzip curl ca-certificates gnupg postgresql-client postgresql-client-common ldap-utils pass"
    apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests \
    --no-conflicts --no-breaks --no-replaces --no-enhances \
    --no-pre-depends ${PACKAGES} | grep "^\w")

sudo apt update
sudo apt-get install ca-certificates gnupg -y
sudo apt-get install docker.io -y
sudo apt-get install postgresql-client-common -y
sudo apt-get install postgresql-client -y
sudo apt-get install ldap-utils -y
sudo apt-get install unzip -y

    echo "Downloading Boundary CLI..."
    BOUNDARY_VERSION="0.18.2"  # Update to desired version
    ARCH="amd64"  # or arm64 for ARM systems
    wget "https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}/boundary_${BOUNDARY_VERSION}_linux_${ARCH}.zip"

    echo "Download Vault CLI..."
    wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install vault
    cd ..

    echo "Downloading Docker images..."
    docker pull hashicorp/vault-enterprise:latest
    docker save -o ./offline-packages/vault.tar hashicorp/vault-enterprise:latest

    docker pull hashicorp/boundary-enterprise:latest
    docker save -o ./offline-packages/boundary.tar hashicorp/boundary-enterprise:latest

    docker pull postgres:latest
    docker save -o ./offline-packages/postgres.tar postgres:latest

    docker pull quay.io/minio/minio:latest
    docker save -o ./offline-packages/minio.tar quay.io/minio/minio:latest

    echo ""
    echo "=== Download Complete ==="
    echo "Copy the './offline-packages' directory to your target machine"
    echo "Then run: ./installation.sh install"
}

install_packages() {
    echo "=== PHASE 2: Installing from offline packages ==="

    if [ ! -d "./offline-packages" ]; then
        echo "Error: ./offline-packages directory not found!"
        echo "Please copy the offline-packages directory from the download machine"
        exit 1
    fi

    echo "Installing APT packages..."
    sudo dpkg -i ./offline-packages/*.deb
    sudo apt-get install -f -y  # Fix any dependency issues

    echo "Installing Boundary CLI..."
    cd ./offline-packages
    unzip -o boundary_*.zip
    sudo mv boundary /usr/local/bin/
    sudo chmod +x /usr/local/bin/boundary
    cd ..

    echo "Loading Docker images..."
    docker load -i ./vault.tar
    docker load -i .//boundary.tar
    docker load -i ./postgres.tar
    docker load -i ./minio.tar

    echo "Adding current user to docker group..."
    sudo usermod -aG docker $USER

    echo ""
    echo "=== Installation Complete ==="
    echo "Please log out and log back in, or run: newgrp docker"
    echo "Then test with: docker ps"
}

# Main script logic
case "$1" in
    download)
        download_packages
        ;;
    install)
        install_packages
        ;;
    *)
        echo "Usage: $0 {download|install}"
        echo ""
        echo "  download - Run on internet-connected machine to download all packages"
        echo "  install  - Run on target machine to install from offline packages"
        exit 1
        ;;
esac



