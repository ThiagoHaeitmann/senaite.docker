# ---------- builder (com toolchain) ----------
FROM debian:12-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash patch xz-utils \
    build-essential make gcc g++ \
    libbz2-dev zlib1g-dev libssl-dev \
    libreadline-dev libsqlite3-dev \
    libffi-dev uuid-dev liblzma-dev \
    libncursesw5-dev tk-dev \
    libnss3-dev libgdbm-dev libgdbm-compat-dev \
    libexpat1-dev \
    libxml2-dev libxslt1-dev libjpeg-dev \
    libpcre3-dev libcairo2-dev libpango1.0-dev \
    libldap2-dev libsasl2-dev \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/pyenv/pyenv.git /opt/pyenv \
 && pyenv install 2.7.18 \
 && pyenv global 2.7.18

# toolchain python2 compat
RUN pip install --no-cache-dir "pip<21" \
 && pip install --no-cache-dir "setuptools==42.0.2" "wheel==0.37.1" "zc.buildout==2.13.8"

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir "zc.buildout==2.13.8"

COPY buildout.cfg.template /app/buildout.cfg.template

# Gera buildout.cfg com defaults (não precisa ENV section nem ${ENV:})
RUN /opt/pyenv/versions/2.7.18/bin/python - <<'PY'
import os, io
template="/app/buildout.cfg.template"
outcfg="/app/buildout.cfg"
repl={
  "@SENAITE_VERSION@": "2.6.0",
  "@HTTP_ADDRESS@": "0.0.0.0",
  "@HTTP_PORT@": "8080",
  "@ZEO_LISTEN@": "127.0.0.1",
  "@ZEO_PORT@": "8100",
  "@ZEO_ADDRESS@": "127.0.0.1:8100",
  "@ADMIN_USER@": "admin",
  "@ADMIN_PASS@": "admin",
}
data=io.open(template,"r",encoding="utf-8").read()
for k,v in repl.items():
  data=data.replace(k,v)
io.open(outcfg,"w",encoding="utf-8").write(data)
print("generated", outcfg)
PY

# Roda buildout AQUI (com gcc), deixa /app pronto
RUN buildout -c /app/buildout.cfg

# ---------- runtime (sem gcc) ----------
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bash curl \
    # libs runtime
    libbz2-1.0 liblzma5 libreadline8 libsqlite3-0 \
    libffi8 libncursesw6 libtinfo6 libgdbm6 libuuid1 \
    libssl3 libnss3 \
    libpcre3 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libxml2 libxslt1.1 libjpeg62-turbo \
    libldap-2.5-0 libsasl2-2 \
    tini \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/pyenv /opt/pyenv
COPY --from=builder /app /app

ENV PYTHON_VERSION=2.7.18 \
    PATH=/opt/pyenv/versions/2.7.18/bin:/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN ln -sf /opt/pyenv/versions/2.7.18/bin/python /usr/local/bin/python \
 && ln -sf /opt/pyenv/versions/2.7.18/bin/pip /usr/local/bin/pip \
 && /opt/pyenv/bin/pyenv rehash || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && mkdir -p /data/zeo /data/blob /data/var

WORKDIR /app

ENV \
  SENAITE_VERSION=2.6.0 \
  HTTP_ADDRESS=0.0.0.0 \
  HTTP_PORT=8080 \
  ZEO_LISTEN=127.0.0.1 \
  ZEO_PORT=8100 \
  ZEO_ADDRESS=127.0.0.1:8100 \
  ADMIN_USER=admin \
  ADMIN_PASS=admin \
  FIX_PERMS=0 \
  PUID=0 \
  PGID=0

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD ["instance"]
