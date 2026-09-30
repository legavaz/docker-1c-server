#!/usr/bin/env bash
set -euo pipefail

SMB_USER="smb1c"
SMB_PASS="V8xKp3mQ7rTz9wLd"
SMB_UNC="//192.168.1.57/rep"
MP="/srv/rep"
CRED="/etc/cifs-rep"

printf 'username=%s\npassword=%s\n' "${SMB_USER}" "${SMB_PASS}" > "${CRED}"
chmod 600 "${CRED}"

mkdir -p "${MP}"

if mountpoint -q "${MP}"; then
  echo "already mounted: ${MP}"
else
  mount -t cifs "${SMB_UNC}" "${MP}" \
    -o credentials="${CRED}",uid=1000,gid=1000,file_mode=0660,dir_mode=0770,iocharset=utf8,vers=3.0,noperm
  echo "mounted ${SMB_UNC} -> ${MP}"
fi

# fstab: убрать битую строку и добавить запись (идемпотентно)
if ! grep -q "options>.*<dump>" /etc/fstab; then :; else sed -i '/options>.*<dump>/d' /etc/fstab; fi
if ! grep -q "${MP}" /etc/fstab; then
  echo "${SMB_UNC} ${MP} cifs credentials=${CRED},uid=1000,gid=1000,file_mode=0660,dir_mode=0770,iocharset=utf8,vers=3.0,noperm,_netdev,nofail 0 0" >> /etc/fstab
fi

echo "=== fstab ==="
cat /etc/fstab
echo "=== ls ${MP} ==="
ls -la "${MP}" | head -n 10
