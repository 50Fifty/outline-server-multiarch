help:
	@echo "use: $(MAKE) [clone-upstream]"
	@echo ""
	@echo "  clone-upstream -> clone upstream(Jigsaw-Code/outline-server) into ./workspace/outline-server"
	@echo "  apply-patches -> patch diff files into ./workspace/outline-server PATCH_SET=release|master"
	@echo "  create-patch -> create patch file from workspace TARGET=target_to_execute_diff"
	@echo "  clean -> clean workspace directory"

clone-upstream:
	mkdir -p ./workspace;
	@if [ ! -d ./workspace/outline-server ]; then \
		git clone https://github.com/Jigsaw-Code/outline-server.git ./workspace/outline-server; \
	else \
		cd ./workspace/outline-server; \
		git pull; \
	fi;

apply-patches:
	@cd ./workspace/outline-server; \
	PATCH_DIR="../../patches/$${PATCH_SET:-release}"; \
	if [ ! -d "$${PATCH_DIR}" ]; then \
		echo "Patch directory not found: $${PATCH_DIR}" >&2; \
		exit 1; \
	fi; \
	set -- "$${PATCH_DIR}"/*.patch; \
	if [ ! -f "$$1" ]; then \
		echo "No patch files found in $${PATCH_DIR}" >&2; \
		exit 1; \
	fi; \
	for FILE in "$$@"; do \
		echo "Applying $${FILE}"; \
		git apply "$${FILE}"; \
	done;

create-patch:
	@cd ./workspace/outline-server; \
	mkdir -p ../../patches/$${PATCH_SET:-release}; \
	git diff $(TARGET) > ../../patches/$${PATCH_SET:-release}/_.patch;

clean:
	rm -rf ./workspace/outline-server;
