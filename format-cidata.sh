#!/bin/bash

set -eu -o pipefail

: "${DEVICE_PATH:?}"

tmp_dir="$(mktemp -d)"
trap '{ rm -rf "${tmp_dir}"; }' EXIT

sudo wipefs -a "${DEVICE_PATH}"
genisoimage -output "${tmp_dir}/seed.iso" \
  -volid cidata -joliet -rock \
  user-data meta-data network-config

sudo dd bs=2048 if="${tmp_dir}/seed.iso" \
    of="${DEVICE_PATH}" status=progress oflag=sync
