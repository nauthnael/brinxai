#!/bin/bash

echo "Setting up BrinX AI Worker Node..."

# Kiểm tra các tường lửa
echo "Checking firewall system..."
FIREWALL=""

# Kiểm tra UFW
if command -v ufw >/dev/null 2>&1; then
    if sudo ufw status | grep -q "Status: active"; then
        FIREWALL="ufw"
        echo "UFW firewall detected and active"
    fi
fi

# Kiểm tra FirewallD
if command -v firewall-cmd >/dev/null 2>&1; then
    if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
        FIREWALL="firewalld"
        echo "FirewallD detected and active"
    fi
fi

# Kiểm tra IPtables
if command -v iptables >/dev/null 2>&1; then
    if ! [ "$FIREWALL" ]; then
        FIREWALL="iptables"
        echo "IPtables detected"
    fi
fi

# Mở ports dựa trên loại tường lửa
echo "Opening required ports..."
case $FIREWALL in
    "ufw")
        sudo ufw allow 5011/tcp
        sudo ufw allow 1194/udp
        ;;
    "firewalld")
        sudo firewall-cmd --permanent --add-port=5011/tcp
        sudo firewall-cmd --permanent --add-port=1194/udp
        sudo firewall-cmd --reload
        ;;
    "iptables")
        sudo iptables -A INPUT -p tcp --dport 5011 -j ACCEPT
        sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
        sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
        ;;
    *)
        echo "No supported firewall detected. Please manually configure ports 5011/tcp and 1194/udp"
        ;;
esac

# Kiểm tra và xử lý Docker containers

# Kiểm tra Worker Node container
echo "Checking BrinX AI Worker container..."
if docker ps -a | grep -q "admier/brinxai_nodes-worker:latest"; then
    echo "Existing BrinX AI Worker container found..."
    if docker ps | grep -q "admier/brinxai_nodes-worker:latest"; then
        echo "Worker container is running. Stopping it for update..."
        docker stop $(docker ps -q --filter ancestor=admier/brinxai_nodes-worker:latest)
    fi
    docker rm $(docker ps -a -q --filter ancestor=admier/brinxai_nodes-worker:latest)
    echo "Old Worker container removed"
fi

# Kiểm tra Relay Node container
echo "Checking BrinX AI Relay container..."
if docker ps -a | grep -q "admier/brinxai_nodes-relay:latest"; then
    echo "Existing BrinX AI Relay container found..."
    if docker ps | grep -q "admier/brinxai_nodes-relay:latest"; then
        echo "Relay container is running. Stopping it for update..."
        docker stop $(docker ps -q --filter ancestor=admier/brinxai_nodes-relay:latest)
    fi
    docker rm $(docker ps -a -q --filter ancestor=admier/brinxai_nodes-relay:latest)
    echo "Old Relay container removed"
fi

# Kiểm tra và xử lý rembg container
echo "Checking rembg container..."
if docker ps -a | grep -q "admier/brinxai_nodes-rembg:latest"; then
    echo "Existing rembg container found..."
    if docker ps | grep -q "admier/brinxai_nodes-rembg:latest"; then
        echo "Rembg container is running. Stopping it for update..."
        docker stop rembg
    fi
    docker rm rembg
    echo "Old rembg container removed"
fi

# Kiểm tra và xử lý upscaler container
echo "Checking upscaler container..."
if docker ps -a | grep -q "admier/brinxai_nodes-upscaler:latest"; then
    echo "Existing upscaler container found..."
    if docker ps | grep -q "admier/brinxai_nodes-upscaler:latest"; then
        echo "Upscaler container is running. Stopping it for update..."
        docker stop upscaler
    fi
    docker rm upscaler
    echo "Old upscaler container removed"
fi

# Pull latest images
echo "Pulling latest BrinX AI images..."
docker pull admier/brinxai_nodes-worker:latest
docker pull admier/brinxai_nodes-relay:latest
docker pull admier/brinxai_nodes-rembg:latest
docker pull admier/brinxai_nodes-upscaler:latest

echo "Setting up Worker Node..."
if [ -d "BrinxAI-Worker-Nodes" ]; then
    echo "Existing repository found. Removing..."
    rm -rf BrinxAI-Worker-Nodes
fi

git clone https://github.com/admier1/BrinxAI-Worker-Nodes
cd BrinxAI-Worker-Nodes || exit
chmod +x install_ubuntu.sh
./install_ubuntu.sh
cd ..

echo "Setting up BrinX AI Relay Node..."

echo "Checking CPU architecture..."
CPU_ARCH=$(uname -m)
if [[ "$CPU_ARCH" == "x86_64" ]]; then
    echo "Architecture: AMD64"
    RELAY_COMMAND="sudo docker run -d --name brinxai_relay --cap-add=NET_ADMIN admier/brinxai_nodes-relay:latest"
elif [[ "$CPU_ARCH" == "aarch64" || "$CPU_ARCH" == "arm64" ]]; then
    echo "Architecture: ARM64"
    RELAY_COMMAND="sudo docker run -d --name brinxai_relay --cap-add=NET_ADMIN admier/brinxai_nodes-relay:latest"
else
    echo "Unsupported architecture: $CPU_ARCH"
    exit 1
fi

# Tạo docker network nếu chưa tồn tại
echo "Checking brinxai-network..."
if ! docker network ls | grep -q "brinxai-network"; then
    echo "Creating brinxai-network..."
    docker network create brinxai-network
fi

echo "Running Relay Node..."
eval $RELAY_COMMAND

echo "Running rembg and upscaler containers..."
docker run -d --name rembg --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:7000:7000 admier/brinxai_nodes-rembg:latest
docker run -d --name upscaler --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:3000:3000 admier/brinxai_nodes-upscaler:latest

echo "Setup completed successfully!"
echo "Follow the instructions to register your Worker and Relay Nodes at https://workers.brinxai.com/"
