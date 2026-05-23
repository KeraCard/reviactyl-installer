#!/bin/bash
# KeraCard™ ReviActyl Installer v0.1 - https://kera-card.github.io/reviactyl-installer
# IP: KeraCard™ is Intellectual Property of KeraLabs

set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root. sudo bash install.sh"
  exit 1
fi

clear
echo -e "\e[35m"
echo " ██╗ ██╗███████╗██████╗ █████╗ ██████╗ █████╗ ██████╗ ██████╗ "
echo " ██║ ██╔╝██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗"
echo " █████╔╝ █████╗ ██████╔╝███████║██║ ███████║██████╔╝██║ ██║"
echo " ██╔═██╗ ██╔══╝ ██╔══██╗██╔══██║██║ ██╔══██║██╔══██╗██║ ██║"
echo " ██║ ██╗███████╗██║ ██║██║ ██║╚██████╗██║ ██║██║ ██║██████╔╝"
echo " ╚═╝ ╚═╝╚══════╝╚═╝ ╚═╝╚═╝ ╚═╝ ╚═════╝╚═╝ ╚═╝╚═╝ ╚═╝╚═════╝ "
echo -e "\e[36m ⚙ REVIACTYL AUTO-INSTALLER v0.1 \e[0m"
echo -e "\e[35m========================================================================\e[0m"
echo ""

ADMIN_EMAIL=""
ADMIN_PASS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --admin-email=*) ADMIN_EMAIL="${1#*=}" ; shift ;;
    --admin-pass=*) ADMIN_PASS="${1#*=}" ; shift ;;
    *) echo "❌ Unknown flag: $1"; exit 1 ;;
  esac
done

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASS" ]; then
  echo "❌ Required: --admin-email= --admin-pass="
  exit 1
fi

if! grep -qi "ubuntu\|debian" /etc/os-release; then
  echo "❌ KeraCard™ Law #2: Ubuntu/Debian only. DELETE OR DIE."
  exit 1
fi

apt update -y
apt install -y curl wget ufw

curl -L -o /usr/local/bin/reviactyl "https://github.com/reviactyl/reviactyl/releases/latest/download/reviactyl-linux-amd64"
chmod +x /usr/local/bin/reviactyl

mkdir -p /etc/reviactyl

cat > /etc/systemd/system/reviactyl.service <<EOF
[Unit]
Description=KeraCard™ ReviActyl Panel
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/reviactyl serve --host 0.0.0.0 --port 80
WorkingDirectory=/etc/reviactyl

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now reviactyl

ufw allow 80
ufw allow 443
ufw --force enable

sleep 3
reviactyl admin create --email="$ADMIN_EMAIL" --password="$ADMIN_PASS" --root

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

cat > /root/kera-reviactyl-receipt.txt <<EOF
KeraCard™ ReviActyl Deploy v0.1
Panel: http://$IP
Admin: $ADMIN_EMAIL
Install time: $(date)
IP: KeraCard™ is Intellectual Property
EOF

echo "=================================================="
echo " 🎉 INSTALLATION COMPLETE 🎉"
echo "=================================================="
echo "Panel URL: http://$IP"
echo "Admin Email: $ADMIN_EMAIL"
echo "Receipt: /root/kera-reviactyl-receipt.txt"
echo "=================================================="
