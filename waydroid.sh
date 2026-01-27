
#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Optional: ensure Android binder/ashmem kernel modules are loaded (best-effort) ---
ensure_android_kernel_modules() {
    # Only attempt on Linux with modprobe available
    if ! command -v modprobe >/dev/null 2>&1; then
        return 0
    fi

    # binder_linux
    if ! grep -qw "binder_linux" /proc/modules 2>/dev/null; then
        echo -e "${YELLOW}Attempting to load Android binder kernel module (binder_linux)...${NC}"
        if ! sudo modprobe binder_linux 2>/dev/null; then
            echo -e "${YELLOW}Warning: could not load binder_linux. Waydroid may still work if binder is built into the kernel.${NC}"
        fi
    fi

    # ashmem_linux (not present on all kernels)
    if ! grep -qw "ashmem_linux" /proc/modules 2>/dev/null; then
        sudo modprobe ashmem_linux 2>/dev/null || true
    fi
}

# --- Mirror-aware downloader config for Waydroid images ---
# Default architecture used on SourceForge paths
WAYDROID_ARCH="x86_64"

# SourceForge mirror codes (key = label, value = mirror code or empty for auto)
# See https://sourceforge.net/p/forge/documentation/Mirrors/
declare -A WAYDROID_MIRRORS=(
    # --- AUTOMATIC ---
    ["[Auto] Best Available (Default)"]=""

    # --- NORTH AMERICA (USA/Canada) ---
    ["[US] Cytranet (Chicago)"]="cytranet"
    ["[US] Eweka (New York)"]="eweka"
    ["[US] Pilot Fiber (New York)"]="pilotfiber"
    ["[US] PhoenixNAP (Arizona)"]="phoenixnap"
    ["[US] New Continuum (Chicago)"]="newcontinuum"
    ["[US] ManagedWay (Detroit)"]="managedway"
    ["[US] NetActuate (Durham, NC)"]="netactuate"
    ["[US] VersaWeb (Las Vegas)"]="versaweb"
    ["[US] DataPacket (Dallas)"]="datapacket"
    ["[CA] iWeb (Montreal)"]="iweb"
    ["[CA] Astute Internet (Vancouver)"]="astuteinternet"

    # --- EUROPE ---
    ["[DE] NetCologne (Germany)"]="netcologne"
    ["[DE] Kumi Systems (Germany)"]="kumisystems"
    ["[UK] Vorboss (London)"]="vorboss"
    ["[UK] Kent University (UK)"]="kent"
    ["[FR] Free.fr (France)"]="freefr"
    ["[NL] DEAC (Amsterdam)"]="deac-ams"
    ["[LV] DEAC (Riga)"]="deac-riga"
    ["[SE] Umeå University (Sweden)"]="umu"
    ["[BG] NetIX (Bulgaria)"]="netix"
    ["[RO] Nav (Romania)"]="nav"

    # --- ASIA / PACIFIC ---
    ["[JP] JAIST (Japan)"]="jaist"
    ["[TW] NCHC (Taiwan)"]="nchc"
    ["[HK] UDomain (Hong Kong)"]="udomain"
    ["[IN] Excell Media (India)"]="excellmedia"
    ["[AU] IX Peering (Australia)"]="ixpeering"

    # --- SOUTH AMERICA ---
    ["[BR] UFSCar (Brazil)"]="ufscar"
    ["[BR] C3SL (Brazil)"]="ufpr"
    ["[BR] Razaoinfo (Brazil)"]="razaoinfo"
    ["[BR] Megalink (Brazil)"]="megalink"
    ["[AR] SiTSA (Argentina)"]="sitsa"

    # --- AFRICA ---
    ["[ZA] TENET (South Africa)"]="tenet"
    ["[KE] Liquid Telecom (Kenya)"]="liquidtelecom"
)

# Selected mirror code for this run (empty = auto/select best at SF side)
WAYDROID_SELECTED_MIRROR_CODE=""

