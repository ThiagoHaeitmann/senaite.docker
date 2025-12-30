FROM python:2.7-slim-buster

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Buster é EOL → usar archive.debian.org
RUN set -eux; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until; \
    sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list; \
    sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list; \
    sed -i '/buster-updates/d' /etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates bash git curl \
      build-essential gcc g++ make \
      libssl-dev libffi-dev zlib1g-dev libjpeg62-turbo-dev \
      libxml2-dev libxslt1-dev \
      libpcre3-dev libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
      tini; \
    rm -rf /var/lib/apt/lists/*

# toolchain buildout alinhada com Plone 5.2/Py2
RUN pip install --no-cache-dir "setuptools==44.1.1" "zc.buildout==2.13.8" wheel

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY buildout.cfg.template /app/buildout.cfg.template
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
 && mkdir -p /data/zeo /data/blob /data/var /app/eggs /app/downloads

ENV \
  SENAITE_VERSION=2.6.0 \
  HTTP_ADDRESS=0.0.0.0 \
  HTTP_PORT=8080 \
  ZEO_LISTEN=127.0.0.1 \
  ZEO_PORT=8100 \
  ZEO_ADDRESS=127.0.0.1:8100 \
  ADMIN_USER=admin \
  ADMIN_PASS=admin

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD ["instance"]
