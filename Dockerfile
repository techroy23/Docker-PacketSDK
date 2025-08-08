FROM alpine:latest

WORKDIR /app

RUN apk update && apk upgrade --no-cache

COPY packet_sdk /app/packet_sdk
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/packet_sdk /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
