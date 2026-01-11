APP=server
PREFIX=/opt/artisan
ERLANG_PREFIX=/opt/erlang/otp-28
GLEAM_BIN=/usr/local/bin/gleam
REBAR3_BIN=/usr/local/bin/rebar3

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

# -------------------------------------------------
# Reliable Gleam build helper
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
# Server build
# -------------------------------------------------
build-client:
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u

	$(call gleam_build,client)

	# we are currently in client/ because gleam_build does cd client
	mkdir -p ../server/priv/static
	$(GLEAM_BIN) run -m lustre/dev build --minify sales_intake --outdir=../server/priv/static

build-server:
	set +u
	. $(ERLANG_PREFIX)/activate
	set -u

	$(call gleam_build,server)
	mkdir -p data
	mkdir -p priv/migrations
	$(GLEAM_BIN) run

# -------------------------------------------------
# Deploy / update app (fast path)
# -------------------------------------------------
install: build-client build-server
	sudo mkdir -p $(PREFIX)
	sudo rsync -a --delete --exclude .git --exclude build . $(PREFIX)

	# systemd service
	sudo cp $(PREFIX)/infra/server.service \
		/etc/systemd/system/$(APP).service

	# journald limits (safe, idempotent)
	sudo mkdir -p /etc/systemd/journald.conf.d
	sudo install -m 0644 $(PREFIX)/infra/journald.conf \
		/etc/systemd/journald.conf.d/limits.conf
	sudo mkdir -p /var/log/journal
	sudo systemctl restart systemd-journald

	# app
	sudo systemctl daemon-reload
	sudo systemctl enable $(APP)
	sudo systemctl restart $(APP)


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

# -------------------------------------------------
# Ops helpers
# -------------------------------------------------
logs:
	journalctl -u $(APP) -f

status:
	systemctl status $(APP)