# Ensure axel (multi-connection downloader) is installed
ensure_axel() {
    if command -v axel >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${YELLOW}axel is not installed. Attempting to install it now...${NC}"
    local AXEL_CMD=""
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case "${ID}" in
            fedora|rhel|rocky|centos)
                AXEL_CMD="sudo dnf install -y axel" ;;
            debian|ubuntu|linuxmint|pop)
                AXEL_CMD="sudo apt install -y axel" ;;
            arch|manjaro|endeavouros)
                AXEL_CMD="sudo pacman -S --noconfirm axel" ;;
            opensuse*|suse|sles)
                AXEL_CMD="sudo zypper install -y axel" ;;
            *)
                AXEL_CMD="" ;;
        esac
    fi
    if [ -n "${AXEL_CMD}" ]; then
        echo "Running: ${AXEL_CMD}"
        if ! eval "${AXEL_CMD}"; then
            echo -e "${RED}Failed to install axel automatically. Please install the 'axel' package manually and rerun this script.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Could not determine package manager to install axel. Please install the 'axel' package manually and rerun this script.${NC}"
        exit 1
    fi
}

waydroid_get_latest_filename() {
    local base_url="$1"      # directory listing URL
    local pattern="$2"       # grep pattern for file name
    local label="$3"         # human label for logs

    # Log to stderr so callers can safely capture just the filename via $(...) 
    echo -e "${YELLOW}Resolving latest ${label} image from SourceForge...${NC}" >&2
    echo "  URL: $base_url" >&2

    local filename
    # The plain HTML listing contains bare filenames like:
    #   lineage-20.0-20250809-GAPPS-waydroid_x86_64-system.zip
    #   lineage-20.0-20250803-MAINLINE-waydroid_x86_64-vendor.zip
    filename=$(curl -sL "$base_url" \
        | grep -oE 'lineage-[0-9.]+-[0-9]{8}-[A-Za-z0-9_]+-waydroid_'"$WAYDROID_ARCH"'-[a-z]+\.zip' \
        | grep -E "$pattern" \
        | head -n 1)

    if [[ -z "$filename" ]]; then
        echo -e "${RED}Failed to resolve latest $label image with pattern: $pattern${NC}" >&2
        return 1
    fi

    echo "  -> found: $filename" >&2
    echo "$filename"
}

# Mode flag: when called as `waydroid.sh --setup-only`, skip reset/network and only ensure customization tooling
SETUP_ONLY=0
if [[ "$1" == "--setup-only" ]]; then
    SETUP_ONLY=1
fi

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
                if [ -r /etc/os-release ]; then
                    . /etc/os-release
                fi
                if [[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID}" == "linuxmint" || "${ID}" == "pop" ]]; then
                    echo -e "${RED}Failed to install Waydroid. The package manager may be locked (e.g. unattended-upgrades). Please wait a bit and re-run this script.${NC}"
                else
                    echo -e "${RED}Failed to install Waydroid. Please install it manually and re-run this script.${NC}"
                fi
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

if [[ $SETUP_ONLY -eq 0 ]]; then
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

        # Determine the regular user home (avoid wiping all of /home/* on multi-user systems)
        USER_HOME="$HOME"
        if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
            # Resolve the invoking user's home directory safely
            USER_HOME="$(eval echo "~$SUDO_USER")"
        fi

        if [[ -n "$USER_HOME" && -d "$USER_HOME" ]]; then
            rm -rf "$USER_HOME/.waydroid"
            rm -rf "$USER_HOME/.share/waydroid"
            rm -rf "$USER_HOME/.local/share/waydroid"
        fi

        # Also clean root's Waydroid data if present
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
                    # On openSUSE, Waydroid is split into multiple packages (core + images + magisk helpers)
                    # Reinstall all of them if available in the configured repositories.
                    PKG_REINSTALL_CMD="sudo zypper install -y --force waydroid waydroid-image waydroid-image-system waydroid-image-vendor waydroid-magisk waydroid-magisk-apk"
                    ;;
                *)
                    PKG_REINSTALL_CMD=""
                    ;;
            esac
        fi

        if [ -n "${PKG_REINSTALL_CMD}" ]; then
            echo "Running: ${PKG_REINSTALL_CMD}"
            eval "${PKG_REINSTALL_CMD}" || echo -e "${YELLOW}Warning: failed to reinstall Waydroid packages. Continuing with existing installation (if any).${NC}"
        else
            echo -e "${YELLOW}Could not determine package manager to reinstall Waydroid. Please manage the Waydroid package manually if needed.${NC}"
        fi

        # Ensure Android binder/ashmem kernel modules are loaded (best-effort)
        ensure_android_kernel_modules

        # --- 2. NETWORK FIX PHASE ---
        echo -e "\n${YELLOW}[2/5] Applying Network Fixes (No-Firewall Mode)...${NC}"

        # Enable IP Forwarding
        echo "Enabling IP Forwarding..."
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-waydroid.conf

        # Detect Main Interface
        DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        echo -e "Detected Primary Network Interface: ${GREEN}$DEFAULT_IFACE${NC}"

        # Apply NAT Masquerade
        # First add a temporary iptables rule for this session, then try to persist it via firewalld/ufw when available
        if command -v iptables &> /dev/null; then
            echo "Adding Masquerade rule via iptables..."
            iptables -t nat -A POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE

            # Try to make networking persistent using a firewall manager
            if command -v firewall-cmd &> /dev/null; then
                echo "Detected firewalld; adding waydroid0 to trusted zone (permanent)..."
                firewall-cmd --permanent --zone=trusted --add-interface=waydroid0 || \
                    echo -e "${YELLOW}Warning: failed to add waydroid0 to firewalld trusted zone.${NC}"
                firewall-cmd --reload || \
                    echo -e "${YELLOW}Warning: failed to reload firewalld. You may need to reload it manually.${NC}"
            elif command -v ufw &> /dev/null; then
                echo "Detected ufw; allowing routed traffic from waydroid0 to $DEFAULT_IFACE..."
                ufw route allow in on waydroid0 out on "$DEFAULT_IFACE" || \
                    echo -e "${YELLOW}Warning: failed to add persistent ufw route rule. You may need to configure ufw manually.${NC}"
            fi
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

        # Clean any custom images Waydroid might try to use so we control the flow
        if [ -d "/etc/waydroid-extra/images" ]; then
            echo -e "${YELLOW}Removing stale custom images in /etc/waydroid-extra/images before OTA init...${NC}"
            rm -rf "/etc/waydroid-extra/images"
        fi

        # Use Waydroid's OTA server with axel as the download tool
        ensure_axel

        echo -e "${YELLOW}Initializing Waydroid via OTA with axel (8 connections)...${NC}"
        WAYDROID_DOWNLOAD_TOOL="axel -n 8" \
        waydroid init -s "$TYPE" -f -c https://ota.waydro.id/system -v https://ota.waydro.id/vendor

        if [ $? -ne 0 ]; then
            echo -e "${RED}Waydroid OTA init failed. Please check your internet connection or try again later.${NC}"
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
else
    echo -e "${YELLOW}Setup-only mode detected: skipping Waydroid reset phase.${NC}"
