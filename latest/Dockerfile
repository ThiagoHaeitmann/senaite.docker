FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Dependências de build do Python 2.7 + libs que o Plone/SENAITE costuma precisar
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git bash \
    build-essential make \
    libbz2-dev zlib1g-dev libssl-dev \
    libsqlite3-dev libffi-dev uuid-dev libnss3-dev libgdbm-dev libgdbm-compat-dev \
    libncursesw5-dev liblzma-dev libreadline-dev \
    libpcre3-dev libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    rsync tini \
 && rm -rf /var/lib/apt/lists/*

# pyenv + python2.7.18
RUN git clone --depth 1 https://github.com/pyenv/pyenv.git /opt/pyenv \
 && /opt/pyenv/bin/pyenv install 2.7.18 \
 && /opt/pyenv/bin/pyenv global 2.7.18

# buildout toolchain
RUN pip install --no-cache-dir "setuptools==44.1.1" "zc.buildout==2.13.8" wheel

# App
WORKDIR /app
COPY buildout.cfg.template /app/buildout.cfg.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# dirs padrão (você vai bindar volume nelas)
RUN mkdir -p /data/zeo /data/blob /data/var /app/instance

ENV \
  SENAITE_VERSION=2.6.0 \
  HTTP_ADDRESS=0.0.0.0 \
  HTTP_PORT=8080 \
  ZEO_LISTEN=127.0.0.1 \
  ZEO_PORT=8100 \
  ZEO_ADDRESS=127.0.0.1:8100 \
  ADMIN_USER=admin \
  ADMIN_PASS=admin \
  PLONE_SITE=senaite

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD ["instance"]
