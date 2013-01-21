# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5
PYTHON_COMPAT=( python{2_6,2_7,3_1,3_2,3_3} )

inherit python-r1 java-pkg-opt-2
inherit git-2 autotools

DESCRIPTION="oVirt Task Oriented Pluggable Installer/Implementation"
HOMEPAGE="http://www.ovirt.org"
EGIT_REPO_URI="git://gerrit.ovirt.org/${PN}.git"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS=""
IUSE=""

RDEPEND="sys-devel/gettext
	${PYTHON_DEPS}
	java? (
		>=virtual/jre-1.5
		dev-java/commons-logging
	)
"
DEPEND="${RDEPEND}
	dev-python/pep8
	dev-python/pyflakes
	java? (
		>=virtual/jdk-1.5
		dev-java/junit:4
	)
"

src_prepare() {
	eautoreconf
	python_copy_sources
}

src_configure() {
	python_foreach_impl run_in_build_dir default

	if use java; then
		export COMMONS_LOGGING_JAR="$(java-pkg_getjar commons-logging \
				commons-logging.jar)"
		export JUNIT_JAR="$(java-pkg_getjar --build-only junit-4 junit.jar)"
		econf \
			$(use_enable java java-sdk)
	fi
}

src_compile() {
	python_foreach_impl run_in_build_dir default

	use java && default
}

src_install() {
	inst() {
		emake install DESTDIR="${ED}" am__py_compile=true
		python_optimize
		python_optimize "${ED}/usr/share/otopi/plugins"
	}
	python_foreach_impl run_in_build_dir inst

	use java && java-pkg_dojar target/${PN}*.jar
	dodoc README*
}

run_in_build_dir() {
	pushd "${BUILD_DIR}" > /dev/null
	"$@"
	popd > /dev/null
}