SUMMARY = "An image with full multimedia, Machine Learning and Basler camera support"

require karo-image-ml.bb
DEFAULT_DTB = "imx8mp-qsxp-ml81-qsbase3-ov5640.dtb"

REQUIRED_DISTRO_FEATURES = "x11 wayland"

IMAGE_INSTALL_append = " \
        gentl-producer \
        v4l-utils \
        iperf3 \
        ethtool \
        i2c-tools \
        sclbl \
        nano \
        openssh-sftp \
        openssh-sftp-server \
        gstreamer1.0-rtsp-server gst-variable-rtsp-server \
        xauth \
        imx-vpu-hantro-daemon \
        packagegroup-fsl-gstreamer1.0 \
        packagegroup-fsl-gstreamer1.0-full \
"

# IMAGE_INSTALL_remove = "busybox"

IMAGE_INSTALL_append_mx8mp = " \
        imx8mp-modprobe-config \
        isp-imx \
        packagegroup-imx-isp \
"

IMAGE_FEATURES_remove = "read-only-rootfs"
