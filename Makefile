.DEFAULT_GOAL := build

.PHONY: build build-full test test-full

.PHONY: no_targets list

SHELL = /usr/bin/env bash

#############
# Variables # 
#############
# Git
CI_BUILD_CONCURRECY ?= 40
CI_COMMIT_SHORT_SHA ?= no_sha
CI_COMMIT_REF_NAME ?= master
CI_PROJECT_DIR ?= $(shell pwd)
GIT_CLONE_COMMAND ?= git clone --recurse-submodules -j$(CI_BUILD_CONCURRECY)

# Athena athena_cyberdog build variables
ATHENA_LCM_URL ?= https://partner-gitlab.mioffice.cn/cyberdog/athena_lcm_type.git
ATHENA_ASSISTANT_URL ?= https://partner-gitlab.mioffice.cn/cyberdog/athena_assistant.git
ATHENA_VISION_URL ?= https://partner-gitlab.mioffice.cn/cyberdog/athena_vision.git

CYBERDOG_PATH ?= /opt/ros2/cyberdog
CROSS_ROOT_PATH ?= /mnt/sdcard
CROSS_HOME_PATH ?= $(CROSS_ROOT_PATH)/home
CROSS_SETUP_BASH_FILE ?= $(CROSS_ROOT_PATH)/opt/ros2/foxy/local_setup.bash
CROSS_BUILD_WITH_LCM_FLAG ?= --cmake-force-configure --cmake-args -DCMAKE_TOOLCHAIN_FILE=/home/builder/toolchainfile.cmake --merge-install --event-handlers console_cohesion+ --install-base $(INSTALL_BASE_WITH_LCM) --parallel-workers $(CI_BUILD_CONCURRECY)
CROSS_TEST_WITH_LCM_FLAG ?= --merge-install --event-handlers console_cohesion+ --return-code-on-test-failure --install-base $(INSTALL_BASE_WITH_LCM) --packages-select $(TEST_BRINGUP_NAMES) $(TEST_CEPTION_NAMES) $(TEST_COMMON_NAMES) $(TEST_DECISION_NAMES) $(TEST_INTERACTION_NAMES)
CROSS_BUILD_WITH_FULL_FLAG ?= --cmake-force-configure --cmake-args -DCMAKE_TOOLCHAIN_FILE=/home/builder/toolchainfile.cmake --merge-install --event-handlers console_cohesion+ --install-base $(INSTALL_BASE_WITH_FULL) --parallel-workers $(CI_BUILD_CONCURRECY)
CROSS_TEST_WITH_FULL_FLAG ?= --merge-install --event-handlers console_cohesion+ --return-code-on-test-failure --install-base $(INSTALL_BASE_WITH_FULL) --packages-select $(TEST_BRINGUP_NAMES) $(TEST_CEPTION_NAMES) $(TEST_COMMON_NAMES) $(TEST_DECISION_NAMES) $(TEST_INTERACTION_NAMES)

REPO_NAME := $(lastword $(subst /, ,$(CI_PROJECT_DIR)))
PACKAGE_NAME ?= athena_cyberdog
PACKAGE_NAME_WITH_NAME ?= athena_cyberdog_with
PACKAGE_NAME_WITH_LCM ?= $(PACKAGE_NAME_WITH_NAME)_lcm
PACKAGE_NAME_WITH_FULL ?= $(PACKAGE_NAME_WITH_NAME)_full
PACKAGE_NAME_CLEAN ?= -name lcm_translate_msgs
PACKAGE_NAME_BUILD ?= build

TEST_BRINGUP_NAMES ?= athena_bringup
TEST_CEPTION_NAMES ?= athena_bms athena_body_state athena_lightsensor athena_obstacle_detection athena_scene_detection
TEST_COMMON_NAMES ?= athena_grpc athena_utils media_vendor toml11_vendor
TEST_DECISION_NAMES ?= athena_decisionmaker athena_decisionutils
TEST_INTERACTION_NAMES ?= athena_audio audio_base audio_interaction athena_camera athena_led athena_touch bluetooth live_stream wifirssi

