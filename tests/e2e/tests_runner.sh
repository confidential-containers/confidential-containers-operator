#!/bin/bash
#
# Copyright 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(dirname "$(readlink -f "$0")")"
project_dir="$(readlink -f ${script_dir}/../..)"

export GOPATH="$(mktemp -d)"
tests_repo_dir="$GOPATH/src/github.com/kata-containers/tests"
export CI=true

# TODO: Debug should be enabled in order for some tests to enable the console
# debug and search for patterns on agent logs. Probably console debug should
# be enabled always.
export DEBUG=true

# The container runtime class (e.g. kata, kata-qemu, kata-clh) test pods should
# be created with.
runtimeclass="kata-qemu"

# TODO: some tests use the SKOPEO variable (which is a build time variable) to
# decide whether run or not. This should be no longer the case when we replace
# skopeo with image-rs.
export SKOPEO=yes
echo "IMPORTANT: Assume the image was built with SKOPEO=${SKOPEO}"

# Tests will attempt to re-configure containerd. In our case it is already
# proper set by the operator, so let's skip that step.
export TESTS_CONFIGURE_CC_CONTAINERD=no

clone_kata_tests() {
	local cc_branch="CCv0"

	# TODO: checkout on the exact sha1 where the kata-deploy was created
	# so that we ensure the same tests are used here.
	git clone --branch="$cc_branch" \
		https://github.com/kata-containers/tests "$tests_repo_dir"
}

cleanup() {
	[ ! -s "/usr/local/bin/kata-runtime" ] || \
		unlink /usr/local/bin/kata-runtime
	rm -rf "$tests_repo_dir" || true

	# Restore the configuration.toml to its default value.
	if [ "$runtimeclass" != "kata-qemu" ];then
		set_kata_config "kata-qemu"
	fi
}

trap cleanup EXIT

parse_args() {
	while getopts "hr:" opt; do
		case $opt in
			h) usage && exit 0;;
			r) runtimeclass="$OPTARG";;
			*) usage && exit 1;;
		esac
	done
}

set_kata_config() {
	local runtimeclass="$1"
	# Remove "kata-" prefix to get the name of the configuration file.
	local kata_config="$(echo "$runtimeclass" | sed 's/^kata-//g')"
	local kata_config_dir="/opt/confidential-containers/share/defaults/kata-containers/"
	local default_config_link="${kata_config_dir}/configuration.toml"
	local config_file="${kata_config_dir}/configuration-${kata_config}.toml"

	if [ ! -f "$config_file" ]; then
		echo "ERROR: Kata configuration file does exist: $config_file"
		return 1
	fi

	[ ! -s "$default_config_link" ] || unlink "$default_config_link"
	ln -s "$config_file" "$default_config_link"
}

usage() {
	cat <<-EOF
	Utility to run the tests.

	Use: $0 [-h|--help] [-r RUNTIMECLASS], where:
	-h | --help : show this usage
	-r RUNTIMECLASS: configure to use the RUNTIMECLASS (e.g. kata-clh) on
	                 the tests. Defaults to "kata-qemu".
	EOF
}

main() {

	parse_args $@

	if [ "$runtimeclass" != "kata-qemu" ];then
		set_kata_config "$runtimeclass"
	fi

	clone_kata_tests

	cd "${tests_repo_dir}/integration/kubernetes/confidential"

        # Update runtimeclass and kata default config for the scripts in tests repo
        sed -i "s/runtimeClassName: kata/runtimeClassName: $runtimeclass/g" fixtures/*.yaml
	local default_config_link="/opt/confidential-containers/share/defaults/kata-containers/configuration.toml"
        sed -i "s#kata-runtime kata-env#kata-runtime --config $default_config_link kata-env#g" ../../../lib/common.bash

	# Test scripts rely on kata-runtime so it should be reacheable on PATH.
	# Re-export PATH is error prone as some calls to kata-runtime use sudo,
	# so let's create a symlink.
	ln -sf /opt/confidential-containers/bin/kata-runtime \
		/usr/local/bin/kata-runtime

	# Run tests.

	# Results for agent_image.bats:
	#
	# ok 1 [cc][agent][kubernetes][containerd] Test can pull an unencrypted image inside the guest
	# ok 2 [cc][agent][kubernetes][containerd] Test can pull a unencrypted signed image from a protected registry
	# not ok 3 [cc][agent][kubernetes][containerd] Test cannot pull an unencrypted unsigned image from a protected registry
	# ok 4 [cc][agent][kubernetes][containerd] Test can pull an unencrypted unsigned image from an unprotected registry
	# not ok 5 [cc][agent][kubernetes][containerd] Test unencrypted signed image with unknown signature is rejected

	# Results for agent_image_encrypted.bats
	#
	# ok 1 [cc][agent][kubernetes][containerd] Test can pull an encrypted image inside the guest with decryption key
	# ok 2 [cc][agent][kubernetes][containerd] Test cannot pull an encrypted image inside the guest without decryption key

	local tests_passing="Test can pull an unencrypted image inside the guest"
	tests_passing+="|Test can pull a unencrypted signed image from a protected registry"
	tests_passing+="|Test can pull an unencrypted unsigned image from an unprotected registry"
	tests_passing+="|Test cannot pull an encrypted image inside the guest without decryption key"
	tests_passing+="|Test can pull an encrypted image inside the guest with decryption key"
	tests_passing+="|Test can uninstall the operator"

	bats -f "$tests_passing" \
		"agent_image.bats" \
		"agent_image_encrypted.bats" \
		"${script_dir}/operator_tests.bats"
}

main "$@"
