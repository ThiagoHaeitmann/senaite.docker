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

: "${RUN_AS_USER:=senaite}"
: "${RUN_AS_GROUP:=senaite}"


APP_DIR="/app"
TEMPLATE="${APP_DIR}/buildout.cfg.template"
CFG="${APP_DIR}/buildout.cfg"

log(){ echo "[senaite] $*"; }
die(){ echo "[senaite][FATAL] $*" >&2; exit 1; }

is_true() { case "${1,,}" in 1|true|yes|y|on) return 0;; *) return 1;; esac; }

case "${MODE}" in
  instance|zeo|check|render-config) ;;
  *)
    exec "$@"
    ;;
esac

mkdir -p "${DATA_ZEO}" "${DATA_BLOB}/blobstorage" "${DATA_VAR}" \
  "${DATA_VAR}/log" "${DATA_VAR}/cache" "${DATA_VAR}/instance" \
  "${APP_DIR}/downloads" "${APP_DIR}/eggs" \
  /data/var/log /data/var/cache /data/var/instance

touch "${DATA_VAR}/log/instance-access.log" \
      "${DATA_VAR}/log/instance-error.log" \
      "${DATA_VAR}/log/zeo.log" \
      "${DATA_VAR}/log/zeo-access.log" || true

[[ -f "${TEMPLATE}" ]] || die "Missing ${TEMPLATE}"

if is_true "${FIX_PERMS}"; then
  mkdir -p "${DATA_VAR}/log"
  chown -R "${RUN_AS_USER}:${RUN_AS_GROUP}" "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" || true
  chmod -R u+rwX,g+rwX "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" || true
fi

run_as() {
  # Se não for root, roda normal
  if [ "$(id -u)" -ne 0 ]; then
    exec "$@"
  fi

  # Se for root e existir gosu, roda como senaite
  if command -v gosu >/dev/null 2>&1; then
    exec gosu "${RUN_AS_USER}:${RUN_AS_GROUP}" "$@"
  fi

  # fallback (menos elegante, mas funciona)
  exec su -s /bin/bash -c "$(printf '%q ' "$@")" "${RUN_AS_USER}"
}

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

case "${MODE}" in
  render-config)
    exit 0
    ;;
  check)
    ls -la "${CFG}" || true
    # NÃO exige /app/bin aqui.
    exit 0
    ;;
esac

if [ ! -x "${APP_DIR}/bin/instance" ] || [ ! -x "${APP_DIR}/bin/zeoserver" ]; then
  if is_true "${RUN_BUILDOUT}"; then
    die "Image missing ${APP_DIR}/bin/* and RUN_BUILDOUT=1. This runtime image has no gcc. Rebuild the image so buildout runs in the builder stage."
  fi
  die "Image missing ${APP_DIR}/bin/* (buildout not executed during build). Rebuild the image (builder stage must run buildout)."
fi

if is_true "${RUN_BUILDOUT}"; then
  die "RUN_BUILDOUT=1 is not supported in runtime. Rebuild the image; buildout must run in builder stage."
fi

case "${MODE}" in
  zeo)      run_as "${APP_DIR}/bin/zeoserver" fg ;;
  instance) run_as "${APP_DIR}/bin/instance"  fg ;;
  check)    ls -la "${CFG}" "${APP_DIR}/bin/instance" "${APP_DIR}/bin/zeoserver" || true; exit 0 ;;
  *)        die "Unknown MODE '${MODE}' (use zeo|instance|check)" ;;
esac


