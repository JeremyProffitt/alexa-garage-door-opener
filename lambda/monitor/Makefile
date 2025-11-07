.PHONY: build clean test deps

build:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap main.go
	chmod +x bootstrap

clean:
	rm -f bootstrap
	rm -rf vendor/

test:
	go test -v ./...

deps:
	go mod download
	go mod tidy

.DEFAULT_GOAL := build
