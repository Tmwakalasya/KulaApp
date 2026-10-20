SHELL := /bin/sh
GO := env GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOTELEMETRY=off go

.PHONY: api build-backend check-backend smoke build-ios

api:
	cd backend && $(GO) run ./cmd/api

build-backend:
	mkdir -p .build
	cd backend && $(GO) build -o ../.build/kula-api ./cmd/api

check-backend:
	cd backend && $(GO) build ./...
	cd backend && $(GO) vet ./...
	cd backend && $(GO) test ./...
	cd backend && $(GO) test -race ./...

smoke: build-backend
	python3 scripts/smoke.py

build-ios:
	xcodebuild -project ios/Kula.xcodeproj -scheme Kula -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
