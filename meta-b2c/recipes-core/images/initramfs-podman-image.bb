DESCRIPTION = "TorizonCore OSTree initramfs image"

PACKAGE_INSTALL = "initramfs-podman-runner podman conmon virtual-runc udev ${VIRTUAL-RUNTIME_base-utils} base-passwd"
# PACKAGE_EXCLUDE += "skopeo podman-remote kernel-modules"
SYSTEMD_DEFAULT_TARGET = "initrd.target"

# Do not pollute the initrd image with rootfs features
# IMAGE_FEATURES = "splash"

export IMAGE_BASENAME = "initramfs-podman-image"
IMAGE_LINGUAS = ""

LICENSE = "MIT"

IMAGE_FSTYPES = "cpio.gz"

IMAGE_CLASSES:remove = "image_repo_manifest license_image qemuboot"

# avoid circular dependencies
EXTRA_IMAGEDEPENDS = ""

inherit core-image nopackages

IMAGE_ROOTFS_SIZE = "8192"

# Users will often ask for extra space in their rootfs by setting this
# globally.  Since this is a initramfs, we don't want to make it bigger
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_OVERHEAD_FACTOR = "1.0"

BAD_RECOMMENDATIONS += "busybox-syslog"

INITRAMFS_MAXSIZE = "250000"