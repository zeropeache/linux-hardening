# Linux Homelab Hardening Script

A modular Bash hardening framework for Kali Linux / Debian-based systems, aligned to the **CIS Debian Linux Benchmark v2.0** .

Built as part of a personal homelab security practice environment. Every control includes an inline reference to its CIS Benchmark mapping so the *why* is never separated from the *what*.

---

## Features

- **Dry-run by default** — safe to run without touching the system; prints every action it would take
- **Idempotent** — safe to run multiple times; checks current state before making changes
- **Modular architecture** — run all modules or target a single one
- **CIS-aligned** — every control maps to a specific CIS Debian Linux Benchmark v2.0 reference
- **Automated logging** — timestamped log file generated on every run

---

## Coverage

| Module | Domain | Key Controls |
|--------|--------|-------------|
| `01_network.sh` | Network | UFW default-deny, Fail2ban SSH protection |
| `02_kernel.sh` | Kernel Parameters | sysctl hardening — ASLR, anti-spoofing, SYN cookies |
| `03_auth.sh` | Authentication | SSH hardening, PAM password policy, account lockout |
| `04_services.sh` | Attack Surface | Disable unnecessary services, remove risky packages |
| `05_audit.sh` | Audit & Logging | auditd rules, rsyslog, log permissions |

---

## Usage

```bash
# Clone the repository
git clone https://github.com/zeropeache/linux-hardening.git
cd linux-hardening

# Make scripts executable
chmod +x harden.sh modules/*.sh

# Dry-run (safe — no changes made)
./harden.sh

# Apply all modules
sudo ./harden.sh --apply

# Dry-run a single module
./harden.sh --module 01_network

# Apply a single module
sudo ./harden.sh --module 03_auth --apply
```

---

## Prerequisites

- Debian-based Linux (Kali Linux, Ubuntu, Debian)
- `sudo` / root access (required for `--apply` mode)
- SSH key pair configured **before** applying `03_auth.sh` (password auth will be disabled)

---

## Important: Read Before Applying

### SSH Key Requirement
`03_auth.sh` sets `PasswordAuthentication no`. Before applying this module, ensure you have an SSH key pair set up:

```bash
# Generate a key pair (if you don't have one)
ssh-keygen -t ed25519 -C "homelab"

# Add your public key to authorized_keys
ssh-copy-id yourusername@localhost
```

### Validate SSH Config First
The script validates `configs/sshd_config` with `sshd -t` before deploying it. If validation fails, SSH hardening is skipped and your existing config is untouched.

### squashfs & Snap
`04_services.sh` skips disabling `squashfs` if Snap packages are detected on your system, to avoid breaking them.

### auditd Immutability
`configs/auditd.rules` ends with `-e 2` which makes audit rules immutable until the next reboot. This is intentional — it prevents an attacker from disabling auditing. To modify rules, reboot first.

---

## Project Structure

```
linux-hardening/
├── harden.sh              # Main orchestrator
├── modules/
│   ├── 01_network.sh      # UFW + Fail2ban
│   ├── 02_kernel.sh       # sysctl parameters
│   ├── 03_auth.sh         # SSH + PAM
│   ├── 04_services.sh     # Services + packages
│   └── 05_audit.sh        # auditd + rsyslog
├── configs/
│   ├── fail2ban.local      # Fail2ban jail config
│   ├── sshd_config         # Hardened SSH daemon config
│   └── auditd.rules        # CIS-aligned audit rules
└── README.md
```

---

## CIS Benchmark Mapping

> **Note:** The table below is a representative sample of key controls, not an exhaustive mapping.

| CIS Control | Description | Module |
|-------------|-------------|--------|
| 1.1.x | Disable unused filesystems | 04_services.sh |
| 1.5.3 | ASLR enabled | 02_kernel.sh |
| 2.1.x | Disable unnecessary services | 04_services.sh |
| 3.1–3.3 | Network parameters | 02_kernel.sh |
| 3.5.x | Firewall (UFW) | 01_network.sh |
| 4.1.x | auditd configuration | 05_audit.sh |
| 4.2.x | rsyslog configuration | 05_audit.sh |
| 5.2.x | SSH Server configuration | 03_auth.sh |
| 5.3.x | PAM configuration | 03_auth.sh |

