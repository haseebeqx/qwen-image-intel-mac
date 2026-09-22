.PHONY: doctor build download install test clean

doctor:
	./scripts/doctor.sh

build:
	./scripts/build.sh

download:
	./scripts/download-models.sh --accept-license

install:
	@echo "Run ./install.sh --accept-license after reviewing the Qwen model license."

test:
	./tests/test-wrapper.sh
	./tests/test-web-installer.sh
	bash -n qwen-image install.sh web-install.sh scripts/*.sh tests/*.sh

clean:
	rm -rf build
