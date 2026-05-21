#!/bin/bash
# NeoOptimize RMM - Security Onion + OpenFang Deployment Script
# Execute this on your Host Machine (Linux Mint)

echo "[+] Preparing to deploy Security Onion VM via Libvirt/virt-manager..."

# 1. Download Security Onion ISO (If not exists)
ISO_PATH="/var/lib/libvirt/images/securityonion.iso"
if [ ! -f "$ISO_PATH" ]; then
    echo "[!] Security Onion ISO not found at $ISO_PATH"
    echo "[*] Please download the latest Security Onion ISO from https://securityonion.net/download"
    echo "[*] And place it at /var/lib/libvirt/images/securityonion.iso"
    echo "Once downloaded, run this script again."
    exit 1
fi

# 2. Deploy VM
echo "[+] Deploying Security Onion 2.4.x VM..."
sudo virt-install \
  --name SecurityOnion-OpenFang \
  --memory 16384 \
  --vcpus 8 \
  --disk size=200,bus=virtio,format=qcow2 \
  --os-variant ubuntu22.04 \
  --network network=default,model=virtio \
  --network network=default,model=virtio \
  --cdrom $ISO_PATH \
  --noautoconsole \
  --boot cdrom,hd

echo "[+] VM Deployment Initiated!"
echo "    -> Open virt-manager to complete the Security Onion OS Installation."
echo "    -> Choose 'Standalone' deployment during the SO setup phase."
echo "    -> Once installation is complete, copy the 'OpenFangBridge' folder into the Security Onion VM."
