APP=server
PREFIX=/opt/artisan
ASDF_DIR=/opt/asdf
DOMAIN=avilaville.online
WWW_DOMAIN=www.$(DOMAIN)

GLEAM_BIN=gleam
REBAR3_BIN=rebar3

BLUE_DIR=$(PREFIX)/blue
GREEN_DIR=$(PREFIX)/green
BLUE_PORT=8000
GREEN_PORT=8001

NGINX_SITE=/etc/nginx/sites-enabled/production
NGINX_SITE_SRC=infra/production

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

# =================================================
# Machine setup (run once per VM)
# =================================================
env-setup:
	apt install -y \
		build-essential autoconf libncurses5-dev libssl-dev \
		libwxgtk3.0-gtk3-dev libgl1-mesa-dev libglu1-mesa-dev \
		libpng-dev libssh-dev unixodbc-dev xsltproc fop \
		libxml2-utils rsync nginx m4 certbot python3-certbot-nginx

	# asdf
	if [ ! -d "$(ASDF_DIR)" ]; then
		git clone https://github.com/asdf-vm/asdf.git $(ASDF_DIR) --branch v0.14.0
	fi

	if [ ! -f /etc/profile.d/asdf.sh ]; then
		echo '. $(ASDF_DIR)/asdf.sh' > /etc/profile.d/asdf.sh
	fi

	set +u
	. $(ASDF_DIR)/asdf.sh
	set -u

	asdf plugin list | grep -q '^erlang$$' || \
		asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
	asdf plugin list | grep -q '^rebar$$' || \
		asdf plugin add rebar https://github.com/Stratus3D/asdf-rebar.git
	asdf plugin list | grep -q '^gleam$$' || \
		asdf plugin add gleam https://github.com/asdf-community/asdf-gleam.git

	asdf install

	$(MAKE) runtime-sync
	systemctl enable server-blue server-green

define require_env
	if [ ! -d "$(ASDF_DIR)" ]; then
		echo "ERROR: env-setup not run (missing $(ASDF_DIR))"
		exit 1
	fi
	if [ ! -f "/etc/nginx/nginx.conf" ]; then
		echo "ERROR: env-setup not run (nginx not installed)"
		exit 1
	fi
endef

# =================================================
# Public exposure (HTTPS ingress)
# =================================================
expose:
	@echo ""
	@echo "== Preparing to expose Artisan to the public =="
	@echo ""

	@echo "== Checking DNS resolution =="

	@SERVER_IP="$$(curl -fsSL https://api.ipify.org)"; \
	DNS_IPS="$$(getent ahostsv4 $(DOMAIN) | awk '{print $$1}' | sort -u)"; \
	echo "Server IP: $$SERVER_IP"; \
	echo "DNS IPs ($(DOMAIN)): $$DNS_IPS"; \
	echo "$$DNS_IPS" | grep -qx "$$SERVER_IP" || \
	{ echo "ERROR: $(DOMAIN) does not resolve to this server"; exit 1; }

	@SERVER_IP="$$(curl -fsSL https://api.ipify.org)"; \
	DNS_IPS="$$(getent ahostsv4 $(WWW_DOMAIN) | awk '{print $$1}' | sort -u)"; \
	echo "Server IP: $$SERVER_IP"; \
	echo "DNS IPs ($(WWW_DOMAIN)): $$DNS_IPS"; \
	echo "$$DNS_IPS" | grep -qx "$$SERVER_IP" || \
	{ echo "ERROR: $(WWW_DOMAIN) does not resolve to this server"; exit 1; }

	@echo ""
	@echo "== Checking TLS certificates =="

	@test -f /etc/letsencrypt/live/$(DOMAIN)/fullchain.pem || \
		{ echo "ERROR: TLS certificate not found for $(DOMAIN)"; exit 1; }
	@test -f /etc/letsencrypt/live/$(DOMAIN)/privkey.pem || \
		{ echo "ERROR: TLS private key not found for $(DOMAIN)"; exit 1; }

	@echo ""
	@echo "== TLS detected. Enabling public access =="

	# install nginx site
	rm -f /etc/nginx/sites-enabled/default
	cp $(NGINX_SITE_SRC) /etc/nginx/sites-available/production
	ln -sf /etc/nginx/sites-available/production $(NGINX_SITE)

	nginx -t
	systemctl enable nginx
	systemctl restart nginx

	@echo ""
	@echo "== Public access enabled =="
	@echo "https://$(DOMAIN)"
	@echo ""

