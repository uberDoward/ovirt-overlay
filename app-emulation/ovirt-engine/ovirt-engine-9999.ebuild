# Copyright 1999-2009 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5
PYTHON_COMPAT=( python2_7 )

CHECKREQS_MEMORY="8G"

inherit eutils java-pkg-2 git-2 python-r1 check-reqs

DESCRIPTION="oVirt Engine"
HOMEPAGE="http://www.ovirt.org"
#EGIT_REPO_URI="git://gerrit.ovirt.org/ovirt-engine"
EGIT_REPO_URI="git://github.com/alonbl/ovirt-engine.git"
EGIT_BRANCH="otopi"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS=""
IUSE="+system-jars minimal"

MAVEN_SLOT="3.0"
MAVEN="mvn-${MAVEN_SLOT}"
JBOSS_HOME="/usr/share/ovirt/jboss-as"

JARS="
	app-emulation/ovirt-host-deploy[java]
	dev-java/aopalliance
	dev-java/c3p0
	dev-java/commons-beanutils
	dev-java/commons-codec
	dev-java/commons-collections
	dev-java/commons-compress
	dev-java/commons-configuration 
	dev-java/commons-httpclient
	dev-java/commons-jxpath 
	dev-java/commons-lang
	dev-java/httpcomponents-client-bin
	dev-java/jaxb
	dev-java/jdbc-postgresql
	dev-java/slf4j-api
	dev-java/stax
	dev-java/validation-api
	dev-java/ws-commons-util
	dev-java/xml-commons 
	dev-java/xz-java
	"

DEPEND=">=virtual/jdk-1.7
	dev-java/maven-bin:${MAVEN_SLOT}
	app-arch/unzip
	${JARS}"
RDEPEND=">=virtual/jre-1.7
	www-servers/apache[apache2_modules_headers,apache2_modules_proxy_ajp,ssl]
	${PYTHON_DEPS}
	app-emulation/ovirt-jboss-as-bin
	dev-db/postgresql-server[uuid]
	virtual/cron
	dev-libs/openssl
	app-arch/gzip
	net-dns/bind-tools
	sys-libs/cracklib[python]
	dev-python/psycopg
	dev-python/m2crypto
	dev-python/cheetah
	dev-python/python-daemon
	${JARS}"

# for the unneeded custom logrotate: ovirtlogrot.sh
RDEPEND="${RDEPEND}
	app-arch/xz-utils"

pkg_setup() {
	java-pkg-2_pkg_setup

	enewgroup ovirt
	enewuser ovirt -1 "" "" ovirt
	enewuser vdsm -1 "" "" kvm

	export MAVEN_OPTS="-Djava.io.tmpdir=${T} \
		-Dmaven.repo.local=$(echo ~portage)/${PN}-maven-repository"

	python_export python2_7	 PYTHON PYTHON_SITEDIR

	# TODO: we should be able to disable pom install
	MAKE_COMMON_ARGS=" \
		MVN=mvn-${MAVEN_SLOT} \
		PYTHON=${PYTHON} \
		PYTHON_DIR=${PYTHON_SITEDIR} \
		PREFIX=/usr \
		SYSCONF_DIR=/etc \
		PKG_PKI_DIR=/etc/ovirt-engine/pki \
		LOCALSTATE_DIR=/var \
		MAVENPOM_DIR=/tmp \
		JAVA_DIR=/usr/share/${PN}/java \
		EXTRA_BUILD_FLAGS=$(use minimal && echo "-Dgwt.userAgent=gecko1_8") \
		DISPLAY_VERSION=${PVR} \
		"
}

src_compile() {
	emake -j1 \
		${MAKE_COMMON_ARGS} \
		all \
		|| die
}

