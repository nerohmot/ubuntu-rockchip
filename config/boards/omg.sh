#
# Open Marine Gateway Board Configuration
#
BOARD_NAME="Open Marine Gateway"
BOARD_SINGLE="omg"
SOA_ARCH="arm64"
SOC="rk3588s"
DTB="rockchip/rk3588s-rock-5a.dtb"

U_BOOT_PACKAGE="u-boot-radxa-rk3588"
U_BOOT_TARGET="radxa-rk3588"
U_BOOT_CONFIG="rock-5a-rk3588_defconfig"

KERNEL_CMDLINE="quiet splash vt.global_cursor_default=0"
