# Certbot + Cloudflare DNS [Docker Hub repo](https://hub.docker.com/r/loudyo/certbot-cloudflare)
A minimal Alpine image that runs Certbot with the Cloudflare DNS plugin and keeps server's TLS certificate up to date.

One run of the container does the following:

1. Requests a certificate for the given domain(s) using the DNS-01 challenge (Cloudflare), or does nothing if the current one is not due yet.
2. Copies `fullchain.pem` and `privkey.pem` from `/etc/letsencrypt/live/<name>/` to `/export/<name>/` (mode `0400`, owner `EXPORT_UID`:`EXPORT_GID`, if set), replacing only files that differ. `<name>` is the first domain. This runs on every start, so a failed copy is retried next time instead of waiting for the next renewal.

Mount `/etc/letsencrypt`, `/var/lib/letsencrypt` and `/export` (the container refuses to start otherwise).

Run it from cron (or any scheduler) once a day. It is a one-shot container, not a daemon.

0 3 * * * cd /opt/certbot && docker compose run --rm certbot 'example.com,*.example.com' 