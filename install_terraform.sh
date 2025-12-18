#!/bin/bash
# Install Terraform on Ubuntu via binary download
# Usage: ./install_terraform.sh [version]
# Example: ./install_terraform.sh 1.9.8

set -euo pipefail

# Configuration
TERRAFORM_VERSION="${1:-1.14.3}"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)
ARCH=$(uname -m)

# Map architecture to Terraform naming
case "${ARCH}" in
    x86_64)
        TF_ARCH="amd64"
        ;;
    aarch64|arm64)
        TF_ARCH="arm64"
        ;;
    armv7l)
        TF_ARCH="arm"
        ;;
    i386|i686)
        TF_ARCH="386"
        ;;
    *)
        echo "ERROR: Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

# Cleanup on exit
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "=== Terraform Binary Installer ==="
echo "Version: ${TERRAFORM_VERSION}"
echo "Architecture: ${TF_ARCH}"
echo "Install directory: ${INSTALL_DIR}"
echo ""

# Check for required tools
for cmd in curl unzip; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo "ERROR: Required command '${cmd}' not found"
        echo "Install with: sudo apt-get update && sudo apt-get install -y ${cmd}"
        exit 1
    fi
done

# Download Terraform
DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TF_ARCH}.zip"
CHECKSUM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"

echo "Downloading Terraform from ${DOWNLOAD_URL}..."
cd "${TMP_DIR}"
curl -fsSL -o terraform.zip "${DOWNLOAD_URL}"

# Download and verify checksum
echo "Verifying checksum..."
curl -fsSL -o SHA256SUMS "${CHECKSUM_URL}"
EXPECTED_CHECKSUM=$(grep "terraform_${TERRAFORM_VERSION}_linux_${TF_ARCH}.zip" SHA256SUMS | awk '{print $1}')
ACTUAL_CHECKSUM=$(sha256sum terraform.zip | awk '{print $1}')

if [ "${EXPECTED_CHECKSUM}" != "${ACTUAL_CHECKSUM}" ]; then
    echo "ERROR: Checksum verification failed!"
    echo "Expected: ${EXPECTED_CHECKSUM}"
    echo "Actual: ${ACTUAL_CHECKSUM}"
    exit 1
fi
echo "Checksum verified successfully"

# Extract binary
echo "Extracting Terraform binary..."
unzip -q terraform.zip

# Install binary
echo "Installing to ${INSTALL_DIR}..."
if [ -w "${INSTALL_DIR}" ]; then
    mv terraform "${INSTALL_DIR}/terraform"
    chmod +x "${INSTALL_DIR}/terraform"
else
    echo "Elevated privileges required for ${INSTALL_DIR}"
    sudo mv terraform "${INSTALL_DIR}/terraform"
    sudo chmod +x "${INSTALL_DIR}/terraform"
fi

# Verify installation
echo ""
echo "=== Installation Complete ==="
"${INSTALL_DIR}/terraform" version
echo ""
echo "Terraform installed at: ${INSTALL_DIR}/terraform"
