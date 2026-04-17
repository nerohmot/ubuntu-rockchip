#!/bin/bash
set -e

echo "----------------------------------------------------"
echo "⚓ OPEN MARINE GATEWAY: CUSTOM SETUP STARTING"
echo "----------------------------------------------------"

# 1. Update and install standard UI/System tools
apt-get update
apt-get install -y \
    plymouth \
    plymouth-themes \
    qrencode \
    imagemagick \
    expect \
    hostapd \
    dnsmasq \
    can-utils \
    gpsd \
    i2c-tools \
    bash-completion

# 2. Install Node.js & Signal K (The Heart of the Gateway)
echo "📦 Installing Signal K Stack..."
# Optimized Node.js 20.x installation for Ubuntu Noble
curl -fsSL https://nodesource.com | bash -
apt-get install -y nodejs
npm install -g --unsafe-perm signalk-server

# 3. Prepare the Air-Gapped Package Cache
echo "💾 Caching packages for offline use..."
mkdir -p /opt/omg/pkg
cd /opt/omg/pkg
apt-get download qrencode imagemagick expect hostapd dnsmasq nodejs

# 4. Finalize Permissions for OMG CLI & Completion
echo "🔑 Finalizing OMG script permissions..."
chmod +x /usr/local/bin/omg
if [ -d "/usr/local/lib/omg" ]; then
    chmod +x /usr/local/lib/omg/omg-*
fi
# Ensure the bash completion we put in overlay is readable
if [ -f "/usr/share/bash-completion/completions/omg" ]; then
    chmod 644 /usr/share/bash-completion/completions/omg
fi

# 5. Factory Defaults & Wallpaper Logic
echo "🖼️  Setting up branding and factory defaults..."
# Save the clean hostapd config so 'omg reset' can restore it
if [ -f "/etc/hostapd/hostapd.conf" ]; then
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.factory
fi

# Compile the GNOME wallpaper schema so it recognizes the OMG backgrounds
if [ -d "/usr/share/glib-2.0/schemas/" ]; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

# 6. Clean up to keep image small
apt-get clean

echo "✅ OMG SETUP COMPLETE"
