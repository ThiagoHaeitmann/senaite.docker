# ---- builder: compila Python 2.7.18 + roda buildout e deixa /app pronto ----
FROM debian:12-slim AS py2builder

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# deps de build (gcc etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash patch xz-utils \
    build-essential make gcc g++ \
    dpkg-dev libc6-dev libjpeg62-turbo-dev libopenjp2-7-dev libtiff-dev \
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

# --- cria user senaite no builder ---
ARG SENAITE_UID=1000
ARG SENAITE_GID=1000
RUN groupadd -g ${SENAITE_GID} senaite \
 && useradd -m -u ${SENAITE_UID} -g ${SENAITE_GID} -s /bin/bash senaite

# pyenv + python2
RUN git clone --depth 1 https://github.com/pyenv/pyenv.git /opt/pyenv \
 && pyenv install 2.7.18 \
 && pyenv global 2.7.18

# toolchain pip/setuptools/buildout compatível py2
RUN pip install --no-cache-dir "pip==20.3.4" \
 && pip install --no-cache-dir "setuptools==42.0.2" "wheel==0.37.1" "zc.buildout==2.13.8"

WORKDIR /app

# requirements base (seu requirements.txt)
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt \
 && pip install --no-cache-dir "zc.buildout==2.13.8"

# buildout template + entrypoint
COPY buildout.cfg.template /app/buildout.cfg.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh 

RUN mkdir -p /data/zeo /data/blob/blobstorage /data/var/log /data/var/cache /data/var/instance \
             /app/eggs /app/downloads /app/src \
 && chown -R senaite:senaite /app /data


# defaults (podem ser sobrescritos no Nomad)
ENV \
  SENAITE_VERSION=2.6.0 \
  HTTP_ADDRESS=0.0.0.0 \
  HTTP_PORT=8080 \
  ZEO_LISTEN=127.0.0.1 \
  ZEO_PORT=8100 \
  ZEO_ADDRESS=127.0.0.1:8100 \
  ADMIN_USER=admin \
  ADMIN_PASS=admin

USER senaite

# gera buildout.cfg sem ${ENV:} e roda buildout AQUI NO BUILDER
RUN /entrypoint.sh render-config \
 && buildout -c /app/buildout.cfg \
 && test -x /app/bin/instance \
 && test -x /app/bin/zeoserver

RUN mkdir -p /app/var /app/var/log \
 && chown -R senaite:senaite /app/var

USER root



 
# ---- runtime: leve, sem gcc, só roda ----
FROM debian:12-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYENV_ROOT=/opt/pyenv

# libs runtime (sem build-essential)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bash git curl \
    gosu lynx procps rsync vim \
    zlib1g libexpat1 libcrypt1 \
    libgdk-pixbuf2.0-0 libopenjp2-7 libtiff6 \
    tk8.6 \
    libbz2-1.0 liblzma5 libreadline8 libsqlite3-0 \
    libffi8 libncursesw6 libtinfo6 libgdbm6 libuuid1 \
    libssl3 libnss3 \
    libpcre3 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libxml2 libxslt1.1 libjpeg62-turbo \
    libldap-2.5-0 libsasl2-2 \
    tini \
 && rm -rf /var/lib/apt/lists/*

# --- cria user senaite no runtime ---
ARG SENAITE_UID=1000
ARG SENAITE_GID=1000
RUN groupadd -g ${SENAITE_GID} senaite \
 && useradd -m -u ${SENAITE_UID} -g ${SENAITE_GID} -s /bin/bash senaite

# pyenv e python2
COPY --from=py2builder /opt/pyenv /opt/pyenv

ENV PYTHON_VERSION=2.7.18
ENV PATH=/opt/pyenv/versions/${PYTHON_VERSION}/bin:/opt/pyenv/bin:/opt/pyenv/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

# copia /app pronto do builder
COPY --from=py2builder /app /app
COPY --from=py2builder /entrypoint.sh /entrypoint.sh

RUN mkdir -p /data/zeo /data/blob/blobstorage /data/var/log /data/var/cache /data/var/instance \
 && chown -R senaite:senaite /app /data \
 && ln -sf /opt/pyenv/versions/${PYTHON_VERSION}/bin/python /usr/local/bin/python \
 && ln -sf /opt/pyenv/versions/${PYTHON_VERSION}/bin/pip /usr/local/bin/pip \
 && /opt/pyenv/bin/pyenv rehash || true \
 && chmod +x /entrypoint.sh \
 && test -x /app/bin/instance \
 && test -x /app/bin/zeoserver

RUN mkdir -p /app/var /app/var/log \
 && chown -R senaite:senaite /app/var

# defaults (podem ser sobrescritos no Nomad)
ENV \
  SENAITE_VERSION=2.6.0 \
  HTTP_ADDRESS=0.0.0.0 \
  HTTP_PORT=8080 \
  ZEO_LISTEN=127.0.0.1 \
  ZEO_PORT=8100 \
  ZEO_ADDRESS=127.0.0.1:8100 \
  ADMIN_USER=admin \
  ADMIN_PASS=admin \
  RUN_BUILDOUT=0 \
  FIX_PERMS=0

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD ["instance"]