fi

# Offer to install the 'way-fix' CLI helper
echo -e "\n${YELLOW}Do you want to install the 'way-fix' CLI helper (way-fix, way-fix reboot, way-fix config, way-fix uninstall)?${NC}"
read -p "Install way-fix CLI into /usr/local/bin? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing waydroid.sh to /usr/local/bin/waydroid.sh..."
    sudo install -m 0755 "$0" /usr/local/bin/waydroid.sh || {
        echo -e "${YELLOW}Warning: failed to install waydroid.sh. You may need to run it from the repository path or install it manually.${NC}"
    }

    echo "Installing way-fix to /usr/local/bin/way-fix..."
    sudo tee /usr/local/bin/way-fix >/dev/null <<'EOF'
#!/bin/bash

# way-fix: small CLI wrapper for waydroi-fix
#
# Usage:
#   way-fix              Open waydroid_script menu (and set it up if missing)

# Simple color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
#   way-fix reboot       Restart Waydroid container service
#   way-fix config       Open waydroid_script configuration menu (if installed)
#   way-fix uninstall    Remove this way-fix CLI script
#   way-fix help         Show help

usage() {
  cat <<EOF_INNER
way-fix - helper CLI for waydroi-fix

Usage:
  way-fix              Open waydroid_script menu (and set it up if missing)
  way-fix reboot       Restart Waydroid container service
  way-fix config       Open waydroid_script configuration menu (if installed)
  way-fix uninstall    Remove this way-fix CLI script
  way-fix help         Show this help
EOF_INNER
}

start_container_with_progress() {
  # Avoid double-starting the container
  local active_state
  active_state=$(systemctl show -p ActiveState --value waydroid-container 2>/dev/null || echo "unknown")
  if [[ "$active_state" == "active" ]]; then
    echo "Waydroid container is already running. Skipping start."
    sleep 1
    return
  elif [[ "$active_state" == "activating" ]]; then
    echo "Waydroid container is currently starting. Please wait and try again."
    sleep 1
    return
  fi

  echo -n "Starting Waydroid container "
  sudo systemctl start waydroid-container &>/dev/null &
  local pid=$!
  local spinner='|/-\\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\rStarting Waydroid container %s" "${spinner:$i:1}"
    sleep 0.2
  done
  if sudo systemctl is-active --quiet waydroid-container; then
    printf "\rStarting Waydroid container [DONE]\n"
  else
    printf "\rStarting Waydroid container [FAILED]\n"
  fi
  sleep 1
}

