#!/bin/bash
set -e

BIN_SDK="/app/packetSDK"
IP_CHECKER_URL="https://raw.githubusercontent.com/techroy23/IP-Checker/refs/heads/main/app.sh"
ENABLE_IP_CHECKER="${ENABLE_IP_CHECKER:-false}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

if [ -z "${APPKEY:-}" ]; then
  log " >>> An2Kin >>> ERROR: APPKEY environment variable is not set."
  exit 1
fi

setup_iptables() {
  log " >>> An2Kin >>> Setting up iptables and redsocks..."
  if ! iptables -t nat -L REDSOCKS -n >/dev/null 2>&1; then
    iptables -t nat -N REDSOCKS
  else
    iptables -t nat -F REDSOCKS
  fi
  iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
  iptables -t nat -A REDSOCKS -d $host -j RETURN
  iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

  if ! iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; then
    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
  fi
}

cleanup() {
  log " >>> An2Kin >>> Cleaning up iptables and redsocks..."
  iptables -t nat -F REDSOCKS 2>/dev/null || true
  iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
  iptables -t nat -X REDSOCKS 2>/dev/null || true
  kill $REDSOCKS_PID 2>/dev/null || true
}
trap cleanup EXIT

setup_proxy() {
  if [ -n "$PROXY" ]; then
    log " >>> An2Kin >>> External routing via proxy: $PROXY"

    host=$(echo "$PROXY" | cut -d: -f1)
    port=$(echo "$PROXY" | cut -d: -f2)

    cat >/etc/redsocks.conf <<EOF
base {
  log_debug = off;
  log_info = off;
  log = "stderr";
  daemon = off;
  redirector = iptables;
}

redsocks {
  local_ip = 0.0.0.0;
  local_port = 12345;
  ip = $host;
  port = $port;
  type = socks5;
}
EOF

    redsocks -c /etc/redsocks.conf >/dev/null 2>&1 &
    REDSOCKS_PID=$!

    setup_iptables
  else
    log " >>> An2Kin >>> Proxy not set, proceeding with direct connection"
  fi
}

check_ip() {
  if [ "$ENABLE_IP_CHECKER" = "true" ]; then
    log " >>> An2Kin >>> Checking current public IP..."
    if curl -fsSL "$IP_CHECKER_URL" | sh; then
      log " >>> An2Kin >>> IP checker script ran successfully"
    else
      log " >>> An2Kin >>> WARNING: Could not fetch or execute IP checker script"
    fi
  else
    log " >>> An2Kin >>> IP checker disabled (ENABLE_IP_CHECKER=$ENABLE_IP_CHECKER)"
  fi
}

main() {
  FORCE_TIMEOUT="${FORCE_TIMEOUT:-21600}"   # default 6 hours
  OFFSET_RANGE="${OFFSET_RANGE:-500}"       # default 500 seconds

  while true; do
      setup_proxy
      check_ip
      log " >>> An2Kin >>> Starting binary..."
      "$BIN_SDK" -appkey="$APPKEY" &
      PID=$!
      log " >>> An2Kin >>> APP PID is $PID"

      OFFSET=$(( RANDOM % (2 * OFFSET_RANGE + 1) - OFFSET_RANGE ))
      EFFECTIVE_TIMEOUT=$(( FORCE_TIMEOUT + OFFSET ))
      log " >>> An2Kin >>> Watchdog set for ${EFFECTIVE_TIMEOUT} seconds"

      (
        sleep "$EFFECTIVE_TIMEOUT"
        if kill -0 $PID 2>/dev/null; then
          log " >>> An2Kin >>> Timeout reached, killing PID $PID"
          kill $PID 2>/dev/null || true
        fi
      ) &
      WATCHDOG=$!

      wait $PID
      log " >>> An2Kin >>> Process exited, restarting..."
      kill $WATCHDOG 2>/dev/null || true
      sleep 5
  done
}



main
