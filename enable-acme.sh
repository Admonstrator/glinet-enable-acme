#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC3036
# Description: This script enables ACME support on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/script-lets-encrypt-for-gl-inet-router-https-access/41991
# Author: Admon
SCRIPT_VERSION="2025.11.28.01"
SCRIPT_NAME="enable-acme.sh"
UPDATE_URL="https://get.admon.me/acme-update"
#
# Variables
FORCE=0
RENEW=0
RESTORE=0
SHOW_LOG=0
ASCII_MODE=0
USER_WANTS_PERSISTENCE=""
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
INFO='\033[0m' # No Color

# Functions
invoke_intro() {
    echo "============================================================"
    echo ""
    echo "  OpenWrt/GL.iNet ACME Certificate Manager by Admon"
    echo "  Version: $SCRIPT_VERSION"
    echo ""
    echo "============================================================"
    echo ""
    echo "  WARNING: THIS SCRIPT MIGHT HARM YOUR ROUTER!"
    echo "  Use at your own risk. Only proceed if you know"
    echo "  what you're doing."
    echo ""
    echo "============================================================"
    echo ""
    echo "  Support this project:"
    echo "    - GitHub: github.com/sponsors/admonstrator"
    echo "    - Ko-fi: ko-fi.com/admon"
    echo "    - Buy Me a Coffee: buymeacoffee.com/admon"
    echo ""
    echo "============================================================"
    echo ""
}

