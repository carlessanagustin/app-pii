.DEFAULT_GOAL := docker-build
.PHONY: py-venv py-reqs
.PHONY: docker-build docker-push docker-run docker-clean

IMAGE_NAME ?= pii:1.0

# python environment
py-venv:
	python3 -m venv .venv

py-reqs:
	source .venv/bin/activate && pip install -r requirements.txt


# docker image
docker-build:
	docker build -t $(IMAGE_NAME) .

docker-push:
	docker push $(IMAGE_NAME)

docker-run:
	docker run --rm -it $(IMAGE_NAME) bash

docker-clean:
	-docker rmi $(IMAGE_NAME)
