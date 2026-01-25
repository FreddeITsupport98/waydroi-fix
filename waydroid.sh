
#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 0. Ensure Waydroid is installed ---
if ! command -v waydroid >/dev/null 2>&1; then
    echo -e "${YELLOW}Waydroid does not appear to be installed on this system.${NC}"
    read -p "Install Waydroid package now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        PKG_INSTALL_CMD=""
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            case "${ID}" in
                fedora|rhel|rocky|centos)
                    PKG_INSTALL_CMD="sudo dnf install -y waydroid"
                    ;;
                debian|ubuntu|linuxmint|pop)
                    PKG_INSTALL_CMD="sudo apt install -y waydroid"
                    ;;
                arch|manjaro|endeavouros)
                    PKG_INSTALL_CMD="sudo pacman -S --noconfirm waydroid"
                    ;;
                opensuse*|suse|sles)
                    PKG_INSTALL_CMD="sudo zypper install -y waydroid"
                    ;;
                *)
                    PKG_INSTALL_CMD=""
                    ;;
            esac
        fi

        if [ -n "${PKG_INSTALL_CMD}" ]; then
            echo "Running: ${PKG_INSTALL_CMD}"
            if ! eval "${PKG_INSTALL_CMD}"; then
                echo -e "${RED}Failed to install Waydroid. Please install it manually and re-run this script.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Could not determine package manager to install Waydroid. Please install it manually and re-run this script.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Waydroid is required for this script to work. Aborting.${NC}"
        exit 1
    fi
fi

# Ask whether to perform a full reset first
echo -e "${YELLOW}Do you want to RESET Waydroid? This can delete ALL Waydroid data (apps, settings, images).${NC}"
read -p "Reset Waydroid? (y/n): " -n 1 -r
echo

DO_RESET=0
if [[ $REPLY =~ ^[Yy]$ ]]; then
    DO_RESET=1
fi

if [[ $DO_RESET -eq 1 ]]; then
    echo -e "${YELLOW}WARNING: This will delete ALL Waydroid data (apps, settings, images).${NC}"
    read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting reset. Proceeding to customization only."
    else
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

        PKG_REINSTALL_CMD=""
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            case "${ID}" in
                fedora|rhel|rocky|centos)
                    PKG_REINSTALL_CMD="sudo dnf reinstall -y waydroid"
                    ;;
                debian|ubuntu|linuxmint|pop)
                    PKG_REINSTALL_CMD="sudo apt install --reinstall -y waydroid"
                    ;;
                arch|manjaro|endeavouros)
                    PKG_REINSTALL_CMD="sudo pacman -S --noconfirm waydroid"
                    ;;
                opensuse*|suse|sles)
                    PKG_REINSTALL_CMD="sudo zypper install -y --force waydroid"
                    ;;
                *)
                    PKG_REINSTALL_CMD=""
                    ;;
            esac
        fi

        if [ -n "${PKG_REINSTALL_CMD}" ]; then
            echo "Running: ${PKG_REINSTALL_CMD}"
            eval "${PKG_REINSTALL_CMD}" || echo -e "${YELLOW}Warning: failed to reinstall Waydroid package. Continuing with existing installation.${NC}"
        else
            echo -e "${YELLOW}Could not determine package manager to reinstall Waydroid. Please manage the Waydroid package manually if needed.${NC}"
        fi

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

        # Ensure dnsmasq is installed (some distros lack it by default for Waydroid)
        if ! command -v dnsmasq >/dev/null 2>&1; then
            echo "Installing dnsmasq dependency..."

            DNSMASQ_CMD=""
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                case "${ID}" in
                    fedora|rhel|rocky|centos)
                        DNSMASQ_CMD="sudo dnf install -y dnsmasq"
                        ;;
                    debian|ubuntu|linuxmint|pop)
                        DNSMASQ_CMD="sudo apt install -y dnsmasq"
                        ;;
                    arch|manjaro|endeavouros)
                        DNSMASQ_CMD="sudo pacman -S --noconfirm dnsmasq"
                        ;;
                    opensuse*|suse|sles)
                        DNSMASQ_CMD="sudo zypper install -y dnsmasq"
                        ;;
                    *)
                        DNSMASQ_CMD=""
                        ;;
                esac
            fi

            if [ -n "${DNSMASQ_CMD}" ]; then
                echo "Running: ${DNSMASQ_CMD}"
                eval "${DNSMASQ_CMD}" || echo -e "${YELLOW}Warning: failed to install dnsmasq. Waydroid networking may not work correctly.${NC}"
            else
                echo -e "${YELLOW}Could not determine package manager to install dnsmasq. Please install it manually if Waydroid networking fails.${NC}"
            fi
        fi

        # --- 3. INITIALIZATION PHASE ---
        echo -e "\n${YELLOW}[3/5] Downloading Android Images...${NC}"
        echo "Do you want to use a GAPPS base image (with Google Play Store)?"
        read -p "Install GAPPS base image? (y/n): " -n 1 -r
        echo

        TYPE="VANILLA"
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            TYPE="GAPPS"
        fi

        echo -e "Selected base image: ${GREEN}$TYPE${NC}"
        echo -e "Downloading ${GREEN}$TYPE${NC} images. Please wait, this may take a while..."\

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
    fi
