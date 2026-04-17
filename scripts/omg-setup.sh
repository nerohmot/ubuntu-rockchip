#!/bin/bash
set -e

echo "----------------------------------------------------"
echo "⚓ OPEN MARINE GATEWAY: CUSTOM SETUP STARTING"
echo "----------------------------------------------------"

# 1. 🔥 DE-SNAP-IFYING (Performance Optimization)
echo "🧹 Removing Snap and pinning it to prevent re-installation..."
snap list | awk 'NR>1 {print $1}' | xargs -n1 snap remove || true
apt-get purge -y snapd
apt-get autoremove -y
rm -rf /root/snap /var/snap /var/lib/snapd /var/cache/snapd

# 🚫 EXTENDED Blacklist (prevents accidental re-install)
mkdir -p /etc/apt/preferences.d
cat <<EOF > /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
Package: chromium-browser
Pin: release a=*
Pin-Priority: -10
Package: firefox
Pin: release a=*
Pin-Priority: -10
Package: cups
Pin: release a=*
Pin-Priority: -10
Package: lxd
Pin: release a=*
Pin-Priority: -10
EOF

# 2. 🦊 REPOSITORIES SETUP
echo "🦊 Adding Firefox ESR and Node.js repositories..."
add-apt-repository -y ppa:mozillateam/ppa
curl -fsSL https://nodesource.com | bash -
apt-get update

# 3. 💾 UNIFIED DOWNLOAD & INSTALL (Air-Gapped Strategy)
echo "💾 Stage 1: Downloading all dependencies to local cache..."
mkdir -p /opt/omg/pkg
cd /opt/omg/pkg

# Single source of truth for all packages
PKG_LIST="
    plymouth 
    plymouth-themes 
    qrencode 
    imagemagick 
    expect 
    hostapd 
    dnsmasq 
    can-utils 
    gpsd 
    i2c-tools 
    bash-completion 
    firefox-esr 
    cups-daemon 
    cups-client 
    cups-common 
    nodejs
"

apt-get download $PKG_LIST

echo "📦 Stage 2: Installing packages from local cache..."
# Install directly from the .deb files we just downloaded
dpkg -i /opt/omg/pkg/*.deb || apt-get install -f -y
cd - > /dev/null

# 4. ⚓ INSTALL SIGNAL K
echo "📦 Installing Signal K Server..."
npm install -g --unsafe-perm signalk-server

# 5. 📺 CONFIGURE AUTO-START KIOSK
echo "📺 Setting up Signal K Kiosk mode..."
mkdir -p /home/omg/.config/autostart
cat <<EOF > /home/omg/.config/autostart/signalk-kiosk.desktop
[Desktop Entry]
Type=Application
Name=Signal K Dashboard
Exec=firefox-esr --kiosk http://localhost:3000
X-GNOME-Autostart-enabled=true
EOF
chown -R 1000:1000 /home/omg/.config

# 6. 🔑 PERMISSIONS & COMPLETION
echo "🔑 Finalizing OMG script permissions..."
chmod +x /usr/local/bin/omg
if [ -d "/usr/local/lib/omg" ]; then
    chmod +x /usr/local/lib/omg/omg-*
fi
if [ -f "/usr/share/bash-completion/completions/omg" ]; then
    chmod 644 /usr/share/bash-completion/completions/omg
fi

# 7. 🖼️ BRANDING & FACTORY DEFAULTS
echo "🖼️  Setting up branding and factory defaults..."
if [ -f "/etc/hostapd/hostapd.conf" ]; then
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.factory
fi

if [ -d "/usr/share/glib-2.0/schemas/" ]; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

# 8. 🧹 CLEAN UP
apt-get clean
echo "✅ OMG SETUP COMPLETE (Snap-Free & Air-Gapped Ready)"
