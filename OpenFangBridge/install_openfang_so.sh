#!/bin/bash
# NeoOptimize RMM - OpenFang AI Engine Installer for Security Onion
# Execute this INSIDE the Security Onion VM

echo "[+] Preparing OpenFang AI Environment on Security Onion..."

# 1. Install prerequisites
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv curl git

# 2. Setup OpenFang Environment
echo "[+] Setting up OpenFang Virtual Environment..."
mkdir -p /opt/openfang
cd /opt/openfang
python3 -m venv venv
source venv/bin/activate

# 3. Install OpenFang Core (Simulated via typical AI agent frameworks, e.g., Langchain/OpenAI/Requests)
echo "[+] Installing LLM dependencies..."
pip install requests langchain openai anthropic

# 4. Copy Configurations
echo "[+] Linking NeoOptimize Bridge..."
mkdir -p /opt/openfang/config
mkdir -p /opt/openfang/skills

# Note: User must copy the OpenFangBridge folder from the host to /tmp/OpenFangBridge in SO
if [ -d "/tmp/OpenFangBridge" ]; then
    cp /tmp/OpenFangBridge/agents.toml /opt/openfang/config/
    cp -r /tmp/OpenFangBridge/skills/* /opt/openfang/skills/
    echo "    -> Configs applied successfully."
else
    echo "    [!] /tmp/OpenFangBridge not found. Please SCP the folder from your host into the VM."
fi

# 5. Set Environment Variables
echo "export NEO_MONITOR_URL='https://<HOST_IP>'" >> ~/.bashrc
echo "export OPENFANG_API_KEY='your-secure-openfang-key'" >> ~/.bashrc
echo "export ANTHROPIC_API_KEY='your-claude-api-key'" >> ~/.bashrc

echo "[+] OpenFang AI Engine Installed!"
echo "[*] To start the Guardian Hand, run: cd /opt/openfang && source venv/bin/activate && python3 -m openfang --agent guardian"
