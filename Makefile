ifdef VERSION
else
	VERSION := $(shell sh -c 'git describe --always --tags')
endif

OUTPUT ?= dist/anycable-go

ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

LD_FLAGS="-s -w -X main.version=$(VERSION)"
GOBUILD=go build -ldflags $(LD_FLAGS) -a

# Standard build
default: prepare build

# Install current version
install:
	go install ./...

install-with-mruby:
	go install -tags mrb ./...

build:
	env go build -tags mrb -ldflags $(LD_FLAGS) -o $(OUTPUT) cmd/anycable-go/main.go

prepare-cross-mruby:
	(cd vendor/github.com/mitchellh/go-mruby && MRUBY_CROSS_OS=linux MRUBY_CONFIG=../../../../../../etc/build_config.rb make libmruby.a)

prepare-mruby:
	(cd vendor/github.com/mitchellh/go-mruby && MRUBY_CONFIG=../../../../../../etc/build_config.rb make libmruby.a)

build-all-mruby:
	env $(GOBUILD) -tags mrb -o "dist/anycable-go-$(VERSION)-mrb-macos-amd64" cmd/anycable-go/main.go
	docker run --rm -v $(PWD):/go/src/github.com/anycable/anycable-go -w /go/src/github.com/anycable/anycable-go -e OUTPUT="dist/anycable-go-$(VERSION)-mrb-linux-amd64" amd64/golang:1.11.4 make build

build-clean:
	rm -rf ./dist

build-linux:
	env GOOS=linux   GOARCH=386   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-linux-386"     cmd/anycable-go/main.go

build-all: build-clean build-linux
	env GOOS=linux   GOARCH=arm   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-linux-arm"     cmd/anycable-go/main.go
	env GOOS=linux   GOARCH=arm64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-linux-arm64"   cmd/anycable-go/main.go
	env GOOS=linux   GOARCH=amd64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-linux-amd64"   cmd/anycable-go/main.go
	env GOOS=windows GOARCH=386   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-win-386"       cmd/anycable-go/main.go
	env GOOS=windows GOARCH=amd64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-win-amd64"     cmd/anycable-go/main.go
	env GOOS=darwin  GOARCH=386   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-macos-386"     cmd/anycable-go/main.go
	env GOOS=darwin  GOARCH=amd64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-macos-amd64"   cmd/anycable-go/main.go
	env GOOS=freebsd GOARCH=arm   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-freebsd-arm"   cmd/anycable-go/main.go
	env GOOS=freebsd GOARCH=386   $(GOBUILD) -o "dist/anycable-go-$(VERSION)-freebsd-386"   cmd/anycable-go/main.go
	env GOOS=freebsd GOARCH=amd64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-freebsd-amd64" cmd/anycable-go/main.go

release-heroku:
	env GOOS=linux   GOARCH=amd64 $(GOBUILD) -o "dist/anycable-go-$(VERSION)-linux-amd64"   cmd/anycable-go/main.go
	docker run --rm -v $(PWD):/go/src/github.com/anycable/anycable-go -w /go/src/github.com/anycable/anycable-go -e OUTPUT="dist/anycable-go-$(VERSION)-mrb-linux-amd64" amd64/golang:1.11.4 make build
	aws s3 cp --acl=public-read ./dist/anycable-go-$(VERSION)-linux-amd64 "s3://anycable/builds/$(VERSION)/anycable-go-$(VERSION)-heroku"
	aws s3 cp --acl=public-read ./dist/anycable-go-$(VERSION)-mrb-linux-amd64 "s3://anycable/builds/$(VERSION)-mrb/anycable-go-$(VERSION)-mrb-heroku"

downloads-md:
	ruby etc/generate_downloads.rb

release: build-all s3-deploy dockerize

docker-release: dockerize
	docker push "anycable/anycable-go:$(VERSION)"

dockerize:
	GOOS=linux go build -ldflags "-X main.version=$(VERSION)" -a -o .docker/anycable-go cmd/anycable-go/main.go
	docker build -t "anycable/anycable-go:$(VERSION)" .

# Run server
run:
	go run ./cmd/anycable-go/main.go

build-protos:
	protoc --proto_path=./etc --go_out=plugins=grpc:./protos ./etc/rpc.proto

test:
	go test -tags mrb github.com/anycable/anycable-go/cli \
		github.com/anycable/anycable-go/config \
		github.com/anycable/anycable-go/node \
		github.com/anycable/anycable-go/pool \
		github.com/anycable/anycable-go/pubsub \
		github.com/anycable/anycable-go/rpc \
		github.com/anycable/anycable-go/server \
		github.com/anycable/anycable-go/metrics \
		github.com/anycable/anycable-go/mrb \
		github.com/anycable/anycable-go/utils

test-cable:
	go build -o tmp/anycable-go-test cmd/anycable-go/main.go
	anyt -c "tmp/anycable-go-test --headers=cookie,x-api-token" --target-url="ws://localhost:8080/cable"
	anyt -c "tmp/anycable-go-test --headers=cookie,x-api-token --ssl_key=etc/ssl/server.key --ssl_cert=etc/ssl/server.crt --port=8443" --target-url="wss://localhost:8443/cable"

test-ci: prepare prepare-mruby test test-cable

# Get dependencies and use gdm to checkout changesets
prepare:
	go get -u github.com/golang/dep/cmd/dep
	dep ensure

gen-ssl:
	mkdir -p tmp/ssl
	openssl genrsa -out tmp/ssl/server.key 2048
	openssl req -new -x509 -sha256 -key tmp/ssl/server.key -out tmp/ssl/server.crt -days 3650

vet:
	go vet ./...

fmt:
	go fmt ./...
