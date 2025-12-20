# F-Droid Repository Server for Subfrost
# Based on fdroidserver with nginx for serving

FROM debian:bookworm-slim AS fdroidserver

# Install fdroidserver and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    fdroidserver \
    python3 \
    python3-pip \
    python3-yaml \
    python3-requests \
    python3-pil \
    openjdk-17-jdk-headless \
    apksigner \
    zipalign \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

# Copy repository configuration
COPY config.yml /repo/config.yml
COPY update-repo.sh /usr/local/bin/update-repo.sh
RUN chmod +x /usr/local/bin/update-repo.sh

# Final image with nginx for serving
FROM nginx:alpine

# Install fdroidserver in nginx image for updates
RUN apk add --no-cache \
    python3 \
    py3-pip \
    openjdk17-jre-headless \
    bash \
    curl \
    && pip3 install --break-system-packages fdroidserver

WORKDIR /var/www/fdroid

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Copy repo configuration
COPY config.yml /var/www/fdroid/config.yml
COPY update-repo.sh /usr/local/bin/update-repo.sh
RUN chmod +x /usr/local/bin/update-repo.sh

# Create directories
RUN mkdir -p /var/www/fdroid/repo \
    /var/www/fdroid/metadata \
    /var/www/fdroid/unsigned \
    /var/www/fdroid/keystore

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/repo/index-v1.jar || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
