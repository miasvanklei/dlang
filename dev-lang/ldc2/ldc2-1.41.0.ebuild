# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DLANG_COMPAT=( dmd-2_{106..109} gdc-1{3..4} ldc2-1_{35..41} )
LLVM_COMPAT=( {15..20} )
PYTHON_COMPAT=( python3_{10..13} )
inherit dlang-single llvm-r1 multiprocessing python-any-r1 toolchain-funcs cmake

PATCH_VER=1
PATCH_TAG_NAME="1.40.0-patches-${PATCH_VER}"
PATCH_URL_BASE="https://github.com/the-horo/ldc-patches/archive/refs/tags"

DESCRIPTION="LLVM D Compiler"
HOMEPAGE="https://github.com/ldc-developers/ldc"
MY_PV="${PV//_/-}"
MY_P="ldc-${MY_PV}-src"
SRC_URI="
	https://github.com/ldc-developers/ldc/releases/download/v${MY_PV}/${MY_P}.tar.gz
	${PATCH_URL_BASE}/${PATCH_TAG_NAME}.tar.gz
"
S=${WORKDIR}/${MY_P}
LICENSE="BSD"
# dmd code but without the runtime libs, see dmd-r1.eclass for more details
LICENSE+=" Boost-1.0 || ( CC0-1.0 Apache-2.0 )"
# llvm bits
LICENSE+=" Apache-2.0-with-LLVM-exceptions UoI-NCSA"
# old gdc + dmd code
LICENSE+=" GPL-2+ Artistic"

SLOT="$(ver_cut 1-2)"
KEYWORDS="~amd64 ~arm64 ~x86"

IUSE="debug test"
RESTRICT="!test? ( test )"

REQUIRED_USE=${DLANG_REQUIRED_USE}
COMMON_DEPEND="
	${DLANG_DEPS}
	$(llvm_gen_dep '
	  llvm-core/llvm:${LLVM_SLOT}=[debug=]
	')
"
RDEPEND="${COMMON_DEPEND}"
DEPEND="
	${COMMON_DEPEND}
	test? (
		  dev-libs/ldc2-runtime:${SLOT}
	)
"
BDEPEND="
	${DLANG_DEPS}
	test? (
		  ${PYTHON_DEPS}
		  $(python_gen_any_dep '
			dev-python/lit[${PYTHON_USEDEP}]
		  ')
	)
"
IDEPEND=">=app-eselect/eselect-dlang-20241230"
PDEPEND="dev-libs/ldc2-runtime:${SLOT}"

INSTALL_PREFIX="${EPREFIX}/usr/lib/ldc2/${SLOT}" # /usr/lib/ldc2/1.41

python_check_deps() {
	python_has_version "dev-python/lit[${PYTHON_USEDEP}]"
}

pkg_setup() {
	dlang_setup
	llvm-r1_pkg_setup
	use test && python_setup
}

src_prepare() {
	# Disable GDB tests by passing GDB_FLAGS=OFF
	# Put this here to avoid trigerring reconfigurations later on.
	sed -i 's/\(GDB_FLAGS=\)\S\+/\1OFF/' "${S}"/tests/dmd/CMakeLists.txt

	# Calls gcc directly
	sed -i "s/gcc/$(tc-getCC)/" "${S}"/tests/dmd/runnable/importc-test1.sh || die

	local patches_dir="${WORKDIR}/ldc-patches-${PATCH_TAG_NAME}/compiler"
	eapply "${patches_dir}"/0001-lit-cfg-disable-gdb.patch
	eapply "${patches_dir}"/0002-remove-dmd-common-int128-unittest.patch
	eapply "${patches_dir}"/0003-dont-overwrite-user-flags.patch

	eapply "${FILESDIR}/0006-1.41.0-disable-installing-includes.patch"

	cmake_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-DLDC_ENABLE_ASSERTIONS=$(usex debug ON OFF)
		-DD_COMPILER="$(dlang_get_dmdw) $(dlang_get_dmdw_dcflags)"
		-DCOMPILER_RT_BASE_DIR="${EPREFIX}"/usr/lib/clang
		-DCOMPILER_RT_LIBDIR_OS=linux

		-DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
		-DPHOBOS_SYSTEM_ZLIB=ON
		-DLDC_BUILD_RUNTIME=OFF
		-DLDC_WITH_LLD=OFF
		-DLDC_BUNDLE_LLVM_TOOLS=OFF
		-DCOMPILE_D_MODULES_SEPARATELY=ON
		-DTEST_COMPILER_RT_LIBRARIES=none
		# Avoid collisions with other slots. We hardcode the path to
		# make it easier for eselect-dlang to find the right compdir.
		-DBASH_COMPLETION_COMPLETIONSDIR="${INSTALL_PREFIX}/usr/share/bash-completion/completions"
	)
	cmake_src_configure
}

src_test() {
	local libdir="${ESYSROOT}/usr/lib/ldc2/${SLOT}/$(get_libdir)"
	cat >> "${BUILD_DIR}/bin/ldc2.conf" <<-EOF || die
	"${CHOST}":
	{
		lib-dirs = [
			"${libdir}",
		];
		rpath = "${libdir}";
	};
	EOF

	# Call the same tests that .github/actions/main.yml does
	local jobs=$(get_makeopts_jobs)

	# We build it explicitly so that MAKEOPTS is respected
	cmake_src_compile ldc2-unittest
	cmake_src_test -R ldc2-unittest

	# Instead of running cmake_src_test -R lit-tests we call lit directly
	pushd "${BUILD_DIR}"/tests > /dev/null || die
	"${EPYTHON}" runlit.py -j${jobs} -v . || die 'lit tests failed'
	popd > /dev/null || die

	# The dmd testsuite comes into debug and release variants. The debug
	# one does compilable + fail_compilation + runnable, release only
	# does runnable. Since it's a compiler I think it's fine to allow
	# the duplicate tests. A few compilable tests fail with -O.
	#
	# These tests invoke a runner that runs the tests in parallel so
	# specify the jobs only to the runner and not cmake. I'm pretty sure
	# that some of the tests can't be run simultaneously by multiple
	# runners so keep the cmake jobs to 1.
	DMD_TESTSUITE_MAKE_ARGS=-j${jobs} cmake_src_test -j 1 -V -R dmd-testsuite
}

src_install() {
	cmake_src_install

	dosym -r "${INSTALL_PREFIX#${EPREFIX}}/bin/ldc2" "/usr/bin/ldc2-${SLOT}"
	dosym -r "${INSTALL_PREFIX#${EPREFIX}}/bin/ldmd2" "/usr/bin/ldmd2-${SLOT}"
}

pkg_postinst() {
	"${EROOT}"/usr/bin/eselect dlang update ldc2
}

pkg_postrm() {
	"${EROOT}"/usr/bin/eselect dlang update ldc2
}
