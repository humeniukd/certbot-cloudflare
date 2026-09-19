# Minimal Certbot image containing only the Cloudflare DNS plugin.

# ---- builder: compile/install everything into an isolated venv ----
FROM alpine:3.24 AS builder

ARG CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN apk add --no-cache \
        python3 py3-pip \
        gcc linux-headers openssl-dev musl-dev libffi-dev \
        python3-dev cargo git pkgconfig

WORKDIR /build
COPY certbot/CHANGELOG.md certbot/README.rst src/
COPY certbot/tools tools
COPY certbot/acme src/acme
COPY certbot/certbot src/certbot
COPY certbot/certbot-dns-cloudflare src/certbot-dns-cloudflare

RUN python -m venv /opt/venv \
    && /opt/venv/bin/python tools/pip_install.py --no-cache-dir \
            ./src/acme ./src/certbot ./src/certbot-dns-cloudflare \
    # drop packaging tooling (uv alone is ~45MB) and bytecode caches from the final venv
    && /opt/venv/bin/python -m pip uninstall -y pip setuptools wheel uv 2>/dev/null || true \
    && find /opt/venv -type d -name __pycache__ -prune -exec rm -rf {} + \
    && find /opt/venv -type d \( -name tests -o -name test \) -path '*site-packages/*' -prune -exec rm -rf {} +

# ---- runtime: plain Alpine + apk python3 + venv only ----
FROM alpine:3.24

# The venv's interpreter symlinks to /usr/bin/python3, so the runtime python3
# must match the builder's (same Alpine release). ca-certificates is needed for
# TLS to the ACME server and the Cloudflare API.
RUN apk add --no-cache python3 ca-certificates \
    && rm -rf /root/.cache /usr/lib/python3*/ensurepip /usr/lib/python3*/idlelib \
              /usr/lib/python3*/turtledemo /usr/lib/python3*/test

COPY --from=builder /opt/venv /opt/venv
COPY --chmod=755 entrypoint.sh /

ENTRYPOINT [ "/entrypoint.sh" ]
