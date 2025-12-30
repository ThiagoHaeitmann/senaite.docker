#!/usr/bin/env bash
set -euo pipefail

# ---------- defaults ----------
MODE="${1:-${MODE:-instance}}"

: "${SENAITE_VERSION:=2.6.0}"
: "${HTTP_ADDRESS:=0.0.0.0}"
: "${HTTP_PORT:=8080}"

: "${ZEO_LISTEN:=127.0.0.1}"
: "${ZEO_PORT:=8100}"
: "${ZEO_ADDRESS:=127.0.0.1:${ZEO_PORT}}"

: "${ADMIN_USER:=admin}"
: "${ADMIN_PASS:=admin}"

: "${DATA_ZEO:=/data/zeo}"
: "${DATA_BLOB:=/data/blob}"
: "${DATA_VAR:=/data/var}"

: "${RUN_BUILDOUT:=1}"
: "${FIX_PERMS:=0}"
: "${PUID:=0}"
: "${PGID:=0}"

APP_DIR="/app"
TEMPLATE="${APP_DIR}/buildout.cfg.template"
CFG="${APP_DIR}/buildout.cfg"

log() { echo "[senaite] $*"; }
die() { echo "[senaite][FATAL] $*" >&2; exit 1; }

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_port_int() {
  local name="$1" val="$2"
  [[ "$val" =~ ^[0-9]+$ ]] || die "${name} must be an integer, got: ${val}"
  (( val > 0 && val < 65536 )) || die "${name} must be 1-65535, got: ${val}"
}

# ---------- sanity ----------
log "MODE=${MODE}"
log "SENAITE_VERSION=${SENAITE_VERSION}"
log "HTTP=${HTTP_ADDRESS}:${HTTP_PORT}"
log "ZEO_LISTEN=${ZEO_LISTEN}:${ZEO_PORT}"
log "ZEO_ADDRESS=${ZEO_ADDRESS}"
log "ADMIN_USER=${ADMIN_USER}"
log "DATA_ZEO=${DATA_ZEO} DATA_BLOB=${DATA_BLOB} DATA_VAR=${DATA_VAR}"
log "RUN_BUILDOUT=${RUN_BUILDOUT} FIX_PERMS=${FIX_PERMS} PUID=${PUID} PGID=${PGID}"

if [[ "${MODE}" == "instance" || "${MODE}" == "fg" ]]; then
  require_port_int "HTTP_PORT" "${HTTP_PORT}"
fi
require_port_int "ZEO_PORT" "${ZEO_PORT}

if [[ ! -f "${TEMPLATE}" ]]; then
  die "Missing ${TEMPLATE}. You must COPY buildout.cfg.template into the image at ${TEMPLATE}"
fi

# instance precisa do ZEO_ADDRESS
if [[ "${MODE}" == "instance" || "${MODE}" == "fg" ]]; then
  [[ -n "${ZEO_ADDRESS}" ]] || die "ZEO_ADDRESS is required in instance mode (e.g. 127.0.0.1:8100)"
fi

# ---------- prepare dirs ----------
mkdir -p "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs"

# ---------- optional perms fix ----------
if is_true "${FIX_PERMS}"; then
  log "Fixing permissions on data dirs (PUID=${PUID}, PGID=${PGID}) ..."
  # Só nos diretórios que interessam (sem varrer /data inteiro)
  chown -R "${PUID}:${PGID}" "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
  chmod -R u+rwX,g+rwX "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
fi

# ---------- write buildout.cfg ----------
# Aqui não "substitui" nada: buildout usa ${ENV:VAR} direto.
# escreve o template
cat "${TEMPLATE}" > "${CFG}"

# injeta seção ENV com os valores do container/Nomad
cat >> "${CFG}" <<EOF

[ENV]
SENAITE_VERSION = ${SENAITE_VERSION}
HTTP_ADDRESS = ${HTTP_ADDRESS}
HTTP_PORT = ${HTTP_PORT}
ZEO_LISTEN = ${ZEO_LISTEN}
ZEO_PORT = ${ZEO_PORT}
ZEO_ADDRESS = ${ZEO_ADDRESS}
ADMIN_USER = ${ADMIN_USER}
ADMIN_PASS = ${ADMIN_PASS}
EOF


# ---------- buildout idempotent ----------
need_buildout=0
if [[ ! -x "${APP_DIR}/bin/buildout" ]]; then need_buildout=1; fi
if [[ ! -x "${APP_DIR}/bin/instance" ]]; then need_buildout=1; fi
if [[ ! -x "${APP_DIR}/bin/zeoserver" ]]; then need_buildout=1; fi

if (( need_buildout == 1 )); then
  if is_true "${RUN_BUILDOUT}"; then
    log "Running buildout (bin/* missing)..."
    # garante toolchain
    python -c "import zc.buildout" >/dev/null 2>&1 || pip install -q "zc.buildout==2.13.8"
    buildout -c "${CFG}"
  else
    die "bin/* missing but RUN_BUILDOUT=0. Refusing to start."
  fi
else
  log "buildout OK (bin/* exists)."
fi

# ---------- start ----------
case "${MODE}" in
  zeo)
    # ZEO: só servidor
    log "Starting ZEO server..."
    exec "${APP_DIR}/bin/zeoserver" fg
    ;;
  instance|fg)
    # Instance: web
    log "Starting SENAITE instance..."
    exec "${APP_DIR}/bin/instance" fg
    ;;
  check)
    log "Health check:"
    log " - buildout cfg: ${CFG}"
    log " - instance bin: ${APP_DIR}/bin/instance"
    log " - zeoserver bin: ${APP_DIR}/bin/zeoserver"
    exit 0
    ;;
  *)
    die "Unknown MODE '${MODE}'. Use: zeo | instance | fg | check"
    ;;
esac
