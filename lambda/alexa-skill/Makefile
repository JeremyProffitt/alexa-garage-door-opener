.PHONY: build clean deploy test

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

local-invoke:
	sam local invoke AlexaSkillFunction -e test-event.json

.DEFAULT_GOAL := build
