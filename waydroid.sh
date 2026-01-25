
#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WARNING: This will delete ALL Waydroid data (apps, settings, images).${NC}"
read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# --- 1. CLEANUP PHASE ---
echo -e "\n${YELLOW}[1/5] Cleaning up old installation...${NC}"

# Stop services
echo "Stopping Waydroid services..."
systemctl stop waydroid-container 2>/dev/null
waydroid session stop 2>/dev/null

# Unmount potential stuck mounts
echo "Unmounting stuck directories..."
umount /var/lib/waydroid/rootfs/vendor 2>/dev/null
umount /var/lib/waydroid/rootfs 2>/dev/null

# Remove Data
echo "Removing Waydroid folders..."
rm -rf /var/lib/waydroid
rm -rf /home/*/.waydroid
rm -rf /home/*/.share/waydroid
rm -rf /home/*/.local/share/waydroid
rm -rf /root/.waydroid

# Reinstall Package (Optional but good for sanity)
echo "Reinstalling Waydroid package..."
dnf reinstall waydroid -y

# --- 2. NETWORK FIX PHASE ---
echo -e "\n${YELLOW}[2/5] Applying Network Fixes (No-Firewall Mode)...${NC}"

# Enable IP Forwarding
echo "Enabling IP Forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-waydroid.conf

# Detect Main Interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo -e "Detected Primary Network Interface: ${GREEN}$DEFAULT_IFACE${NC}"

# Apply NAT Masquerade (Since you have no firewalld)
# We check if nftables or iptables is present
if command -v iptables &> /dev/null; then
    echo "Adding Masquerade rule via iptables..."
    iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
else
    echo -e "${RED}Warning: iptables not found. Internet might not work immediately.${NC}"
fi

# Ensure DNSMasq is installed (Fedora sometimes lacks it for Waydroid)
if ! rpm -q dnsmasq &> /dev/null; then
    echo "Installing dnsmasq dependency..."
    dnf install dnsmasq -y
fi

# --- 3. INITIALIZATION PHASE ---
echo -e "\n${YELLOW}[3/5] Downloading Android Images...${NC}"
echo "Select Android Type:"
echo "1) GAPPS (With Google Play Store) - Recommended"
echo "2) VANILLA (No Google Apps)"
read -p "Enter 1 or 2: " choice

TYPE="GAPPS"
if [ "$choice" == "2" ]; then
    TYPE="VANILLA"
fi

echo -e "Downloading ${GREEN}$TYPE${NC} images. Please wait, this may take a while..."

# We manually specify URLs to avoid the "OTA URL" error you saw earlier
waydroid init -s $TYPE -f -c https://ota.waydro.id/system -v https://ota.waydro.id/vendor

if [ $? -ne 0 ]; then
    echo -e "${RED}Download failed! Please check your internet connection.${NC}"
    exit 1
fi

# --- 4. STARTUP PHASE ---
echo -e "\n${YELLOW}[4/5] Starting Services...${NC}"
systemctl enable --now waydroid-container

# Wait for container to settle
sleep 5

# --- 5. FINAL CHECK ---
echo -e "\n${GREEN}=== DONE ===${NC}"
echo "Waydroid has been reset and reinstalled."
echo "You can now launch it from your menu or by running:"
echo -e "${YELLOW}waydroid session start${NC}"
