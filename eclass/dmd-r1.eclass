# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: dmd-r1.eclass
# @MAINTAINER:
# Andrei Horodniceanu <a.horodniceanu@proton.me>
# @AUTHOR:
# Andrei Horodniceanu <a.horodniceanu@proton.me>
# Based on dmd.eclass by Marco Leise <marco.leise@gmx.de>.
# @BUGREPORTS:
# Please report bugs via https://github.com/gentoo/dlang/issues
# @VCSURL: https://github.com/gentoo/dlang
# @SUPPORTED_EAPIS: 8
# @BLURB: Captures most of the logic for building and installing DMD
# @DESCRIPTION:
# Helps with the maintenance of the various DMD versions by capturing common
# logic.

if [[ ! ${_ECLASS_ONCE_DMD_R1} ]] ; then
_ECLASS_ONCE_DMD_R1=1

case ${EAPI:-0} in
	8) ;;
	*) die "${ECLASS}: EAPI ${EAPI:-0} not supported" ;;
esac

DESCRIPTION="Reference compiler for the D programming language"
HOMEPAGE="https://dlang.org/"

# DMD supports amd64/x86 exclusively
# @ECLASS_VARIABLE: MULTILIB_COMPAT
# @DESCRIPTION:
# A list of multilib ABIs supported by $PN. It only supports
# abi_x86_{32,64}. See the multilib-build.eclass documentation for this
# variable for more information.
MULTILIB_COMPAT=( abi_x86_{32,64} )

inherit desktop edos2unix dlang-single multilib-build multiprocessing optfeature

# @FUNCTION: _have_examples
# @INTERNAL
# @RETURN: shell true if the package version has the samples folder
_have_examples() {
	ver_test -lt 2.111.0_beta1
}

LICENSE=Boost-1.0
# A couple of files are public domain, e.g. dmd/compiler/src/dmd/backend/bcomplex.d
LICENSE+=" public-domain"
# valgrind headers are BSD-like, see: dmd/druntime/src/etc/valgrind/memcheck.h
LICENSE+=" BZIP2"
# curl header: phobos/etc/c/curl.d
LICENSE+=" curl"
# zlib header: phobos/etc/c/zlib.d
LICENSE+=" ZLIB"
# Older versions use md5 for hashing newer ones use blake3
if ver_test -ge 2.109.0_beta1; then
	# see: dmd/compiler/src/dmd/common/blake3.d which is based on:
	# https://github.com/oconnor663/blake3_reference_impl_c
	LICENSE+=" || ( CC0-1.0 Apache-2.0 )"
else
	# see: dmd/compiler/src/dmd/common/md5.d
	LICENSE+=" RSA"
fi
# Some files in dmd/compiler/samples like htmlget.d are public-domain.
# dmd/compiler/samples/d2html.d has a license which sounds like the colt
# license which is not free. The file has little value so it won't be
# installed.
_have_examples && LICENSE+=" examples? ( public-domain )"

SLOT=$(ver_cut 1-2)
readonly MAJOR=$(ver_cut 1)
readonly MINOR=$(ver_cut 2)
readonly PATCH=$(ver_cut 3)
: "${BOOTSTRAP_VERSION:=${PV}}"

# For prereleases, 2.097.0_rc1 -> 2.097.0-rc.1
MY_VER=$(ver_rs 3 - 4 .)
MY_BOOTSTRAP_VER=$(ver_rs 3 - 4 . "${BOOTSTRAP_VERSION}")


# @FUNCTION: _gen_dmd_tarball_uri
# @USAGE: <version>
# @INTERNAL
# @DESCRIPTION:
# Output a URI to the dmd upstream tarball identified by the given version.
_gen_dmd_tarball_uri() {
	local v=${1}
	local isBeta=$(ver_cut 4- "${v}")
	local directory=$(ver_cut 1-3 "${v}")
	echo "https://downloads.dlang.org/${isBeta:+pre-}releases/2.x/${directory}/dmd.${v}.linux.tar.xz"
}

