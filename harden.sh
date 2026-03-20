#!/usr/bin/env bash
# =============================================================================
# harden.sh — Linux Homelab Hardening Orchestrator
# Author      : Etienne Moran
# Target      : Kali Linux (Debian-based)
# Reference   : CIS Debian Linux Benchmark v2.0
# Description : Orchestrates all hardening modules. Runs in DRY-RUN mode by
#               default. Pass --apply to make real changes to the system.
# =============================================================================
# Usage:
#   ./harden.sh            → dry-run (safe, no changes made)
#   ./harden.sh --apply    → apply all hardening changes
#   ./harden.sh --module 01_network --apply  → apply a single module
# =============================================================================

set -euo pipefail

# ─── Colour palette ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Global state ─────────────────────────────────────────────────────────────
APPLY=false
SINGLE_MODULE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/modules"
LOG_FILE="${SCRIPT_DIR}/hardening_$(date +%Y%m%d_%H%M%S).log"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write plain text to log file
    echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"

    # Write coloured output to terminal
    case "${level}" in
        INFO)  echo -e "${CYAN}[INFO]${RESET}  ${msg}" ;;
        OK)    echo -e "${GREEN}[OK]${RESET}    ${msg}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${RESET}  ${msg}" ;;
        ERROR) echo -e "${RED}[ERROR]${RESET} ${msg}" ;;
        DRY)   echo -e "${YELLOW}[DRY-RUN]${RESET} Would: ${msg}" ;;
    esac
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply)
                APPLY=true
                shift
                ;;
            --module)
                SINGLE_MODULE="${2:-}"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${RESET}"
                usage
                exit 1
                ;;
        esac
    done
}

usage() {
    echo -e "${BOLD}Usage:${RESET}"
    echo "  ./harden.sh                        → dry-run all modules"
    echo "  ./harden.sh --apply                → apply all modules"
    echo "  ./harden.sh --module 01_network    → dry-run single module"
    echo "  ./harden.sh --module 01_network --apply  → apply single module"
}

# ─── Preflight checks ─────────────────────────────────────────────────────────
preflight() {
    log INFO "Running preflight checks..."

    # Must be root to apply changes
    if [[ "${APPLY}" == true && "${EUID}" -ne 0 ]]; then
        log ERROR "Root privileges required to apply changes. Run with sudo."
        exit 1
    fi

    # Warn if running as root in dry-run (unusual but allowed)
    if [[ "${APPLY}" == false && "${EUID}" -eq 0 ]]; then
        log WARN "Running dry-run as root — no changes will be made."
    fi

    # Confirm Debian-based distro
    if ! command -v apt-get &>/dev/null; then
        log ERROR "This script targets Debian/Kali Linux (apt-based). Aborting."
        exit 1
    fi

    log OK "Preflight checks passed."
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          Linux Homelab Hardening Script              ║"
    echo "║          CIS Debian Benchmark v2.0 — Aligned         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    if [[ "${APPLY}" == true ]]; then
        echo -e "${RED}${BOLD}  ⚠  APPLY MODE — Real changes will be made to this system${RESET}"
    else
        echo -e "${YELLOW}${BOLD}  ℹ  DRY-RUN MODE — No changes will be made (pass --apply to execute)${RESET}"
    fi
    echo ""
}

# ─── Module runner ────────────────────────────────────────────────────────────
run_module() {
    local module_file="$1"
    local module_name
    module_name="$(basename "${module_file}" .sh)"

    echo -e "\n${BOLD}${CYAN}━━━ Module: ${module_name} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    log INFO "Loading module: ${module_name}"

    if [[ ! -f "${module_file}" ]]; then
        log ERROR "Module file not found: ${module_file}"
        return 1
    fi

    # Source module — each module reads APPLY and DRY_RUN from environment
    # shellcheck source=/dev/null
    source "${module_file}"

    # Each module must expose a run() function
    if declare -f run > /dev/null; then
        run
        # Unset run() so next module starts clean
        unset -f run
    else
        log ERROR "Module ${module_name} does not define a run() function. Skipping."
    fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────
summary() {
    echo -e "\n${BOLD}${GREEN}━━━ Hardening Complete ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    if [[ "${APPLY}" == true ]]; then
        log OK "All modules applied. Log saved to: ${LOG_FILE}"
        log WARN "A reboot is recommended to ensure all kernel parameters take effect."
    else
        log INFO "Dry-run complete. No changes were made."
        log INFO "Review the output above, then re-run with --apply to execute."
        log INFO "Log saved to: ${LOG_FILE}"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    banner
    preflight

    # Export globals so sourced modules can read them
    export APPLY
    export LOG_FILE

    if [[ -n "${SINGLE_MODULE}" ]]; then
        # Run a specific module only
        run_module "${MODULE_DIR}/${SINGLE_MODULE}.sh"
    else
        # Run all modules in order
        for module in "${MODULE_DIR}"/0*.sh; do
            run_module "${module}"
        done
    fi

    summary
}

main "$@"