restart_container_with_progress() {
  echo -n "Restarting Waydroid container "
  sudo systemctl restart waydroid-container &>/dev/null &
  local pid=$!
  local spinner='|/-\\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\rRestarting Waydroid container %s" "${spinner:$i:1}"
    sleep 0.2
  done
  if sudo systemctl is-active --quiet waydroid-container; then
    printf "\rRestarting Waydroid container [DONE]\n"
  else
    printf "\rRestarting Waydroid container [FAILED]\n"
  fi
  sleep 1
}

stop_container_with_progress() {
  echo -n "Stopping Waydroid container "
  sudo systemctl stop waydroid-container &>/dev/null &
  local pid=$!
  local spinner='|/-\\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\rStopping Waydroid container %s" "${spinner:$i:1}"
    sleep 0.2
  done
  if ! sudo systemctl is-active --quiet waydroid-container; then
    printf "\rStopping Waydroid container [DONE]\n"
  else
    printf "\rStopping Waydroid container [FAILED]\n"
  fi
  sleep 1
}

print_container_status() {
  local active_state sub_state
  active_state=$(systemctl show -p ActiveState --value waydroid-container 2>/dev/null || echo "unknown")
  sub_state=$(systemctl show -p SubState --value waydroid-container 2>/dev/null || echo "unknown")

  case "$active_state" in
    active)
      echo -e "STATUS: ${GREEN}running${NC} ($sub_state)"
      ;;
    activating)
      echo -e "STATUS: ${YELLOW}starting${NC} ($sub_state)"
      ;;
    deactivating)
      echo -e "STATUS: ${YELLOW}stopping${NC} ($sub_state)"
      ;;
    failed)
      echo -e "STATUS: ${RED}failed${NC} ($sub_state) - press R to view logs"
      ;;
    *)
      echo -e "STATUS: ${YELLOW}stopped${NC} ($sub_state)"
      ;;
  esac
}

view_waydroid_logs() {
  clear 2>/dev/null || printf "\033c"
  echo "Waydroid logs (last 100 lines from waydroid-container service):"
  echo "--------------------------------------------------------------"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u waydroid-container --no-pager -n 100 2>&1 || echo "No journal entries for waydroid-container."
  else
    echo "journalctl not available on this system."
  fi
  echo
  echo "Hint: For in-container logs you can also run: waydroid logcat"
  read -p "Press Enter to return to the menu..." _
}

show_menu() {
  WAYDROID_SCRIPT_DIR="$HOME/.local/share/waydroid_script"

  if [ ! -d "$WAYDROID_SCRIPT_DIR" ] || [ ! -f "$WAYDROID_SCRIPT_DIR/main.py" ]; then
    echo "Setting up waydroid_script in $WAYDROID_SCRIPT_DIR..."
    mkdir -p "$(dirname "$WAYDROID_SCRIPT_DIR")" || exit 1
    if ! command -v git >/dev/null 2>&1; then
      echo "Error: git is required to clone waydroid_script." >&2
      exit 1
    fi
    git clone https://github.com/casualsnek/waydroid_script "$WAYDROID_SCRIPT_DIR" || {
      echo "Failed to clone waydroid_script." >&2
      exit 1
    }
  fi

  cd "$WAYDROID_SCRIPT_DIR" || exit 1

  # Ensure lzip is installed (required by waydroid_script)
  if ! command -v lzip >/dev/null 2>&1; then
    echo "Installing 'lzip' dependency (requires sudo)..."
    PKG_CMD=""
    if [ -r /etc/os-release ]; then
      . /etc/os-release
      case "$ID" in
        fedora|rhel|rocky|centos)
          PKG_CMD="sudo dnf install -y lzip";;
        debian|ubuntu|linuxmint|pop)
          PKG_CMD="sudo apt install -y lzip";;
        arch|manjaro|endeavouros)
          PKG_CMD="sudo pacman -S --noconfirm lzip";;
        opensuse*|suse|sles)
          PKG_CMD="sudo zypper install -y lzip";;
        *) PKG_CMD="";;
      esac
    fi
    if [ -n "$PKG_CMD" ]; then
      echo "Running: $PKG_CMD"
      eval "$PKG_CMD" || {
        echo "Failed to install 'lzip'. Please install it manually and re-run way-fix." >&2
        exit 1
      }
    else
      echo "Could not determine package manager to install 'lzip'. Please install it manually and re-run way-fix." >&2
      exit 1
    fi
  fi

  # Ensure Python venv
  if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment for waydroid_script..."
    python3 -m venv venv || {
      echo "Failed to create Python virtual environment." >&2
      exit 1
    }
  fi

  echo "Installing Python dependencies for waydroid_script..."
  venv/bin/pip install -r requirements.txt || {
    echo "Failed to install Python dependencies for waydroid_script." >&2
    exit 1
  }

  echo "Launching waydroid_script configuration menu..."
  sudo venv/bin/python3 main.py
  echo "Configuration session finished."
}