if [[ ${PV} != *9999* ]]; then
	SRC_URI="
		https://github.com/dlang/${PN}/archive/refs/tags/v${MY_VER}.tar.gz -> ${PN}-${MY_VER}.tar.gz
		https://github.com/dlang/phobos/archive/refs/tags/v${MY_VER}.tar.gz -> phobos-${MY_VER}.tar.gz
	"
	if ver_test -ge 2.110.0; then
		man_pages_uri="https://github.com/the-horo/distfiles/releases/download/init"
		SRC_URI+=" ${man_pages_uri}/${PN}-man-pages-${PV}.tar.xz"
	fi
else
	inherit git-r3
	EGIT_REPO_URI="https://github.com/dlang/dmd"
	PHOBOS_REPO_URI="https://github.com/dlang/phobos"
	: "${EGIT_BRANCH:=master}"
fi

SRC_URI+=" selfhost? ( $(_gen_dmd_tarball_uri "${MY_BOOTSTRAP_VER}") )"
IUSE="+selfhost static-libs"
_have_examples && IUSE+=" examples"

if [[ ${PV} != *9999* ]]; then
	SRC_URI+=" doc? ( $(_gen_dmd_tarball_uri "${MY_VER}") )"
	IUSE+=" doc"
fi

REQUIRED_USE="^^ ( selfhost ${DLANG_REQUIRED_USE} )"
IDEPEND=">=app-eselect/eselect-dlang-20140709"
BDEPEND="!selfhost? ( ${DLANG_DEPS} )"
# We don't need anything in DEPEND, curl is dl-opened
# so it belongs in RDEPEND.
#
# Thinking about this more ${DLANG_DEPS} should probably go in DEPEND. I
# want, however, to test this before making the fix.
#DEPEND=
RDEPEND="
	${IDEPEND}
	net-misc/curl[${MULTILIB_USEDEP}]
	!selfhost? ( ${DLANG_DEPS} )
"

MAN_PAGES_S="${WORKDIR}/${PN}-man-pages-${PV}"

dmd-r1_pkg_setup() {
	if use !selfhost; then
		dlang-single_pkg_setup
		# set by dlang-single.eclass:
		# $EDC, $DC, $DLANG_LDFLAGS, $DCFLAGS

		# Now let's build our environment
		export DMDW=$(dlang_get_dmdw)
		export DMDW_DCFLAGS=$(dlang_get_dmdw_dcflags)
		export DMDW_LDFLAGS=$(dlang_get_dmdw_ldflags)
	else
		# Setup up similar variables to the above
		export EDC=dmd-${SLOT}
		#export DC= # is set inside src_unpack
		#export DMDW= # is set inside src_unpack
		export DLANG_LDFLAGS=$(dlang_get_ldflags)
		# Should we put user DMDFLAGS here?
		export DMDW_DCFLAGS= DCFLAGS=
		export DMDW_LDFLAGS=$(dlang_get_dmdw_ldflags)
	fi
}

dmd-r1_src_unpack() {
	# Here because pkgdev complains about it being in pkg_setup
	if use selfhost; then
		export DC=${WORKDIR}/dmd2/linux/bin$(dlang_get_abi_bits)/dmd
		export DMDW=${DC}
	fi

	default

	if [[ ${PV} != *9999* ]]; then
		# $S may collide with $PN-$MY_VER
		mv "${PN}-${MY_VER}" tmp || die
		mkdir "${S}" || die
		mv -T tmp "${S}/${PN}" || die
		mv -T "phobos-${MY_VER}" "${S}/phobos" || die
	else
		git-r3_fetch
		git-r3_fetch "${PHOBOS_REPO_URI}" "refs/heads/${EGIT_BRANCH}"

		git-r3_checkout "" "${S}/dmd"
		git-r3_checkout "${PHOBOS_REPO_URI}" "${S}/phobos"
	fi
}

