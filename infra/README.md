# artisan

Monorepo. The Gleam web server lives in `server/` and the frontend lives in `client/`.

## Requirements

* Linux with systemd
* Gleam installed (`gleam run` works)
* sudo access
* nginx installed (for HTTPS + reverse proxy)

## Install & run the server

This builds the frontend and installs/runs the server in one step:

```bash
make install
```

## What `make install` does

1. Builds the frontend from `client/` using Lustre
2. Outputs static assets into `server/priv/static`
3. Copies the repo to `/opt/artisan`
4. Installs and starts the systemd service (`server`)

## Nginx setup (one-time per VM)

The Gleam app listens on `127.0.0.1:8000`. nginx handles:

* public HTTP/HTTPS
* HTTPS-only redirects
* TLS termination

The nginx site config lives at the **repo root**:

```
avilaville.site
```

Install and enable it:

```bash
make install-nginx
```

Then obtain TLS certificates (one time):

```bash
sudo certbot --nginx -d avilaville.site -d www.avilaville.site
```

After this, nginx will automatically renew certificates via systemd.

## View logs

```bash
make logs
```

## Check status

```bash
make status
```

## Notes

* Logs are handled by systemd (journald, auto-rotated)
* nginx access/error logs are handled separately by nginx
* Safe for small VMs (10 GB disk, 512 MB RAM)
* No ongoing maintenance expected

## One-time system setup (recommended)

Enable persistent logs and cap disk usage:

```bash
sudo mkdir -p /var/log/journal
sudo nano /etc/systemd/journald.conf
```

Set:

```
SystemMaxUse=200M
```

Restart journald:

```bash
sudo systemctl restart systemd-journald
```