---

## Tools Used

- **UFW** - Uncomplicated Firewall (netfilter frontend)
- **Fail2ban** - Intrusion prevention via log analysis
- **auditd** - Linux Audit Daemon (kernel-level event logging)
- **rsyslog** - System logging daemon
- **libpam-pwquality** - PAM password quality enforcement

---

## Known Issues and Edge Cases

A few things that came up during real-world testing on Kali. None of these are blockers, but they are good to know before you apply this on your own system.

### log_martians gets reset by Docker

`02_kernel.sh` sets `net.ipv4.conf.all.log_martians = 1` and writes it to `/etc/sysctl.d/99-hardening.conf`. If Docker is running, it resets this to 0 at startup because it manipulates routing between network namespaces. Re-running the script corrects it, but Docker will flip it back again. This only affects martian packet logging - not any active protection - so it has no real security impact.

### ip_forward is left enabled

`net.ipv4.ip_forward` is not disabled by this script. Docker and VPN software both need it to route traffic between interfaces, so disabling it would break them. If you are running this on a machine without Docker or a VPN, you can set it to 0 manually in `/etc/sysctl.d/99-hardening.conf`.

### squashfs block is skipped when Snap is detected

`04_services.sh` skips blocking the squashfs kernel module if Snap packages are found on the system, since Snap mounts depend on it. On a Snap-free system the block applies as normal.

### auditd rules are immutable until the next reboot

The last line of `configs/auditd.rules` is `-e 2`, which locks the ruleset in memory after it loads. Audit rules cannot be changed or reloaded without rebooting first. This is by design - it stops an attacker from disabling auditing after gaining access. If you need to update the rules, reboot, then re-run the script.

### rsyslog is installed but not running

`05_audit.sh` installs rsyslog but skips starting it when `systemd-journald` is already active, which is the default on modern Kali. Journald handles logging, rsyslog ends up installed but idle. On systems where journald is not running, rsyslog will start normally.

### Xorg log permissions reset each session

X11 recreates `/var/log/Xorg.0.log` with 644 permissions every time a new display session starts. The script corrects this to 640 on each run, but it will not persist between sessions. If this is a concern, run the script after login or handle it outside of this script with a systemd service or similar.

---

## License

This project is provided for educational use only. No warranty is expressed or implied. Use at your own risk.

---

## Disclaimer

This script is built for a personal homelab environment and provided for educational purposes. Test in a non-production environment first. Always review each module before applying to understand the changes being made to your system.

---

## References

Resources used during development and testing:

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks) - the primary reference for all controls in this project; the CIS Debian Linux Benchmark v2.0 was used specifically
- [Fail2ban documentation](https://www.fail2ban.org) - jail configuration and backend options
- `man auditctl`, `man auditd`, `man auditd.conf` - used heavily for understanding rule syntax and the `-e 2` immutability flag
- `man ufw`, `man ufw-framework` - UFW rule ordering and default policy behaviour
- `man pam_faillock`, `man pwquality.conf` - PAM lockout and password policy configuration
- `man sysctl`, `man sysctl.d` - persistent kernel parameter behaviour and load order

---

## Acknowledgements

This project was built and refined with help from [Claude](https://claude.ai) and [Claude Code](https://www.anthropic.com) by Anthropic. Claude was used as a development assistant throughout - for debugging, reviewing script logic, and improving documentation. The hardening decisions, controls, and final code are my own.

---

## Author

**Etienne Moran** - Aspiring Junior SOC Analyst  
Tryhackme SEC1 | Google Cybersecurity Professional Certificate | CVSS v4.0  
[LinkedIn](https://linkedin.com/in/etienne-laurence-moran3340) · [GitHub](https://github.com/zeropeache)