# =================================================
# Build helpers
# =================================================
define gleam_build
	set -e
	cd $(1)
	echo "==> Resolving Gleam deps in $(1)"
	for i in 1 2 3 4 5; do
		if $(GLEAM_BIN) deps download; then break; fi
		echo "deps download failed, retry $$i"
		sleep 3
		if [ $$i -eq 5 ]; then exit 1; fi
	done
	echo "==> Building Gleam project in $(1)"
	$(GLEAM_BIN) build
endef

build-client:
	set +u; . $(ASDF_DIR)/asdf.sh; set -u
	$(call gleam_build,client)
	mkdir -p ../server/priv/static
	$(GLEAM_BIN) run -m lustre/dev build --minify sales_intake \
		--outdir=../server/priv/static

build-server:
	set +u; . $(ASDF_DIR)/asdf.sh; set -u
	$(call gleam_build,server)
	mkdir -p priv/migrations

build: build-client build-server

# =================================================
# Slot install (never touches running service)
# =================================================
install-blue: build
	sudo mkdir -p $(BLUE_DIR)
	sudo rsync -a --delete \
		--exclude data --exclude .git --exclude build \
		. $(BLUE_DIR)

install-green: build
	sudo mkdir -p $(GREEN_DIR)
	sudo rsync -a --delete \
		--exclude data --exclude .git --exclude build \
		. $(GREEN_DIR)

# =================================================
# Data guard (for stateful deploys)
# =================================================
define require_data
	if [ ! -d "$(PREFIX)/data" ]; then
		echo "ERROR: $(PREFIX)/data directory missing"
		exit 1
	fi
	if [ ! -f "$(PREFIX)/data/data.db" ]; then
		echo "ERROR: required data.db not found"
		exit 1
	fi
endef

# =================================================
# Active slot detection (nginx is truth)
# =================================================
define detect_active
	port="$$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+' \
		$(NGINX_SITE) | sed -E 's/.*:([0-9]+)/\1/')"

	if [ "$$port" = "$(BLUE_PORT)" ]; then echo blue; \
	elif [ "$$port" = "$(GREEN_PORT)" ]; then echo green; \
	else echo none; fi
endef

