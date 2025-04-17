#!/bin/bash
# KinuxOTA Cleanup Script
# This script removes all KinuxOTA components from the system

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

# Stop and disable the service
stop_service() {
    log "Stopping and disabling KinuxOTA service..."
    
    # Check if service exists
    if systemctl list-unit-files | grep -q "kinuxota.service"; then
        # Stop the service if it's running
        if systemctl is-active --quiet kinuxota.service; then
            log "Stopping kinuxota.service..."
            systemctl stop kinuxota.service
        else
            log "kinuxota.service is not running"
        fi
        
        # Disable the service
        log "Disabling kinuxota.service..."
        systemctl disable kinuxota.service
        
        # Remove the service file
        log "Removing service file..."
        rm -f /etc/systemd/system/kinuxota.service
        
        # Reload systemd
        log "Reloading systemd..."
        systemctl daemon-reload
    else
        log "kinuxota.service not found, skipping"
    fi
}

# Remove binaries
remove_binaries() {
    log "Removing KinuxOTA binaries..."
    
    # Remove binaries from /usr/local/bin
    rm -f /usr/local/bin/kinuxota_client
    rm -f /usr/local/bin/kinuxctl
    rm -f /usr/local/bin/update-executor.sh
    
    log "Binaries removed"
}

# Remove configuration files
remove_config() {
    log "Removing KinuxOTA configuration files..."
    
    # Remove system-wide config directory
    rm -rf /etc/kinuxota
    
    # Remove user config directories
    if [ -d "/root/.config/kinuxota" ]; then
        rm -rf /root/.config/kinuxota
    fi
    
    # Check for other user configs
    for user_home in /home/*; do
        if [ -d "${user_home}/.config/kinuxota" ]; then
            rm -rf "${user_home}/.config/kinuxota"
        fi
    done
    
    # Remove sudoers file
    if [ -f "/etc/sudoers.d/kinuxota" ]; then
        rm -f /etc/sudoers.d/kinuxota
    fi
    
    log "Configuration files removed"
}

# Remove log files
remove_logs() {
    log "Removing KinuxOTA log files..."
    
    # Remove system-wide log directory
    rm -rf /var/log/kinuxota
    
    # Remove user log directories
    for user_home in /home/*; do
        if [ -d "${user_home}/.local/share/kinuxota/logs" ]; then
            rm -rf "${user_home}/.local/share/kinuxota/logs"
        fi
    done
    
    log "Log files removed"
}

# Remove data files
remove_data() {
    log "Removing KinuxOTA data files..."
    
    # Remove system-wide data directory
    rm -rf /var/lib/kinuxota
    
    # Remove runtime directory
    rm -rf /run/kinuxota
    
    # Remove user data directories
    for user_home in /home/*; do
        if [ -d "${user_home}/.local/share/kinuxota" ]; then
            rm -rf "${user_home}/.local/share/kinuxota"
        fi
    done
    
    log "Data files removed"
}

# Remove system user
remove_user() {
    log "Removing KinuxOTA system user..."
    
    # Check if user exists
    if getent passwd kinuxota > /dev/null; then
        # Remove user
        userdel kinuxota
        log "User kinuxota removed"
    else
        log "User kinuxota not found, skipping"
    fi
}

# Kill any running processes
kill_processes() {
    log "Killing any running KinuxOTA processes..."
    
    # Find and kill kinuxota_client processes
    pkill -f kinuxota_client || true
    
    log "Processes killed"
}

# Main function
main() {
    print_colored "KinuxOTA Cleanup" "$RED"
    print_colored "This script will remove all KinuxOTA components from your system." "$YELLOW"
    echo ""
    
    # Check if running as root
    check_root
    
    # Confirm with user
    read -p "Are you sure you want to remove all KinuxOTA components? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "Cleanup aborted by user"
        exit 0
    fi
    
    # Kill any running processes
    kill_processes
    
    # Stop and disable the service
    stop_service
    
    # Remove binaries
    remove_binaries
    
    # Remove configuration files
    remove_config
    
    # Remove log files
    remove_logs
    
    # Remove data files
    remove_data
    
    # Remove system user
    remove_user
    
    print_colored "Cleanup complete!" "$GREEN"
    echo ""
    print_colored "All KinuxOTA components have been removed from your system." "$YELLOW"
    echo ""
}

# Run the main function
main