ATHENA_REPOS_NAME ?= src
ATHENA_ROS2_DEBS_PATH ?= athena_ros2_deb/src
ATHENA_ROS2_DEBS_SUFFIX ?= *.deb
ATHENA_ROS2_DEBS_VERSION_PATH ?= $(ATHENA_ROS2_DEBS_PATH)/DEBIAN/control
INSTALL_BASE_WITH_LCM ?= $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_LCM)/$(ATHENA_ROS2_DEBS_PATH)$(CYBERDOG_PATH)
INSTALL_BASE_WITH_FULL ?= $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_FULL)/$(ATHENA_ROS2_DEBS_PATH)$(CYBERDOG_PATH)
CLEAN_FILES ?= $(ATHENA_REPOS_NAME) $(ATHENA_ROS2_DEBS_PATH)$(CYBERDOG_PATH)/* $(PACKAGE_NAME_BUILD) athena_*
BUILD_DEFAULT_VERDION_PREFIX ?= 1.
BUILD_FILE_NAME_WITH_LCM ?= $(PACKAGE_NAME_WITH_LCM)_deb-$(CI_COMMIT_SHORT_SHA).tgz
BUILD_FILE_NAME_WITH_FULL ?= $(PACKAGE_NAME_WITH_FULL)_deb-$(CI_COMMIT_SHORT_SHA).tgz
BUILD_TMP_FILE_LIST ?= build src $(PACKAGE_NAME_WITH_NAME)* $(CROSS_ROOT_PATH)/opt/ros2
BUILD_TMP_FILE_COPY_FLAGS ?= mnt/* /mnt

# Athena athena_cyberdog FDS variables
FDS_BUILD_TMP_FILE_DIR ?= $(FDS_URL_PREFIX)/$(REPO_NAME)/$(CI_COMMIT_REF_NAME)/build_temp
FDS_BUILD_TMP_FILE_NAME ?= $(REPO_NAME)_tmp-$(CI_COMMIT_SHORT_SHA).tar
FDS_BUILD_FULL_TMP_FILE_NAME ?= $(REPO_NAME)_full_tmp-$(CI_COMMIT_SHORT_SHA).tar
FDS_ATHENA_ROS2_DEB_URL ?= https://cnbj2m-fds.api.xiaomi.net/mirp-public/cyberdog-tools/ota_debs/athena_ros2_deb.tgz

#################
# BUILD TARGET  #
#################
build: touch-files build-files build-deb
build-files:
	@echo "[INFO] build cyberdog with lcm_type" && \
		cd $(CROSS_HOME_PATH) && \
		source $(CROSS_SETUP_BASH_FILE) && \
		$(GIT_CLONE_COMMAND) $(ATHENA_LCM_URL) && \
		curl -s $(FDS_ATHENA_ROS2_DEB_URL) | tar zx -C $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_LCM) && \
		colcon build $(CROSS_BUILD_WITH_LCM_FLAG)

build-deb:
	@echo "[INFO] build cyberdog deb with lcm_type" && \
		cd $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_LCM) && \
		if [[ $(CI_COMMIT_REF_NAME) =~ ^[0-9].* ]]; then \
    		sed -i 's/Version: .*/Version: $(CI_COMMIT_REF_NAME)/' $(ATHENA_ROS2_DEBS_VERSION_PATH); \
		else \
			sed -i 's/Version: .*/Version: $(BUILD_DEFAULT_VERDION_PREFIX)$(CI_COMMIT_REF_NAME)/' $(ATHENA_ROS2_DEBS_VERSION_PATH); \
		fi && \
		dpkg -b $(ATHENA_ROS2_DEBS_PATH) .

upload-files:
	@echo "[INFO] upload build deb of cyberdog with lcm_type" && \
		cd $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_LCM) && \
		tar czf $(BUILD_FILE_NAME_WITH_LCM) $(ATHENA_ROS2_DEBS_SUFFIX) && \
		$(FDS_COMMAND_UPLOAD) $(BUILD_FILE_NAME_WITH_LCM) $(FDS_URL_PREFIX)/$(REPO_NAME)/$(CI_COMMIT_REF_NAME)/$(BUILD_FILE_NAME_WITH_LCM)

build-full: touch-files build-full-files build-full-deb
build-full-files:
	@echo "[INFO] build cyberdog with lcm_type/assistant/vision" && \
		cd $(CROSS_HOME_PATH) && \
		source $(CROSS_SETUP_BASH_FILE) && \
		$(GIT_CLONE_COMMAND) $(ATHENA_LCM_URL) && \
		$(GIT_CLONE_COMMAND) $(ATHENA_ASSISTANT_URL) && \
		$(GIT_CLONE_COMMAND) $(ATHENA_VISION_URL) && \
		curl -s $(FDS_ATHENA_ROS2_DEB_URL) | tar zx -C $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_FULL) && \
		colcon build $(CROSS_BUILD_WITH_FULL_FLAG)

