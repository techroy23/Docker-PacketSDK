#!/bin/bash
set -eu
#
# ============================================================
#  Packet SDK Launcher Script
#  - Detects system architecture
#  - Selects correct binary from /app/source/<arch>/
#  - Ensures binary is executable
#  - Runs binary with restart loop (1h max runtime per cycle)
# ============================================================
#

# Enable debug logging by default (set DEBUG=0 to silence)
: "${DEBUG:=1}"

# ------------------------------------------------------------
# Logging helper
# ------------------------------------------------------------
log() {
    if [ "${DEBUG:-0}" = "1" ]; then
        printf '%s\n' "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    fi
}

# ------------------------------------------------------------
# Validate required environment variables
# ------------------------------------------------------------
if [ -z "${APPKEY:-}" ]; then
  echo "Error: APPKEY is not set" >&2
  exit 1
fi

# ------------------------------------------------------------
# Detect architecture via uname -m
# ------------------------------------------------------------
UNAME_M=$(uname -m 2>/dev/null || echo unknown)
ARCH_DIR=""

log "uname -m reports: $UNAME_M"

case "$UNAME_M" in
  x86_64|amd64)  ARCH_DIR="x86_64"  ;;
  i386|i686|x86) ARCH_DIR="i386"    ;;
  aarch64|arm64) ARCH_DIR="aarch64" ;;
  armv7l|armv7)  ARCH_DIR="armv7l"  ;;
  armv6l)        ARCH_DIR="armv6l"  ;;
  armv5l)        ARCH_DIR="armv5l"  ;;
  *)             ARCH_DIR=""        ;;  # Unknown, fallback to dpkg if available
esac

# ------------------------------------------------------------
# Fallback: use dpkg architecture if uname is inconclusive
# ------------------------------------------------------------
if [ -z "$ARCH_DIR" ] && command -v dpkg >/dev/null 2>&1; then
  DPKG_ARCH=$(dpkg --print-architecture 2>/dev/null || true)
  if [ -n "$DPKG_ARCH" ]; then
    log "dpkg --print-architecture reports: $DPKG_ARCH"
    case "$DPKG_ARCH" in
      amd64) ARCH_DIR="x86_64"  ;;
      i386)  ARCH_DIR="i386"    ;;
      arm64) ARCH_DIR="aarch64" ;;
      armhf) ARCH_DIR="armv7l"  ;;
      armel) ARCH_DIR="armv5l"  ;;
      *)     :                  ;;
    esac
  fi
fi

# ------------------------------------------------------------
# Extra refinement for ARM: check CPU architecture level
# ------------------------------------------------------------
if [ "${ARCH_DIR#arm}" != "$ARCH_DIR" ]; then
  CPU_ARCH_NUM=$(awk -F: '
    /CPU architecture/ { gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; found=1; exit }
    END { if (!found) exit 1 }
  ' /proc/cpuinfo 2>/dev/null || true)

  if [ -n "${CPU_ARCH_NUM:-}" ]; then
    log "Detected CPU architecture level: $CPU_ARCH_NUM"
    case "$CPU_ARCH_NUM" in
      8|AArch64|aarch64)                ARCH_DIR="aarch64" ;;
      7) [ "$ARCH_DIR" != "armv7l" ] && ARCH_DIR="armv7l"  ;;
      6) [ "$ARCH_DIR" != "armv6l" ] && ARCH_DIR="armv6l"  ;;
      5) [ "$ARCH_DIR" != "armv5l" ] && ARCH_DIR="armv5l"  ;;
      *) :                                                 ;;
    esac
  fi
fi

# ------------------------------------------------------------
# Abort if architecture is still unknown
# ------------------------------------------------------------
if [ -z "$ARCH_DIR" ]; then
  echo "Unsupported or unrecognized architecture: uname -m='$UNAME_M'" >&2
  if command -v dpkg >/dev/null 2>&1; then
    echo "dpkg --print-architecture: $(dpkg --print-architecture 2>/dev/null || echo 'n/a')" >&2
  fi
  echo "Available binaries:" >&2
  ls -1 /app/source 2>/dev/null || echo "(none found)" >&2
  exit 1
fi

# ------------------------------------------------------------
# Select binary for detected architecture
# ------------------------------------------------------------
BIN_SRC="/app/source/${ARCH_DIR}/packet_sdk"
BIN_DST="/app/packet_sdk"

if [ ! -f "$BIN_SRC" ]; then
  echo "Binary not found for detected architecture '$ARCH_DIR' at: $BIN_SRC" >&2
  echo "Available binaries:" >&2
  ls -1 /app/source 2>/dev/null || echo "(none found)" >&2
  exit 1
fi

log "Selecting binary: $BIN_SRC -> $BIN_DST"
cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"

# ------------------------------------------------------------
# Main supervision loop
# - Runs binary with APPKEY
# - Restarts if process exits early
# - Kills and restarts after 1 hour
# ------------------------------------------------------------
while true; do
    log "Starting binary..."
    "$BIN_DST" -appkey="$APPKEY" "$@" &
    PID=$!

    # Background sleep timer
    sleep 10800 &
    SLEEP_PID=$!

    # Wait for either the binary or the sleep to finish
    wait -n $PID $SLEEP_PID

    if kill -0 $PID 2>/dev/null; then
        log "1h elapsed, killing process $PID"
        kill -TERM $PID
        wait $PID || true
    else
        log "Process exited before 1h, restarting..."
    fi

    # Clean up sleep process if still running
    kill $SLEEP_PID 2>/dev/null || true
done
