
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append := "  \
	file://system.conf \
	file://ca.cert.pem \
        file://rauc_setup_and_run.sh \
        file://rauc-setup.service \
"

# additional dependencies required to run RAUC on the target
# u-boot-tegra-env is checked in for TX2
# efibootmgr may be the necessary component, u-boot-tegra-env may need to be deleted
RDEPENDS:${PN} += "u-boot-fw-utils efibootmgr ${PN}-setup "

inherit systemd

PACKAGES += "${PN}-setup"
SYSTEMD_PACKAGES += "${PN}-setup"
SYSTEMD_SERVICE:${PN}-setup = "rauc-setup.service"
# SYSTEMD_AUTO_ENABLE:${PN}-setup = "enable"
FILES:${PN}-setup += "${systemd_system_unitdir}/rauc-setup.service"

do_install:prepend () {
	sed -i "s|@@MACHINE@@|${MACHINE}|g" ${WORKDIR}/system.conf
}

do_install:append () {
    install -d ${D}${sysconfdir}/rauc
    install -m 0755 ${WORKDIR}/rauc_setup_and_run.sh ${D}${sysconfdir}/rauc
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/rauc-setup.service ${D}${systemd_system_unitdir}
}