dmd-r1_src_compile() {
	einfo "Building dmd build script"
	dlang_compile_bin dmd/compiler/src/build{,.d}
	local BUILD_D=${S}/dmd/compiler/src/build

	local cmd=(
		env
		VERBOSE=1
		HOST_DMD="${DMDW}"
		# Just like old dmd.eclass.
		#
		# TODO, this has to be fixed but right now we either do
		# ENABLE_RELEASE (we add -O -inline -release) or build.d will
		# add -g.
		ENABLE_RELEASE=1
		"${BUILD_D}"
		-j$(makeopts_jobs)
		# A bit overkill to specify the flags here but it does get the
		# job done.
		DFLAGS="${DMDW_DCFLAGS} ${DMDW_LDFLAGS}"
	)

	einfo "Building dmd"
	echo "${cmd[@]}"
	"${cmd[@]}" || die "Failed to build dmd"

	# The release here is from ENABLE_RELEASE, keep them in sync.
	export GENERATED_DMD=${S}/dmd/generated/linux/release/$(dlang_get_abi_bits)/dmd

	compile_libraries() {
		local commonMakeArgs=(
			DMD="${GENERATED_DMD}"
			MODEL=${MODEL}

			# Just like how multilib_toolchain_setup does it:
			CC="$(tc-getCC) $(get_abi_CFLAGS)"
			# The flags are, a little, project dependent
			#CFLAGS=

			# With DFLAGS we have 2 problems:
			#
			# 1. it's pretty hard to specify them for druntime so
			#    it would need a makefile patch
			#
			# 2. we have the same question as in pkg_setup, do we
			#    respect DMDFLAGS when building with the generated dmd?
			#
			#DFLAGS=
		)
		local druntimeMakeArgs=(
			# Calls git in global scope, only used for whitespace checks.
			MANIFEST=

			# Specifying user flags here discards the, hopefully
			# relevant, values from the makefile so add them back.
			CFLAGS="${CFLAGS} -fPIC -DHAVE_UNISTD_H" # -m32/64 is added in $CC.

			# druntime's notion of a shared library is a static archive
			# that is embedded into the phobos shared library.
			#
			# Technically there is the dll_so target which is the proper
			# so file but who's gonna use it? Perhaps if phobos would
			# not incorporate druntime we could install them as separate
			# libraries (like ldc2 and gdc).
			$(usex static-libs 'lib dll' dll)

			# We also need to copy the headers to the proper location
			import
		)
		local phobosMakeArgs=(
			# If unspecified, would rebuild druntime.
			CUSTOM_DRUNTIME=1

			# Like druntime, specifying flags removes the makefile added ones.
			#
			# Since 2.108.0 -DHAVE_UNISTD_H is handled by CPPFLAGS => we
			# don't need to specify it here.
			CFLAGS="${CFLAGS} -fPIC -std=c11 -DHAVE_UNISTD_H" # -m32/64 is added in $CC.

			# Overkill but it does work. Remember that we have to
			# convert $LDFLAGS to something dmd understands.
			DFLAGS="$(dlang_get_ldflags ${PN}-${SLOT})"

			# By default builds both static+dynamic libraries.
			$(usex static-libs 'lib dll' dll)
		)
		# Prefer compiling C files with CC, not with dmd. (USE_IMPORTC=1
		# adds a dependency on libdruntime.a)
		ver_test -ge 2.108.0 && phobosMakeArgs+=( "USE_IMPORTC=0" )

		emake -C dmd/druntime "${commonMakeArgs[@]}" "${druntimeMakeArgs[@]}"
		emake -C phobos "${commonMakeArgs[@]}" "${phobosMakeArgs[@]}"
	}

	_dmd_foreach_abi compile_libraries

	if [[ ${PV} == *9999* ]] || ver_test -lt 2.110.0 ; then
		# Build the man pages
		local cmd=(
			env
			VERBOSE=1
			HOST_DMD="${GENERATED_DMD}"
			"${BUILD_D}"
			-j$(makeopts_jobs)
			man
			# ${GENERATED_DMD} is not yet fully functional as we didn't
			# create a good dmd.conf. But instead of doing that we're going
			# to specify our flags here.
			DFLAGS="-defaultlib=phobos2 -L-rpath=${S}/phobos/generated/linux/release/$(dlang_get_abi_bits)"
		)
		echo "${cmd[@]}"
		"${cmd[@]}" || die "Could not generate man pages"

		# Place them in a predictable directory
		mkdir "${MAN_PAGES_S}" || die
		cp dmd/generated/docs/man/{man1/dmd.1,man5/dmd.conf.5} "${MAN_PAGES_S}" || die
	fi

	# Now clean up some artifacts that would make the install phase
	# harder (we rely on globbing and recursive calls a lot).

	# The object file is useless, to support 9999 we glob for it
	rm -f phobos/generated/linux/release/*/libphobos2.so.*.o || die
	# the zlib folder contains source code which is no longer
	# needed. Don't touch etc/c/zlib.d however, that's important.
	rm -rf phobos/etc/c/zlib || die
}

dmd-r1_src_test() {
	# As opposed to old dmd.eclass we have access to actual tests. For
	# porting reasons we're going to keep only the old test,
	# hello_world.
	cat <<-EOF > "${T}/hello.d"
	import std.stdio;

	void main(string[] args) {
		writeln("hello world");
		writefln("args.length = %d", args.length);

		foreach (index, arg; args) {
			writefln("args[%d] = '%s'", index, arg);
		}
	}
EOF

	test_hello_world() {
		local phobosDir=${S}/phobos/generated/linux/release/${MODEL}
		local commandArgs=(
			# Copied from _gen_dmd.conf
			-L--export-dynamic
			-defaultlib=phobos2 # If unspecified, defaults to libphobos2.a
			-fPIC
			-L-L"${phobosDir}"
			-L-rpath="${phobosDir}"

			-conf= # Don't use dmd.conf
			-m${MODEL}
			-Iphobos
			-Idmd/druntime/import
		)

		"${GENERATED_DMD}" "${commandArgs[@]}" "${T}/hello.d" \
			|| die "Failed to build hello.d (${MODEL}-bit)"
		./hello ${MODEL}-bit || die "Failed to run test sample (${MODEL}-bit)"
	}

	_dmd_foreach_abi test_hello_world
}

dmd-r1_src_install() {
	local EDC=${PN}-${SLOT} # overwrite the one from pkg_setup
	local dmd_prefix=/usr/lib/${PN}/$(dlang_get_be_version)

	dodir /etc/dmd
	_gen_dmd.conf > "${ED}"/etc/dmd/${SLOT}.conf || die "Could not generate dmd.conf"
	# Put a symlink to dmd.conf into the same folder as the dmd
	# executable so it gets picked up automatically (and instead of
	# /etc/dmd.conf).
	dosym -r "/etc/dmd/${SLOT}.conf" "${dmd_prefix}/bin/dmd.conf"

	into "${dmd_prefix}"
	dobin "${GENERATED_DMD}"
	dosym -r "${dmd_prefix}/bin/dmd" "/usr/bin/dmd-${SLOT}"

	insinto "${dmd_prefix}"
	doins -r dmd/druntime/import

	# Old dmd.eclass installed the so to $(get_libdir) and symlinked it
	# into ${dmd_prefix}. We do it the other way around.
	install_phobos_2() {
		local G=phobos/generated/linux/release/${MODEL}
		into /usr

		dlang_dolib.so "${G}"/libphobos2.so*
		use static-libs && dlang_dolib.a "${G}"/libphobos2.a

		# Avoid collisions of 9999 and other slots
		if [[ ${PV} != *9999* ]]; then
			# The symlinks under $(get_libdir) are only for backwards
			# compatibility purposes.
			local filename=libphobos2.so.0.${MINOR}
			dosym -r "/usr/$(dlang_get_libdir)/${filename}" "/usr/$(get_libdir)/${filename}"
			dosym -r "/usr/$(dlang_get_libdir)/${filename}.${PATCH}" "/usr/$(get_libdir)/${filename}.${PATCH}"
		fi
	}
	_dmd_foreach_abi install_phobos_2
	insinto "${dmd_prefix}"/import
	doins -r phobos/{etc,std}

	insinto "${dmd_prefix}"/man/man1
	doins "${MAN_PAGES_S}"/dmd.1
	insinto "${dmd_prefix}"/man/man5
	doins "${MAN_PAGES_S}"/dmd.conf.5

	if _use_examples; then
		# Problematic license
		rm dmd/compiler/samples/d2html.d || die

		insinto "${dmd_prefix}"/samples
		doins -r dmd/compiler/samples/*
		docompress -x "${dmd_prefix}"/samples
	fi

	if _use_doc; then
		HTML_DOCS=( "${WORKDIR}"/dmd2/html/* )
		einstalldocs
		insinto "/usr/share/doc/${PF}/html"
		doins "${FILESDIR}/dmd-doc.png"
		make_desktop_entry "xdg-open ${EPREFIX}/usr/share/doc/${PF}/html/d/index.html" \
						   "DMD ${PV}" \
						   "${EPREFIX}/usr/share/doc/${PF}/html/dmd-doc.png" \
						   "Development"
	fi
}

dmd-r1_pkg_postinst() {
	"${EROOT}"/usr/bin/eselect dlang update dmd

	_use_examples &&
		elog "Examples can be found in: ${EPREFIX}/usr/lib/${PN}/${SLOT}/samples"
	_use_doc && elog "HTML documentation is in: ${EPREFIX}/usr/share/doc/${PF}/html"

	optfeature "additional D development tools" "dev-util/dlang-tools"
}

dmd-r1_pkg_postrm() {
	"${ERROT}"/usr/bin/eselect dlang update dmd
}

# @FUNCTION: _use_doc
# @INTERNAL
# @RETURN: shell true if the doc USE flag is enabled
_use_doc() {
	[[ ${PV} != *9999* ]] && use doc
}

# @FUNCTION: _use_examples
# @INTERNAL
# @RETURN: shell true if the examples use flag exists and is enabled
_use_examples() {
	_have_examples && use examples
}

# @FUNCTION: _gen_dmd.conf
# @INTERNAL
# @DESCRIPTION:
# Print a dmd.conf to be installed on the user system. Needs $EDC to be
# set up up beforehand.
_gen_dmd.conf() {
	debug-print-function ${FUNCNAME} "${@}"

	# Note, the logic for which libdir is used is all kept in
	# dlang-utils.eclass in order not to duplicate code.

	local import_dir=${EPREFIX}/usr/lib/${PN}/$(dlang_get_be_version)/import
	# Should this, instead, check which ABIs have been enabled?
	if has_multilib_profile; then
		local libdir_amd64=${EPREFIX}/usr/$(ABI=amd64 dlang_get_libdir)
		local libdir_x86=${EPREFIX}/usr/$(ABI=x86 dlang_get_libdir)
		cat <<EOF
[Environment]
DFLAGS=-I${import_dir} -L--export-dynamic -defaultlib=phobos2 -fPIC
[Environment32]
DFLAGS=%DFLAGS% -L-L${libdir_x86} -L-rpath=${libdir_x86}
[Environment64]
DFLAGS=%DFLAGS% -L-L${libdir_amd64} -L-rpath=${libdir_amd64}
EOF

	else
		local libdir=${EPREFIX}/usr/$(dlang_get_libdir)
		cat <<EOF
[Environment]
DFLAGS=-I${import_dir} -L--export-dynamic -defaultlib=phobos2 -fPIC -L-L${libdir} -L-rpath=${libdir}
EOF

	fi
}

# @FUNCTION: _dmd_foreach_abi
# @USAGE: <cmd> [<args>...]
# @INTERNAL
# @DESCRIPTION:
# Run a command for each enabled ABI, similar to multilib_foreach_abi but
# without setting $BUILD_DIR. Sets up $ABI and $MODEL (bits)
# appropriately.
_dmd_foreach_abi() {
	debug-print-function ${FUNCNAME} "${@}"

	local ABI
	for ABI in $(multilib_get_enabled_abis); do
		local MODEL=$(dlang_get_abi_bits)
		einfo "Executing ${1} in ${MODEL}-bit"
		"${@}"
	done
}

fi

EXPORT_FUNCTIONS pkg_setup src_unpack src_compile src_test src_install pkg_postinst pkg_postrm
