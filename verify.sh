#!/bin/bash
# Post-reboot hardening verification script

sep() { echo; echo "=== $1 ==="; echo; }

sep "1. Firewall (UFW)"
sudo ufw status verbose

sep "2. IPv6 disabled"
sysctl net.ipv6.conf.all.disable_ipv6

sep "3. Kernel params"
sysctl -a 2>/dev/null | grep -E "rp_filter|log_martians|syncookies|dmesg_restrict|kptr_restrict"

sep "4. Audit rules"
sudo auditctl -l
echo
sudo auditctl -s | grep enabled

sep "5. Fail2ban"
sudo systemctl status fail2ban --no-pager
echo
sudo fail2ban-client status sshd

sep "6. Root shell"
grep "^root:" /etc/passwd | cut -d: -f7

sep "7. SUID bits"
stat -c "%a %n" /usr/bin/pkexec /usr/bin/rsh-redone-rsh /usr/sbin/pppd /usr/bin/ntfs-3g 2>/dev/null || echo "(some files not present — that is fine)"

sep "8. Filesystem module blocks"
cat /etc/modprobe.d/hardening-filesystems.conf

echo
echo "=== DONE ==="
