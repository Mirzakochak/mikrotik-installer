#!/bin/bash
# =======================================================
# Auto MikroTik CHR Installer with Network Auto-Provision
# Repository: https://github.com/Mirzakochak/mikrotik-installer
# =======================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mError: Please run this script as root.\e[0m"
  exit 1
fi

echo -e "\e[34m[1/6] Installing dependencies...\e[0m"
apt-get update -yq
apt-get install -yq wget unzip parted iproute2

# ==========================================
# 1. استخراج خودکار اطلاعات شبکه سرور
# ==========================================
echo -e "\e[34m[2/6] Extracting current network configuration...\e[0m"
ETH=$(ip route get 8.8.8.8 | grep dev | awk '{print $5}')
IP_CIDR=$(ip -o -4 addr list "$ETH" | awk '{print $4}')
GATEWAY=$(ip route show default | awk '/default/ {print $3}')

if [ -z "$IP_CIDR" ] || [ -z "$GATEWAY" ]; then
    echo -e "\e[31mError: Could not extract network info.\e[0m"
    exit 1
fi
echo -e "\e[32mNetwork Info Extracted -> IP: $IP_CIDR | GW: $GATEWAY\e[0m"

# ==========================================
# 2. پیدا کردن هوشمندانه هارد دیسک اصلی
# ==========================================
echo -e "\e[34m[3/6] Detecting main target disk...\e[0m"
ROOT_MOUNT=$(findmnt -n -o SOURCE /)
TARGET_DISK=$(lsblk -no pkname "$ROOT_MOUNT" 2>/dev/null)

if [ -n "$TARGET_DISK" ]; then
    TARGET_DISK="/dev/$TARGET_DISK"
else
    # حذف شماره پارتیشن با استفاده از Regex
    TARGET_DISK=$(echo "$ROOT_MOUNT" | sed -E 's/[0-9]+$//; s/p$//')
fi

echo -e "\e[32mTarget Disk Detected: $TARGET_DISK\e[0m"

# ==========================================
# 3. دانلود و اکسترکت میکروتیک
# ==========================================
CHR_VERSION="7.14.3"
IMAGE_URL="https://download.mikrotik.com/routeros/$CHR_VERSION/chr-$CHR_VERSION.img.zip"

echo -e "\e[34m[4/6] Downloading and extracting MikroTik CHR v$CHR_VERSION...\e[0m"
wget --no-check-certificate -qO /tmp/chr.img.zip "$IMAGE_URL"
unzip -q -o /tmp/chr.img.zip -d /tmp/

# ==========================================
# 4. تزریق تنظیمات شبکه به داخل ایمیج (با تاخیر هوشمند)
# ==========================================
echo -e "\e[34m[5/6] Injecting network configuration for Winbox access...\e[0m"

# پیدا کردن Offset پارتیشن دوم
OFFSET=$(parted -s /tmp/chr-$CHR_VERSION.img unit B print | grep -E '^ 2 ' | awk '{print $2}' | tr -d 'B')

mkdir -p /mnt/chr
mount -o loop,offset=$OFFSET /tmp/chr-$CHR_VERSION.img /mnt/chr

# ساخت اسکریپت ران‌شونده با دیلی ۱۵ ثانیه‌ای برای اطمینان از لود شدن ether1
mkdir -p /mnt/chr/rw/disk
cat <<EOF > /mnt/chr/rw/disk/setup.auto.rsc
:delay 15;
/ip address add address=$IP_CIDR interface=ether1;
/ip route add dst-address=0.0.0.0/0 gateway=$GATEWAY;
EOF

umount /mnt/chr

# ==========================================
# 5. رایت ایمیج و ریبوت
# ==========================================
echo -e "\e[33m[6/6] Flashing modified CHR to $TARGET_DISK (Overwriting Ubuntu)...\e[0m"
echo 1 > /proc/sys/kernel/sysrq

# همگام‌سازی و رایت نهایی
dd if="/tmp/chr-$CHR_VERSION.img" of="$TARGET_DISK" bs=4M oflag=sync status=progress

echo -e "\e[32m>>> Installation complete!\e[0m"
echo -e "\e[32m>>> Server is rebooting... Wait 1-2 minutes and connect via Winbox.\e[0m"
echo -e "\e[32m>>> Connect to: $(echo $IP_CIDR | cut -d'/' -f1) | User: admin | Pass: [blank]\e[0m"

sleep 3
echo b > /proc/sysrq-trigger
