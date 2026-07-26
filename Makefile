-include mobile/.env
export

DART_DEFINES = --dart-define=SUPABASE_URL=$(SUPABASE_URL) --dart-define=SUPABASE_PUBLISHABLE_KEY=$(SUPABASE_PUBLISHABLE_KEY)
APK = mobile/build/app/outputs/flutter-apk/app-debug.apk

.PHONY: help check-env mobile-generate mobile-run mobile-build mobile-install mobile-analyze mobile-test backend-venv backend-run backend-test backend-render-url backend-deploy backend-logs

help:
	@echo "make mobile-generate  - regenerate build_runner code (drift, etc.), gitignored"
	@echo "make mobile-run       - flutter run on a connected device (DEVICE=<id> to target one)"
	@echo "make mobile-build     - flutter build apk --debug, with Supabase dart-defines"
	@echo "make mobile-install   - build + adb install -r onto a connected device (DEVICE=<id>)"
	@echo "make mobile-analyze   - flutter analyze"
	@echo "make mobile-test      - flutter test"
	@echo "make backend-venv     - create backend/.venv and install deps + chromium"
	@echo "make backend-run      - run the poller/renderer worker locally"
	@echo "make backend-test     - run backend pytest suite"
	@echo "make backend-render-url URL=<url> - render one real URL through the pipeline, no Supabase needed"
	@echo "make backend-deploy   - flyctl deploy the worker to Fly.io (deepread-worker app)"
	@echo "make backend-logs     - tail production logs from Fly.io"

# mobile/.env is gitignored — copy mobile/.env.example and fill in your
# project's URL + anon/publishable key before running any mobile-* target.
check-env:
	@if [ -z "$(SUPABASE_URL)" ] || [ -z "$(SUPABASE_PUBLISHABLE_KEY)" ]; then \
		echo "Missing SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY."; \
		echo "Copy mobile/.env.example to mobile/.env and fill it in."; \
		exit 1; \
	fi

mobile-generate:
	cd mobile && dart run build_runner build

mobile-run: check-env mobile-generate
	cd mobile && flutter run $(if $(DEVICE),-d $(DEVICE)) $(DART_DEFINES)

mobile-build: check-env mobile-generate
	cd mobile && flutter build apk --debug $(DART_DEFINES)

mobile-install: mobile-build
	adb $(if $(DEVICE),-s $(DEVICE)) install -r $(APK)

mobile-analyze: mobile-generate
	cd mobile && flutter analyze

mobile-test: mobile-generate
	cd mobile && flutter test

backend-venv:
	cd backend && python3 -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]" && playwright install chromium

backend-run:
	cd backend && . .venv/bin/activate && python -m deepread_worker.main

backend-test:
	cd backend && . .venv/bin/activate && python -m pytest

backend-render-url:
	cd backend && . .venv/bin/activate && python -m deepread_worker.debug_render $(URL)

# Requires flyctl (https://fly.io/install.sh) authenticated against the
# "deepread" org — secrets (SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY) are
# already set on the deepread-worker app via `flyctl secrets set`.
backend-deploy:
	cd backend && flyctl deploy --app deepread-worker

backend-logs:
	flyctl logs --app deepread-worker
