#!/bin/bash

echo "BrinX AI Port Configuration Script"
echo "--------------------------------"

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Kiểm tra các tường lửa
echo "Checking firewall system..."
FIREWALL=""

# Kiểm tra UFW
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        FIREWALL="ufw"
        echo "UFW firewall detected and active"
    fi
fi

# Kiểm tra FirewallD
if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        FIREWALL="firewalld"
        echo "FirewallD detected and active"
    fi
fi

# Kiểm tra IPtables
if command -v iptables >/dev/null 2>&1; then
    if ! [ "$FIREWALL" ]; then
        FIREWALL="iptables"
        echo "IPtables detected"
        
        # Kiểm tra và cài đặt iptables-persistent
        if ! dpkg -l | grep -q "iptables-persistent"; then
            echo "Installing iptables-persistent..."
            # Tự động trả lời yes cho các câu hỏi cài đặt
            echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
            echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
            apt-get update
            apt-get install -y iptables-persistent
            if [ $? -eq 0 ]; then
                echo "iptables-persistent installed successfully"
            else
                echo "Warning: Failed to install iptables-persistent"
            fi
        else
            echo "iptables-persistent is already installed"
        fi
    fi
fi

# Mở ports dựa trên loại tường lửa
echo "Opening required ports (5011/tcp, 1194/udp, 4000/tcp)..."
case $FIREWALL in
    "ufw")
        echo "Configuring UFW..."
        ufw allow 5011/tcp
        ufw allow 1194/udp
        ufw allow 4000/tcp
        echo "UFW rules added successfully"
        ;;
    "firewalld")
        echo "Configuring FirewallD..."
        firewall-cmd --permanent --add-port=5011/tcp
        firewall-cmd --permanent --add-port=1194/udp
        firewall-cmd --permanent --add-port=4000/tcp
        firewall-cmd --reload
        echo "FirewallD rules added and reloaded successfully"
        ;;
    "iptables")
        echo "Configuring IPtables..."
        # Kiểm tra xem rule đã tồn tại chưa
        if ! iptables -C INPUT -p tcp --dport 5011 -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p tcp --dport 5011 -j ACCEPT
        fi
        if ! iptables -C INPUT -p udp --dport 1194 -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p udp --dport 1194 -j ACCEPT
        fi
        if ! iptables -C INPUT -p tcp --dport 4000 -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p tcp --dport 4000 -j ACCEPT
        fi
        
        # Lưu rules với iptables-persistent
        if [ -d "/etc/iptables" ]; then
            echo "Saving IPtables rules..."
            sh -c 'iptables-save > /etc/iptables/rules.v4'
            echo "IPtables rules saved successfully"
        else
            echo "Error: /etc/iptables directory not found"
            echo "Something went wrong with iptables-persistent installation"
            exit 1
        fi
        ;;
    *)
        echo "Error: No supported firewall detected"
        echo "Please manually configure the following ports:"
        echo "- TCP port 5011"
        echo "- UDP port 1194"
        echo "- TCP port 4000"
        exit 1
        ;;
esac

echo "Verifying port configuration..."
# Kiểm tra port đã được mở chưa
if command -v netstat >/dev/null 2>&1; then
    echo "Current listening ports:"
    netstat -tuln | grep -E ':5011|:1194|:4000'
elif command -v ss >/dev/null 2>&1; then
    echo "Current listening ports:"
    ss -tuln | grep -E ':5011|:1194|:4000'
fi

# Hiển thị rules hiện tại của iptables nếu đang sử dụng iptables
if [ "$FIREWALL" = "iptables" ]; then
    echo -e "\nCurrent IPtables rules:"
    iptables -L INPUT -n -v | grep -E "dpt:5011|dpt:1194|dpt:4000"
fi

echo "Port configuration completed!"
echo "Make sure your cloud provider's security group/firewall also allows these ports."
