#!/usr/bin/env bash
# =============================================================================
# 03_auth.sh — Authentication & Access Hardening Module
# CIS Controls : 5.2 (SSH), 5.3 (PAM), 5.4 (user accounts)
# Description  : Hardens SSH daemon configuration and PAM password policy.
#                SSH config is deployed from configs/sshd_config.
#                Existing sshd_config is backed up before any changes.
# =============================================================================

SSHD_CONFIG="/etc/ssh/sshd_config"

apply() {
    if [[ "${APPLY}" == true ]]; then
        eval "$*"
    else
        log DRY "$*"
    fi
}

# ─── SSH Hardening ────────────────────────────────────────────────────────────
harden_ssh() {
    log INFO "[CIS 5.2] Hardening SSH daemon..."

    local sshd_source="${SCRIPT_DIR}/configs/sshd_config"

    if [[ ! -f "${sshd_source}" ]]; then
        log ERROR "configs/sshd_config not found. Cannot harden SSH safely. Skipping."
        return 1
    fi

    # Validate config before deploying — prevents lockout
    # sshd -t requires root to read host keys; only enforce in apply mode
    if [[ "${APPLY}" == true ]]; then
        if ! sshd -t -f "${sshd_source}" 2>/dev/null; then
            log ERROR "configs/sshd_config failed sshd syntax check. Aborting SSH hardening."
            return 1
        fi
        log OK "sshd_config syntax validated."
    else
        log INFO "Skipping sshd syntax check in dry-run (requires root for host keys)."
    fi

    # Backup existing config
    if [[ "${APPLY}" == true ]]; then
        if [[ -f "${SSHD_CONFIG}" ]]; then
            local SSHD_BACKUP="/etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)"
            cp "${SSHD_CONFIG}" "${SSHD_BACKUP}"
            log OK "Backup saved: ${SSHD_BACKUP}"
        fi
        cp "${sshd_source}" "${SSHD_CONFIG}"
        chmod 600 "${SSHD_CONFIG}"
        log OK "sshd_config deployed."

        # Restart SSH — warn user
        log WARN "Restarting SSH. If your session drops, reconnect with: ssh localhost"
        systemctl restart ssh || systemctl restart sshd
        log OK "SSH restarted successfully."
    else
        log DRY "cp ${SSHD_CONFIG} ${SSHD_BACKUP}  (backup)"
        log DRY "cp ${sshd_source} ${SSHD_CONFIG}"
        log DRY "systemctl restart ssh"
    fi
}

# ─── PAM Password Policy ──────────────────────────────────────────────────────
harden_pam() {
    # CIS 5.3 — Configure PAM password quality requirements
    log INFO "[CIS 5.3] Configuring PAM password policy..."

    local pwquality_conf="/etc/security/pwquality.conf"

    # Install libpam-pwquality if not present
    if ! dpkg-query -W -f='${Status}' libpam-pwquality 2>/dev/null | grep -q "install ok installed"; then
        log INFO "Installing libpam-pwquality..."
        apply "apt-get install -y libpam-pwquality >> '${LOG_FILE}' 2>&1"
    else
        log OK "libpam-pwquality already installed."
    fi

    # Write pwquality config
    local pwq_content="# CIS 5.3 — PAM Password Quality
minlen  = 14
minclass = 4
dcredit  = -1
ucredit  = -1
ocredit  = -1
lcredit  = -1
maxrepeat = 3
reject_username = yes
enforce_for_root = yes"

    if [[ "${APPLY}" == true ]]; then
        echo "${pwq_content}" > "${pwquality_conf}"
        log OK "PAM pwquality policy written to ${pwquality_conf}"
    else
        log DRY "Write pwquality.conf: minlen=14, minclass=4, enforce_for_root=yes"
    fi
}

# ─── Account Lockout Policy ───────────────────────────────────────────────────
configure_lockout() {
    # CIS 5.3.2 — Lockout accounts after failed attempts
    log INFO "[CIS 5.3.2] Checking account lockout policy (pam_faillock)..."

    local faillock_conf="/etc/security/faillock.conf"

    local lock_content="# CIS 5.3.2 — Account lockout
deny = 5
unlock_time = 900
even_deny_root = yes"

    if [[ "${APPLY}" == true ]]; then
        echo "${lock_content}" > "${faillock_conf}"
        log OK "Account lockout policy written: 5 attempts → 15 min lockout"
    else
        log DRY "Write faillock.conf: deny=5, unlock_time=900 (15 min), even_deny_root=yes"
    fi
}

# ─── Password Ageing ──────────────────────────────────────────────────────────
configure_password_ageing() {
    # CIS 5.4.1 — Set password expiry parameters
    log INFO "[CIS 5.4.1] Configuring password ageing in /etc/login.defs..."

    local login_defs="/etc/login.defs"

    apply "sed -i $'s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\\t365/' ${login_defs}"
    apply "sed -i $'s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\\t1/' ${login_defs}"
    apply "sed -i $'s/^PASS_WARN_AGE.*/PASS_WARN_AGE\\t14/' ${login_defs}"
    log OK "Password ageing set: max=365 days, min=1 day, warn at 14 days"
}

# ─── Root account ─────────────────────────────────────────────────────────────
check_root() {
    # CIS 5.4.2 — Ensure root login is restricted
    # Sets root shell to nologin — blocks direct root login (local + su).
    # Break-glass access: boot into recovery mode if needed.
    log INFO "[CIS 5.4.2] Locking root account shell..."

    local root_shell
    root_shell=$(grep "^root:" /etc/passwd | cut -d: -f7)

    if [[ "${root_shell}" == "/sbin/nologin" || "${root_shell}" == "/usr/sbin/nologin" ]]; then
        log OK "Root shell is already nologin — direct root login disabled."
    else
        log INFO "Root shell is ${root_shell} → setting to /sbin/nologin"
        apply "usermod -s /sbin/nologin root"
        log OK "Root shell locked. Use sudo for privileged access; recovery mode as break-glass."
    fi
}

# ─── Module entry point ───────────────────────────────────────────────────────
run() {
    harden_ssh
    harden_pam
    configure_lockout
    configure_password_ageing
    check_root
}