show_menu() {
  while true; do
    clear 2>/dev/null || printf "\033c"  # clear screen for a cleaner menu
    echo "way-fix menu (use keys in [ ], Enter = default, E = exit):"
    echo "  [W] Open waydroid_script configuration menu"
    echo -e "  [Q] ${GREEN}Start${NC} Waydroid container"
    echo -e "  [S] ${YELLOW}Restart${NC} Waydroid container"
    echo -e "  [A] ${RED}Stop${NC} Waydroid container"
    echo "  [R] View Waydroid logs (last 100 lines)"
    echo "  [D] Uninstall way-fix CLI"
    echo "  [E] Exit"
    print_container_status
    printf "Press W/Q/S/A/R/D/E (Enter = W): "
    read -r -n1 choice

    # Handle arrow keys (escape sequences like ESC [ A/B/etc.) so they don't spam the menu
    if [[ "$choice" == $'\e' ]]; then
      # Consume the rest of the escape sequence if present
      read -r -n2 -t 0.05 _ 2>/dev/null || true
      choice="?"  # treat as invalid once
    fi

    # If user just pressed Enter, default to W
    if [[ -z "$choice" ]]; then
      choice="w"
    fi

    echo
    case "$choice" in
      "w"|"W" )
        run_menu
        ;;
      "q"|"Q" )
        start_container_with_progress
        ;;
      "s"|"S" )
        restart_container_with_progress
        ;;
      "a"|"A" )
        stop_container_with_progress
        ;;
      "r"|"R" )
        view_waydroid_logs
        ;;
      "d"|"D" )
        echo "This will remove the way-fix CLI at: $0"
        read -p "Type YES in capital letters to uninstall, anything else to cancel: " confirm
        if [[ "$confirm" == "YES" ]]; then
          TARGET="$0"
          if [ ! -w "$(dirname "$TARGET")" ]; then
            echo "Attempting to remove with sudo..."
            sudo rm -- "$TARGET" || {
              echo "Failed to remove $TARGET" >&2
              exit 1
            }
          else
            rm -- "$TARGET" || {
              echo "Failed to remove $TARGET" >&2
              exit 1
            }
          fi
          echo "way-fix CLI has been uninstalled."
          break
        else
          echo "Uninstall cancelled."
        fi
        ;;
      "e"|"E" )
        break
        ;;
      * )
        echo "Invalid choice, please press W, S, D or E."
        ;;
    esac
  done
}

case "$1" in
  "" )
    show_menu
    ;;
  start )
    start_container_with_progress
    ;;
  reboot )
    restart_container_with_progress
    ;;
  shutdown )
    stop_container_with_progress
    ;;
  config )
    WAYDROID_SCRIPT_DIR="$HOME/.local/share/waydroid_script"
    if [ ! -d "$WAYDROID_SCRIPT_DIR" ] || [ ! -f "$WAYDROID_SCRIPT_DIR/main.py" ]; then
      echo "waydroid_script not found at $WAYDROID_SCRIPT_DIR. Run 'way-fix' first to install and set it up." >&2
      exit 1
    fi
    cd "$WAYDROID_SCRIPT_DIR" || exit 1
    if [ ! -x "venv/bin/python3" ]; then
      echo "Python venv for waydroid_script not found. Run 'way-fix' to set it up." >&2
      exit 1
    fi
    echo "Launching waydroid_script configuration menu..."
    sudo venv/bin/python3 main.py
    echo "Configuration session finished."
    ;;
  uninstall )
    echo "This will remove the way-fix CLI at: $0"
    read -p "Are you sure you want to uninstall way-fix? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      TARGET="$0"
      if [ ! -w "$(dirname "$TARGET")" ]; then
        echo "Attempting to remove with sudo..."
        sudo rm -- "$TARGET" || {
          echo "Failed to remove $TARGET" >&2
          exit 1
        }
      else
        rm -- "$TARGET" || {
          echo "Failed to remove $TARGET" >&2
          exit 1
        }
      fi
      echo "way-fix CLI has been uninstalled."
    else
      echo "Uninstall cancelled."
    fi
    ;;
  help|-h|--help )
    usage
    ;;
  * )
    echo "Unknown subcommand: $1" >&2
    usage
    exit 1
    ;;
