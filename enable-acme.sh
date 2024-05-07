#!/bin/sh
# shellcheck shell=dash
#
# Description: This script enables ACME support on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/is-there-a-way-to-get-a-letsencrypt-certificate-for-the-factory-ddns-on-the-mt6000/
# Author: Admon
# Update: 2024-05-07
# Date: 2023-12-27
SCRIPT_VERSION="2024.05.07.02"
#
# Usage: ./enable-acme.sh [--renew]
# Warning: This script might potentially harm your router. Use it at your own risk.
#
# Variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
INFO='\033[0m' # No Color

# Functions
create_acme_config() {
    # Delete old ACME configuration file
    log "INFO" "Deleting old ACME configuration file for $DDNS_DOMAIN_PREFIX ..."
    uci delete acme.$DDNS_DOMAIN_PREFIX
    uci commit acme
    # Create new ACME configuration file
    log "INFO" "Creating ACME configuration file ..."
    uci set acme.@acme[0]=acme
    uci set acme.@acme[0].account_email='acme@glddns.com'
    uci set acme.@acme[0].debug='1'
    uci set acme.$DDNS_DOMAIN_PREFIX=cert
    uci set acme.$DDNS_DOMAIN_PREFIX.enabled='1'
    uci set acme.$DDNS_DOMAIN_PREFIX.use_staging='0'
    uci set acme.$DDNS_DOMAIN_PREFIX.keylength='2048'
    uci set acme.$DDNS_DOMAIN_PREFIX.validation='standalone'
    uci set acme.$DDNS_DOMAIN_PREFIX.update_nginx='1'
    uci set acme.$DDNS_DOMAIN_PREFIX.domains="$DDNS_DOMAIN"
    uci commit acme
    /etc/init.d/acme restart
}

open_firewall() {
    if [ "$1" -eq 1 ]; then
        log "INFO" "Creating firewall rule to open port 80 on WAN ..."
        uci set firewall.acme=rule
        uci set firewall.acme.dest_port='80'
        uci set firewall.acme.proto='tcp'
        uci set firewall.acme.name='GL-ACME'
        uci set firewall.acme.target='ACCEPT'
        uci set firewall.acme.src='wan'
        uci set firewall.acme.enabled='1'
    else
        log "INFO" "Disabling firewall rule to open port 80 on WAN ..."
        uci set firewall.acme.enabled='0'
    fi
    log "INFO" "Restarting firewall ..."
    /etc/init.d/firewall restart 2&>/dev/null
    uci commit firewall
}

preflight_check() {
    FIRMWARE_VERSION=$(cut -c1 </etc/glversion)
    PREFLIGHT=0
    log "INFO" "Checking if prerequisites are met ..."
    if [ "${FIRMWARE_VERSION}" -lt 4 ]; then
        log "ERROR" "This script only works on firmware version 4 or higher."
        PREFLIGHT=1
    else
        log "SUCCESS" "Firmware version: $FIRMWARE_VERSION"
    fi
    # Check if public IP address is available
    PUBLIC_IP=$(sudo -g nonevpn curl -4 -s https://api.ipify.org)
    if [ -z "$PUBLIC_IP" ]; then
        log "ERROR" "Could not get public IP address. Please check your internet connection."
        PREFLIGHT=1
    else
        log "SUCCESS" "Public IP address: $PUBLIC_IP"
    fi
    DDNS_DOMAIN=$(uci get ddns.glddns.domain)
    DDNS_IP=$(nslookup $DDNS_DOMAIN | sed -n '/Address/s/.*: \(.*\)/\1/p' | grep -v ':')
    if [ -z "$DDNS_IP" ]; then
        log "ERROR" "DDNS IP address not found. Please enable DDNS first."
        PREFLIGHT=1
    else
        log "SUCCESS" "Detected DDNS IP address: $DDNS_IP"
    fi
    if [ -z "$DDNS_DOMAIN" ]; then
        log "ERROR" "DDNS domain name not found. Please enable DDNS first."
        PREFLIGHT=1
    else
        log "SUCCESS" "Detected DDNS domain name: $DDNS_DOMAIN"
    fi
    # Get only the first part of the domain name
    DDNS_DOMAIN_PREFIX=$(echo $DDNS_DOMAIN | cut -d'.' -f1)
    log "SUCCESS" "Prefix of the DDNS domain name: $DDNS_DOMAIN_PREFIX"
    # Check if public IP matches DDNS IP
    if [ "$PUBLIC_IP" != "$DDNS_IP" ]; then
        log "ERROR" "Public IP does not match DDNS IP!"
        PREFLIGHT=1
    else
        log "SUCCESS" "Public IP matches DDNS IP."
    fi

    if [ "$PREFLIGHT" -eq "1" ]; then
        log "ERROR" "Prerequisites are not met. Exiting ..."
        exit 1
    else
        log "SUCCESS" "Prerequisites are met."
    fi
}

invoke_intro() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ GL.iNet router script by Admon 🦭 for the GL.iNet community            │"
    echo "| Version: $SCRIPT_VERSION                                                 |"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ WARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!               │"
    echo "│ It's only recommended to use this script if you know what you're doing.│"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ This script will enable ACME support on your router.                   │"
    echo "│                                                                        │"
    echo "│ Prerequisites:                                                         │"
    echo "│ 1. You need to have the GL DDNS service enabled.                       │"
    echo "│ 2. The router needs to have a public IPv4 address.                     │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
}

