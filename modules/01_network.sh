#!/usr/bin/env bash
# =============================================================================
# 01_network.sh — Network Hardening Module
# CIS Controls : 3.5.1 (UFW), 3.5.2 (default deny), custom (Fail2ban)
# Description  : Configures UFW firewall with a default-deny posture and
#                installs/configures Fail2ban for brute-force protection.
# =============================================================================

# ─── Helpers (inherit log() and APPLY from orchestrator) ─────────────────────
apply() {
    # Wrapper: runs a command live or prints it in dry-run
    if [[ "${APPLY}" == true ]]; then
        eval "$*"
    else
        log DRY "$*"
    fi
}

pkg_install() {
    local pkg="$1"
    if dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"; then
        log OK "${pkg} already installed — skipping."
    else
        log INFO "Installing ${pkg}..."
        apply "apt-get install -y ${pkg} >> '${LOG_FILE}' 2>&1"
    fi
}

# ─── UFW Configuration ────────────────────────────────────────────────────────
configure_ufw() {
    log INFO "[CIS 3.5.1] Configuring UFW firewall..."

    pkg_install "ufw"

    # Default deny inbound, allow outbound
    # CIS 3.5.2.1 — Ensure default deny firewall policy
    log INFO "[CIS 3.5.2.1] Setting default deny inbound policy..."
    apply "ufw --force reset"
    apply "ufw default deny incoming"
    apply "ufw default allow outgoing"

    # Allow SSH before enabling — critical, prevents lockout
    # Limit SSH to rate-limit brute force at the firewall level too
    log INFO "Allowing SSH (rate-limited)..."
    apply "ufw limit ssh comment 'Rate-limited SSH'"

    # Allow common homelab ports — comment/uncomment as needed
    # apply "ufw allow 80/tcp comment 'HTTP'"
    # apply "ufw allow 443/tcp comment 'HTTPS'"
    # apply "ufw allow 8080/tcp comment 'Alt HTTP'"

    # Enable UFW
    log INFO "Enabling UFW..."
    apply "ufw --force enable"

    # Ensure UFW starts on boot (systemd)
    apply "systemctl enable ufw"

    log OK "UFW configuration complete."
}

# ─── Fail2ban Configuration ───────────────────────────────────────────────────
configure_fail2ban() {
    log INFO "Configuring Fail2ban (brute-force protection)..."

    pkg_install "fail2ban"

    local f2b_local="/etc/fail2ban/jail.local"
    local f2b_config="${SCRIPT_DIR}/configs/fail2ban.local"

    if [[ -f "${f2b_config}" ]]; then
        log INFO "Deploying fail2ban.local from configs/..."
        if [[ "${APPLY}" == true ]]; then
            # Backup existing config if present
            [[ -f "${f2b_local}" ]] && cp "${f2b_local}" "${f2b_local}.bak.$(date +%Y%m%d)"
            cp "${f2b_config}" "${f2b_local}"
            log OK "fail2ban.local deployed."
        else
            log DRY "cp ${f2b_config} ${f2b_local}"
        fi
    else
        log WARN "configs/fail2ban.local not found — writing inline defaults..."
        apply "cat > ${f2b_local} << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 2h
EOF"
    fi

    apply "systemctl enable fail2ban"
    apply "systemctl restart fail2ban"

    log OK "Fail2ban configuration complete."
}

# ─── IPv6 Check ───────────────────────────────────────────────────────────────
check_ipv6() {
    # CIS 3.3.3 — Disable IPv6 if not required
    log INFO "[CIS 3.3.3] Checking IPv6 status..."
    if sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q "= 1"; then
        log OK "IPv6 already disabled."
    else
        log WARN "IPv6 is enabled. If unused, consider disabling via 02_kernel.sh (net.ipv6 params)."
    fi
}

# ─── Module entry point ───────────────────────────────────────────────────────
run() {
    configure_ufw
    configure_fail2ban
    check_ipv6
}
