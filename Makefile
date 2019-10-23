current_dir := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
### Load some important stuff

include .env
ccred=$(if $(filter $(OS),Windows_NT),,$(shell    echo "\033[31m"))
ccgreen=$(if $(filter $(OS),Windows_NT),,$(shell  echo "\033[32m"))
ccyellow=$(if $(filter $(OS),Windows_NT),,$(shell echo "\033[33m"))
ccbold=$(if $(filter $(OS),Windows_NT),,$(shell   echo "\033[1m"))
cculine=$(if $(filter $(OS),Windows_NT),,$(shell  echo "\033[4m"))
ccend=$(if $(filter $(OS),Windows_NT),,$(shell    echo "\033[0m"))

sleep := $(if $(filter $(OS),Windows_NT),timeout,sleep)

ifeq ($(OS),Windows_NT)
	# Docker for Windows takes care of the user mapping.
else
	ifndef COMPOSE_IMPERSONATION
		COMPOSE_IMPERSONATION="$(shell id -u):$(shell id -g)"
	endif
endif

### Transform code between odoo versions
TEST_SRC := $(shell git status --porcelain | grep 'src/')
transform_usage = "$(ccyellow)Usage: $(ccbold)make modules=<mod1,mod2> from=<11.0> transfrom$(ccend)"
TRANSFORM_TARGETS =
ifeq ($(TEST_SRC),)
	TRANSFORM_TARGETS += transform-docs
endif
transform: $(TRANSFORM_TARGETS)
ifneq ($(TEST_SRC),)
	@echo "$(ccred)$(ccbold)Clean your src workdir before applying code transformations to it.$(ccend)"
	@echo "$(ccred)Then, run $(ccbold)make transform$(ccend)$(ccred) again.$(ccend)"
	exit 1
endif
ifndef modules
	@echo "$(transform_usage)"
	exit 1
endif
ifndef from
	@echo "$(transform_usage)"
	exit 1
endif
	docker run \
	--volume "$(current_dir)/src:/mnt/src" \
	--user ${COMPOSE_IMPERSONATION} \
	--entrypoint "" \
	${FROM}:${FROM_VERSION}-${ODOO_VERSION}-devops \
	odoo-migrate \
	--directory "/mnt/src" \
	--no-commit \
	--modules $(modules) \
	--init-version-name $(from) \
	--target-version-name $(ODOO_VERSION)


### Common repo maintenance

create: pull patch build

TEST := $(shell git submodule --quiet foreach git status --porcelain)
ifneq ($(TEST),)
patch:
	@echo "$(ccred)$(ccbold)Clean your vendor workdirs before applying patches.$(ccend)"
	@echo "$(ccred)Then, run $(ccbold)make patch$(ccend)$(ccred) again.$(ccend)"
	@echo "$(ccyellow)Run $(ccbold)git submodule foreach git status --porcelain$(ccend)$(ccyellow) for more info.$(ccend)"
else
patch: patch-docs
	@echo "$(ccgreen)$(ccbold)$(cculine)Apply DockeryOdoo default patches.$(ccend)"
	docker run \
	--entrypoint "" \
	--user ${COMPOSE_IMPERSONATION} \
	--volume '$(current_dir)/vendor:/mnt/vendor' \
	${FROM}:${FROM_VERSION}-${ODOO_VERSION}-devops \
	/usr/local/bin/apply-patches.sh \
	"/opt/odoo/patches.d" "/mnt/"
	@echo "$(ccgreen)$(ccbold)$(cculine)Apply custom patches.$(ccend)"
	docker run \
	--entrypoint "" \
	--user ${COMPOSE_IMPERSONATION} \
	--volume '$(current_dir)/vendor:/mnt/vendor' \
	--volume '$(current_dir)/patches.d:/mnt/patches.d' \
	${FROM}:${FROM_VERSION}-${ODOO_VERSION}-devops \
	/usr/local/bin/apply-patches.sh \
	"/mnt/patches.d/" "/mnt/"
endif

update:
	git remote add scaffold https://github.com/xoe-labs/dockery-odoo-scaffold.git 2> /dev/null || true
	git pull scaffold master


# Load a backup into the database

DB_DOCKER := $(shell docker-compose ps -q db)
restore:
ifndef DB_DOCKER
	@echo '$(ccyellow)DB Service must be running, run with: $(ccbold)dcu -d db$(ccend)'
	exit 1
endif
ifndef file
	@echo '$(ccyellow)Usage: $(ccbold)make file=<file within ~/odoo/.backups/...> restore$(ccend)'
	exit 1
endif
	docker exec -i $(DB_DOCKER) pg_restore -U odoo --create --clean --no-acl --no-owner -d postgres < ~/odoo/.backups/$(file)


### Pulling images

pull: pull-base pull-devops

pull-base:
	docker pull $(FROM):$(FROM_VERSION)-$(ODOO_VERSION)

pull-devops:
	docker pull $(FROM):$(FROM_VERSION)-$(ODOO_VERSION)-devops



### Building images

build: build-base-docs build-base build-devops-docs build-devops

build-base:
	docker build --tag $(IMAGE):edge-$(ODOO_VERSION)         --build-arg "FROM_IMAGE=$(FROM):$(FROM_VERSION)-$(ODOO_VERSION)" .

build-devops:
	docker build --tag $(IMAGE):edge-$(ODOO_VERSION)-devops  --build-arg "FROM_IMAGE=$(FROM):$(FROM_VERSION)-$(ODOO_VERSION)-devops" .

lint:
	git config commit.template $(shell pwd)/.git-commit-template
	pre-commit install --hook-type pre-commit
	pre-commit install --hook-type commit-msg
	pre-commit install --install-hooks
	pre-commit run --all

include docs.mk
