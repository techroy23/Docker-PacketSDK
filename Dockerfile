FROM alpine:latest

ARG TARGETARCH

WORKDIR /app

RUN apk update \
    && apk upgrade --no-cache \
    && apk add --no-cache ca-certificates ca-certificates-bundle unzip curl bash dos2unix tzdata iptables redsocks \
    && update-ca-certificates

COPY source/aarch64/packet_sdk /tmp/packet_sdk_arm64

COPY source/x86_64/packet_sdk /tmp/packet_sdk_amd64

RUN if [ "$TARGETARCH" = "arm64" ]; then \
        cp /tmp/packet_sdk_arm64 /app/packetSDK && chmod +x /app/packetSDK; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        cp /tmp/packet_sdk_amd64 /app/packetSDK && chmod +x /app/packetSDK; \
    else \
        echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi \
    && rm -rf /tmp/packet_sdk_*

COPY entrypoint.sh /app/entrypoint.sh

RUN dos2unix /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]