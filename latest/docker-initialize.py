#!/usr/local/bin/python
import os
import re


class Environment(object):
    """Configure container via environment variables"""

    def __init__(
        self, env=os.environ,
        zope_conf="/home/senaite/senaitelims/parts/instance/etc/zope.conf",
        custom_conf="/home/senaite/senaitelims/custom.cfg",
        zeopack_conf="/home/senaite/senaitelims/bin/zeopack",
        cors_conf="/home/senaite/senaitelims/parts/instance/etc/package-includes/999-additional-overrides.zcml"
    ):
        self.env = env
        self.zope_conf = zope_conf
        self.custom_conf = custom_conf
        self.zeopack_conf = zeopack_conf
        self.cors_conf = cors_conf

        # ZEO server config: depending on buildout it can be in parts/zeo or parts/zeoserver
        self.zeo_confs = [
            "/home/senaite/senaitelims/parts/zeo/etc/zeo.conf",
            "/home/senaite/senaitelims/parts/zeoserver/etc/zeo.conf",
        ]

    def zeoclient(self):
        """ZEO Client"""
        server = self.env.get("ZEO_ADDRESS", None)
        if not server:
            return

        with open(self.zope_conf, "r") as cfile:
            config = cfile.read()

        # Already initialized (no blobstorage marker)
        if "<blobstorage>" not in config:
            return

        read_only = self.env.get("ZEO_READ_ONLY", "false")
        zeo_ro_fallback = self.env.get("ZEO_CLIENT_READ_ONLY_FALLBACK", "false")
        shared_blob_dir = self.env.get("ZEO_SHARED_BLOB_DIR", "off")
        zeo_storage = self.env.get("ZEO_STORAGE", "1")
        zeo_client_cache_size = self.env.get("ZEO_CLIENT_CACHE_SIZE", "128MB")

        zeo_conf = ZEO_TEMPLATE.format(
            zeo_address=server,
            read_only=read_only,
            zeo_client_read_only_fallback=zeo_ro_fallback,
            shared_blob_dir=shared_blob_dir,
            zeo_storage=zeo_storage,
            zeo_client_cache_size=zeo_client_cache_size
        )

        pattern = re.compile(r"<blobstorage>.+</blobstorage>", re.DOTALL)
        config = re.sub(pattern, zeo_conf, config)

        with open(self.zope_conf, "w") as cfile:
            cfile.write(config)

    def set_zeo_bind_port(self):
        """Set zeo server bind/port in zeo.conf (server side)"""
        zeo_port = self.env.get("ZEO_PORT", "").strip()
        zeo_bind = self.env.get("ZEO_BIND", "").strip() or "127.0.0.1"
        if not zeo_port:
            return

        for conf in self.zeo_confs:
            if not os.path.exists(conf):
                continue

            with open(conf, "r") as f:
                text = f.read()

            new = text

            # Replace any address form with bind:port
            # address 8080
            # address 127.0.0.1:8080
            # address 0.0.0.0:8080
            # address [::]:8080
            new = re.sub(
                r'(^\s*address\s+)(?:([0-9a-fA-F\.\:\[\]]+):)?(\d+)\s*$',
                lambda m: m.group(1) + ("%s:%s" % (zeo_bind, zeo_port)),
                new, flags=re.M
            )

            # If no address line exists at all, append one (safe)
            if not re.search(r'^\s*address\s+', new, flags=re.M):
                new += "\n  address %s:%s\n" % (zeo_bind, zeo_port)

            if new != text:
                with open(conf, "w") as f:
                    f.write(new)

    def set_http_port(self):
        """Set instance HTTP port (zope.conf)"""
        http_port = self.env.get("HTTP_PORT", "").strip()
        if not http_port:
            return

        if not os.path.exists(self.zope_conf):
            return

        with open(self.zope_conf, "r") as f:
            text = f.read()

        new = text

        # Matches:
        # http-address 8080
        # http-address = 8080
        # http-address 0.0.0.0:8080
        # http-address = 0.0.0.0:8080
        new = re.sub(
            r'(^\s*http-address\s*=?\s*)(?:([0-9a-fA-F\.\:\[\]]+):)?(\d+)\s*$',
            lambda m: m.group(1) + ((m.group(2) + ":") if m.group(2) else "") + http_port,
            new, flags=re.M
        )

        # Some templates use "address" for the http listener
        new = re.sub(
            r'(^\s*address\s*=?\s*)(?:([0-9a-fA-F\.\:\[\]]+):)?(\d+)\s*$',
            lambda m: m.group(1) + ((m.group(2) + ":") if m.group(2) else "") + http_port,
            new, flags=re.M
        )

        if new != text:
            with open(self.zope_conf, "w") as f:
                f.write(new)

    def zeopack(self):
        """ZEO Pack helper script points to correct server"""
        server = self.env.get("ZEO_ADDRESS", None)
        if not server:
            return

        if ":" in server:
            host, port = server.split(":")
        else:
            host, port = (server, "8080")

        if not os.path.exists(self.zeopack_conf):
            return

        with open(self.zeopack_conf, 'r') as cfile:
            text = cfile.read()

        text = re.sub(r'address\s*=\s*".*?"', 'address = "%s"' % server, text)
        text = re.sub(r'host\s*=\s*".*?"', 'host = "%s"' % host, text)
        text = re.sub(r'port\s*=\s*".*?"', 'port = "%s"' % port, text)

        with open(self.zeopack_conf, 'w') as cfile:
            cfile.write(text)

    def zeoserver(self):
        """ZEO Server extra options"""
        pack_keep_old = self.env.get("ZEO_PACK_KEEP_OLD", '')
        if pack_keep_old.lower() in ("false", "no", "0", "n", "f"):
            for conf in self.zeo_confs:
                if not os.path.exists(conf):
                    continue
                with open(conf, 'r') as cfile:
                    text = cfile.read()
                if 'pack-keep-old' not in text:
                    text = text.replace(
                        '</filestorage>',
                        '  pack-keep-old false\n</filestorage>'
                    )
                    with open(conf, 'w') as cfile:
                        cfile.write(text)

    def cors(self):
        """Configure CORS Policies"""
        if not [e for e in self.env if e.startswith("CORS_")]:
            return

        allow_origin = self.env.get("CORS_ALLOW_ORIGIN",
            "http://localhost:3000,http://127.0.0.1:3000")
        allow_methods = self.env.get("CORS_ALLOW_METHODS",
            "DELETE,GET,OPTIONS,PATCH,POST,PUT")
        allow_credentials = self.env.get("CORS_ALLOW_CREDENTIALS", "true")
        expose_headers = self.env.get("CORS_EXPOSE_HEADERS",
            "Content-Length,X-My-Header")
        allow_headers = self.env.get("CORS_ALLOW_HEADERS",
            "Accept,Authorization,Content-Type,X-Custom-Header")
        max_age = self.env.get("CORS_MAX_AGE", "3600")

        cors_conf = CORS_TEMPLACE.format(
            allow_origin=allow_origin,
            allow_methods=allow_methods,
            allow_credentials=allow_credentials,
            expose_headers=expose_headers,
            allow_headers=allow_headers,
            max_age=max_age
        )
        with open(self.cors_conf, "w") as cfile:
            cfile.write(cors_conf)

    def buildout(self):
        """Buildout from environment variables"""
        if os.path.exists(self.custom_conf):
            return

        findlinks = self.env.get("FIND_LINKS", "").strip().split()
        eggs = self.env.get("PLONE_ADDONS", self.env.get("ADDONS", "")).strip().split()
        zcml = self.env.get("PLONE_ZCML", self.env.get("ZCML", "")).strip().split()
        develop = self.env.get("PLONE_DEVELOP", self.env.get("DEVELOP", "")).strip().split()
        site = self.env.get("PLONE_SITE", self.env.get("SITE", "")).strip()
        profiles = self.env.get("PLONE_PROFILES", self.env.get("PROFILES", "")).strip().split()
        versions = self.env.get("PLONE_VERSIONS", self.env.get("VERSIONS", "")).strip().split()
        sources = self.env.get("SOURCES", "").strip().split(",")
        password = self.env.get("PASSWORD", "").strip()

        if not profiles:
            for egg in eggs:
                base = egg.split("=")[0]
                profiles.append("%s:default" % base)

        if not (eggs or zcml or develop or site or password):
            return

        buildout = BUILDOUT_TEMPLATE.format(
            password=password or "admin",
            findlinks="\n\t".join(findlinks),
            eggs="\n\t".join(eggs),
            zcml="\n\t".join(zcml),
            develop="\n\t".join(develop),
            versions="\n".join(versions),
            sources="\n".join(sources),
        )

        if site:
            buildout += PLONESITE_TEMPLATE.format(
                site=site,
                profiles="\n\t".join(profiles),
            )

        server = self.env.get("ZEO_ADDRESS", None)
        if server:
            buildout += ZEO_INSTANCE_TEMPLATE.format(
                zeoaddress=server,
            )

        with open(self.custom_conf, 'w') as cfile:
            cfile.write(buildout)

    def setup(self):
        self.buildout()
        self.cors()
        self.zeoclient()
        self.zeopack()
        self.zeoserver()
        self.set_zeo_bind_port()
        self.set_http_port()


