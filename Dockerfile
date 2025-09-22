FROM ubuntu:24.04

WORKDIR /app

# Install only what’s needed (no recommends to keep it minimal)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy all architecture-specific binaries
COPY source /app/source

# Copy entrypoint
COPY entrypoint.sh /app/entrypoint.sh

# Ensure executables are runnable
RUN chmod +x /app/source/*/packet_sdk /app/entrypoint.sh

# Create non-root user
RUN useradd -m -s /bin/sh appuser
RUN chown -R appuser:appuser /app
USER appuser

ENTRYPOINT ["/app/entrypoint.sh"]
