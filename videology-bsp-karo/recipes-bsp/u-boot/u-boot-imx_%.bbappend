FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
FILESEXTRAPATHS:prepend := "${THISDIR}/u-boot-imx:"

SRC_URI:append:mx8-camera = " file://imx8mp_evk_scailx_defconfig;subdir=git/configs "
SRC_URI:append:mx8-camera = " file://mx8-camera_mfg_defconfig;subdir=git/configs "
SRC_URI:append:mx8-camera = " file://mx8-camera_env.txt;subdir=git "
# SRC_URI:append:mx8-camera = "file://0001-add-clk-delay-for-rtl8211.patch"
# SRC_URI:append:mx8-camera = " file://0001-increase-eqos-ethernet-phy-reset-delay.patch "

SRC_URI:append = " \
	file://0001-add-933.patch \
	file://0001-chnage-timings-c-files.patch \
	file://0003-chnage-to-evk-dts.patch \
"
