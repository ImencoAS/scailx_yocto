SUMMARY = "An image with full multimedia and Machine Learning support"

require recipes-core/images/karo-image-weston.bb

DEFAULT_DTB = 'imx8mp-qsxp-ml81-qsbase3-raspi-display.dtb'

GOOGLE_CORAL_PKGS = " \
        libedgetpu \
"

OPENCV_PKGS_imxgpu = " \
        opencv-apps \
        opencv-samples \
        python3-opencv \
        python3-pygobject \
"

IMAGE_INSTALL_append = " \
        ${OPENCV_PKGS} \
        packagegroup-fsl-tools-gpu \
        packagegroup-fsl-tools-gpu-external \
        packagegroup-imx-ml \
        python3-pip \
        python3-smbus \
        tzdata \
"

TOOLCHAIN_TARGET_TASK_append = " \
        tensorflow-lite-staticdev \
"