collect_user_preferences() {
    log "INFO" "Collecting user preferences before starting the ACME setup"
    echo ""

    # Ask about persistence
    if [ "$FORCE" -eq 1 ]; then
        USER_WANTS_PERSISTENCE="y"
        log "INFO" "--force flag is used. Installation will be made permanent"
    else
        echo "┌────────────────────────────────────────────────────────────────────────────────┐"
        echo "| Make Installation Permanent                                                    |"
        echo "| This will make your ACME configuration persistent over firmware upgrades.      |"
        echo "| The certificate files and nginx configuration will be preserved.               |"
        echo "└────────────────────────────────────────────────────────────────────────────────┘"
        printf "> \033[36mDo you want to make the installation permanent?\033[0m (y/N) "
        read -r USER_WANTS_PERSISTENCE
        USER_WANTS_PERSISTENCE=$(echo "$USER_WANTS_PERSISTENCE" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        echo ""
    fi

    # Final confirmation unless --force is used
    if [ "$FORCE" -eq 0 ]; then
        printf "\033[93m┌──────────────────────────────────────────────────┐\033[0m\n"
        printf "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m\n"
        printf "\033[93m└──────────────────────────────────────────────────┘\033[0m\n"
        read -r answer
        answer_lower=$(echo "$answer" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        if [ "$answer_lower" != "${answer_lower#[y]}" ]; then
            log "INFO" "Starting ACME setup process..."
            echo ""
        else
            log "SUCCESS" "Ok, see you next time!"
            exit 0
        fi
    else
        log "WARNING" "--force flag is used. Continuing without final confirmation"
        echo ""
    fi
}

create_acme_config() {
    # Delete old ACME configuration file
    log "INFO" "Deleting old ACME configuration file for $DDNS_DOMAIN_PREFIX"
    uci delete acme.$DDNS_DOMAIN_PREFIX
    uci commit acme
    # Create new ACME configuration file
    log "INFO" "Creating ACME configuration file"
    if [ "$GL_DDNS" -eq 1 ]; then
        uci set acme.@acme[0]=acme
        uci set acme.@acme[0].account_email='acme@glddns.com'
        uci set acme.@acme[0].debug='1'
        uci set acme.$DDNS_DOMAIN_PREFIX=cert
        uci set acme.$DDNS_DOMAIN_PREFIX.enabled='1'
        uci set acme.$DDNS_DOMAIN_PREFIX.use_staging='0'
        uci set acme.$DDNS_DOMAIN_PREFIX.keylength='2048'
        uci set acme.$DDNS_DOMAIN_PREFIX.validation_method='standalone'
        uci set acme.$DDNS_DOMAIN_PREFIX.update_nginx='1'
        uci set acme.$DDNS_DOMAIN_PREFIX.domains="$DDNS_DOMAIN"
    else
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
    fi
    uci commit acme
    /etc/init.d/acme restart
}

open_firewall() {
    if [ "$1" -eq 1 ]; then
        log "INFO" "Creating firewall rule to open port 80 on WAN"
        uci set firewall.acme=rule
        uci set firewall.acme.dest_port='80'
        uci set firewall.acme.proto='tcp'
        uci set firewall.acme.name='GL-ACME'
        uci set firewall.acme.target='ACCEPT'
        uci set firewall.acme.src='wan'
        uci set firewall.acme.enabled='1'
    else
        log "INFO" "Disabling firewall rule to open port 80 on WAN"
        uci set firewall.acme.enabled='0'
    fi
    log "INFO" "Restarting firewall"
    /etc/init.d/firewall restart 2 &>/dev/null
    uci commit firewall
}

preflight_check() {
    PREFLIGHT=0
    log "INFO" "Checking if prerequisites are met"
    
    # Check if this is a GL.iNet router
    if [ -f "/etc/glversion" ]; then
        FIRMWARE_VERSION=$(cut -c1 </etc/glversion)
        if [ "${FIRMWARE_VERSION}" -lt 4 ]; then
            log "ERROR" "This script only works on GL.iNet firmware version 4 or higher."
            PREFLIGHT=1
        else
            log "SUCCESS" "GL.iNet firmware version: $FIRMWARE_VERSION"
        fi
    else
        log "SUCCESS" "OpenWrt system detected"
    fi
    # Check if public IP address is available
    PUBLIC_IP=$(sudo -g nonevpn curl -4 -s https://api.ipify.org 2>/dev/null || curl -4 -s https://api.ipify.org)
    if [ -z "$PUBLIC_IP" ]; then
        log "ERROR" "Could not get public IP address. Please check your internet connection."
        PREFLIGHT=1
    else
        log "SUCCESS" "Public IP address: $PUBLIC_IP"
    fi
    log "INFO" "Trying to find DDNS domain name"
    DDNS_DOMAIN=$(uci -q get ddns.glddns.domain)
    if [ -z "$DDNS_DOMAIN" ]; then
        log "INFO" "Not found in ddns.glddns. Trying gl_ddns.glddns"
        DDNS_DOMAIN=$(uci -q get gl_ddns.glddns.domain)
        if [ -z "$DDNS_DOMAIN" ]; then
            log "ERROR" "DDNS domain name not found. Please enable DDNS first."
            PREFLIGHT=1
        fi
        GL_DDNS=1
    else
        log "SUCCESS" "Detected DDNS domain name: $DDNS_DOMAIN"
    fi

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
    
    # Check if required files and directories exist
    log "INFO" "Checking if required files and directories exist"
    
    # Check for nginx configuration file
    if [ ! -f "/etc/nginx/conf.d/gl.conf" ]; then
        log "ERROR" "Nginx configuration file /etc/nginx/conf.d/gl.conf not found"
        log "ERROR" "This script requires a GL.iNet router or compatible OpenWrt setup"
        PREFLIGHT=1
    else
        log "SUCCESS" "Nginx configuration file found"
    fi
    
    # Check for nginx init script
    if [ ! -f "/etc/init.d/nginx" ]; then
        log "ERROR" "Nginx init script /etc/init.d/nginx not found"
        PREFLIGHT=1
    else
        log "SUCCESS" "Nginx init script found"
    fi
    
    # Check for firewall init script
    if [ ! -f "/etc/init.d/firewall" ]; then
        log "WARNING" "Firewall init script not found. Firewall configuration will be skipped"
    else
        log "SUCCESS" "Firewall init script found"
    fi
    
    # Check if uci command is available
    if ! command -v uci >/dev/null 2>&1; then
        log "ERROR" "UCI command not found. This script requires OpenWrt/GL.iNet firmware"
        PREFLIGHT=1
    else
        log "SUCCESS" "UCI command available"
    fi
    
    # Check if sysupgrade.conf exists (for persistence)
    if [ ! -f "/etc/sysupgrade.conf" ]; then
        log "WARNING" "File /etc/sysupgrade.conf not found. Persistence feature will be unavailable"
    else
        log "SUCCESS" "Sysupgrade configuration file found"
    fi
    
    # Check if required commands are available
    local required_commands="wget curl sed grep awk"
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "Required command '$cmd' not found"
            PREFLIGHT=1
        fi
    done
    if [ "$PREFLIGHT" -eq 0 ]; then
        log "SUCCESS" "All required commands are available"
    fi
}

install_prequisites() {
    log "INFO" "Installing luci-app-acme"
    opkg update >/dev/null 2>&1
    opkg install luci-app-acme --force-depends >/dev/null 2>&1
}

config_nginx() {
    if [ "$1" -eq 1 ]; then
        log "INFO" "Disabling HTTP access to the router"
        # Commenting out the HTTP line in nginx.conf
        sed -i 's/listen 80;/#listen 80;/g' /etc/nginx/conf.d/gl.conf
        # Same for IPv6
        sed -i 's/listen \[::\]:80;/#listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
    else
        log "INFO" "Enabling HTTP access to the router"
        # Uncommenting the HTTP line in nginx.conf
        sed -i 's/#listen 80;/listen 80;/g' /etc/nginx/conf.d/gl.conf
        # Same for IPv6
        sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
    fi
    log "INFO" "Restarting nginx"
    /etc/init.d/nginx restart

}

get_acme_cert() {
    log "INFO" "Restarting acme"
    /etc/init.d/acme restart
    sleep 5
    /etc/init.d/acme restart
    log "INFO" "Checking if certificate was issued"
    # Wait for 10 seconds
    sleep 10
    # Check if certificate was issued
    if [ -f "/etc/acme/$DDNS_DOMAIN/fullchain.cer" ]; then
        log "SUCCESS" "Certificate was issued successfully."
        log "INFO" "Installing certificate in nginx"
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
        log "ERROR" "Please report any issues on the GL.iNET forum or GitHub repository."
        log "ERROR" "You can find the log file by executing: logread"
        exit 1
    else
        # Install cronjob
        install_cronjob
        log "SUCCESS" "The ACME certificate was installed successfully."
        log "SUCCESS" "You can now access your router via HTTPS."
        echo ""
        log "INFO" "Certificate files location: /etc/acme/$DDNS_DOMAIN/"
        log "INFO" "  - Certificate: /etc/acme/$DDNS_DOMAIN/fullchain.cer"
        log "INFO" "  - Private key: /etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key"
        echo ""
        log "INFO" "The certificate will expire after 90 days."
        log "INFO" "Automatic renewal is configured via cron job (daily at 00:00)."
        echo ""
        echo ""
        echo "If you like this script, please consider supporting the project:"
        echo "  - GitHub: github.com/sponsors/admonstrator"
        echo "  - Ko-fi: ko-fi.com/admon"
        echo "  - Buy Me a Coffee: buymeacoffee.com/admon"
        exit 0
    fi
}

install_cronjob() {
    # Create cronjob to renew the certificate
    log "INFO" "Checking if cronjob already exists"
    if crontab -l | grep -q "enable-acme"; then
        log "WARNING" "Cronjob already exists. Removing it."
        crontab -l | grep -v "enable-acme" | crontab -
    fi
        log "INFO" "Installing cronjob"
        install_script
        (
            crontab -l 2>/dev/null
            echo "0 0 * * * /usr/bin/enable-acme --renew "
        ) | crontab -
        log "SUCCESS" "Cronjob installed successfully."
}

install_script() {
    # Copying the script to /usr/bin
    log "INFO" "Copying the script to /usr/bin"
    cp $0 /usr/bin/enable-acme
    chmod +x /usr/bin/enable-acme
    log "SUCCESS" "Script installed successfully."
}

invoke_renewal() {
    open_firewall 1
    config_nginx 1
    log "INFO" "Renewing certificate"
    /usr/lib/acme/acme.sh --cron --home /etc/acme
    config_nginx 0
    open_firewall 0
}

make_permanent() {
    # Use the pre-collected user preference for persistence
    if [ "$USER_WANTS_PERSISTENCE" != "${USER_WANTS_PERSISTENCE#[y]}" ]; then
        log "INFO" "Making installation permanent"
        log "INFO" "Modifying /etc/sysupgrade.conf"
        if ! grep -q "/etc/acme" /etc/sysupgrade.conf; then
            echo "/etc/acme" >>/etc/sysupgrade.conf
        fi

        if ! grep -q "/etc/nginx/conf.d/gl.conf" /etc/sysupgrade.conf; then
            echo "/etc/nginx/conf.d/gl.conf" >>/etc/sysupgrade.conf
        fi
        log "SUCCESS" "Configuration added to /etc/sysupgrade.conf."
    else
        log "INFO" "Installation will not be made permanent"
        log "INFO" "Configuration will be lost after firmware upgrade"
    fi
}

invoke_update() {
    log "INFO" "Checking for script updates"
    SCRIPT_VERSION_NEW=$(curl -s "$UPDATE_URL" | grep -o 'SCRIPT_VERSION="[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}"' | cut -d '"' -f 2 || echo "Failed to retrieve scriptversion")
    if [ -n "$SCRIPT_VERSION_NEW" ] && [ "$SCRIPT_VERSION_NEW" != "$SCRIPT_VERSION" ]; then
        log "WARNING" "A new version of the script is available: $SCRIPT_VERSION_NEW"
        log "INFO" "Updating the script ..."
        wget -qO /tmp/$SCRIPT_NAME "$UPDATE_URL"
        # Get current script path
        SCRIPT_PATH=$(readlink -f "$0")
        # Replace current script with updated script
        rm "$SCRIPT_PATH"
        mv /tmp/$SCRIPT_NAME "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        log "INFO" "The script has been updated. It will now restart ..."
        sleep 3
        exec "$SCRIPT_PATH" "$@"
    else
        log "SUCCESS" "The script is up to date"
    fi
}

log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$INFO # Default to no color
    local symbol=""

    # Assign color and symbol based on level
    case "$level" in
    ERROR)
        color=$RED
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[X] "
        else
            symbol="❌ "
        fi
        ;;
    WARNING)
        color=$YELLOW
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[!] "
        else
            symbol="⚠️  "
        fi
        ;;
    SUCCESS)
        color=$GREEN
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[OK] "
        else
            symbol="✅ "
        fi
        ;;
    INFO)
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[->] "
        else
            symbol="ℹ️  "
        fi
        ;;
    esac

    # Build output with or without timestamp
    if [ "$SHOW_LOG" -eq 1 ]; then
        printf "${color}[$timestamp] $symbol$message${INFO}\n"
    else
        printf "${color}$symbol$message${INFO}\n"
    fi
}

