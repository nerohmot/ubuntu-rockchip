# shellcheck shell=bash

export BOARD_NAME="Open Marine Gateway"
export BOARD_MAKER="nerohmot"
export BOARD_SOC="Rockchip RK3588S"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-radxa-rk3588"
export UBOOT_RULES_TARGET="radxa-nx5-io-rk3588s"
export COMPATIBLE_SUITES=("noble")
export COMPATIBLE_FLAVORS=("server")

function config_image_hook__omg() {
    local rootfs="$1"
    local overlay="$2"
    local suite="$3"

    return 0
}
# cache_bust: 1745299200
