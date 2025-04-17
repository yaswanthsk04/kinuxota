#!/bin/bash
# KinuxOTA Client Installation Script
# This script installs the KinuxOTA client on the system by:
# 1. Detecting the OS and architecture
# 2. Downloading the appropriate binaries from GitHub
# 3. Creating a systemd service file
# 4. Starting the service

# Exit on any error
set -e

# Print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Print error and exit
error() {
    log "ERROR: $1"
    exit 1
}

# Print colored output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_colored() {
    echo -e "${2}$1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root. Please use sudo."
    fi
}

# Detect OS and version
detect_os() {
    log "Detecting operating system..."
    
    # Check if /etc/os-release exists
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        log "Detected OS: $OS $VERSION"
        
        # Currently only supporting Ubuntu
        if [ "$OS" != "ubuntu" ]; then
            log "Auto-detected OS: $OS, but only Ubuntu is currently supported."
            
            # Ask user if they want to continue anyway
            read -p "Are you using Ubuntu? (y/n): " UBUNTU_CONFIRM
            if [[ "$UBUNTU_CONFIRM" =~ ^[Yy]$ ]]; then
                log "User confirmed Ubuntu. Continuing installation..."
                OS="ubuntu"
                # Try to get version from lsb_release if available
                if command -v lsb_release &> /dev/null; then
                    VERSION=$(lsb_release -rs)
                else
                    VERSION="20.04" # Default to a reasonable version
                fi
            else
                error "Installation aborted. Only Ubuntu is currently supported."
            fi
        fi
    else
        log "Could not auto-detect operating system. /etc/os-release not found."
        
        # Ask user if they want to continue with Ubuntu
        read -p "Are you using Ubuntu? (y/n): " UBUNTU_CONFIRM
        if [[ "$UBUNTU_CONFIRM" =~ ^[Yy]$ ]]; then
            log "User confirmed Ubuntu. Continuing installation..."
            OS="ubuntu"
            # Try to get version from lsb_release if available
            if command -v lsb_release &> /dev/null; then
                VERSION=$(lsb_release -rs)
            else
                VERSION="20.04" # Default to a reasonable version
            fi
        else
            error "Installation aborted. Only Ubuntu is currently supported."
        fi
    fi
    
    # Return OS and version
    echo "$OS:$VERSION"
}

# Detect architecture
detect_arch() {
    log "Detecting system architecture..."
    
    # Get architecture
    ARCH=$(uname -m)
    log "Detected architecture: $ARCH"
    
    # Map architecture to standardized names
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armhf"
            ;;
        *)
            log "Auto-detection failed or unsupported architecture: $ARCH"
            
            # Ask user to confirm architecture
            echo "Please select your architecture:"
            echo "1) amd64 (64-bit x86)"
            echo "2) arm64 (64-bit ARM)"
            echo "3) armhf (32-bit ARM)"
            read -p "Enter choice [1-3]: " ARCH_CHOICE
            
            case $ARCH_CHOICE in
                1)
                    ARCH="amd64"
                    ;;
                2)
                    ARCH="arm64"
                    ;;
                3)
                    ARCH="armhf"
                    ;;
                *)
                    error "Invalid choice. Installation aborted."
                    ;;
            esac
            ;;
    esac
    
    # Currently only supporting amd64
    if [ "$ARCH" != "amd64" ]; then
        log "Detected architecture: $ARCH, but only amd64 is currently supported."
        
        # Ask user if they want to continue with amd64
        read -p "Are you using amd64 architecture? (y/n): " AMD64_CONFIRM
        if [[ "$AMD64_CONFIRM" =~ ^[Yy]$ ]]; then
            log "User confirmed amd64. Continuing installation..."
            ARCH="amd64"
        else
            error "Installation aborted. Only amd64 is currently supported."
        fi
    fi
    
    log "Using architecture: $ARCH"
    echo $ARCH
}

