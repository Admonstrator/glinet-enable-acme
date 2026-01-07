#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC3036
# Description: This script enables ACME support on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/script-lets-encrypt-for-gl-inet-router-https-access/41991
# Author: Admon

SCRIPT_VERSION="2026.01.07.01"
SCRIPT_NAME="enable-acme.sh"
UPDATE_URL="https://get.admon.me/acme-update"
REFLECTOR_URL="https://glinet-reflector.admon.me/check?ports=80"
ACME_SH="/usr/lib/acme/client/acme.sh"
ACME_HOME="/etc/acme"
ACME_CERT_HOME="/etc/acme"
HAS_NGINX=0
HAS_UHTTPD=0
NGINX_CONFIG=""
UHTTPD_CONFIG="/etc/config/uhttpd"
FORCE=0
RENEW=0
RESTORE=0
SHOW_LOG=0
ASCII_MODE=0
REFLECTOR_CHECK=0
USER_WANTS_PERSISTENCE=""
USER_WANTS_REFLECTOR_CHECK=""
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

    # Ask about reflector check
    if [ "$FORCE" -eq 1 ]; then
        USER_WANTS_REFLECTOR_CHECK="y"
        log "INFO" "--force flag is used. Reflector check will be performed"
    else
        echo "┌────────────────────────────────────────────────────────────────────────────────┐"
        echo "| Port Reachability Check                                                        |"
        echo "| Check if port 80 is reachable from the internet using Admon's reflector.       |"
        echo "| This helps verify that ACME HTTP-01 challenges will succeed.                   |"
        echo "| This check is completely optional and safe.                                    |"
        echo "└────────────────────────────────────────────────────────────────────────────────┘"
        printf "> \033[36mDo you want to check port 80 reachability?\033[0m (Y/n) "
        read -r USER_WANTS_REFLECTOR_CHECK
        USER_WANTS_REFLECTOR_CHECK=$(echo "$USER_WANTS_REFLECTOR_CHECK" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        # Default to yes if user just presses enter
        if [ -z "$USER_WANTS_REFLECTOR_CHECK" ]; then
            USER_WANTS_REFLECTOR_CHECK="y"
        fi
        echo ""
    fi

    # Ask about persistence
    if [ "$FORCE" -eq 1 ]; then
        USER_WANTS_PERSISTENCE="y"
        log "INFO" "--force flag is used. Certificates will be made persistent"
    else
        echo "┌────────────────────────────────────────────────────────────────────────────────┐"
        echo "| Make Certificates Persistent                                                   |"
        echo "| Preserve certificates and renewal script across firmware upgrades.             |"
        echo "| Note: After firmware upgrade, re-run this script to reconfigure webservers.    |"
        echo "└────────────────────────────────────────────────────────────────────────────────┘"
        printf "> \033[36mDo you want to preserve certificates over firmware upgrades?\033[0m (y/N) "
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

issue_acme_cert() {
    log "INFO" "Issuing certificate for $DDNS_DOMAIN"
    
    # Create directories if they don't exist
    mkdir -p "$ACME_HOME"
    mkdir -p "$ACME_CERT_HOME/$DDNS_DOMAIN"
    
    # Issue certificate using acme.sh with Let's Encrypt
    "$ACME_SH" --issue \
        -d "$DDNS_DOMAIN" \
        --standalone \
        --keylength 2048 \
        --server letsencrypt \
        --home "$ACME_HOME" \
        --cert-home "$ACME_CERT_HOME" \
        --httpport 80 \
        --force \
        --no-cron
    
    ACME_EXIT_CODE=$?
    
    if [ $ACME_EXIT_CODE -eq 0 ]; then
        log "SUCCESS" "Certificate issued successfully"
        return 0
    else
        log "ERROR" "Failed to issue certificate (exit code: $ACME_EXIT_CODE)"
        return 1
    fi
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
    /etc/init.d/firewall restart >/dev/null 2>&1
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
    
    # Check if public IP addresses are available (IPv4 and IPv6)
    log "INFO" "Checking public IP addresses"
    PUBLIC_IP_V4=$(sudo -g nonevpn curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    PUBLIC_IP_V6=$(sudo -g nonevpn curl -6 -s --max-time 5 https://api64.ipify.org 2>/dev/null || curl -6 -s --max-time 5 https://api64.ipify.org 2>/dev/null || echo "")
    
    if [ -z "$PUBLIC_IP_V4" ] && [ -z "$PUBLIC_IP_V6" ]; then
        log "ERROR" "Could not get any public IP address. Please check your internet connection."
        PREFLIGHT=1
    else
        if [ -n "$PUBLIC_IP_V4" ]; then
            log "SUCCESS" "Public IPv4 address: $PUBLIC_IP_V4"
        else
            log "INFO" "No IPv4 connectivity detected (IPv6-only network or no IPv4 available)"
        fi
        if [ -n "$PUBLIC_IP_V6" ]; then
            log "SUCCESS" "Public IPv6 address: $PUBLIC_IP_V6"
        else
            log "INFO" "No IPv6 connectivity detected (IPv4-only network or no IPv6 available)"
        fi
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

    # Query both A (IPv4) and AAAA (IPv6) records
    DDNS_IP_V4=$(dig +short A "$DDNS_DOMAIN" @ns1.glddns.com 2>/dev/null | head -n1 || echo "")
    DDNS_IP_V6=$(dig +short AAAA "$DDNS_DOMAIN" @ns1.glddns.com 2>/dev/null | head -n1 || echo "")
    
    if [ -z "$DDNS_IP_V4" ] && [ -z "$DDNS_IP_V6" ]; then
        log "ERROR" "No DDNS IP addresses found (neither IPv4 nor IPv6). Please enable DDNS first."
        PREFLIGHT=1
    else
        if [ -n "$DDNS_IP_V4" ]; then
            log "SUCCESS" "DDNS IPv4 address: $DDNS_IP_V4"
        else
            log "INFO" "No DDNS IPv4 (A) record configured"
        fi
        if [ -n "$DDNS_IP_V6" ]; then
            log "SUCCESS" "DDNS IPv6 address: $DDNS_IP_V6"
        else
            log "INFO" "No DDNS IPv6 (AAAA) record configured"
        fi
    fi
    
    # Get only the first part of the domain name
    DDNS_DOMAIN_PREFIX=$(echo $DDNS_DOMAIN | cut -d'.' -f1)
    log "SUCCESS" "Prefix of the DDNS domain name: $DDNS_DOMAIN_PREFIX"
    
    # Check if at least one public IP matches the corresponding DDNS IP
    IP_MATCH_V4=0
    IP_MATCH_V6=0
    IP_MISMATCH=0
    
    if [ -n "$PUBLIC_IP_V4" ] && [ -n "$DDNS_IP_V4" ]; then
        if [ "$PUBLIC_IP_V4" = "$DDNS_IP_V4" ]; then
            IP_MATCH_V4=1
            log "SUCCESS" "Public IPv4 matches DDNS IPv4"
        else
            log "ERROR" "Public IPv4 ($PUBLIC_IP_V4) does not match DDNS IPv4 ($DDNS_IP_V4)"
            IP_MISMATCH=1
        fi
    fi
    
    if [ -n "$PUBLIC_IP_V6" ] && [ -n "$DDNS_IP_V6" ]; then
        if [ "$PUBLIC_IP_V6" = "$DDNS_IP_V6" ]; then
            IP_MATCH_V6=1
            log "SUCCESS" "Public IPv6 matches DDNS IPv6"
        else
            log "ERROR" "Public IPv6 ($PUBLIC_IP_V6) does not match DDNS IPv6 ($DDNS_IP_V6)"
            IP_MISMATCH=1
        fi
    fi
    
    # At least one IP version must match, and no mismatches allowed
    if [ "$IP_MISMATCH" -eq 1 ]; then
        log "ERROR" "IP address mismatch detected - DDNS synchronization issue or CGNAT"
        PREFLIGHT=1
    elif [ "$IP_MATCH_V4" -eq 0 ] && [ "$IP_MATCH_V6" -eq 0 ]; then
        # No matches at all - but maybe no IPs to compare
        if [ -n "$PUBLIC_IP_V4" ] || [ -n "$PUBLIC_IP_V6" ]; then
            log "ERROR" "No public IP matches the DDNS IP!"
            PREFLIGHT=1
        fi
    else
        log "SUCCESS" "IP verification successful - DDNS is working correctly"
    fi
    
    # Check if required files and directories exist
    log "INFO" "Checking if required files and directories exist"
    
    # Detect webserver(s) - nginx and/or uhttpd
    if [ -f "/etc/init.d/nginx" ]; then
        if [ -f "/etc/nginx/conf.d/gl.conf" ]; then
            NGINX_CONFIG="/etc/nginx/conf.d/gl.conf"
            log "SUCCESS" "Detected nginx (GL.iNet GUI)"
        elif [ -f "/etc/nginx/nginx.conf" ]; then
            NGINX_CONFIG="/etc/nginx/nginx.conf"
            log "SUCCESS" "Detected nginx (generic)"
        fi
        if [ -n "$NGINX_CONFIG" ]; then
            HAS_NGINX=1
        fi
    fi
    
    if [ -f "/etc/init.d/uhttpd" ] && [ -f "/etc/config/uhttpd" ]; then
        HAS_UHTTPD=1
        # Save current HTTP ports for later restoration
        UHTTPD_PORTS=$(uci get uhttpd.main.listen_http 2>/dev/null | tr ' ' '\n' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
        log "SUCCESS" "Detected uhttpd (OpenWrt LuCI)"
        if [ -n "$UHTTPD_PORTS" ]; then
            log "INFO" "uhttpd HTTP ports: $UHTTPD_PORTS"
        fi
    fi
    
    if [ $HAS_NGINX -eq 0 ] && [ $HAS_UHTTPD -eq 0 ]; then
        log "ERROR" "No supported webserver found (nginx or uhttpd)"
        PREFLIGHT=1
    elif [ $HAS_NGINX -eq 1 ] && [ $HAS_UHTTPD -eq 1 ]; then
        log "INFO" "Both nginx and uhttpd detected - will configure both"
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
    local required_commands="wget curl sed grep awk dig"
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
    log "INFO" "Installing acme.sh"
    
    # Check if acme.sh is already installed
    if [ -f "$ACME_SH" ]; then
        log "SUCCESS" "acme.sh is already installed"
        return 0
    fi
    
    # Install acme package
    opkg update >/dev/null 2>&1
    opkg install acme >/dev/null 2>&1
    
    # Verify installation
    if [ ! -f "$ACME_SH" ]; then
        log "ERROR" "Failed to install acme.sh"
        return 1
    fi
    
    log "SUCCESS" "acme.sh installed successfully"
}

config_webserver() {
    if [ $HAS_NGINX -eq 1 ]; then
        if [ "$1" -eq 1 ]; then
            log "INFO" "Disabling HTTP access on nginx"
            sed -i 's/listen 80;/#listen 80;/g' "$NGINX_CONFIG"
            sed -i 's/listen \[::\]:80;/#listen \[::\]:80;/g' "$NGINX_CONFIG"
        else
            log "INFO" "Enabling HTTP access on nginx"
            sed -i 's/#listen 80;/listen 80;/g' "$NGINX_CONFIG"
            sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' "$NGINX_CONFIG"
        fi
        log "INFO" "Restarting nginx"
        /etc/init.d/nginx restart
    fi
    
    if [ $HAS_UHTTPD -eq 1 ]; then
        if [ "$1" -eq 1 ]; then
            log "INFO" "Disabling HTTP access on uhttpd"
            uci delete uhttpd.main.listen_http 2>/dev/null || true
            uci commit uhttpd
        else
            log "INFO" "Enabling HTTP access on uhttpd"
            uci -q delete uhttpd.main.listen_http
            # Restore saved ports or use defaults
            if [ -n "$UHTTPD_PORTS" ]; then
                for port in $UHTTPD_PORTS; do
                    uci add_list uhttpd.main.listen_http="$port"
                done
            else
                # Fallback to common defaults
                uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
                uci add_list uhttpd.main.listen_http='[::]:8080'
            fi
            uci commit uhttpd
        fi
        log "INFO" "Restarting uhttpd"
        /etc/init.d/uhttpd restart
    fi
}

install_cert_to_webserver() {
    log "INFO" "Installing certificate to webserver(s)"
    FAIL=0
    
    if [ $HAS_NGINX -eq 1 ]; then
        log "INFO" "Installing certificate for nginx"
        "$ACME_SH" --install-cert \
            -d "$DDNS_DOMAIN" \
            --cert-file "/etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.cer" \
            --key-file "/etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key" \
            --fullchain-file "/etc/acme/$DDNS_DOMAIN/fullchain.cer" \
            --reloadcmd "/etc/init.d/nginx restart" \
            --home "$ACME_HOME"
        
        if [ $? -eq 0 ]; then
            sed -i "s|ssl_certificate .*;|ssl_certificate /etc/acme/$DDNS_DOMAIN/fullchain.cer;|g" "$NGINX_CONFIG"
            sed -i "s|ssl_certificate_key .*;|ssl_certificate_key /etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key;|g" "$NGINX_CONFIG"
            /etc/init.d/nginx restart
            log "SUCCESS" "Certificate installed successfully for nginx"
        else
            log "ERROR" "Failed to install certificate for nginx"
            FAIL=1
        fi
    fi
    
    if [ $HAS_UHTTPD -eq 1 ]; then
        log "INFO" "Installing certificate for uhttpd"
        "$ACME_SH" --install-cert \
            -d "$DDNS_DOMAIN" \
            --cert-file "/etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.cer" \
            --key-file "/etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key" \
            --fullchain-file "/etc/acme/$DDNS_DOMAIN/fullchain.cer" \
            --reloadcmd "/etc/init.d/uhttpd restart" \
            --home "$ACME_HOME"
        
        if [ $? -eq 0 ]; then
            uci set uhttpd.main.cert="/etc/acme/$DDNS_DOMAIN/fullchain.cer"
            uci set uhttpd.main.key="/etc/acme/$DDNS_DOMAIN/$DDNS_DOMAIN.key"
            uci commit uhttpd
            /etc/init.d/uhttpd restart
            log "SUCCESS" "Certificate installed successfully for uhttpd"
        else
            log "ERROR" "Failed to install certificate for uhttpd"
            FAIL=1
        fi
    fi
    
    if [ $FAIL -eq 1 ]; then
        return 1
    fi
    return 0
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
        log "INFO" "Automatic renewal is configured via cron job (daily)."
        echo ""
        log "INFO" "After firmware upgrade: Re-run this script to reconfigure webservers."
        log "INFO" "Certificates will be preserved and reused automatically."
        echo ""
        echo "If you like this script, please consider supporting the project:"
        echo "  - GitHub: github.com/sponsors/admonstrator"
        echo "  - Ko-fi: ko-fi.com/admon"
        echo "  - Buy Me a Coffee: buymeacoffee.com/admon"
        exit 0
    fi
}

install_cronjob() {
    log "INFO" "Installing ACME renewal cron job"
    
    # Create wrapper script for renewal that handles firewall and webservers
    cat > /usr/bin/acme-renew-wrapper.sh << 'EOF'
#!/bin/sh
# ACME Certificate Renewal Wrapper
# Opens firewall, stops webservers, renews certificates, restarts webservers

ACME_SH="/usr/lib/acme/client/acme.sh"
ACME_HOME="/etc/acme"
HAS_NGINX=0
HAS_UHTTPD=0
NGINX_CONFIG=""

# Detect webservers
if [ -f "/etc/init.d/nginx" ]; then
    if [ -f "/etc/nginx/conf.d/gl.conf" ]; then
        NGINX_CONFIG="/etc/nginx/conf.d/gl.conf"
    elif [ -f "/etc/nginx/nginx.conf" ]; then
        NGINX_CONFIG="/etc/nginx/nginx.conf"
    fi
    if [ -n "$NGINX_CONFIG" ]; then
        HAS_NGINX=1
    fi
fi

if [ -f "/etc/init.d/uhttpd" ] && [ -f "/etc/config/uhttpd" ]; then
    HAS_UHTTPD=1
fi

# Save uhttpd ports before disabling
if [ $HAS_UHTTPD -eq 1 ]; then
    UHTTPD_PORTS=$(uci get uhttpd.main.listen_http 2>/dev/null)
fi

# Open firewall port 80
uci set firewall.acme.enabled='1' 2>/dev/null
uci commit firewall 2>/dev/null
/etc/init.d/firewall restart >/dev/null 2>&1

# Disable HTTP on webservers
if [ $HAS_NGINX -eq 1 ]; then
    sed -i 's/listen 80;/#listen 80;/g' "$NGINX_CONFIG"
    sed -i 's/listen \[::\]:80;/#listen \[::\]:80;/g' "$NGINX_CONFIG"
    /etc/init.d/nginx restart >/dev/null 2>&1
fi

if [ $HAS_UHTTPD -eq 1 ]; then
    uci delete uhttpd.main.listen_http 2>/dev/null
    uci commit uhttpd 2>/dev/null
    /etc/init.d/uhttpd restart >/dev/null 2>&1
fi

# Wait for services to restart
sleep 3

# Run ACME renewal
"$ACME_SH" --cron --home "$ACME_HOME" >/dev/null 2>&1

# Re-enable HTTP on webservers
if [ $HAS_NGINX -eq 1 ]; then
    sed -i 's/#listen 80;/listen 80;/g' "$NGINX_CONFIG"
    sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' "$NGINX_CONFIG"
    /etc/init.d/nginx restart >/dev/null 2>&1
fi

if [ $HAS_UHTTPD -eq 1 ]; then
    uci -q delete uhttpd.main.listen_http
    # Restore saved ports
    if [ -n "$UHTTPD_PORTS" ]; then
        for port in $UHTTPD_PORTS; do
            uci add_list uhttpd.main.listen_http="$port"
        done
    else
        # Fallback to defaults if ports couldn't be saved
        uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
        uci add_list uhttpd.main.listen_http='[::]:8080'
    fi
    uci commit uhttpd 2>/dev/null
    /etc/init.d/uhttpd restart >/dev/null 2>&1
fi

# Close firewall port 80 again
uci set firewall.acme.enabled='0' 2>/dev/null
uci commit firewall 2>/dev/null
/etc/init.d/firewall restart >/dev/null 2>&1
EOF

    chmod +x /usr/bin/acme-renew-wrapper.sh
    log "SUCCESS" "Created renewal wrapper script"
    
    # Remove any existing acme.sh cronjobs
    "$ACME_SH" --uninstall-cronjob --home "$ACME_HOME" 2>/dev/null || true
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        crontab -l 2>/dev/null | grep -v "acme.sh" | crontab - 2>/dev/null || true
    fi
    
    # Generate random time to distribute load (Let's Encrypt recommendation)
    RANDOM_HOUR=$((RANDOM % 24))
    RANDOM_MINUTE=$((RANDOM % 60))
    
    # Install our custom cronjob with random time
    if crontab -l 2>/dev/null | grep -q "acme-renew-wrapper"; then
        log "INFO" "Cron job already exists"
    else
        (
            crontab -l 2>/dev/null
            echo "$RANDOM_MINUTE $RANDOM_HOUR * * * /usr/bin/acme-renew-wrapper.sh"
        ) | crontab -
        log "SUCCESS" "Renewal cron job installed (daily at $(printf '%02d:%02d' $RANDOM_HOUR $RANDOM_MINUTE))"
    fi
}

install_script() {
    # Copying the script to /usr/bin
    log "INFO" "Copying the script to /usr/bin"
    cp $0 /usr/bin/enable-acme
    chmod +x /usr/bin/enable-acme
    log "SUCCESS" "Script installed successfully."
}

invoke_renewal() {
    log "INFO" "Renewing certificates"
    
    # Detect webservers if not already set
    if [ $HAS_NGINX -eq 0 ] && [ $HAS_UHTTPD -eq 0 ]; then
        if [ -f "/etc/init.d/nginx" ]; then
            if [ -f "/etc/nginx/conf.d/gl.conf" ]; then
                NGINX_CONFIG="/etc/nginx/conf.d/gl.conf"
            elif [ -f "/etc/nginx/nginx.conf" ]; then
                NGINX_CONFIG="/etc/nginx/nginx.conf"
            fi
            if [ -n "$NGINX_CONFIG" ]; then
                HAS_NGINX=1
            fi
        fi
        if [ -f "/etc/init.d/uhttpd" ]; then
            HAS_UHTTPD=1
        fi
    fi
    
    # Save uhttpd ports before disabling
    if [ $HAS_UHTTPD -eq 1 ]; then
        UHTTPD_PORTS=$(uci get uhttpd.main.listen_http 2>/dev/null | tr ' ' '\n' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
    fi
    
    # Open firewall for renewal
    log "INFO" "Opening firewall port 80 for renewal"
    open_firewall 1
    
    # Disable HTTP on webservers
    if [ $HAS_NGINX -eq 1 ]; then
        log "INFO" "Disabling HTTP on nginx"
        sed -i 's/listen 80;/#listen 80;/g' "$NGINX_CONFIG"
        sed -i 's/listen \\[::\\]:80;/#listen \\[::\\]:80;/g' "$NGINX_CONFIG"
        /etc/init.d/nginx restart
    fi
    
    if [ $HAS_UHTTPD -eq 1 ]; then
        log "INFO" "Disabling HTTP on uhttpd"
        uci delete uhttpd.main.listen_http 2>/dev/null || true
        uci commit uhttpd
        /etc/init.d/uhttpd restart
    fi
    
    sleep 3
    
    # Run renewal
    "$ACME_SH" --cron --home "$ACME_HOME"
    RENEWAL_EXIT=$?
    
    # Re-enable HTTP on webservers
    if [ $HAS_NGINX -eq 1 ]; then
        log "INFO" "Re-enabling HTTP on nginx"
        sed -i 's/#listen 80;/listen 80;/g' "$NGINX_CONFIG"
        sed -i 's/#listen \\[::\\]:80;/listen \\[::\\]:80;/g' "$NGINX_CONFIG"
        /etc/init.d/nginx restart
    fi
    
    if [ $HAS_UHTTPD -eq 1 ]; then
        log "INFO" "Re-enabling HTTP on uhttpd"
        uci -q delete uhttpd.main.listen_http
        # Restore saved ports
        if [ -n "$UHTTPD_PORTS" ]; then
            for port in $UHTTPD_PORTS; do
                uci add_list uhttpd.main.listen_http="$port"
            done
        else
            # Fallback to defaults
            uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
            uci add_list uhttpd.main.listen_http='[::]:8080'
        fi
        uci commit uhttpd
        /etc/init.d/uhttpd restart
    fi
    
    # Close firewall again
    log "INFO" "Closing firewall port 80"
    open_firewall 0
    
    if [ $RENEWAL_EXIT -eq 0 ]; then
        log "SUCCESS" "Certificate renewal completed"
    else
        log "ERROR" "Certificate renewal failed"
        return 1
    fi
}

make_permanent() {
    # Use the pre-collected user preference for persistence
    if [ "$USER_WANTS_PERSISTENCE" != "${USER_WANTS_PERSISTENCE#[y]}" ]; then
        log "INFO" "Making certificates and renewal script persistent"
        log "INFO" "Modifying /etc/sysupgrade.conf"
        
        # Preserve certificates (important due to Let's Encrypt rate limits)
        if ! grep -q "/etc/acme" /etc/sysupgrade.conf; then
            echo "/etc/acme" >>/etc/sysupgrade.conf
        fi
        
        # Preserve renewal wrapper script
        if ! grep -q "/usr/bin/acme-renew-wrapper.sh" /etc/sysupgrade.conf; then
            echo "/usr/bin/acme-renew-wrapper.sh" >>/etc/sysupgrade.conf
        fi
        log "SUCCESS" "Certificates and renewal script will be preserved across firmware upgrades"
    fi
}

call_reflector() {
    # Admon hosts an public reflector service to check the reachability of your public IP
    # This is completely optional but will help to check if your router is reachable from the internet and ACME challenges can be completed.
    log "INFO" "Calling reflector service to check public IP reachability"
    
    # Call reflector service for port 80 (required for ACME HTTP-01 challenge)
    REFLECTOR_RESPONSE=$(curl -s -m 10 "$REFLECTOR_URL" 2>/dev/null)
    
    # Check if we got any response
    if [ -z "$REFLECTOR_RESPONSE" ]; then
        log "WARNING" "Could not reach reflector service (timeout or network error)"
        log "INFO" "Skipping port reachability check - continuing anyway"
        return 0
    fi
    
    # Parse JSON response (without requiring jq)
    # Extract success field first to verify valid response
    SUCCESS=$(echo "$REFLECTOR_RESPONSE" | grep -o '"success":[a-z]*' | cut -d':' -f2)
    
    if [ "$SUCCESS" != "true" ]; then
        # Check if there's an error message in the response
        ERROR_MSG=$(echo "$REFLECTOR_RESPONSE" | grep -o '"error":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$ERROR_MSG" ]; then
            log "WARNING" "Reflector service returned error: $ERROR_MSG"
        else
            log "WARNING" "Reflector service returned unexpected response"
        fi
        log "INFO" "Skipping port reachability check - continuing anyway"
        return 0
    fi
    
    # Extract client_ip and IP version (optional fields)
    CLIENT_IP=$(echo "$REFLECTOR_RESPONSE" | grep -o '"client_ip":"[^"]*"' | cut -d'"' -f4)
    IP_VERSION=$(echo "$REFLECTOR_RESPONSE" | grep -o '"ip_version":[0-9]*' | cut -d':' -f2)
    
    if [ -n "$CLIENT_IP" ]; then
        if [ -n "$IP_VERSION" ]; then
            log "INFO" "Reflector detected your IP: $CLIENT_IP (IPv$IP_VERSION)"
            # Warn if IPv6 is being used (might indicate connectivity issues)
            if [ "$IP_VERSION" = "6" ]; then
                log "INFO" "Note: Your connection is using IPv6"
            fi
        else
            log "INFO" "Reflector detected your IP: $CLIENT_IP"
        fi
    fi
    
    # Check if results field exists
    if ! echo "$REFLECTOR_RESPONSE" | grep -q '"results"'; then
        log "WARNING" "No port check results in reflector response"
        log "INFO" "Skipping port reachability check - continuing anyway"
        return 0
    fi
    
    # Check port 80 reachability
    PORT80_REACHABLE=$(echo "$REFLECTOR_RESPONSE" | grep -o '"80"[[:space:]]*:[[:space:]]*{[^}]*"reachable"[[:space:]]*:[[:space:]]*[a-z]*' | grep -o 'reachable"[[:space:]]*:[[:space:]]*[a-z]*' | cut -d':' -f2 | tr -d ' ')
    
    # If we couldn't parse port 80 status, check if it exists in results
    if [ -z "$PORT80_REACHABLE" ]; then
        if echo "$REFLECTOR_RESPONSE" | grep -q '"80"'; then
            log "WARNING" "Could not parse port 80 reachability status"
        else
            log "WARNING" "Port 80 not found in reflector response"
        fi
        log "INFO" "Skipping port reachability check - continuing anyway"
        return 0
    fi
    
    # Extract additional port 80 information (optional)
    PORT80_ERROR=$(echo "$REFLECTOR_RESPONSE" | grep -o '"80"[[:space:]]*:[[:space:]]*{[^}]*"error":"[^"]*"' | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    PORT80_LATENCY=$(echo "$REFLECTOR_RESPONSE" | grep -o '"80"[[:space:]]*:[[:space:]]*{[^}]*"latency_ms"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o 'latency_ms"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    
    # Display results
    if [ "$PORT80_REACHABLE" = "true" ]; then
        if [ -n "$PORT80_LATENCY" ] && [ "$PORT80_LATENCY" -gt 0 ]; then
            log "SUCCESS" "Port 80 is reachable from the internet (${PORT80_LATENCY}ms latency)"
        else
            log "SUCCESS" "Port 80 is reachable from the internet"
        fi
    else
        log "ERROR" "Port 80 is NOT reachable from the internet"
        if [ -n "$PORT80_ERROR" ]; then
            log "ERROR" "Error: $PORT80_ERROR"
        fi
        log "ERROR" "ACME challenge might fail. Please check your port forwarding"
        log "ERROR" "Troubleshooting tips:"
        log "ERROR" "  1. Check if your router has a public IP address"
        log "ERROR" "  2. Configure port forwarding on your upstream router/modem"
        log "ERROR" "  3. Check if your ISP blocks incoming connections (CGNAT)"
        log "ERROR" "  4. Verify firewall rules allow incoming traffic on port 80"
        echo ""
        return 1
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
    printf "\033[31mWARNING: This will restore the webserver configuration to factory default!\033[0m\n"
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
        # Detect webserver(s) if not already set
        if [ $HAS_NGINX -eq 0 ] && [ $HAS_UHTTPD -eq 0 ]; then
            if [ -f "/etc/init.d/nginx" ]; then
                if [ -f "/etc/nginx/conf.d/gl.conf" ]; then
                    NGINX_CONFIG="/etc/nginx/conf.d/gl.conf"
                elif [ -f "/etc/nginx/nginx.conf" ]; then
                    NGINX_CONFIG="/etc/nginx/nginx.conf"
                fi
                if [ -n "$NGINX_CONFIG" ]; then
                    HAS_NGINX=1
                    log "INFO" "Detected nginx"
                fi
            fi
            if [ -f "/etc/init.d/uhttpd" ] && [ -f "/etc/config/uhttpd" ]; then
                HAS_UHTTPD=1
                # Get current ports for restoration
                UHTTPD_PORTS=$(uci get uhttpd.main.listen_http 2>/dev/null | tr ' ' '\n' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
                log "INFO" "Detected uhttpd"
            fi
            
            if [ $HAS_NGINX -eq 0 ] && [ $HAS_UHTTPD -eq 0 ]; then
                log "ERROR" "No supported webserver found (nginx or uhttpd)"
                exit 1
            fi
        fi
        
        log "INFO" "Restoring webserver configuration(s) to factory default"
        
        if [ $HAS_NGINX -eq 1 ]; then
            log "INFO" "Restoring HTTP access on nginx port 80"
            sed -i 's/#listen 80;/listen 80;/g' "$NGINX_CONFIG"
            sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' "$NGINX_CONFIG"
            
            log "INFO" "Restoring original self-signed certificates for nginx"
            sed -i 's|ssl_certificate .*;|ssl_certificate /etc/nginx/nginx.cer;|g' "$NGINX_CONFIG"
            sed -i 's|ssl_certificate_key .*;|ssl_certificate_key /etc/nginx/nginx.key;|g' "$NGINX_CONFIG"
        fi
        
        if [ $HAS_UHTTPD -eq 1 ]; then
            log "INFO" "Restoring HTTP access on uhttpd"
            uci -q delete uhttpd.main.listen_http
            # Restore to saved ports or use defaults
            if [ -n "$UHTTPD_PORTS" ]; then
                for port in $UHTTPD_PORTS; do
                    uci add_list uhttpd.main.listen_http="$port"
                done
            else
                # Fallback to common defaults
                uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
                uci add_list uhttpd.main.listen_http='[::]:8080'
            fi
            
            log "INFO" "Restoring original self-signed certificates for uhttpd"
            if [ -f "/etc/uhttpd.crt" ]; then
                uci set uhttpd.main.cert='/etc/uhttpd.crt'
                uci set uhttpd.main.key='/etc/uhttpd.key'
            fi
            uci commit uhttpd
        fi
        
        # Remove firewall rule for ACME
        log "INFO" "Removing ACME firewall rule"
        uci delete firewall.acme 2>/dev/null || true
        uci commit firewall
        /etc/init.d/firewall restart >/dev/null 2>&1
        
        # Remove ACME certificates
        log "INFO" "Removing ACME certificates"
        if [ -d "$ACME_CERT_HOME" ]; then
            rm -rf "$ACME_CERT_HOME"/* 2>/dev/null || true
        fi
        
        # Remove cronjob and wrapper script
        log "INFO" "Removing ACME cronjob"
        "$ACME_SH" --uninstall-cronjob --home "$ACME_HOME" 2>/dev/null || true
        # Remove any cron entries
        if crontab -l 2>/dev/null | grep -q "acme"; then
            crontab -l 2>/dev/null | grep -v "acme.sh" | grep -v "acme-renew-wrapper" | crontab - 2>/dev/null || true
        fi
        # Remove wrapper script
        rm -f /usr/bin/acme-renew-wrapper.sh 2>/dev/null || true
        
        # Remove from sysupgrade.conf
        log "INFO" "Removing entries from /etc/sysupgrade.conf"
        sed -i '/\/etc\/acme/d' /etc/sysupgrade.conf 2>/dev/null || true
        sed -i '/acme-renew-wrapper/d' /etc/sysupgrade.conf 2>/dev/null || true
        
        # Restart webserver(s)
        if [ $HAS_NGINX -eq 1 ]; then
            log "INFO" "Restarting nginx"
            /etc/init.d/nginx restart
        fi
        if [ $HAS_UHTTPD -eq 1 ]; then
            log "INFO" "Restarting uhttpd"
            /etc/init.d/uhttpd restart
        fi
        
        log "SUCCESS" "Webserver configuration has been restored to factory default."
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
    printf "  \033[93m--restore\033[0m            \033[97mRestore webserver to factory default configuration\033[0m\n"
    printf "  \033[93m--reflector\033[0m          \033[97mCheck port 80 reachability only (no installation)\033[0m\n"
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
    --reflector)
        REFLECTOR_CHECK=1
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




# ------------------------------------
# ---- MAIN SCRIPT STARTS HERE -------
# ------------------------------------

# Handle special operation modes
if [ "$RESTORE" -eq 1 ] || [ "$RENEW" -eq 1 ] || [ "$REFLECTOR_CHECK" -eq 1 ]; then
    case 1 in
        "$RESTORE")
            restore_configuration
            ;;
        "$RENEW")
            invoke_renewal
            ;;
        "$REFLECTOR_CHECK")
            invoke_intro
            call_reflector
            ;;
    esac
    exit $?
fi

GL_DDNS=0
invoke_update "$@"

invoke_intro
preflight_check
if [ "$PREFLIGHT" -eq "1" ]; then
    log "ERROR" "Prerequisites are not met. Exiting"
    exit 1
fi
log "SUCCESS" "Prerequisites are met."

collect_user_preferences

install_prequisites
open_firewall 1

# Call reflector service if user wants it (after firewall rules are set)
if [ "$USER_WANTS_REFLECTOR_CHECK" = "y" ]; then
    if ! call_reflector; then
        log "ERROR" "Port 80 is not reachable - ACME challenge will fail"
        log "INFO" "Cleaning up firewall rules"
        open_firewall 0
        exit 1
    fi
fi

# Issue certificate
config_webserver 1
if ! issue_acme_cert; then
    log "ERROR" "Failed to issue certificate"
    config_webserver 0
    open_firewall 0
    exit 1
fi

# Install certificate to webserver
if ! install_cert_to_webserver; then
    log "ERROR" "Failed to install certificate to webserver"
    config_webserver 0
    open_firewall 0
    exit 1
fi

config_webserver 0
open_firewall 0
make_permanent
invoke_outro
