APP=server
PREFIX=/opt/artisan
ERLANG_PREFIX=/opt/erlang/otp-28
GLEAM_BIN=/usr/local/bin/gleam
REBAR3_BIN=/usr/local/bin/rebar3

BLUE_DIR=$(PREFIX)/blue
GREEN_DIR=$(PREFIX)/green

BLUE_PORT=8000
GREEN_PORT=8001

NGINX_SITE=/etc/nginx/sites-enabled/avilaville.site

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

# -------------------------------------------------
# Infrastructure bootstrap (run once per VM)
# -------------------------------------------------
bootstrap:
	apt update
	apt install -y \
		build-essential autoconf libncurses5-dev libssl-dev \
		libwxgtk3.0-gtk3-dev libgl1-mesa-dev libglu1-mesa-dev \
		libpng-dev libssh-dev unixodbc-dev xsltproc fop \
		libxml2-utils curl git ca-certificates

	if ! command -v kerl >/dev/null; then
		curl -fsSL https://raw.githubusercontent.com/kerl/kerl/master/kerl -o /usr/local/bin/kerl
		chmod +x /usr/local/bin/kerl
	fi

	if [ ! -d "$(ERLANG_PREFIX)" ]; then
		kerl build 28.0 otp-28
		kerl install otp-28 $(ERLANG_PREFIX)
	fi

	# kerl activate is NOT nounset-safe: always source under set +u
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u

	erl -noshell -eval 'io:format("OTP ~s~n",[erlang:system_info(otp_release)]), halt().'

	if [ ! -x "$(REBAR3_BIN)" ]; then
		curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o $(REBAR3_BIN)
		chmod +x $(REBAR3_BIN)
	fi

	# Source activate again only if you really need it; but if you do, do it safely.
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u
	$(REBAR3_BIN) --version

	if [ ! -x "$(GLEAM_BIN)" ]; then
		VERSION="$$(curl -fsSL https://api.github.com/repos/gleam-lang/gleam/releases/latest | grep tag_name | sed -E 's/.*"v([^\"]+)".*/\1/')" 
		curl -fsSL https://github.com/gleam-lang/gleam/releases/download/v$$VERSION/gleam-v$$VERSION-x86_64-unknown-linux-musl.tar.gz | tar xz
		mv gleam $(GLEAM_BIN)
		chmod +x $(GLEAM_BIN)
	fi

	$(GLEAM_BIN) --version

# -------------------------------------------------
# Gleam build helper
# -------------------------------------------------
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

# -------------------------------------------------
# Build
# -------------------------------------------------
build-client:
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u
	$(call gleam_build,client)
	mkdir -p ../server/priv/static
	$(GLEAM_BIN) run -m lustre/dev build --minify sales_intake --outdir=../server/priv/static

build-server:
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u
	$(call gleam_build,server)
	mkdir -p priv/migrations

build: build-client build-server

# -------------------------------------------------
# Install into slots (never touch running one)
# -------------------------------------------------
install-blue: build
	sudo mkdir -p $(BLUE_DIR)
	sudo rsync -a --delete \
		--exclude data \
		--exclude .git \
		--exclude build \
		. $(BLUE_DIR)

install-green: build
	sudo mkdir -p $(GREEN_DIR)
	sudo rsync -a --delete \
		--exclude data \
		--exclude .git \
		--exclude build \
		. $(GREEN_DIR)

# -------------------------------------------------
# Detect active slot
# -------------------------------------------------
define detect_active
	if systemctl is-active --quiet server-blue; then echo blue; exit 0; fi
	if systemctl is-active --quiet server-green; then echo green; exit 0; fi
	echo none
endef

# -------------------------------------------------
# Update: build + start new version ONLY
# -------------------------------------------------
update:
	set -e
	echo "== Updating repository =="
	git fetch origin
	if ! git diff --quiet; then
		echo "ERROR: working tree has uncommitted changes"
		exit 1
	fi
	git pull --ff-only

	ACTIVE=$$($(call detect_active))
	if [ "$$ACTIVE" = "blue" ]; then
		NEW=green
	elif [ "$$ACTIVE" = "green" ]; then
		NEW=blue
	else
		NEW=blue
	fi

	echo "== Active slot: $$ACTIVE =="
	echo "== Installing into: $$NEW =="

	$(MAKE) install-$$NEW

	sudo systemctl start server-$$NEW

	if [ "$$NEW" = "blue" ]; then
		echo "== New server running at http://127.0.0.1:$(BLUE_PORT) =="
	else
		echo "== New server running at http://127.0.0.1:$(GREEN_PORT) =="
	fi

	echo
	echo "Inspect logs, curl it, fix crashes if needed."
	echo "When ready, run: make switch"

# -------------------------------------------------
# Switch traffic (YOU decide when)
# -------------------------------------------------
switch:
	set -e
	ACTIVE=$$($(call detect_active))
	if [ "$$ACTIVE" = "none" ]; then
		echo "ERROR: no active server"
		exit 1
	fi

	if [ "$$ACTIVE" = "blue" ]; then
		NEW=green
		NEW_PORT=$(GREEN_PORT)
	else
		NEW=blue
		NEW_PORT=$(BLUE_PORT)
	fi

	echo "== Switching nginx to $$NEW (:$$NEW_PORT) =="

	sudo sed -i -E \
		"s@(proxy_pass[[:space:]]+http://127\.0\.0\.1:)[0-9]+@\1$$NEW_PORT@" \
		"$(NGINX_SITE)"

	sudo nginx -t
	sudo systemctl reload nginx

	echo "== Stopping old server ($$ACTIVE) =="
	sudo systemctl stop server-$$ACTIVE || true

	echo "== Switch complete =="

# -------------------------------------------------
# Ops helpers
# -------------------------------------------------
status:
	systemctl is-active server-blue || true
	systemctl is-active server-green || true

logs-blue:
	journalctl -u server-blue -f

logs-green:
	journalctl -u server-green -f

logs-prod:
	ACTIVE=$$($(call detect_active)); \
	if [ "$$ACTIVE" = "none" ]; then echo "no prod running"; exit 1; fi; \
	journalctl -u server-$$ACTIVE -f

logs-preview:
	ACTIVE=$$($(call detect_active)); \
	if [ "$$ACTIVE" = "blue" ]; then journalctl -u server-green -f; \
	elif [ "$$ACTIVE" = "green" ]; then journalctl -u server-blue -f; \
	else echo "no preview running"; fi