esac
EOF
    sudo chmod 0755 /usr/local/bin/way-fix || {
        echo -e "${YELLOW}Warning: failed to chmod /usr/local/bin/way-fix. You may need to fix permissions manually.${NC}"
    }

    # Let the user know where way-fix was installed and warn if /usr/local/bin is not in PATH
    echo "way-fix CLI installed to /usr/local/bin/way-fix."
    if ! echo ":$PATH:" | grep -q ':/usr/local/bin:'; then
        echo -e "${YELLOW}Note: /usr/local/bin is not in your PATH. You may need to add it or call 'sudo /usr/local/bin/way-fix'.${NC}"
    fi
else
    echo "Skipping installation of way-fix CLI."
fi

# --- 6. OPTIONAL CUSTOMIZATION VIA waydroid_script ---
echo -e "\n${YELLOW}[Optional] Setting up waydroid_script customization helper...${NC}"

# Use the invoking user's home directory for waydroid_script (not root's)
USER_HOME_FOR_SCRIPT="$HOME"
if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
    USER_HOME_FOR_SCRIPT="$(eval echo "~$SUDO_USER")"
fi
WAYDROID_SCRIPT_DIR="${USER_HOME_FOR_SCRIPT}/.local/share/waydroid_script"

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

    # Ensure git is installed for cloning
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${YELLOW}git is not installed. Attempting to install it now...${NC}"
        GIT_CMD=""
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            case "${ID}" in
                fedora|rhel|rocky|centos)
                    GIT_CMD="sudo dnf install -y git" ;;
                debian|ubuntu|linuxmint|pop)
                    GIT_CMD="sudo apt install -y git" ;;
                arch|manjaro|endeavouros)
                    GIT_CMD="sudo pacman -S --noconfirm git" ;;
                opensuse*|suse|sles)
                    GIT_CMD="sudo zypper install -y git" ;;
                *)
                    GIT_CMD="" ;;
            esac
        fi
        if [ -n "${GIT_CMD}" ]; then
            echo "Running: ${GIT_CMD}"
            eval "${GIT_CMD}"
            if ! command -v git >/dev/null 2>&1; then
                echo -e "${RED}Failed to install git automatically. Please install it manually and rerun this script.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Could not determine package manager to install git. Please install it manually and rerun this script.${NC}"
            exit 1
        fi
    fi

    git clone https://github.com/casualsnek/waydroid_script "${WAYDROID_SCRIPT_DIR}" || {
        echo -e "${RED}Failed to clone waydroid_script. Aborting customization step.${NC}"
        exit 1
    }
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
        eval "${PKG_CMD}"
        if [ $? -ne 0 ]; then
            if [ -r /etc/os-release ]; then
                . /etc/os-release
            fi
            if [[ "${ID}" == "debian" || "${ID}" == "ubuntu" || "${ID}" == "linuxmint" || "${ID}" == "pop" ]]; then
                echo -e "${RED}Failed to install 'lzip'. The package manager may be locked (e.g. unattended-upgrades). Please wait and rerun this script.${NC}"
            else
                echo -e "${RED}Failed to install 'lzip'. Please install it manually and rerun this script.${NC}"
            fi
            exit 1
        fi
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

# Ensure the waydroid_script directory is owned by the invoking user when running under sudo
if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" && -d "${WAYDROID_SCRIPT_DIR}" ]]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "${WAYDROID_SCRIPT_DIR}" || echo -e "${YELLOW}Warning: failed to adjust ownership for ${WAYDROID_SCRIPT_DIR}.${NC}"
fi

echo -e "\n${GREEN}Launching waydroid_script customization tool...${NC}"
sudo venv/bin/python3 main.py

echo -e "\n${GREEN}All done.${NC}"
read -p "Press Enter to exit..." _
