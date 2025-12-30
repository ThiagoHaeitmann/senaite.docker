# ---- builder: compila Python 2.7.18 em Debian 12 ----
FROM debian:12-slim AS py2builder

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
    # se usar senaite.ldap: geralmente precisa compilar ldap/python-ldap
    libldap2-dev libsasl2-dev \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/pyenv/pyenv.git /opt/pyenv \
 && pyenv install 2.7.18 \
 && pyenv global 2.7.18

# Python 2: pip novo quebra. Instala toolchain compatível com Plone 5.2 (Py2).
RUN pip install --no-cache-dir "pip<21" \
 && pip install --no-cache-dir "setuptools==42.0.2" "wheel==0.37.1" "zc.buildout==2.13.8"


# ---- runtime: Debian 12-slim, só libs runtime + pyenv pronto ----
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bash git curl \
    # libs runtime pro Python 2.7 compilado
    libbz2-1.0 liblzma5 libreadline8 libsqlite3-0 \
    libffi8 libncursesw6 libtinfo6 libgdbm6 libuuid1 \
    libssl3 libnss3 \
    # libs runtime Plone/SENAITE (cairo/pango etc.)
    libpcre3 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libxml2 libxslt1.1 libjpeg62-turbo \
    # se usar senaite.ldap em runtime:
    libldap-2.5-0 libsasl2-2 \
    tini \
 && rm -rf /var/lib/apt/lists/*

COPY --from=py2builder /opt/pyenv /opt/pyenv

WORKDIR /app

# requirements do Plone 5.2.15 (Py2/Py3) — no teu caso Py2, então ele puxa setuptools 42.0.2
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir "pip<21" \
 && pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir "zc.buildout==2.13.8"

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
  ADMIN_PASS=admin \
  RUN_BUILDOUT=1 \
  FIX_PERMS=0

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD ["instance"]