else
    echo -e "${YELLOW}Skipping Waydroid reset. Proceeding directly to customization...${NC}"
fi

# Offer to install the 'way-fix' CLI helper
echo -e "\n${YELLOW}Do you want to install the 'way-fix' CLI helper (way-fix, way-fix reboot, way-fix uninstall)?${NC}"
read -p "Install way-fix CLI into /usr/local/bin? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    SRC_WAY_FIX="${SCRIPT_DIR}/way-fix"
    if [ -f "${SRC_WAY_FIX}" ]; then
        echo "Installing way-fix to /usr/local/bin/way-fix..."
        sudo install -m 0755 "${SRC_WAY_FIX}" /usr/local/bin/way-fix || {
            echo -e "${YELLOW}Warning: failed to install way-fix CLI. You can copy it manually.${NC}"
        }
    else
        echo -e "${YELLOW}way-fix script not found next to waydroid.sh; skipping CLI install.${NC}"
    fi
else
    echo "Skipping installation of way-fix CLI."
fi

# --- 6. OPTIONAL CUSTOMIZATION VIA waydroid_script ---
echo -e "\n${YELLOW}[Optional] Setting up waydroid_script customization helper...${NC}"

WAYDROID_SCRIPT_DIR="${HOME}/.local/share/waydroid_script"

if [ -d "${WAYDROID_SCRIPT_DIR}/.git" ] && [ -f "${WAYDROID_SCRIPT_DIR}/main.py" ]; then
    echo "Using existing waydroid_script in ${WAYDROID_SCRIPT_DIR}"
    cd "${WAYDROID_SCRIPT_DIR}" || exit 1
    if command -v git >/dev/null 2>&1; then
        echo "Updating waydroid_script (git pull)..."
        git pull --ff-only || echo -e "${YELLOW}Warning: could not update waydroid_script, continuing with existing copy.${NC}"
    fi
else
    echo "Cloning waydroid_script into ${WAYDROID_SCRIPT_DIR}..."
    mkdir -p "$(dirname "${WAYDROID_SCRIPT_DIR}")"
    if command -v git >/dev/null 2>&1; then
        git clone https://github.com/casualsnek/waydroid_script "${WAYDROID_SCRIPT_DIR}" || {
            echo -e "${RED}Failed to clone waydroid_script. Aborting customization step.${NC}"
            exit 1
        }
    else
        echo -e "${RED}git is not installed. Cannot download waydroid_script. Aborting customization step.${NC}"
        exit 1
    fi
    cd "${WAYDROID_SCRIPT_DIR}" || exit 1
fi

# Ensure lzip is installed (required by waydroid_script)
if ! command -v lzip >/dev/null 2>&1; then
    echo -e "\n${YELLOW}Installing 'lzip' dependency...${NC}"
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case "${ID}" in
            fedora|rhel|rocky|centos)
                PKG_CMD="sudo dnf install -y lzip"
                ;;
            debian|ubuntu|linuxmint|pop)
                PKG_CMD="sudo apt install -y lzip"
                ;;
            arch|manjaro|endeavouros)
                PKG_CMD="sudo pacman -S --noconfirm lzip"
                ;;
            opensuse*|suse|sles)
                PKG_CMD="sudo zypper install -y lzip"
                ;;
            *)
                PKG_CMD=""
                ;;
        esac
    fi

    if [ -n "${PKG_CMD}" ]; then
        echo "Running: ${PKG_CMD}"
        eval "${PKG_CMD}" || {
            echo -e "${RED}Failed to install 'lzip'. Please install it manually and rerun this script.${NC}"
            exit 1
        }
    else
        echo -e "${RED}Could not determine package manager to install 'lzip'. Please install it manually and rerun this script.${NC}"
        exit 1
    fi
else
    echo "'lzip' is already installed."
fi

# Set up Python virtual environment for waydroid_script
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment for waydroid_script..."
    python3 -m venv venv || {
        echo -e "${RED}Failed to create Python virtual environment.${NC}"
        exit 1
    }
fi

echo "Installing Python dependencies for waydroid_script..."
venv/bin/pip install -r requirements.txt || {
    echo -e "${RED}Failed to install Python dependencies for waydroid_script.${NC}"
    exit 1
}

echo -e "\n${GREEN}Launching waydroid_script customization tool...${NC}"
sudo venv/bin/python3 main.py

echo -e "\n${GREEN}All done.${NC}"
read -p "Press Enter to exit..." _