restore_configuration() {
    printf "\033[31mWARNING: This will restore the nginx configuration to factory default!\033[0m\n"
    printf "\033[31mThis will remove ACME certificates and revert to self-signed certificates.\033[0m\n"
    printf "\033[93m┌──────────────────────────────────────────────────┐\033[0m\n"
    printf "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m\n"
    printf "\033[93m└──────────────────────────────────────────────────┘\033[0m\n"
    
    if [ "$FORCE" -eq 1 ]; then
        log "WARNING" "--force flag is used. Continuing with restore"
        answer_restore="y"
    else
        read -r answer_restore
    fi
    
    answer_restore_lower=$(echo "$answer_restore" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    if [ "$answer_restore_lower" != "${answer_restore_lower#[y]}" ]; then
        log "INFO" "Restoring nginx configuration to factory default"
        
        # Restore HTTP ports (uncomment them)
        log "INFO" "Restoring HTTP access on port 80"
        sed -i 's/#listen 80;/listen 80;/g' /etc/nginx/conf.d/gl.conf
        sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
        
        # Restore original SSL certificates
        log "INFO" "Restoring original self-signed certificates"
        sed -i 's|ssl_certificate .*;|ssl_certificate /etc/nginx/nginx.cer;|g' /etc/nginx/conf.d/gl.conf
        sed -i 's|ssl_certificate_key .*;|ssl_certificate_key /etc/nginx/nginx.key;|g' /etc/nginx/conf.d/gl.conf
        
        # Remove firewall rule for ACME
        log "INFO" "Removing ACME firewall rule"
        uci delete firewall.acme 2>/dev/null || true
        uci commit firewall
        /etc/init.d/firewall restart 2>&1 >/dev/null
        
        # Remove ACME configuration
        log "INFO" "Removing ACME configuration"
        # Get all ACME cert sections and delete them
        for cert_section in $(uci show acme | grep "=cert" | cut -d'.' -f2 | cut -d'=' -f1); do
            uci delete acme.$cert_section 2>/dev/null || true
        done
        uci commit acme
        
        # Stop ACME service
        /etc/init.d/acme stop 2>/dev/null || true
        
        # Remove cronjob
        log "INFO" "Removing ACME cronjob"
        if crontab -l 2>/dev/null | grep -q "enable-acme"; then
            crontab -l | grep -v "enable-acme" | crontab -
        fi
        
        # Remove from sysupgrade.conf
        log "INFO" "Removing entries from /etc/sysupgrade.conf"
        sed -i '/\/etc\/acme/d' /etc/sysupgrade.conf 2>/dev/null || true
        sed -i '/\/etc\/nginx\/conf.d\/gl.conf/d' /etc/sysupgrade.conf 2>/dev/null || true
        
        # Restart nginx
        log "INFO" "Restarting nginx"
        /etc/init.d/nginx restart
        
        log "SUCCESS" "Nginx configuration has been restored to factory default."
        log "SUCCESS" "ACME certificates have been removed."
        log "SUCCESS" "The router is now using self-signed certificates again."
        exit 0
    else
        log "SUCCESS" "Ok, see you next time!"
        exit 0
    fi
}

invoke_help() {
    printf "\033[1mUsage:\033[0m \033[92m./enable-acme.sh\033[0m [\033[93mOPTIONS\033[0m]\n"
    printf "\033[1mOptions:\033[0m\n"
    printf "  \033[93m--renew\033[0m              \033[97mRenew the ACME certificate\033[0m\n"
    printf "  \033[93m--restore\033[0m            \033[97mRestore nginx to factory default configuration\033[0m\n"
    printf "  \033[93m--force\033[0m              \033[97mDo not ask for confirmation\033[0m\n"
    printf "  \033[93m--log\033[0m                \033[97mShow timestamps in log messages\033[0m\n"
    printf "  \033[93m--ascii\033[0m              \033[97mUse ASCII characters instead of emojis\033[0m\n"
    printf "  \033[93m--help\033[0m               \033[97mShow this help\033[0m\n"
}

# Read arguments
for arg in "$@"; do
    case $arg in
    --help)
        invoke_help
        exit 0
        ;;
    --force)
        FORCE=1
        ;;
    --renew)
        RENEW=1
        ;;
    --restore)
        RESTORE=1
        ;;
    --log)
        SHOW_LOG=1
        ;;
    --ascii)
        ASCII_MODE=1
        ;;
    *)
        echo "Unknown argument: $arg"
        invoke_help
        exit 1
        ;;
    esac
done

# Main
# Check if --restore is used
if [ "$RESTORE" -eq 1 ]; then
    restore_configuration
    exit 0
fi

# Check if --renew is used
if [ "$RENEW" -eq 1 ]; then
    invoke_renewal
    exit 0
fi

GL_DDNS=0
#invoke_update "$@"
invoke_intro
preflight_check
if [ "$PREFLIGHT" -eq "1" ]; then
    log "ERROR" "Prerequisites are not met. Exiting"
    exit 1
else
    log "SUCCESS" "Prerequisites are met."
fi

# Collect user preferences before starting
collect_user_preferences

install_prequisites
open_firewall 1
create_acme_config
config_nginx 1
get_acme_cert
config_nginx 0
open_firewall 0
make_permanent
invoke_outro
