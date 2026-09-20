# Spending Angel — the short list of things you do with this repo.
# `make` alone prints it. The work lives in scripts/; this is only the front door.

XCODE := /Applications/Xcode.app/Contents/Developer

.PHONY: help install update uninstall bundle run test

help:
	@echo "Spending Angel"
	@echo "  make install     build, bundle, put Spending Angel.app in ~/Applications, start it at login"
	@echo "  make update      git pull --ff-only, then install (reminds you to reload the extension)"
	@echo "  make uninstall   stop it, remove the app and the login item (PURGE=1 also wipes settings + logs)"
	@echo "  make bundle      only build mac-app/.build/Spending Angel.app (safe while the app runs)"
	@echo "  make run         developer run from source (swift run), no install"
	@echo "  make test        extension + script regression tests (node --test) + app (swift test)"
	@echo ""
	@echo "  NO_LOGIN_ITEM=1 make install   skip the LaunchAgent and just open the app"

install:
	scripts/install.sh $(if $(NO_LOGIN_ITEM),--no-login-item,)

update:
	scripts/update.sh $(if $(NO_LOGIN_ITEM),--no-login-item,)

uninstall:
	scripts/uninstall.sh $(if $(PURGE),--purge,)

bundle:
	scripts/bundle.sh

run:
	swift run --package-path mac-app

# The Swift Testing module ships with full Xcode only, so point at it when it
# is there; otherwise trust whatever `swift` is on PATH (CI pins its own).
test:
	node --test extension/tests/*.test.js
	node --test scripts/tests/*.test.cjs
	@if [ -d "$(XCODE)" ]; then \
		echo "DEVELOPER_DIR=$(XCODE) swift test --package-path mac-app"; \
		DEVELOPER_DIR="$(XCODE)" swift test --package-path mac-app; \
	else \
		swift test --package-path mac-app; \
	fi
