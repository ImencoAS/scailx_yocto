# Recipe created by recipetool
# This is the basis of a recipe and may need further editing in order to be fully functional.
# (Feel free to remove these comments when editing.)

# WARNING: the following LICENSE and LIC_FILES_CHKSUM values are best guesses - it is
# your responsibility to verify that the values are complete and correct.
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5b6e7472988e8bc9eae127156113e555"

SRC_URI = "git://github.com/cli/cli.git;protocol=https;branch=trunk;destsuffix=git"

# Modify these as desired
PV = "2.32"
SRCREV = "8622bc0dd5e6ab93e526db47ab5650d63e4ec66f"

S = "${WORKDIR}/git"
# GO_IMPORT = "import"

inherit go

# do_configure[cleandirs] += "${B}"
# do_configure () {
# 	# Specify any needed configure commands here
#     cp -fr ${S}/* ${B}
# }

do_compile () {
	# You will almost certainly need to add additional arguments here
    cd ${S}
	oe_runmake script/build
}

# do_install () {
# 	# This is a guess; additional arguments may be required
# 	oe_runmake install 'DESTDIR=${D}'
# }

