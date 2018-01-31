.PHONY: build

build:
	docker build -t tomologic/cloudformation-utils .

verify: build
	docker run tomologic/cloudformation-utils rotateCursor 1
