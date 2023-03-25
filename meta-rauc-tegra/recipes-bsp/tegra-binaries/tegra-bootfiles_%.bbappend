FILESEXTRAPATHS:append := ":${THISDIR}/${BPN}"

CURTHISDIR := "${THISDIR}"

SRC_URI = "file://flash_t234_qspi_sdmmc.xml"

# This file has been taken from the upstream binary distribution and
# modified to include the required partition layout changes for RAUC slots.
PARTITION_FILE = "${CURTHISDIR}/${BPN}/flash_t234_qspi_sdmmc.xml"
