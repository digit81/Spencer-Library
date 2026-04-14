#!/bin/bash
# =============================================================================
# Spencer Polish Voice Server — Raspberry Pi Setup
# =============================================================================
# Run as: sudo bash setup_pi.sh
#
# This script:
#   1. Installs system dependencies (ffmpeg, python3)
#   2. Downloads Vosk Polish model
#   3. Downloads Piper TTS + Polish voice
#   4. Sets up WiFi hotspot "SpencerNet" via NetworkManager
#      (works on Raspberry Pi OS Bookworm and Trixie)
#   5. Creates a systemd service for the server
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/spencer-server"
HOTSPOT_SSID="SpencerNet"
HOTSPOT_PASS="spencer123"
WLAN_IFACE="wlan0"
PI_IP="192.168.4.1"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash setup_pi.sh"
    exit 1
fi

echo "=== Spencer Polish Voice Server Setup ==="
echo ""

# --- 1. Detect network stack ---
if ! command -v nmcli >/dev/null 2>&1; then
    echo "ERROR: NetworkManager (nmcli) not found."
    echo "This script targets Raspberry Pi OS Bookworm and Trixie."
    echo "For older releases (Bullseye and earlier) you need the dhcpcd/hostapd path."
    exit 1
fi

# --- 2. System packages ---
echo "[1/5] Installing system packages..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv ffmpeg wget unzip

# Make sure hostapd/dnsmasq (if present from a previous run) don't fight NM.
systemctl disable --now hostapd 2>/dev/null || true
systemctl disable --now dnsmasq 2>/dev/null || true

# --- 3. Install directory & Python venv ---
echo "[2/5] Setting up install directory..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/main.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/"

python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"

# --- 4. Download Vosk Polish model ---
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

# --- 5. Download Piper TTS + Polish voice ---
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

# --- 6. WiFi Hotspot via NetworkManager ---
echo "[5/5] Configuring WiFi hotspot ($HOTSPOT_SSID) via NetworkManager..."

# Remove any prior hotspot profile with the same name, idempotently.
nmcli connection delete SpencerHotspot 2>/dev/null || true

# Create the AP profile. `ipv4.method shared` makes NM run an internal
# dnsmasq for DHCP+DNS on this interface — no separate dnsmasq needed.
nmcli connection add \
    type wifi ifname "$WLAN_IFACE" \
    con-name SpencerHotspot autoconnect yes \
    ssid "$HOTSPOT_SSID"

nmcli connection modify SpencerHotspot \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 7 \
    ipv4.method shared \
    ipv4.addresses "$PI_IP/24" \
    ipv6.method disabled \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.proto rsn \
    wifi-sec.pairwise ccmp \
    wifi-sec.group ccmp \
    wifi-sec.psk "$HOTSPOT_PASS"

# Bring the hotspot up now (will also auto-start on boot).
nmcli connection up SpencerHotspot || true

# Verify the AP actually came up — nmcli can return 0 from `up` and still
# fail to activate (e.g. chipset doesn't support AP mode, wlan0 busy).
# Give NM a moment to settle, then confirm the profile is 'activated'.
ap_up=0
for i in 1 2 3 4 5; do
    if nmcli -t -f GENERAL.STATE con show SpencerHotspot 2>/dev/null | grep -q activated; then
        ap_up=1
        break
    fi
    sleep 1
done

if [ "$ap_up" -ne 1 ]; then
    echo ""
    echo "ERROR: Hotspot SpencerHotspot did not activate."
    echo "Common causes:"
    echo "  - wlan0 is managed by another service (wpa_supplicant, rfkill)"
    echo "  - WiFi chipset does not support AP mode on this kernel"
    echo "  - Another NM profile is holding the interface"
    echo ""
    echo "Diagnose with:"
    echo "  nmcli device status"
    echo "  nmcli -f all con show SpencerHotspot"
    echo "  journalctl -u NetworkManager --since '2 minutes ago'"
    exit 1
fi

# --- Systemd service for the server ---
cat > /etc/systemd/system/spencer-server.service <<SERVICE_EOF
[Unit]
Description=Spencer Polish Voice Server
After=network-online.target NetworkManager.service
Wants=network-online.target

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
systemctl restart spencer-server

echo ""
echo "=== Setup complete! ==="
echo ""
echo "WiFi hotspot:  $HOTSPOT_SSID / $HOTSPOT_PASS"
echo "Pi address:    $PI_IP"
echo "Server:        http://$PI_IP:8080"
echo "TTS endpoint:  http://$PI_IP:8080/tts/v1/text:synthesize"
echo "STI endpoint:  http://$PI_IP:8080/sti/speech"
echo ""
echo "Useful commands:"
echo "  nmcli connection show SpencerHotspot"
echo "  systemctl status spencer-server"
echo "  journalctl -u spencer-server -f"
echo ""
echo "Spencer firmware is already configured to connect to:"
echo "  http://$PI_IP:8080/..."
