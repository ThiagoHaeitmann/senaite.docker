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

: "${RUN_BUILDOUT:=0}"
: "${FIX_PERMS:=0}"
: "${PUID:=0}"
: "${PGID:=0}"

APP_DIR="/app"
TEMPLATE="${APP_DIR}/buildout.cfg.template"
CFG="${APP_DIR}/buildout.cfg"

log(){ echo "[senaite] $*"; }
die(){ echo "[senaite][FATAL] $*" >&2; exit 1; }

is_true() { case "${1,,}" in 1|true|yes|y|on) return 0;; *) return 1;; esac; }

mkdir -p "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs"

[[ -f "${TEMPLATE}" ]] || die "Missing ${TEMPLATE}"

if is_true "${FIX_PERMS}"; then
  chown -R "${PUID}:${PGID}" "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
  chmod -R u+rwX,g+rwX "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" "${APP_DIR}/downloads" "${APP_DIR}/eggs" || true
fi

# Gera buildout.cfg sem ${ENV:...}
python - <<'PY'
import os, io
template="/app/buildout.cfg.template"
outcfg="/app/buildout.cfg"
repl={
  "@SENAITE_VERSION@": os.environ.get("SENAITE_VERSION","2.6.0"),
  "@HTTP_ADDRESS@":    os.environ.get("HTTP_ADDRESS","0.0.0.0"),
  "@HTTP_PORT@":       os.environ.get("HTTP_PORT","8080"),
  "@ZEO_LISTEN@":      os.environ.get("ZEO_LISTEN","127.0.0.1"),
  "@ZEO_PORT@":        os.environ.get("ZEO_PORT","8100"),
  "@ZEO_ADDRESS@":     os.environ.get("ZEO_ADDRESS","127.0.0.1:8100"),
  "@ADMIN_USER@":      os.environ.get("ADMIN_USER","admin"),
  "@ADMIN_PASS@":      os.environ.get("ADMIN_PASS","admin"),
}
data=io.open(template,"r",encoding="utf-8").read()
for k,v in repl.items():
  data=data.replace(k,v)
io.open(outcfg,"w",encoding="utf-8").write(data)
print("[senaite] buildout.cfg generated:", outcfg)
PY

if is_true "${RUN_BUILDOUT}"; then
  log "RUN_BUILDOUT=1 -> running buildout"
  buildout -c "${CFG}"
else
  log "RUN_BUILDOUT=0 -> skipping buildout"
fi

case "${MODE}" in
  zeo)      exec "${APP_DIR}/bin/zeoserver" fg ;;
  instance) exec "${APP_DIR}/bin/instance"  fg ;;
  check)    ls -la "${CFG}" "${APP_DIR}/bin/instance" "${APP_DIR}/bin/zeoserver" || true; exit 0 ;;
  *)        die "Unknown MODE '${MODE}' (use zeo|instance|check)" ;;
esac
