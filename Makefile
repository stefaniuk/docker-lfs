ifdef GITHUB_ACCOUNT
	OWNER := $(GITHUB_ACCOUNT)
else
	OWNER := $(USER)
endif
NAME := $(subst docker-,,$(shell basename $(shell dirname $(realpath  $(lastword $(MAKEFILE_LIST))))))
IMAGE :=  $(OWNER)/$(NAME)

all: help

help:
	echo
	echo "Usage:"
	echo
	echo "    make build|create|start|stop|log|test|bash|clean|remove|push [APT_PROXY|APT_PROXY_SSL=ip:port]"
	echo

build:
	docker build \
		--build-arg APT_PROXY=${APT_PROXY} \
		--build-arg APT_PROXY_SSL=${APT_PROXY_SSL} \
		--build-arg VERSION=$(shell cat VERSION) \
		--build-arg BUILD_DATE=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--build-arg VCS_REF=$(shell git rev-parse --short HEAD) \
		--build-arg VCS_URL=$(shell git config --get remote.origin.url) \
		--tag $(IMAGE):$(shell cat VERSION) \
		--rm .
	docker tag $(IMAGE):$(shell cat VERSION) $(IMAGE):latest

create:
	docker stop $(IMAGE) > /dev/null 2>&1 ||:
	docker rm $(IMAGE) > /dev/null 2>&1 ||:
	docker create --interactive --tty \
		--name $(NAME) \
		--hostname $(NAME) \
		$(IMAGE) \
		/bin/bash --login

start:
	docker start $(NAME)

stop:
	docker stop $(NAME)

log:
	docker logs --follow $(NAME)

# test:
# 	docker exec --interactive --tty \
# 		--user "default" \
# 		$(NAME) \
# 		?

bash:
	docker exec --interactive --tty \
		$(NAME) \
		/bin/bash --login ||:

clean:
	docker stop $(NAME) > /dev/null 2>&1 ||:
	docker rm $(NAME) > /dev/null 2>&1 ||:

remove: clean
	docker rmi $(IMAGE):$(shell cat VERSION) > /dev/null 2>&1 ||:
	docker rmi $(IMAGE):latest > /dev/null 2>&1 ||:

push:
	docker push $(IMAGE):$(shell cat VERSION)
	docker push $(IMAGE):latest
	curl --request POST "https://hooks.microbadger.com/images/stefaniuk/lfs/?"

.SILENT:
