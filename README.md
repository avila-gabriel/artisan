# artisan

Monorepo. The Gleam web server lives in `server/` and the frontend lives in `client/`.

This README describes **how to run the application**.

All machine setup, dependencies, and production infrastructure live in:

```
infra/README.md
```

---

## Requirements

* Linux with systemd
* sudo access

> Erlang, Gleam, nginx, TLS, and VM bootstrap are documented in `infra/README.md`.

---

## Install & run the server

This deploys or updates the application on an already bootstrapped machine:

```bash
make install
```

---

## What `make install` does

1. Builds the frontend from `client/` using Lustre
2. Outputs static assets into `server/priv/static`
3. Copies the repo to `/opt/artisan`
4. Installs and starts (or restarts) the systemd service (`server`)

---

## View logs

```bash
make logs
```

---

## Check status

```bash
make status
```

---

## Notes

* Application logs are handled by systemd (journald)
* nginx access/error logs are handled separately by nginx
* This README intentionally avoids infrastructure details
* For first-time VM setup, Erlang/Gleam installation, nginx, TLS, or local VM testing, see `infra/README.md`

---

## Mental model

* This README: **how to run and update the app**
* `infra/README.md`: **how the machine is built and verified**

Keep them separate.

