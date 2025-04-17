# KinuxOTA Client

KinuxOTA is a client-server solution for Over-The-Air updates and remote management of devices.

## Installation

The KinuxOTA client can be easily installed on Ubuntu systems using our installation script.

### Prerequisites

- Ubuntu operating system (other distributions will be supported in future releases)
- Root/sudo access
- Internet connection to download the binaries
- curl installed (`sudo apt-get install curl`)

### Installation Steps

1. Download the installation script:
   ```bash
   curl -O https://raw.githubusercontent.com/kinuxota/kinuxota/main/install_kinuxota.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x install_kinuxota.sh
   ```

3. Run the script with sudo:
   ```bash
   sudo ./install_kinuxota.sh
   ```

The script will:
- Detect your system's architecture and OS
- Download the appropriate binaries from GitHub
- Install the binaries to `/usr/local/bin`
- Create necessary configuration directories
- Set up a systemd service to run the client
- Start the service

## Usage

### Managing the Service

The KinuxOTA client runs as a systemd service. You can manage it using standard systemd commands:

```bash
# Check service status
sudo systemctl status kinuxota.service

# Stop the service
sudo systemctl stop kinuxota.service

# Start the service
sudo systemctl start kinuxota.service

# Restart the service
sudo systemctl restart kinuxota.service

# Enable the service to start on boot
sudo systemctl enable kinuxota.service

# Disable the service from starting on boot
sudo systemctl disable kinuxota.service
```

### Using the kinuxctl Utility

The KinuxOTA client comes with a command-line utility called `kinuxctl` that allows you to manage and monitor the client:

```bash
# Show device status
kinuxctl status

# Check client health
kinuxctl health

# View logs
kinuxctl logs
kinuxctl logs -f  # Follow logs in real-time
kinuxctl logs -n 50  # Show last 50 lines

# Show version information
kinuxctl version

# Show help
kinuxctl help
```

## Configuration

The KinuxOTA client configuration is stored in `/etc/kinuxota/config.json`. You can edit this file to customize the client's behavior.

## Troubleshooting

### Service Won't Start

If the service fails to start, check the logs for more information:

```bash
sudo journalctl -u kinuxota.service -n 50
```

### Connection Issues

If the client can't connect to the server, check your network connection and firewall settings. The client needs to be able to reach the server URL specified in the configuration file.

### Health Check Failures

Use the health check command to diagnose issues:

```bash
kinuxctl health
```

This will return an exit code indicating the health status:
- 0: All systems operational
- 1: Client not running or not connected to MQTT
- 2: Client running but cannot reach server
- 3: Other errors

## Uninstallation

To uninstall the KinuxOTA client:

```bash
# Stop and disable the service
sudo systemctl stop kinuxota.service
sudo systemctl disable kinuxota.service

# Remove the service file
sudo rm /etc/systemd/system/kinuxota.service
sudo systemctl daemon-reload

# Remove the binaries
sudo rm /usr/local/bin/kinuxota_client
sudo rm /usr/local/bin/kinuxctl

# Remove configuration and data directories (optional)
sudo rm -rf /etc/kinuxota
sudo rm -rf /var/log/kinuxota
sudo rm -rf /var/lib/kinuxota
```