# =================================================
# Deploy on machine WITH existing data (migration)
# =================================================
deploy-existing:
	set +u; . $(ASDF_DIR)/asdf.sh; set -u
	$(call require_env)
	$(call require_data)
	echo "== Deploying with existing data (blue) =="
	$(MAKE) install-blue
	sudo systemctl start server-blue

	echo ""
	echo "============================================"
	echo " Deployment complete"
	echo ""
	echo " Create the following DNS records in Namecheap:"
	echo ""
	IP=$$(curl -fsSL https://api.ipify.org)
	echo "   A     @     $$IP"
	echo "   A     www   $$IP"
	echo ""
	echo " URL:"
	echo " https://ap.www.namecheap.com/Domains/DomainControlPanel/avilaville.online/advancedns"
	echo "============================================"

# =================================================
# First deploy (run once per machine)
# =================================================
deploy:
	$(call require_env)
	ACTIVE=$$($(call detect_active))
	if [ "$$ACTIVE" != "none" ]; then
		echo "ERROR: deployment already exists"
		exit 1
	fi
	set +u; . $(ASDF_DIR)/asdf.sh; set -u
	echo "== First deploy: blue =="
	$(MAKE) install-blue
	sudo systemctl start server-blue
	echo "== Blue running on :$(BLUE_PORT) =="

	echo ""
	echo "============================================"
	echo " Deployment complete"
	echo ""
	echo " Create the following DNS records in Namecheap:"
	echo ""
	IP=$$(curl -fsSL https://api.ipify.org)
	echo "   A     @     $$IP"
	echo "   A     www   $$IP"
	echo ""
	echo " URL:"
	echo " https://ap.www.namecheap.com/Domains/DomainControlPanel/avilaville.online/advancedns"
	echo "============================================"

# =================================================
# Stage next version (no traffic change)
# =================================================
stage:
	$(MAKE) runtime-sync
	set +u; . $(ASDF_DIR)/asdf.sh; set -u

	active=$$($(call detect_active))
	if [ "$$active" = "none" ]; then
		echo "error: no active deployment; use 'make deploy' or stage-force"
		exit 1
	fi

	git fetch origin
	git diff --quiet || { echo "error: dirty tree"; exit 1; }
	git pull --ff-only

	if [ "$$active" = "blue" ]; then new=green; else new=blue; fi
	echo "== staging $$new =="
	$(MAKE) install-$$new
	sudo systemctl start server-$$new


stage-force:
	set +u; . $(ASDF_DIR)/asdf.sh; set -u

	active=$$($(call detect_active))

	echo "== force staging (discarding local changes) =="

	git fetch origin
	git reset --hard origin/HEAD
	$(MAKE) runtime-sync

	if [ "$$active" = "none" ]; then
		new=blue
		echo "== no active deployment; staging blue =="
	else
		if [ "$$active" = "blue" ]; then new=green; else new=blue; fi
		echo "== staging $$new =="
	fi

	$(MAKE) install-$$new
	sudo systemctl start server-$$new

# =================================================
# Promote staged version to production
# =================================================
promote:
	ACTIVE=$$($(call detect_active))
	if [ "$$ACTIVE" = "none" ]; then
		echo "ERROR: nothing to promote"
		exit 1
	fi

	if [ "$$ACTIVE" = "blue" ]; then NEW=green; NEW_PORT=$(GREEN_PORT); \
	else NEW=blue; NEW_PORT=$(BLUE_PORT); fi

	echo "== Promoting $$NEW (:$$NEW_PORT) =="

	sudo sed -i -E \
		"s@(proxy_pass[[:space:]]+http://127\.0\.0\.1:)[0-9]+@\1$$NEW_PORT@" \
		"$(NGINX_SITE)"

	sudo nginx -t
	sudo systemctl reload nginx
	sudo systemctl stop server-$$ACTIVE || true

# =================================================
# Runtime wiring (systemd, local config)
# =================================================
runtime-sync:
	set +u; . $(ASDF_DIR)/asdf.sh; set -u

	GLEAM_BIN="$$(asdf which gleam)"
	ERL_BIN="$$(asdf which erl)"
	ERLANG_BIN_DIR="$$(dirname $$ERL_BIN)"

	sed \
		-e "s|{{GLEAM_BIN}}|$$GLEAM_BIN|" \
		-e "s|{{ERLANG_BIN_DIR}}|$$ERLANG_BIN_DIR|" \
		infra/server-blue.service \
		> /etc/systemd/system/server-blue.service

	sed \
		-e "s|{{GLEAM_BIN}}|$$GLEAM_BIN|" \
		-e "s|{{ERLANG_BIN_DIR}}|$$ERLANG_BIN_DIR|" \
		infra/server-green.service \
		> /etc/systemd/system/server-green.service

	systemctl daemon-reload

# =================================================
# Ops helpers
# =================================================
status:
	systemctl is-active server-blue || true
	systemctl is-active server-green || true

logs-blue:
	journalctl -u server-blue -f

logs-green:
	journalctl -u server-green -f

logs-prod:
	ACTIVE=$$($(call detect_active)); \
	[ "$$ACTIVE" != "none" ] && journalctl -u server-$$ACTIVE -f

logs-preview:
	ACTIVE=$$($(call detect_active)); \
	if [ "$$ACTIVE" = "blue" ]; then journalctl -u server-green -f; \
	elif [ "$$ACTIVE" = "green" ]; then journalctl -u server-blue -f; fi

