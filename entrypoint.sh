#!/bin/sh
set -e

# Optional: validate required env
if [ -z "$APPKEY" ]; then
  echo "Error: APPKEY is not set"
  exit 1
fi

exec /app/packet_sdk -appkey="$APPKEY"
