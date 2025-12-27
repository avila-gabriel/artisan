APP=server
PREFIX=/opt/artisan
ERLANG_PREFIX=/opt/erlang/otp-28
GLEAM_BIN=/usr/local/bin/gleam
REBAR3_BIN=/usr/local/bin/rebar3

SHELL := /bin/bash

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

	if ! command -v kerl >/dev/null; then \
		curl -fsSL https://raw.githubusercontent.com/kerl/kerl/master/kerl \
			-o /usr/local/bin/kerl && \
		chmod +x /usr/local/bin/kerl; \
	fi

	if [ ! -d "$(ERLANG_PREFIX)" ]; then \
		kerl build 28.0 otp-28 && \
		kerl install otp-28 $(ERLANG_PREFIX); \
	fi

	. $(ERLANG_PREFIX)/activate && \
		erl -noshell -eval 'io:format("OTP ~s~n",[erlang:system_info(otp_release)]), halt().'

	if [ ! -x "$(REBAR3_BIN)" ]; then \
		curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 \
			-o $(REBAR3_BIN) && \
		chmod +x $(REBAR3_BIN); \
	fi

	. $(ERLANG_PREFIX)/activate && \
		$(REBAR3_BIN) --version

	if [ ! -x "$(GLEAM_BIN)" ]; then \
		VERSION="$$(curl -fsSL https://api.github.com/repos/gleam-lang/gleam/releases/latest | grep tag_name | sed -E 's/.*"v([^\"]+)".*/\1/')" && \
		curl -fsSL https://github.com/gleam-lang/gleam/releases/download/v$$VERSION/gleam-v$$VERSION-x86_64-unknown-linux-musl.tar.gz | tar xz && \
		mv gleam $(GLEAM_BIN) && \
		chmod +x $(GLEAM_BIN); \
	fi

	$(GLEAM_BIN) --version

# -------------------------------------------------
# Frontend build (retry-safe)
# -------------------------------------------------
build-client:
	. $(ERLANG_PREFIX)/activate && cd client && \
		i=1; \
		while true; do \
			if gleam run -m lustre/dev build --minify --outdir=../server/priv/static; then break; fi; \
			echo "gleam build failed, retry $$i"; \
			gleam deps list || true; \
			sleep 2; \
			i=$$((i+1)); \
			if [ $$i -gt 10 ]; then echo "giving up after 10 attempts"; exit 1; fi; \
		done

# -------------------------------------------------
# Deploy / update app (fast path)
# -------------------------------------------------
install: build-client
	sudo mkdir -p $(PREFIX)
	sudo rsync -a --delete --exclude .git --exclude build . $(PREFIX)
	sudo cp $(PREFIX)/infra/server.service /etc/systemd/system/$(APP).service
	sudo systemctl daemon-reload
	sudo systemctl enable $(APP)
	sudo systemctl restart $(APP)

# -------------------------------------------------
# Ops helpers
# -------------------------------------------------
logs:
	journalctl -u $(APP) -f

status:
	systemctl status $(APP)

