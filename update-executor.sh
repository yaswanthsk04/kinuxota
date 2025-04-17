#!/bin/bash
# KinuxOTA Client Update Executor Script
# This script handles the update process for the KinuxOTA client
# It stops the service, replaces the binary, and starts the service again

# Exit on any error
set -e

# Print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Send update status to backend via direct HTTP request
send_update_status() {
    local status=$1
    local message=$2
    local version=$3
    
    log "Sending update status to backend: $status - $message"
    
    # Determine if this is a final status
    local is_complete="false"
    if [ "$status" = "COMPLETED" ] || [ "$status" = "FAILED" ]; then
        is_complete="true"
    fi
    
    # Get configuration file path
    local config_file="/app/config/kinuxota.json"
    if [ ! -f "$config_file" ]; then
        # Try alternate locations
        if [ -f "/etc/kinuxota/config.json" ]; then
            config_file="/etc/kinuxota/config.json"
        elif [ -f "$HOME/.config/kinuxota/config.json" ]; then
            config_file="$HOME/.config/kinuxota/config.json"
        else
            log "ERROR: Cannot find configuration file"
            return 1
        fi
    fi
    
    # Read API key and server URL from config file
    local api_key=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
    local server_url=$(grep -o '"serverUrl"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
    
    if [ -z "$api_key" ] || [ -z "$server_url" ]; then
        log "ERROR: Could not extract API key or server URL from config file"
        return 1
    fi
    
    # Create JSON payload
    local json_payload="{\"version\":\"$version\",\"status\":\"$status\",\"message\":\"$message\",\"isComplete\":$is_complete}"
    
    # Send HTTP request
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $api_key" \
        -d "$json_payload" \
        "${server_url}/api/device/update-status")
    
    # Check response
    if echo "$response" | grep -q "success"; then
        log "Successfully sent update status to backend"
    else
        log "WARNING: Failed to send update status to backend. Response: $response"
    fi
}

# Check if we have the correct number of arguments
if [ $# -lt 1 ]; then
    log "ERROR: Missing argument - version number"
    log "Usage: $0 <version_number> [command_id]"
    exit 1
fi

# Get the version number
VERSION="$1"
log "Update to version: $VERSION"

# Get the command ID if provided
if [ $# -ge 2 ]; then
    COMMAND_ID="$2"
    log "Using command ID: $COMMAND_ID"
else
    log "No command ID provided, will generate one automatically"
fi

# Determine the service name (assuming it's kinuxota.service)
SERVICE_NAME="kinuxota.service"
log "Service name: $SERVICE_NAME"

# Check if the service exists
if ! systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    log "WARNING: Service $SERVICE_NAME not found, will try to continue anyway"
    HAS_SERVICE=false
else
    HAS_SERVICE=true
fi

# Get the path to the current executable
CURRENT_EXECUTABLE=$(which kinuxota_client 2>/dev/null || echo "/usr/local/bin/kinuxota_client")
if [ ! -f "$CURRENT_EXECUTABLE" ]; then
    log "WARNING: Could not find current executable, assuming /usr/local/bin/kinuxota_client"
    CURRENT_EXECUTABLE="/usr/local/bin/kinuxota_client"
fi
log "Current executable path: $CURRENT_EXECUTABLE"

# Get the directory of the current executable
INSTALL_DIR=$(dirname "$CURRENT_EXECUTABLE")
log "Installation directory: $INSTALL_DIR"

# Create backup directory
BACKUP_DIR="$INSTALL_DIR/backup"
mkdir -p "$BACKUP_DIR"
log "Backup directory: $BACKUP_DIR"

# Create a timestamp for the backup
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_FILE="$BACKUP_DIR/kinuxota_client_$TIMESTAMP"

# Send update status - UPDATING
send_update_status "UPDATING" "Starting update process" "$VERSION"

# Backup the current executable
log "Backing up current executable to $BACKUP_FILE"
cp "$CURRENT_EXECUTABLE" "$BACKUP_FILE"

# Stop the service if it exists
if [ "$HAS_SERVICE" = true ]; then
    log "Stopping $SERVICE_NAME"
    systemctl stop "$SERVICE_NAME"
    send_update_status "UPDATING" "Service stopped" "$VERSION"
else
    # If no service exists, try to find and kill the process
    log "No service found, trying to find and kill the process"
    PID=$(pgrep -f "$(basename "$CURRENT_EXECUTABLE")")
    if [ -n "$PID" ]; then
        log "Found process with PID $PID, sending SIGTERM"
        kill -15 "$PID"
        send_update_status "UPDATING" "Process stopped" "$VERSION"
        # Wait for the process to exit
        for i in {1..10}; do
            if ! ps -p "$PID" > /dev/null; then
                break
            fi
            log "Waiting for process to exit ($i/10)..."
            sleep 1
        done
        # Force kill if still running
        if ps -p "$PID" > /dev/null; then
            log "Process still running, sending SIGKILL"
            kill -9 "$PID"
        fi
    else
        log "No running process found"
    fi
fi

# Find the downloaded update package
UPDATE_DIR="/tmp/kinuxota/updates"
UPDATE_FILE=$(find "$UPDATE_DIR" -name "kinuxota" -type f | head -n 1)

if [ -z "$UPDATE_FILE" ]; then
    log "ERROR: Could not find update file for version $VERSION"
    send_update_status "FAILED" "Could not find update file" "$VERSION"
    
    # Restart the service or process
    if [ "$HAS_SERVICE" = true ]; then
        log "Restarting service"
        systemctl start "$SERVICE_NAME"
    else
        log "Restarting process"
        nohup "$CURRENT_EXECUTABLE" > /dev/null 2>&1 &
    fi
    
    exit 1
fi

log "Found update file: $UPDATE_FILE"
send_update_status "UPDATING" "Found update file" "$VERSION"

# Replace the old binary with the new one
log "Replacing executable"
cp "$UPDATE_FILE" "$CURRENT_EXECUTABLE"
chmod +x "$CURRENT_EXECUTABLE"
send_update_status "UPDATING" "Binary replaced" "$VERSION"

# Start the service if it exists
if [ "$HAS_SERVICE" = true ]; then
    log "Starting $SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    # Wait for the service to start
    for i in {1..10}; do
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            break
        fi
        log "Waiting for service to start ($i/10)..."
        sleep 1
    done
    
    # Check if the service started successfully
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Service started successfully"
        send_update_status "UPDATING" "Service started" "$VERSION"
    else
        log "ERROR: Failed to start service with new binary"
        send_update_status "FAILED" "Failed to start service with new binary" "$VERSION"
        
        log "Rolling back to previous version"
        cp "$BACKUP_FILE" "$CURRENT_EXECUTABLE"
        chmod +x "$CURRENT_EXECUTABLE"
        
        log "Starting service with old binary"
        systemctl start "$SERVICE_NAME"
        
        # Check if the service started successfully with the old binary
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log "Service started successfully with old binary"
            send_update_status "FAILED" "Rolled back to previous version" "$VERSION"
        else
            log "ERROR: Failed to start service with old binary"
            send_update_status "FAILED" "Failed to start service with old binary" "$VERSION"
        fi
        
        exit 1
    fi
else
    # If no service exists, start the executable directly
    log "No service found, starting executable directly"
    nohup "$CURRENT_EXECUTABLE" > /dev/null 2>&1 &
    
    # Wait for the process to start
    for i in {1..10}; do
        if pgrep -f "$(basename "$CURRENT_EXECUTABLE")" > /dev/null; then
            break
        fi
        log "Waiting for process to start ($i/10)..."
        sleep 1
    done
    
    # Check if the process started successfully
    if pgrep -f "$(basename "$CURRENT_EXECUTABLE")" > /dev/null; then
        log "Process started successfully"
        send_update_status "UPDATING" "Process started" "$VERSION"
    else
        log "ERROR: Failed to start process with new binary"
        send_update_status "FAILED" "Failed to start process with new binary" "$VERSION"
        
        log "Rolling back to previous version"
        cp "$BACKUP_FILE" "$CURRENT_EXECUTABLE"
        chmod +x "$CURRENT_EXECUTABLE"
        
        log "Starting process with old binary"
        nohup "$CURRENT_EXECUTABLE" > /dev/null 2>&1 &
        
        # Check if the process started successfully with the old binary
        if pgrep -f "$(basename "$CURRENT_EXECUTABLE")" > /dev/null; then
            log "Process started successfully with old binary"
            send_update_status "FAILED" "Rolled back to previous version" "$VERSION"
        else
            log "ERROR: Failed to start process with old binary"
            send_update_status "FAILED" "Failed to start process with old binary" "$VERSION"
        fi
        
        exit 1
    fi
fi

# Check if the client is healthy
log "Checking client health"
sleep 5  # Give the client some time to initialize

# Use the health check command
if command -v kinuxctl &> /dev/null; then
    kinuxctl health
    HEALTH_STATUS=$?
    
    if [ $HEALTH_STATUS -eq 0 ]; then
        log "Client is healthy"
        send_update_status "COMPLETED" "Update completed successfully" "$VERSION"
    else
        log "ERROR: Client health check failed with status $HEALTH_STATUS"
        send_update_status "FAILED" "Client health check failed" "$VERSION"
        
        log "Rolling back to previous version"
        
        # Stop the service or kill the process
        if [ "$HAS_SERVICE" = true ]; then
            systemctl stop "$SERVICE_NAME"
        else
            PID=$(pgrep -f "$(basename "$CURRENT_EXECUTABLE")")
            if [ -n "$PID" ]; then
                kill -15 "$PID"
                sleep 2
                if ps -p "$PID" > /dev/null; then
                    kill -9 "$PID"
                fi
            fi
        fi
        
        # Restore the backup
        cp "$BACKUP_FILE" "$CURRENT_EXECUTABLE"
        chmod +x "$CURRENT_EXECUTABLE"
        
        # Start the service or process again
        if [ "$HAS_SERVICE" = true ]; then
            systemctl start "$SERVICE_NAME"
            
            # Check if the service started successfully with the old binary
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                log "Service started successfully with old binary"
                send_update_status "FAILED" "Rolled back to previous version" "$VERSION"
            else
                log "ERROR: Failed to start service with old binary"
                send_update_status "FAILED" "Failed to start service with old binary" "$VERSION"
            fi
        else
            nohup "$CURRENT_EXECUTABLE" > /dev/null 2>&1 &
            
            # Check if the process started successfully with the old binary
            if pgrep -f "$(basename "$CURRENT_EXECUTABLE")" > /dev/null; then
                log "Process started successfully with old binary"
                send_update_status "FAILED" "Rolled back to previous version" "$VERSION"
            else
                log "ERROR: Failed to start process with old binary"
                send_update_status "FAILED" "Failed to start process with old binary" "$VERSION"
            fi
        fi
        
        exit 1
    fi
else
    log "WARNING: kinuxctl not found, skipping health check"
    send_update_status "COMPLETED" "Update completed, but health check skipped" "$VERSION"
fi

# Clean up
log "Cleaning up temporary files"
rm -rf "$UPDATE_DIR"

log "Update completed successfully"
exit 0
