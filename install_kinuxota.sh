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

# Download binaries
download_binaries() {
    local OS=$1
    local VERSION=$2
    local ARCH=$3
    
    log "Downloading KinuxOTA binaries..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    log "Created temporary directory: $TEMP_DIR"
    
    # Create directory structure in temp dir
    mkdir -p "$TEMP_DIR/bin"
    
    # Download kinuxota_client
    log "Downloading kinuxota_client..."
    if ! curl -L -o "$TEMP_DIR/bin/kinuxota_client" "https://github.com/yaswanthsk04/kinuxota/raw/main/release/1.0.0/ubuntu/amd64/kinuxota_client"; then
        error "Failed to download kinuxota_client"
    fi
    
    # Make the binary executable
    chmod +x "$TEMP_DIR/bin/kinuxota_client"
    
    # Also download kinuxctl
    log "Downloading kinuxctl..."
    if curl -L -o "$TEMP_DIR/bin/kinuxctl" "https://github.com/yaswanthsk04/kinuxota/raw/main/release/1.0.0/ubuntu/amd64/kinuxctl"; then
        log "Successfully downloaded kinuxctl"
        chmod +x "$TEMP_DIR/bin/kinuxctl"
    else
        log "Warning: Failed to download kinuxctl, will continue without it"
    fi
    
    # Also download update-executor.sh
    log "Downloading update-executor.sh..."
    if curl -L -o "$TEMP_DIR/bin/update-executor.sh" "https://github.com/yaswanthsk04/kinuxota/raw/main/kinuxota/update-executor.sh"; then
        log "Successfully downloaded update-executor.sh"
        chmod +x "$TEMP_DIR/bin/update-executor.sh"
    else
        log "Warning: Failed to download update-executor.sh, will try to use local copy during installation"
    fi
    
    # Return the path to the extracted binaries
    echo "$TEMP_DIR"
}

# Install binaries
install_binaries() {
    local BINARIES_DIR=$1
    local INSTALL_DIR="/usr/local/bin"
    
    log "Installing binaries to $INSTALL_DIR..."
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Copy binaries from the bin directory
    cp "$BINARIES_DIR/bin/kinuxota_client" "$INSTALL_DIR/"
    
    # Copy kinuxctl if it exists
    if [ -f "$BINARIES_DIR/bin/kinuxctl" ]; then
        cp "$BINARIES_DIR/bin/kinuxctl" "$INSTALL_DIR/"
        chmod 755 "$INSTALL_DIR/kinuxctl"
        log "Installed kinuxctl"
    else
        log "kinuxctl not found, skipping"
    fi
    
    # Set permissions
    chmod 755 "$INSTALL_DIR/kinuxota_client"
    
    # Copy update-executor.sh script if it exists in the downloaded package
    if [ -f "$BINARIES_DIR/bin/update-executor.sh" ]; then
        cp "$BINARIES_DIR/bin/update-executor.sh" "$INSTALL_DIR/"
        chmod 755 "$INSTALL_DIR/update-executor.sh"
        log "Installed update-executor.sh"
    else
        # Create a copy of the update-executor.sh script from the source directory if available
        if [ -f "./kinuxota/update-executor.sh" ]; then
            cp "./kinuxota/update-executor.sh" "$INSTALL_DIR/"
            chmod 755 "$INSTALL_DIR/update-executor.sh"
            log "Copied update-executor.sh from source directory"
        else
            log "Warning: update-executor.sh not found, updates may not work correctly"
        fi
    fi
    
    log "Binaries installed successfully"
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
    "serverUrl": "https://api.kinuxota.com",
    "mqttBrokerUrl": "mqtt://mqtt.kinuxota.com:1883",
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
    
    # Create service file
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=KinuxOTA Client Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
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

# If a dedicated user exists, use it instead of root
ExecStartPre=/bin/sh -c 'if getent passwd kinuxota > /dev/null; then echo "User=kinuxota"; echo "Group=kinuxota"; fi > /run/kinuxota-user'
ExecStartPre=/bin/sh -c 'if [ -f /run/kinuxota-user ]; then sed -i "s/^User=root/$(grep User /run/kinuxota-user)/" /etc/systemd/system/kinuxota.service; sed -i "s/^Group=root/$(grep Group /run/kinuxota-user)/" /etc/systemd/system/kinuxota.service; fi'
ExecStartPost=/bin/rm -f /run/kinuxota-user

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
    
    log "Systemd service file created"
}

# Start and enable the service
start_service() {
    log "Starting and enabling KinuxOTA service..."
    
    # Reload systemd to recognize the new service
    systemctl daemon-reload
    
    # Enable the service to start on boot
    systemctl enable kinuxota.service
    
    # Start the service
    systemctl start kinuxota.service
    
    # Check if service started successfully
    if systemctl is-active --quiet kinuxota.service; then
        log "Service started successfully"
    else
        error "Failed to start service"
    fi
}

# Cleanup temporary files
cleanup() {
    local TEMP_DIR=$1
    
    log "Cleaning up temporary files..."
    
    # Remove temporary directory
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    log "Cleanup complete"
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
    
    # Download binaries
    BINARIES_DIR=$(download_binaries $OS $VERSION $ARCH)
    
    # Install binaries
    install_binaries "$BINARIES_DIR"
    
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
    
    # Start and enable the service
    start_service
    
    # Cleanup
    cleanup "$BINARIES_DIR"
    
    print_colored "Installation complete!" "$GREEN"
    echo ""
    print_colored "The KinuxOTA client has been installed and started as a service." "$YELLOW"
    echo "You can check the status with: sudo systemctl status kinuxota.service"
    echo "You can view logs with: sudo journalctl -u kinuxota.service"
    echo "You can use the kinuxctl utility to manage the client: kinuxctl status"
    echo ""
}

# Run the main function
main