install_prequisites() {
    log "INFO" "Installing luci-app-acme ..."
    opkg update >/dev/null 2>&1
    opkg install luci-app-acme --force-depends >/dev/null 2>&1
}

config_nginx() {
    if [ "$1" -eq 1 ]; then
        log "INFO" "Disabling HTTP access to the router ..."
        # Commenting out the HTTP line in nginx.conf
        sed -i 's/listen 80;/#listen 80;/g' /etc/nginx/conf.d/gl.conf
        # Same for IPv6
        sed -i 's/listen \[::\]:80;/#listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
    else
        log "INFO" "Enabling HTTP access to the router ..."
        # Uncommenting the HTTP line in nginx.conf
        sed -i 's/#listen 80;/listen 80;/g' /etc/nginx/conf.d/gl.conf
        # Same for IPv6
        sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
    fi
    log "INFO" "Restarting nginx ..."
    /etc/init.d/nginx restart

}

get_acme_cert(){
    log "INFO" "Restarting acme ..."
    /etc/init.d/acme restart
    sleep 5
    /etc/init.d/acme restart
    log "INFO" "Checking if certificate was issued ..."
    # Wait for 10 seconds
    sleep 10
    # Check if certificate was issued
    if [ -f "/etc/acme/$DDNS_DOMAIN/fullchain.cer" ]; then
        log "SUCCESS" "Certificate was issued successfully."
        log "INFO" "Installing certificate in nginx ..."
        # Install the certificate in nginx
        # Replace the ssl_certificate line in nginx.conf
        # Replace the whole line, because the path is different
        sed -i "s|ssl_certificate .*;|ssl_certificate /etc/acme/$DDNS_DOMAIN/fullchain.cer;|g" /etc/nginx/conf.d/gl.conf
        sed -i "s|ssl_certificate_key .*;|ssl_certificate_key /etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key;|g" /etc/nginx/conf.d/gl.conf
        FAIL=0
    else
        log "ERROR" "Certificate was not issued. Please check the log by running logread."
        FAIL=1
    fi
}

invoke_outro() {
    if [ "$FAIL" -eq 1 ]; then
        log "ERROR" "The ACME certificate was not installed successfully."
        log "ERROR" "Please report any issues on the GL.iNET forum or inside the scripts repository."
        log "ERROR" "You can find the log file by executing logread"
        exit 1
    else
        # Install cronjob
        install_cronjob
        log "SUCCESS" "The ACME certificate was installed successfully."
        log "SUCCESS" "You can now access your router via HTTPS."
        log "SUCCESS" "Please report any issues on the GL.iNET forum."
        log "SUCCESS" ""
        log "SUCCESS" "You can find the certificate files in /etc/acme/$DDNS_DOMAIN/"
        log "SUCCESS" "The certificate files are:"
        log "SUCCESS" "  /etc/acme/$DDNS_DOMAIN/fullchain.cer"
        log "SUCCESS" "  /etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key"
        log "SUCCESS" ""
        log "SUCCESS" "The certificate will expire after 90 days."
        log "SUCCESS" "The cronjob to renew the certificate is already installed."
        log "SUCCESS" "Renewal will happen automatically."
        exit 0
    fi
}