ZEO_TEMPLATE = """
    <zeoclient>
      read-only {read_only}
      read-only-fallback {zeo_client_read_only_fallback}
      blob-dir /data/blobstorage
      shared-blob-dir {shared_blob_dir}
      server {zeo_address}
      storage {zeo_storage}
      name zeostorage
      var /home/senaite/senaitelims/parts/instance/var
      cache-size {zeo_client_cache_size}
    </zeoclient>
""".strip()

CORS_TEMPLACE = """<configure
  xmlns="http://namespaces.zope.org/zope">
  <configure
    xmlns="http://namespaces.zope.org/zope"
    xmlns:plone="http://namespaces.plone.org/plone">
    <plone:CORSPolicy
      allow_origin="{allow_origin}"
      allow_methods="{allow_methods}"
      allow_credentials="{allow_credentials}"
      expose_headers="{expose_headers}"
      allow_headers="{allow_headers}"
      max_age="{max_age}"
     />
  </configure>
</configure>
"""

BUILDOUT_TEMPLATE = """
[buildout]
extends = buildout.cfg
user=admin:{password}
find-links += {findlinks}
develop += {develop}
eggs += {eggs}
zcml += {zcml}

[versions]
{versions}

[sources]
{sources}
"""

PLONESITE_TEMPLATE = """

[plonesite]
enabled = true
site-id = {site}
profiles += {profiles}
"""

ZEO_INSTANCE_TEMPLATE = """

[instance]
zeo-client = true
zeo-address = {zeoaddress}
shared-blob = off
http-fast-listen = off
"""


def initialize():
    environment = Environment()
    environment.setup()


if __name__ == "__main__":
    initialize()
