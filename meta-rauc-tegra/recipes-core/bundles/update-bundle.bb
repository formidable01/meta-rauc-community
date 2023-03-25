inherit bundle

RAUC_BUNDLE_COMPATIBLE ?= "jetson-agx-orin-devkit"
RAUC_BUNDLE_VERSION ?= "v2023030723"
RAUC_BUNDLE_DESCRIPTION = "RAUC Demo Bundle"
RAUC_BUNDLE_SLOTS ?= "rootfs" 
RAUC_SLOT_rootfs ?= "core-image-minimal"
RAUC_SLOT_rootfs[type] = "image"
RAUC_SLOT_rootfs[fstype] = "ext4"
RAUC_KEY_FILE = "${THISDIR}/files/development-1.key.pem"
RAUC_CERT_FILE = "${THISDIR}/files/development-1.cert.pem"
