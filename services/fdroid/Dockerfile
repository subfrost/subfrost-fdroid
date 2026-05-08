FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    fdroidserver \
    apksigner \
    default-jre-headless \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/fdroid /var/log/nginx

COPY services/fdroid/nginx.conf /etc/nginx/nginx.conf
COPY services/fdroid/config.yml /etc/fdroid/config.yml
COPY services/fdroid/entrypoint.sh /entrypoint.sh
COPY web/ /var/www/fdroid/
COPY metadata/ /etc/fdroid/metadata/

RUN chmod +x /entrypoint.sh

WORKDIR /fdroid
EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