# Download and install binaries directly
download_and_install_binaries() {
    local OS=$1
    local VERSION=$2
    local ARCH=$3
    
    log "Downloading and installing KinuxOTA binaries..."
    
    # Define installation directory
    local INSTALL_DIR="/usr/local/bin"
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Download kinuxota_client directly to installation directory
    log "Downloading kinuxota_client..."
    curl -L -o "$INSTALL_DIR/kinuxota_client" "https://github.com/yaswanthsk04/kinuxota/raw/main/release/1.0.0/ubuntu/amd64/kinuxota_client"
    if [ ! -f "$INSTALL_DIR/kinuxota_client" ]; then
        error "Failed to download kinuxota_client"
    fi
    
    # Make the binary executable
    chmod 755 "$INSTALL_DIR/kinuxota_client"
    log "Installed kinuxota_client"
    
    # Download kinuxctl directly to installation directory
    log "Downloading kinuxctl..."
    curl -L -o "$INSTALL_DIR/kinuxctl" "https://github.com/yaswanthsk04/kinuxota/raw/main/release/1.0.0/ubuntu/amd64/kinuxctl"
    if [ -f "$INSTALL_DIR/kinuxctl" ]; then
        chmod 755 "$INSTALL_DIR/kinuxctl"
        log "Installed kinuxctl"
    else
        log "Warning: Failed to download kinuxctl, will continue without it"
    fi
    
    # Download update-executor.sh directly to installation directory
    log "Downloading update-executor.sh..."
    curl -L -o "$INSTALL_DIR/update-executor.sh" "https://github.com/yaswanthsk04/kinuxota/raw/main/kinuxota/update-executor.sh"
    if [ -f "$INSTALL_DIR/update-executor.sh" ]; then
        chmod 755 "$INSTALL_DIR/update-executor.sh"
        log "Installed update-executor.sh"
    else
        # Try to use local copy if available
        if [ -f "./kinuxota/update-executor.sh" ]; then
            cp "./kinuxota/update-executor.sh" "$INSTALL_DIR/"
            chmod 755 "$INSTALL_DIR/update-executor.sh"
            log "Copied update-executor.sh from source directory"
        else
            log "Warning: update-executor.sh not found, updates may not work correctly"
        fi
    fi
}

# Create configuration directories
create_config_dirs() {
    log "Creating configuration directories..."
    
    # System-wide config directory
    mkdir -p /etc/kinuxota
    
    # Log directory
    mkdir -p /var/log/kinuxota
    
    # Data directory
    mkdir -p /var/lib/kinuxota
    
    # Runtime directory
    mkdir -p /run/kinuxota
    
    # Set permissions
    chmod 755 /etc/kinuxota
    chmod 755 /var/log/kinuxota
    chmod 755 /var/lib/kinuxota
    chmod 755 /run/kinuxota
    
    # Set ownership (assuming kinuxota user exists, otherwise it will be owned by root)
    if getent passwd kinuxota > /dev/null; then
        chown -R kinuxota:kinuxota /etc/kinuxota
        chown -R kinuxota:kinuxota /var/log/kinuxota
        chown -R kinuxota:kinuxota /var/lib/kinuxota
        chown -R kinuxota:kinuxota /run/kinuxota
        log "Set ownership to kinuxota user"
    else
        log "kinuxota user not found, directories will be owned by root"
    fi
    
    log "Configuration directories created"
}

# Create default configuration file
create_config_file() {
    local CONFIG_FILE="/etc/kinuxota/config.json"
    
    log "Creating default configuration file..."
    
    # Check if config file already exists
    if [ -f "$CONFIG_FILE" ]; then
        log "Configuration file already exists, skipping"
        return
    fi
    
    # Create default config
    cat > "$CONFIG_FILE" << EOF
{
    "serverUrl": "http://172.25.176.1", 
    "mqttBrokerUrl": "tcp://http://172.25.176.1:1883",
    "useMqtt": true,
    "checkForUpdates": true,
    "commandTimeout": 300
}
EOF
    
    # Set permissions
    chmod 644 "$CONFIG_FILE"
    
    log "Default configuration file created"
}

# Create systemd service file
create_service_file() {
    local SERVICE_FILE="/etc/systemd/system/kinuxota.service"
    
    log "Creating systemd service file..."
    
    # Determine user and group for the service
    local SERVICE_USER="root"
    local SERVICE_GROUP="root"
    
    if getent passwd kinuxota > /dev/null; then
        SERVICE_USER="kinuxota"
        SERVICE_GROUP="kinuxota"
        log "Using kinuxota user for service"
    else
        log "Using root user for service"
    fi
    
    # Create service file
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=KinuxOTA Client Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStart=/usr/local/bin/kinuxota_client
Restart=on-failure
RestartSec=10
WorkingDirectory=/var/lib/kinuxota
RuntimeDirectory=kinuxota
RuntimeDirectoryMode=0755
StateDirectory=kinuxota
StateDirectoryMode=0755
LogsDirectory=kinuxota
LogsDirectoryMode=0755
ConfigurationDirectory=kinuxota
ConfigurationDirectoryMode=0755

# Security hardening
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Set permissions
    chmod 644 "$SERVICE_FILE"
    
    log "Systemd service file created with user: ${SERVICE_USER}, group: ${SERVICE_GROUP}"
}