install_cronjob() {
    # Create cronjob to renew the certificate
    log "INFO" "Checking if cronjob already exists ..."
    if crontab -l | grep -q "enable-acme"; then
        log "WARNING" "Cronjob already exists. Skipping ..."
    else
        log "INFO" "Installing cronjob ..."
        install_script
        (crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/enable-acme --renew ") | crontab -
        log "SUCCESS" "Cronjob installed successfully."
    fi
}

install_script() {
    # Copying the script to /usr/bin
    log "INFO" "Copying the script to /usr/bin ..."
    cp $0 /usr/bin/enable-acme
    chmod +x /usr/bin/enable-acme
    log "SUCCESS" "Script installed successfully."
}

invoke_renewal(){
    open_firewall 1
    config_nginx 1
    log "INFO" "Renewing certificate ..."
    /usr/lib/acme/acme.sh --cron --home /etc/acme
    config_nginx 0
    open_firewall 0
}

make_permanent() {
    log "INFO" "Modifying /etc/sysupgrade.conf ..."
    if ! grep -q "/etc/acme" /etc/sysupgrade.conf; then
        echo "/etc/acme" >>/etc/sysupgrade.conf
    fi
    
    if ! grep -q "/etc/nginx/conf.d/gl.conf" /etc/sysupgrade.conf; then
        echo "/etc/nginx/conf.d/gl.conf" >>/etc/sysupgrade.conf
    fi
    log "SUCCESS" "Configuration added to /etc/sysupgrade.conf."
}

invoke_update() {
     SCRIPT_VERSION_NEW=$(curl -s "https://raw.githubusercontent.com/Admonstrator/glinet-enable-acme/main/enable-acme.sh" | grep -o 'SCRIPT_VERSION="[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}"' | cut -d '"' -f 2 || echo "Failed to retrieve script version")
    if [ "$SCRIPT_VERSION_NEW" != "$SCRIPT_VERSION" ]; then
        echo -e "\033[33mA new version of this script is available: $SCRIPT_VERSION_NEW\033[0m"
        echo -e "\033[33mThe script will now be updated ...\033[0m"
        wget -qO /tmp/enable-acme.sh "https://raw.githubusercontent.com/Admonstrator/glinet-enable-acme/main/enable-acme.sh"
        # Get current script path
        SCRIPT_PATH=$(readlink -f "$0")
        # Replace current script with updated script
        rm "$SCRIPT_PATH"
        mv /tmp/enable-acme.sh "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        echo -e "\033[32mThe script has been updated successfully. It will restart in 3 seconds ...\033[0m"
        sleep 3
        exec "$SCRIPT_PATH" "$@"
    else
        echo -e "\033[32mYou are using the latest version of this script!\033[0m"
    fi
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$INFO # Default to no color

    # Assign color based on level
    case "$level" in
        ERROR)
            level="x"
            color=$RED
            ;;
        WARNING)
            level="!"
            color=$YELLOW
            ;;
        SUCCESS)
            level="✓"
            color=$GREEN
            ;;
        INFO)
            level="→"
            ;;
    esac

    echo -e "${color}[$timestamp] [$level] $message${INFO}"
}

# Main
# Check if --renew is used
if [ "$1" = "--renew" ]; then
    invoke_renewal
    exit 0
fi

# Check if --change-ports is used
if [ "$1" = "--change-ports" ]; then
    select_ports
fi

invoke_update
invoke_intro
preflight_check
echo -e "\033[93m┌──────────────────────────────────────────────────┐\033[0m"
echo -e "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m"
echo -e "\033[93m└──────────────────────────────────────────────────┘\033[0m"
read answer
if [ "$answer" != "${answer#[Yy]}" ]; then
    install_prequisites
    open_firewall 1
    create_acme_config
    config_nginx 1
    get_acme_cert
    config_nginx 0
    open_firewall 0
    make_permanent
    invoke_outro
else
    log "SUCCESS" "Ok, see you next time!"
    exit 1
fi