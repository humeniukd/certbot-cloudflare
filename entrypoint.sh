#!/bin/sh

if [ ! -r /etc/cloudflare.ini ]; then
    echo "/etc/cloudflare.ini is required and must be readable" >&2
    exit 1
fi

DOMAINS="${1:-$DOMAINS}"

if [ -z "$DOMAINS" ]; then
    echo "Domain name(s) required (comma-separated for multiple, e.g. 'example.com,*.example.com')" >&2
    exit 1
fi

CERT_NAME="${DOMAINS%%,*}"
CERT_NAME="${CERT_NAME#\*.}"

export PATH="/opt/venv/bin:${PATH}"

# e.g. "7 days"; validated up front so a typo fails before a certificate is requested.
RENEW_BEFORE_EXPIRY="${RENEW_BEFORE_EXPIRY:-7 days}"
case "$RENEW_BEFORE_EXPIRY" in
    [0-9]*" "[a-z]*) ;;
    *) echo "Invalid RENEW_BEFORE_EXPIRY '$RENEW_BEFORE_EXPIRY' (expected e.g. '7 days')" >&2; exit 1 ;;
esac

# Numeric IDs only: this image has no users besides root.
for id in "EXPORT_UID=$EXPORT_UID" "EXPORT_GID=$EXPORT_GID"; do
    case "${id#*=}" in
        "") ;;
        *[!0-9]*) echo "Invalid ${id%%=*} '${id#*=}' (expected a numeric ID)" >&2; exit 1 ;;
    esac
done

for item in /etc/letsencrypt /var/lib/letsencrypt /export; do
    if ! grep -q " $item " /proc/mounts; then
        echo "$item must be mounted" >&2
        exit 1
    fi
done

certbot certonly -n --agree-tos --dns-cloudflare --dns-cloudflare-credentials /etc/cloudflare.ini \
    --cert-name "$CERT_NAME" -d "$DOMAINS" --keep-until-expiring || exit $?

LIVE_DIR="/etc/letsencrypt/live/$CERT_NAME"
EXPORT_DIR="/export/$CERT_NAME"

for file in fullchain.pem privkey.pem; do
    src="$LIVE_DIR/$file" dst="$EXPORT_DIR/$file"
    if ! cmp -s "$src" "$dst"; then
        install_args="-D -m 0400"
        if [ -n "$EXPORT_UID" ]; then
            install_args="$install_args -o $EXPORT_UID"
        fi
        if [ -n "$EXPORT_GID" ]; then
            install_args="$install_args -g $EXPORT_GID"
        fi
        install $install_args "$src" "$dst" || exit 1
    fi
done

# Only renew once the certificate is within RENEW_BEFORE_EXPIRY of expiry
# (certbot's default is 2/3 of the lifetime). takes effect on the next run.
RENEWAL_CONF="/etc/letsencrypt/renewal/$CERT_NAME.conf"
if [ ! -f "$RENEWAL_CONF" ]; then
    echo "Renewal config $RENEWAL_CONF not found after certonly" >&2
    exit 1
fi
if grep -q '^renew_before_expiry *=' "$RENEWAL_CONF"; then
    sed -i "s/^renew_before_expiry *=.*/renew_before_expiry = $RENEW_BEFORE_EXPIRY/" "$RENEWAL_CONF" || exit 1
else
    sed -i "/^version *=/a renew_before_expiry = $RENEW_BEFORE_EXPIRY" "$RENEWAL_CONF" || exit 1
fi

echo "Exported certificate for $DOMAINS to $EXPORT_DIR"
