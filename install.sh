#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root (sudo)."
  exit 1
fi

clear
echo -e "\e[36m"
echo " __      __                    .___                                     .___             "
echo "/  \    /  \_____    ____    __| _/___________   ___________  _______  __| _/___________ "
echo "\   \/\/   /\__  \  /    \  / __ |\_  __ \_  __ \_/ __ \_  __ \ \   \ /   |/ __ \_  __ \\"
echo " \        /  / __ \|   |  \/ /_/ | |  | \/|  | \/\  ___/|  | \/  \   Y   /\  ___/|  | \/"
echo "  \__/\  /  (____  /___|  /\____ | |__|   |__|    \___  >__|      \___ /  \___  >__|   "
echo "       \/        \/     \/      \/                    \/              \/      \/       "
echo -e "\e[0m"
echo -e "\e[35m========================================================================\e[0m"
echo -e "\e[32m                 ⚙️  PTERODACTYL PANEL & WINGS AUTO-INSTALLER          \e[0m"
echo -e "\e[35m========================================================================\e[0m"
echo ""

read -p "Would you like to install [Y/n]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ && ! -z "$CONFIRM" ]]; then
  echo "❌ Installation cancelled."
  exit 1
fi

read -p "Enter Domain or IP for Panel (e.g., panel.example.com): " FQDN
read -p "Enter Admin Email: " ADMIN_EMAIL
read -p "Enter Admin Username: " ADMIN_USER
read -p "Enter Admin First Name: " ADMIN_FIRST
read -p "Enter Admin Last Name: " ADMIN_LAST
read -s -p "Enter Admin Password: " ADMIN_PASS
echo ""
read -s -p "Enter Secure Database Password: " DB_PASS
echo ""

apt update && apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release git coreutils UFW

LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update
apt install -y php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-fpm php8.3-intl php8.3-sqlite3 tar unzip git redis-server

apt install -y mariadb-server
systemctl enable --now mariadb

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

cp .env.example .env
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
composer install --no-dev --optimize-autoloader

php artisan key:generate --force
sed -i "s/DB_PASSWORD=secret/DB_PASSWORD=$DB_PASS/g" .env
php artisan ptero:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password="$DB_PASS"

php artisan migrate --seed --force
php artisan ptero:user:create --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --first-name="$ADMIN_FIRST" --last-name="$ADMIN_LAST" --password="$ADMIN_PASS" --admin=1

chown -R www-data:www-data /var/www/pterodactyl/*

cat <<EOF > /etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq.service

apt install -y nginx
rm /etc/nginx/sites-enabled/default

cat <<EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name $FQDN;
    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx
systemctl restart php8.3-fpm

curl -sSL https://get.docker.com/ | CHANNEL=stable sh
systemctl enable --now docker

mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
chmod u+x /usr/local/bin/wings

cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable wings

ufw allow 80
ufw allow 443
ufw allow 2022
ufw allow 8080
ufw --force enable

echo "=================================================="
echo "   🎉 INSTALLATION COMPLETE 🎉"
echo "=================================================="
echo "Panel FQDN: http://$FQDN"
echo "Admin User: $ADMIN_USER"
echo "--------------------------------------------------"
echo "⚠️  NOTE FOR WINGS CONFIGURATION:"
echo "1. Go to your new Panel web UI and log in."
echo "2. Create a Location, then Create a Node."
echo "3. Go to the Node's 'Configuration' tab, copy the block."
echo "4. Paste it manually into /etc/pterodactyl/config.yml"
echo "5. Run: systemctl start wings"
echo "=================================================="