# Enable the service (but don't start it)
enable_service() {
    log "Enabling KinuxOTA service..."
    
    # Reload systemd to recognize the new service
    systemctl daemon-reload
    
    # Enable the service to start on boot
    systemctl enable kinuxota.service
    
    log "Service enabled successfully"
}

# Set up passwordless sudo for package management
setup_sudo_privileges() {
    log "Setting up passwordless sudo for package management..."
    
    # Detect package managers on the system
    PACKAGE_MANAGERS=""
    
    # Check for common package managers
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/apt-get, /usr/bin/apt,"
    fi
    if command -v yum &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/yum,"
    fi
    if command -v dnf &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/dnf,"
    fi
    if command -v pacman &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/pacman,"
    fi
    if command -v apk &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/apk,"
    fi
    if command -v zypper &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/zypper,"
    fi
    if command -v emerge &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/emerge,"
    fi
    if command -v xbps-install &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/xbps-install, /usr/bin/xbps-remove,"
    fi
    if command -v nix-env &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/nix-env,"
    fi
    if command -v swupd &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/swupd,"
    fi
    if command -v eopkg &> /dev/null; then
        PACKAGE_MANAGERS="$PACKAGE_MANAGERS /usr/bin/eopkg,"
    fi
    
    # Remove trailing comma
    PACKAGE_MANAGERS=${PACKAGE_MANAGERS%,}
    
    if [ -z "$PACKAGE_MANAGERS" ]; then
        log "No package managers detected on the system."
        log "Passwordless sudo configuration will not be set up."
        return 1
    else
        log "Detected package managers: $PACKAGE_MANAGERS"
        
        # Create sudoers file for Kinuxota
        SUDOERS_CONTENT="# Allow Kinuxota client to run package management commands without password\nkinuxota ALL=(ALL) NOPASSWD: $PACKAGE_MANAGERS"
        
        # Create the sudoers file
        echo -e "$SUDOERS_CONTENT" | tee /etc/sudoers.d/kinuxota > /dev/null
        
        # Set proper permissions
        chmod 440 /etc/sudoers.d/kinuxota
        
        log "Passwordless sudo configured successfully."
        
        # Test the configuration
        log "Testing passwordless sudo configuration..."
        if sudo -u kinuxota sudo -n true 2>/dev/null; then
            log "Passwordless sudo is working correctly."
            return 0
        else
            log "Passwordless sudo configuration failed. Please check /etc/sudoers.d/kinuxota"
            return 1
        fi
    fi
}

# Create system user for the service
create_system_user() {
    log "Creating system user for the service..."
    
    # Check if user already exists
    if getent passwd kinuxota > /dev/null; then
        log "User kinuxota already exists, skipping"
        return
    fi
    
    # Create system user without login shell and home directory
    useradd --system --no-create-home --shell /usr/sbin/nologin kinuxota
    
    log "System user kinuxota created"
}

# Main function
main() {
    print_colored "KinuxOTA Client Installation" "$GREEN"
    print_colored "This script will install the KinuxOTA client and configure it as a service." "$YELLOW"
    echo ""
    
    # Check if running as root
    check_root
    
    # Detect OS and architecture
    OS_INFO=$(detect_os)
    OS=$(echo $OS_INFO | cut -d':' -f1)
    VERSION=$(echo $OS_INFO | cut -d':' -f2)
    ARCH=$(detect_arch)
    
    # Download and install binaries directly
    download_and_install_binaries $OS $VERSION $ARCH
    
    # Create system user
    create_system_user
    
    # Create configuration directories
    create_config_dirs
    
    # Create default configuration file
    create_config_file
    
    # Create systemd service file
    create_service_file
    
    # Set up sudo privileges for package management
    setup_sudo_privileges
    
    # Enable the service (but don't start it)
    enable_service
    
    print_colored "Installation complete!" "$GREEN"
    echo ""
    print_colored "The KinuxOTA client has been installed but not started." "$YELLOW"
    echo ""
    print_colored "NEXT STEPS:" "$GREEN"
    echo "1. Configure the client with your API key:"
    echo "   sudo kinuxctl configure"
    echo ""
    echo "2. Start the service:"
    echo "   sudo kinuxctl start"
    echo ""
    echo "3. Check the status:"
    echo "   sudo kinuxctl status"
    echo ""
    echo "Additional commands:"
    echo "- Stop the service:    sudo kinuxctl stop"
    echo "- Restart the service: sudo kinuxctl restart"
    echo "- View logs:           sudo kinuxctl logs -f"
    echo "- Check health:        sudo kinuxctl health"
    echo ""
}

# Run the main function
main
