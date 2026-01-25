<div align="center">

<img src="images/robbenlogo-glinet-small.webp" width="300" alt="GL.iNet ACME" style="border-radius: 10px; margin: 20px 0;">

## ACME Certificate Manager for GL.iNet Routers

**Automate SSL/TLS certificates for your GL.iNet router with Let's Encrypt!**

[![License](https://img.shields.io/github/license/Admonstrator/glinet-enable-acme?style=for-the-badge)](LICENSE) [![Stars](https://img.shields.io/badge/stars-21-yellow?style=for-the-badge&logo=github)](https://github.com/Admonstrator/glinet-enable-acme/stargazers)

---

## 💖 Support the Project

If you find this tool helpful, consider supporting its development:

[![GitHub Sponsors](https://img.shields.io/badge/GitHub-Sponsors-EA4AAA?style=for-the-badge&logo=github)](https://github.com/sponsors/admonstrator) [![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/admon) [![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/admon) [![PayPal](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/aaronviehl)

</div>

---

## 📖 About

The `enable-acme.sh` script enables the Automated Certificate Management Environment (ACME) for GL.iNet routers. It automatically requests a Let's Encrypt certificate for your router's DDNS domain and configures nginx to use it, providing secure HTTPS access to your router's web interface.

Created by [Admon](https://forum.gl-inet.com/u/admon/) for the GL.iNet community.

> 🎖️ **Community Maintained** – Part of the [GL.iNet Toolbox](https://github.com/Admonstrator/glinet-toolbox) project  
> ⚠️ **Independent Project** – Not officially affiliated with GL.iNet or Let's Encrypt

---

## ✨ Features

- 🔒 **Automatic SSL/TLS Certificates** – Requests and installs Let's Encrypt certificates
- 🔄 **Auto-Renewal** – Certificates renew automatically via cron job with randomized timing
- 🌐 **DDNS Integration** – Works seamlessly with GL.iNet DDNS
- 🌍 **IPv4/IPv6 Dual-Stack** – Full support for both IPv4 and IPv6 networks
- 🔌 **Port Reachability Check** – Verifies port 80 accessibility via GL.iNet Community Reflector service
- ⚙️ **Dual Webserver Support** – Configures both nginx (GL.iNet GUI) and uhttpd (LuCI)
- 🎯 **Dynamic Port Detection** – Automatically detects uhttpd ports and preserves configuration
- 🛡️ **Firewall Management** – Intelligent firewall control during certificate issuance and renewal
- ✅ **Validation Checks** – Verifies DDNS and public IP match before proceeding
- 🕐 **Random Renewal Time** – Daily renewal checks at random times (Let's Encrypt best practice)
- 💾 **Optimized Persistence** – Smart persistence strategy avoiding firmware upgrade conflicts
- 🔧 **Restore Function** – Easy restoration to factory default configuration
- 🤖 **Unattended Mode** – Support for automated installations with --force flag
- 🔄 **Modern acme.sh** – Uses acme.sh v3.0.7 directly (no UCI dependencies)

---

## 📋 Requirements

| Requirement      | Details                                                    |
| ---------------- | ---------------------------------------------------------- |
| **Router**       | GL.iNet router with firmware v4.x or later                 |
| **Internet**     | Working internet connection (IPv4 and/or IPv6)             |
| **DDNS**         | DDNS must be enabled and configured                        |
| **IP Match**     | DDNS IP must match router's public IP (verified by script) |
| **Port 80**      | Port 80 must be reachable from the internet                |
| **Webserver**    | nginx or uhttpd (or both) installed                        |

> ⚠️ **Note:** VPN IP addresses are not supported. The certificate is issued for the router's public IP.
> 
> 💡 **IPv6 Support:** The script automatically detects and uses IPv6 if available alongside IPv4.
> 
> 🔍 **Port Check:** The script uses GL.iNet Reflector service to verify port 80 accessibility before attempting certificate issuance.

---

## 🚀 Quick Start

Run the script without cloning the repository:

```bash
wget -O enable-acme.sh https://get.admon.me/acme-update && sh enable-acme.sh
```

Follow the on-screen instructions to complete the ACME setup.

### Testing Port 80 Reachability

Before installing, you can test if port 80 is reachable from the internet:

```bash
sh enable-acme.sh --reflector
```

This performs a comprehensive connectivity check using the GL.iNet Reflector service.

---

## 📚 Usage

### Installation Steps

1. Download the script onto the router (or use the Quick Start command above)
2. Open an SSH connection to the router
3. Navigate to the directory where the script is located
4. Execute the script:

```bash
sh enable-acme.sh
```

5. Follow the on-screen instructions to complete the ACME process

### Persistence Across Firmware Updates

During installation, you'll be asked if you want to make the installation permanent. If you choose "yes", the certificate files and renewal wrapper script will be preserved during firmware upgrades by adding them to `/etc/sysupgrade.conf`.

This means:

- ✅ Your ACME certificates survive firmware updates
- ✅ Renewal wrapper script is preserved
- ✅ Webserver configurations are NOT persisted (to avoid conflicts)
- ✅ Simply re-run the script after upgrading to reconfigure webservers

> 💡 **Why not persist webserver configs?** GL.iNet firmware updates may change nginx/uhttpd configurations. By not persisting them, we avoid potential conflicts. The script quickly reconfigures webservers using your existing certificates after a firmware upgrade.

### Manual Certificate Renewal

While certificates renew automatically, you can manually trigger renewal:

```bash
sh enable-acme.sh --renew
```

Or if you installed the script to `/usr/bin`:

```bash
/usr/bin/enable-acme --renew
```

---

## 🎛️ Command Line Options

The `enable-acme.sh` script supports the following options:

| Option        | Description                                                 |
| ------------- | ----------------------------------------------------------- |
| `--renew`     | Manually renew the ACME certificate                         |
| `--restore`   | Restore webservers to factory default configuration         |
| `--reflector` | Test port 80 reachability via GL.iNet Reflector service    |
| `--force`     | Skip all confirmation prompts (for unattended installation) |
| `--log`       | Show timestamps in log messages                             |
| `--ascii`     | Use ASCII characters instead of emojis                      |
| `--help`      | Display help message                                        |

### Usage Examples

**Standard Installation:**

```bash
sh enable-acme.sh
```

**Unattended Installation (no prompts):**

```bash
sh enable-acme.sh --force
```

**Renew Certificate:**

```bash
sh enable-acme.sh --renew
```

**Restore to Factory Default:**

```bash
sh enable-acme.sh --restore
```

**ASCII Mode (for older terminals):**

```bash
sh enable-acme.sh --ascii
```

**With Timestamps:**

```bash
sh enable-acme.sh --log
```

---

## 🔄 Automatic Renewal

The certificate will be renewed automatically by a cron job installed by the script. The cron job runs at a randomized daily time (following Let's Encrypt best practices to distribute server load).

**How it works:**

1. ⏰ Cron job triggers at random daily time (between 00:00-23:59)
2. 🛡️ Opens firewall port 80 temporarily
3. 🌐 Disables HTTP on webservers (preserving original port configuration)
4. 🔄 Runs acme.sh renewal (only renews if expiring within 60 days)
5. 🌐 Re-enables HTTP on webservers
6. 🛡️ Closes firewall port 80

**Dual Webserver Support:**

- nginx (GL.iNet GUI): Automatically detected and managed on port 80/443
- uhttpd (LuCI): Automatically detected and managed on configured ports (typically 8080/8443)
- Both webservers receive the same certificate
- Port configuration is dynamically detected and preserved

No manual intervention is required – just let it run!

---

## ⚙️ Restoring Factory Configuration

To restore the webserver configurations to factory default and remove ACME certificates, use the built-in restore function:

```bash
sh enable-acme.sh --restore
```

This will:

- ✅ Restore HTTP access on all webservers (nginx and/or uhttpd)
- ✅ Revert to self-signed certificates
- ✅ Restore original port configurations (dynamically detected)
- ✅ Remove ACME firewall rules
- ✅ Remove ACME configuration and certificates
- ✅ Remove renewal wrapper script and cron job
- ✅ Clean up sysupgrade.conf entries
- ✅ Restart all affected webservers

---

### GL.iNet Community Reflector Integration

The script uses the GL.iNet Community Reflector service for comprehensive connectivity testing:

**Features:**

- Port 80 reachability verification
- IPv4 and IPv6 detection
- Detailed diagnostic feedback

---

## 💡 Getting Help

Need assistance or have questions?

- 💬 [Join the discussion on GL.iNet Forum](https://forum.gl-inet.com/t/script-lets-encrypt-for-gl-inet-router-https-access/41991/) – Community support
- 💬 [Join GL.iNet Discord](https://link.gl-inet.com/website-discord-support) – Real-time chat
- 🐛 [Report issues on GitHub](https://github.com/Admonstrator/glinet-enable-acme/issues) – Bug reports and feature requests
- 📧 Contact via forum private message – For private inquiries

---

## ⚠️ Disclaimer

This script is provided **as-is** without any warranty. Use it at your own risk.

It may potentially:

- 🔥 Break your router, computer, or network
- 🔥 Cause unexpected system behavior
- 🔥 Even burn down your house (okay, probably not, but you get the idea)

**You have been warned!**

Always read the documentation carefully and understand what a script does before running it. Ensure you have sufficient permissions to execute the script. The script behavior may vary depending on the router model and firmware version.

---

## 📜 License

This project is licensed under the **MIT License** – see the [LICENSE](LICENSE) file for details.

---

<div align="center">

## 🧰 Part of the GL.iNet Toolbox

This project is part of a comprehensive collection of tools for GL.iNet routers.

**Explore more tools and utilities:**

[![GL.iNet Toolbox](https://img.shields.io/badge/🧰_GL.iNet_Toolbox-Explore_All_Tools-blue?style=for-the-badge)](https://github.com/Admonstrator/glinet-toolbox)

*Discover Tailscale Updater, AdGuard Home Updater, and more community-driven projects!*

</div>

---

<div align="center">

**Made with ❤️ by [Admon](https://github.com/Admonstrator) for the GL.iNet Community**

⭐ If you find this useful, please star the repository!

</div>

<div align="center">

_Last updated: 2026-01-07_

</div>

<div align="center">

_Last updated: 2026-01-25_

</div>
