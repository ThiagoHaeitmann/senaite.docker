#!/usr/bin/env bash
set -euo pipefail

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
require_port_int "ZEO_PORT" "${ZEO_PORT}"

[[ -f "${TEMPLATE}" ]] || die "Missing ${TEMPLATE}"

if [[ "${MODE}" == "instance" || "${MODE}" == "fg" ]]; then
  [[ -n "${ZEO_ADDRESS}" ]] || die "ZEO_ADDRESS is required (e.g. 127.0.0.1:8100)"
fi

mkdir -p "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs"

if is_true "${FIX_PERMS}"; then
  log "Fixing permissions (PUID=${PUID}, PGID=${PGID}) ..."
  chown -R "${PUID}:${PGID}" "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
  chmod -R u+rwX,g+rwX "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
fi

# Gera buildout.cfg SEM ${ENV:...} / ${env:...}
python - <<'PY'
import os, io

template = "/app/buildout.cfg.template"
outcfg   = "/app/buildout.cfg"

repl = {
  "@SENAITE_VERSION@": os.environ.get("SENAITE_VERSION","2.6.0"),
  "@HTTP_ADDRESS@":    os.environ.get("HTTP_ADDRESS","0.0.0.0"),
  "@HTTP_PORT@":       os.environ.get("HTTP_PORT","8080"),
  "@ZEO_LISTEN@":      os.environ.get("ZEO_LISTEN","127.0.0.1"),
  "@ZEO_PORT@":        os.environ.get("ZEO_PORT","8100"),
  "@ZEO_ADDRESS@":     os.environ.get("ZEO_ADDRESS","127.0.0.1:8100"),
  "@ADMIN_USER@":      os.environ.get("ADMIN_USER","admin"),
  "@ADMIN_PASS@":      os.environ.get("ADMIN_PASS","admin"),
}

data = io.open(template, "r", encoding="utf-8").read()
for k,v in repl.items():
  data = data.replace(k, v)

io.open(outcfg, "w", encoding="utf-8").write(data)
print("[senaite] buildout.cfg generated:", outcfg)
PY

need_buildout=0
[[ -x "${APP_DIR}/bin/buildout"   ]] || need_buildout=1
[[ -x "${APP_DIR}/bin/instance"   ]] || need_buildout=1
[[ -x "${APP_DIR}/bin/zeoserver"  ]] || need_buildout=1

if (( need_buildout == 1 )); then
  if is_true "${RUN_BUILDOUT}"; then
    log "Running buildout (bin/* missing)..."
    python -c "import zc.buildout" >/dev/null 2>&1 || pip install -q "zc.buildout==2.13.8"
    buildout -c "${CFG}"
  else
    die "bin/* missing but RUN_BUILDOUT=0"
  fi
else
  log "buildout OK (bin/* exists)."
fi

case "${MODE}" in
  zeo)
    log "Starting ZEO server..."
    exec "${APP_DIR}/bin/zeoserver" fg
    ;;
  instance|fg)
    log "Starting SENAITE instance..."
    exec "${APP_DIR}/bin/instance" fg
    ;;
  check)
    log "Health check:"
    ls -la "${CFG}" "${APP_DIR}/bin/instance" "${APP_DIR}/bin/zeoserver" || true
    exit 0
    ;;
  *)
    die "Unknown MODE '${MODE}'. Use: zeo | instance | fg | check"
    ;;
esac
