<div align="center">

<img src="images/robbenlogo-glinet-small.webp" width="300" alt="GL.iNet ACME" style="border-radius: 10px; margin: 20px 0;">

## ACME Certificate Manager for GL.iNet Routers

**Automate SSL/TLS certificates for your GL.iNet router with Let's Encrypt!**

[![License](https://img.shields.io/github/license/Admonstrator/glinet-enable-acme?style=for-the-badge)](LICENSE) [![Stars](https://img.shields.io/github/stars/Admonstrator/glinet-enable-acme?style=for-the-badge&logo=github)](https://github.com/Admonstrator/glinet-enable-acme/stargazers)

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
- 🔄 **Auto-Renewal** – Certificates renew automatically via cron job
- 🌐 **DDNS Integration** – Works seamlessly with GL.iNet DDNS
- ⚙️ **Nginx Configuration** – Automatically configures nginx for HTTPS
- ✅ **Validation Checks** – Verifies DDNS and public IP match before proceeding
- 🕐 **Daily Checks** – Renewal cron job runs daily at 00:00

---

## 📋 Requirements

| Requirement | Details |
|-------------|---------|
| **Router** | GL.iNet router with latest firmware version |
| **Internet** | Working internet connection |
| **DDNS** | DDNS must be enabled and configured |
| **IP Match** | DDNS IP must match router's public IP (verified by script) |

> ⚠️ **Note:** VPN IP addresses are not supported. The certificate is issued for the router's public IP.

---

## 🚀 Quick Start

Run the script without cloning the repository:

```bash
wget -O enable-acme.sh https://raw.githubusercontent.com/Admonstrator/glinet-enable-acme/main/enable-acme.sh && sh enable-acme.sh
```

Follow the on-screen instructions to complete the ACME setup.

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

| Option | Description |
|--------|-------------|
| `--renew` | Manually renew the ACME certificate |
| `--restore` | Restore nginx to factory default configuration |
| `--force` | Skip all confirmation prompts (for unattended installation) |
| `--log` | Show timestamps in log messages |
| `--ascii` | Use ASCII characters instead of emojis |
| `--help` | Display help message |

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

The certificate will be renewed automatically by a cron job installed by the script. The cron job checks for renewal every day at 00:00.

No manual intervention is required – just let it run!

---

## ⚙️ Restoring Factory Configuration

To restore the nginx configuration to factory default and remove ACME certificates, use the built-in restore function:

```bash
sh enable-acme.sh --restore
```

This will:
- ✅ Restore HTTP access on port 80
- ✅ Revert to self-signed certificates
- ✅ Remove ACME firewall rules
- ✅ Remove ACME configuration
- ✅ Remove renewal cron job
- ✅ Clean up sysupgrade.conf entries
- ✅ Restart nginx

You can also manually revert the changes with these commands:

```bash
sed -i 's/#listen 80;/listen 80;/g' /etc/nginx/conf.d/gl.conf
sed -i 's/#listen \[::\]:80;/listen \[::\]:80;/g' /etc/nginx/conf.d/gl.conf
sed -i 's|ssl_certificate .*;|ssl_certificate /etc/nginx/nginx.cer;|g' /etc/nginx/conf.d/gl.conf
sed -i 's|ssl_certificate_key .*;|ssl_certificate_key /etc/nginx/nginx.key;|g' /etc/nginx/conf.d/gl.conf
/etc/init.d/nginx restart
```

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

_Last updated: 2025-11-29_

</div>