src_install() {
	emake -j1 \
		${MAKE_COMMON_ARGS} \
		DESTDIR="${ED}" \
		install \
		|| die

	# remove the pom files
	rm -fr "${ED}/tmp"

	# Posgresql JDBC driver is missing from maven output
	cd "${ED}/usr/share/ovirt-engine/engine.ear/lib"
	java-pkg_jar-from jdbc-postgresql
	cd "${S}"

	if use system-jars; then
		# TODO: we still have binaries

		cd "${ED}/usr/share/ovirt-engine/engine.ear/lib"
		while read dir package; do
			[ -z "${package}" ] && package="${dir}"
			rm -f ${dir}*.jar
			java-pkg_jar-from "${package}"
		done << __EOF__
aopalliance aopalliance-1
c3p0
commons-beanutils commons-beanutils-1.7
commons-codec
commons-collections
commons-compress
commons-httpclient commons-httpclient-3
commons-lang commons-lang-2.1
jaxb jaxb-2
otopi
ovirt-host-deploy
slf4j-api
stax
validation-api validation-api-1.0
ws-commons-util
xml-apis xml-commons
xz xz-java
__EOF__
		cd "${S}"

		find "${ED}/usr/share/ovirt-engine/modules" -name module.xml | \
		while read module; do
			cd "$(dirname "${module}")"
			while read current package name; do
				[ -z "${package}" ] && package="${current}"
				if grep -q "<resource-root path=\"${current}" module.xml; then
					rm -f ${current}*.jar
					java-pkg_jar-from "${package}"
					if ! [ -e "${current}.jar" ]; then
						if [ -n "${name}" ]; then
							ln -s ${name}.jar "${current}.jar"
						elif [ "${current}" != "${package}" ]; then
							ln -s "${package}.jar" "${current}.jar"
						fi
					fi
				fi
			done << __EOF__
commons-compress
commons-configuration
commons-httpclient commons-httpclient-3
commons-jxpath
otopi otopi otopi*
ovirt-host-deploy ovirt-host-deploy ovirt-host-deploy*
postgresql jdbc-postgresql
slf4j-api
ws-commons-util
__EOF__
		done
	fi

	# TODO:
	# the following should move
	# from make to spec
	# for now just remove them
	# postgres was installed at lib of ear
	rm -fr \
		"${ED}/etc/tmpfiles.d" \
		"${ED}/etc/rc.d" \
		"${ED}/lib/systemd"

	# install only 2nd generation setup
	rm "${ED}/usr/bin/engine-setup"
	dosym engine-setup-2 /usr/bin/engine-setup

	fowners ovirt:ovirt /etc/ovirt-engine/pki/{,certs,requests,private}

	diropts -o ovirt -g ovirt
	keepdir /var/log/ovirt-engine/{,notifier,engine-manage-domains,host-deploy}
	keepdir /var/lib/ovirt-engine/{,deployments,content}
	keepdir /var/cache/ovirt-engine

	insinto /etc/ovirt-engine-setup.conf.d
	newins "${FILESDIR}/gentoo-setup.conf" "01-gentoo.conf"
	insinto /etc/ovirt-engine-setup.env.d
	newins "${FILESDIR}/gentoo-setup.env" "01-gentoo.env"

	#
	# Force TLS/SSL for selected applications.
	#
	for war in restapi userportal webadmin; do
		sed -i \
			-e 's#<transport-guarantee>NONE</transport-guarantee>#<transport-guarantee>CONFIDENTIAL</transport-guarantee>#' \
			"${ED}/usr/share/ovirt-engine/engine.ear/${war}.war/WEB-INF/web.xml"
	done

	python_export python2_7	EPYTHON PYTHON
	find "${ED}" -name '*.py' | while read f; do
		local shebang=$(head -n 1 "${f}")
		from="#!/usr/bin/python"
		to="#!${PYTHON}"
		if [ "${shebang}" = "${from}" ]; then
			sed -i -e "1s:${from}:${to}:" "${f}"
		fi
	done
	python_optimize
	python_optimize "${ED}/usr/share/ovirt-engine"

	newinitd "${FILESDIR}/ovirt-engine.init.d" "ovirt-engine"

	if use system-jars; then
		WHITE_LIST="\
bll.jar|\
common.jar|\
compat.jar|\
dal.jar|\
frontend.jar|\
gwt-extension.jar|\
gwt-servlet.jar|\
scheduler.jar|\
searchbackend.jar|\
tools.jar|\
utils.jar|\
vdsbroker.jar\
"
		BLACK_LIST_JARS="$(
			find "${ED}" -name '*.jar' -type f | \
			xargs -n1 basename -- | sort | uniq | \
			grep -v -E "${WHITE_LIST}" \
		)"
	fi
}

pkg_postinst() {
	if use system-jars; then
		ewarn "system-jars was selected, however, these componets still binary:"
		ewarn "$(echo "${BLACK_LIST_JARS}" | sed 's/^/\t/')"
	fi

	ewarn "You should enable proxy by adding the following to /etc/conf.d/apache2"
	ewarn '    APACHE2_OPTS="${APACHE2_OPTS} -D PROXY"'
}

pkg_config() {
	/usr/bin/engine-setup
}
