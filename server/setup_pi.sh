#!/bin/bash
# =============================================================================
# Spencer Polish Voice Server — Raspberry Pi Setup
# =============================================================================
# Run as: sudo bash setup_pi.sh
#
# This script:
#   1. Installs system dependencies (ffmpeg, hostapd, dnsmasq, python3)
#   2. Downloads Vosk Polish model
#   3. Downloads Piper TTS + Polish voice
#   4. Sets up WiFi hotspot "SpencerNet"
#   5. Creates a systemd service for the server
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/spencer-server"
HOTSPOT_SSID="SpencerNet"
HOTSPOT_PASS="spencer123"
WLAN_IFACE="wlan0"
PI_IP="192.168.4.1"

echo "=== Spencer Polish Voice Server Setup ==="
echo ""

# --- 1. System packages ---
echo "[1/5] Installing system packages..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv ffmpeg \
    hostapd dnsmasq wget unzip

# --- 2. Install directory & Python venv ---
echo "[2/5] Setting up install directory..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/main.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/"

python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"

# --- 3. Download Vosk Polish model ---
echo "[3/5] Downloading Vosk Polish model (~50 MB)..."
if [ ! -d "$INSTALL_DIR/model" ]; then
    wget -q "https://alphacephei.com/vosk/models/vosk-model-small-pl-0.22.zip" \
        -O /tmp/vosk-pl.zip
    unzip -q /tmp/vosk-pl.zip -d "$INSTALL_DIR/"
    mv "$INSTALL_DIR/vosk-model-small-pl-0.22" "$INSTALL_DIR/model"
    rm /tmp/vosk-pl.zip
    echo "    Model downloaded to $INSTALL_DIR/model"
else
    echo "    Model already exists, skipping."
fi

# --- 4. Download Piper TTS + Polish voice ---
echo "[4/5] Downloading Piper TTS + Polish voice..."
PIPER_DIR="$INSTALL_DIR/piper"
if [ ! -f "$PIPER_DIR/piper" ]; then
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64) PIPER_ARCH="aarch64" ;;
        armv7l)  PIPER_ARCH="armv7l" ;;
        x86_64)  PIPER_ARCH="amd64" ;;
        *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    wget -q "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_${PIPER_ARCH}.tar.gz" \
        -O /tmp/piper.tar.gz
    mkdir -p "$PIPER_DIR"
    tar -xzf /tmp/piper.tar.gz -C "$PIPER_DIR" --strip-components=1
    rm /tmp/piper.tar.gz
    echo "    Piper installed to $PIPER_DIR"
else
    echo "    Piper already installed, skipping."
fi

# Polish voice model
if [ ! -f "$PIPER_DIR/pl_PL-darkman-medium.onnx" ]; then
    wget -q "https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/darkman/medium/pl_PL-darkman-medium.onnx" \
        -O "$PIPER_DIR/pl_PL-darkman-medium.onnx"
    wget -q "https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/darkman/medium/pl_PL-darkman-medium.onnx.json" \
        -O "$PIPER_DIR/pl_PL-darkman-medium.onnx.json"
    echo "    Polish voice downloaded."
else
    echo "    Polish voice already exists, skipping."
fi

# --- 5. WiFi Hotspot ---
echo "[5/5] Configuring WiFi hotspot ($HOTSPOT_SSID)..."

# hostapd config
cat > /etc/hostapd/hostapd.conf <<HOSTAPD_EOF
interface=$WLAN_IFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
HOSTAPD_EOF

# Point hostapd to its config
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' \
    /etc/default/hostapd 2>/dev/null || true

# dnsmasq config
cat > /etc/dnsmasq.d/spencer.conf <<DNSMASQ_EOF
interface=$WLAN_IFACE
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
DNSMASQ_EOF

# Static IP for wlan0
if ! grep -q "spencer" /etc/dhcpcd.conf 2>/dev/null; then
    cat >> /etc/dhcpcd.conf <<DHCP_EOF

# spencer hotspot
interface $WLAN_IFACE
static ip_address=$PI_IP/24
nohook wpa_supplicant
DHCP_EOF
fi

# Enable services
systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd
systemctl enable dnsmasq

# --- Systemd service for the server ---
cat > /etc/systemd/system/spencer-server.service <<SERVICE_EOF
[Unit]
Description=Spencer Polish Voice Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment=VOSK_MODEL=$INSTALL_DIR/model
Environment=PIPER_BIN=$PIPER_DIR/piper
Environment=PIPER_MODEL=$PIPER_DIR/pl_PL-darkman-medium.onnx
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable spencer-server

echo ""
echo "=== Setup complete! ==="
echo ""
echo "WiFi hotspot:  $HOTSPOT_SSID / $HOTSPOT_PASS"
echo "Server:        http://$PI_IP:8080"
echo "TTS endpoint:  http://$PI_IP:8080/tts/v1/text:synthesize"
echo "STI endpoint:  http://$PI_IP:8080/sti/speech"
echo ""
echo "To start everything now:  sudo reboot"
echo "Or manually:"
echo "  sudo systemctl start hostapd"
echo "  sudo systemctl start dnsmasq"
echo "  sudo systemctl start spencer-server"
echo ""
echo "Spencer firmware needs these URLs:"
echo "  TextToSpeech.cpp:  http://$PI_IP:8080/tts/v1/text:synthesize"
echo "  SpeechToIntent.cpp: http://$PI_IP:8080/sti/speech"