build-full-deb:
	@echo "[INFO] build cyberdog deb with lcm_type/assistant/vision" && \
		cd $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_FULL) && \
		if [[ $(CI_COMMIT_REF_NAME) =~ ^[0-9].* ]]; then \
    		sed -i 's/Version: .*/Version: $(CI_COMMIT_REF_NAME)/' $(ATHENA_ROS2_DEBS_VERSION_PATH); \
		else \
			sed -i 's/Version: .*/Version: $(BUILD_DEFAULT_VERDION_PREFIX)$(CI_COMMIT_REF_NAME)/' $(ATHENA_ROS2_DEBS_VERSION_PATH); \
		fi && \
		dpkg -b $(ATHENA_ROS2_DEBS_PATH) .

upload-full-files:		
	@echo "[INFO] upload build deb of cyberdog with lcm_type/assistant/vision" && \
		cd $(CROSS_HOME_PATH)/$(PACKAGE_NAME_WITH_FULL) && \
		tar czf $(BUILD_FILE_NAME_WITH_FULL) $(ATHENA_ROS2_DEBS_SUFFIX) && \
		$(FDS_COMMAND_UPLOAD) $(BUILD_FILE_NAME_WITH_FULL) $(FDS_URL_PREFIX)/$(REPO_NAME)/$(CI_COMMIT_REF_NAME)/$(BUILD_FILE_NAME_WITH_FULL)

#################                                                      
# TEST TARGET   #
#################
test:
	@echo "[INFO] test cyberdog with lcm_type" && \
		cd $(CROSS_HOME_PATH) && \
		source $(CROSS_SETUP_BASH_FILE) && \
		colcon test $(CROSS_TEST_WITH_LCM_FLAG)

test-full:
	@echo "[INFO] test cyberdog with lcm_type/assistant/vision" && \
		cd $(CROSS_HOME_PATH) && \
		source $(CROSS_SETUP_BASH_FILE) && \
		colcon test $(CROSS_TEST_WITH_FULL_FLAG)

################
# Minor Targets#
################
no_targets:
list:
	@sh -c "$(MAKE) -p no_targets | awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);for(i in A)print A[i]}' | grep -v '__\$$' \
		| grep -v 'make'| grep -v 'list'| grep -v 'no_targets' |grep -v 'Makefile' | sort | uniq"

clean:
	@cd $(CROSS_HOME_PATH) && \
		rm -rf $(CLEAN_FILES)

find-delete:
	@cd $(CROSS_HOME_PATH) && \
		find $(ATHENA_REPOS_NAME) $(PACKAGE_NAME_CLEAN)| xargs -i -t rm {} -rf

touch-files: clean
	echo "[INFO] touch cyberdog build source" && \
		cd $(CROSS_HOME_PATH) && \
		cp -arp $(CI_PROJECT_DIR) $(CROSS_HOME_PATH)/$(ATHENA_REPOS_NAME) && \
		mkdir -p $(CROSS_HOME_PATH)/build $(PACKAGE_NAME_WITH_LCM) $(PACKAGE_NAME_WITH_FULL)
tmp-upload:
	@cd $(CROSS_HOME_PATH) && \
		tar cf $(FDS_BUILD_TMP_FILE_NAME) $(BUILD_TMP_FILE_LIST) && \
		$(FDS_COMMAND_UPLOAD) $(FDS_BUILD_TMP_FILE_NAME) $(FDS_BUILD_TMP_FILE_DIR)/$(FDS_BUILD_TMP_FILE_NAME)
tmp-download:
	@mkdir -p $(CROSS_HOME_PATH) $(CYBERDOG_PATH) && \
		cd $(CROSS_HOME_PATH) && \
		$(FDS_COMMAND_DOWNLOAD) $(FDS_BUILD_TMP_FILE_DIR)/$(FDS_BUILD_TMP_FILE_NAME) $(FDS_BUILD_TMP_FILE_NAME) && \
		tar xf $(FDS_BUILD_TMP_FILE_NAME) && \
		cp -r $(BUILD_TMP_FILE_COPY_FLAGS)
tmp-full-upload: FDS_BUILD_TMP_FILE_NAME = $(FDS_BUILD_FULL_TMP_FILE_NAME)
tmp-full-upload: tmp-upload
tmp-full-download: FDS_BUILD_TMP_FILE_NAME = $(FDS_BUILD_FULL_TMP_FILE_NAME)
tmp-full-download: tmp-download