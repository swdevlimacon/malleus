#!/bin/bash

set -e

printmsg() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[32m==>\e[0m $msg\n"
	sleep 1
}

printmsgerror() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[31m==!\e[0m $msg\n"
	sleep 1
	exit 1
}

pkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $REPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS
	done
}

pkginstallstage() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Installing $mergepkg"
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $STAGE
	done
}

pkginstallinitrd() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Installing $mergepkg"
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $INITRD
	done
}

toolpkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f
	done
}

pkgupdate() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and updating $mergepkg"
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $REPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS -u
	done
}

toolpkgupdate() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and updating $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f -u
	done
}

initdb() {
	local dir="$@"
	for dbindir in $dir; do
		mkdir -p $dbindir/var/lib/pkg
		touch $dbindir/var/lib/pkg/db
	done
}

rmpkg() {
	local rmpkg="$@"
	for rmpack in $rmpkg; do
		rm -rf $PACKAGES/$rmpack#*
	done
}

check_for_root() {
	if [[ $EUID -ne 0 ]]; then
		printmsgerror "This script must be run as root" 
	fi
}

setup_architecture() {
	case $BARCH in
		riscv32)
			printmsg "Using configuration for riscv32"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="riscv32-linux-musl"
			export XKARCH="riscv"
			export GCCOPTS="--with-arch=rv32imafdc"
			;;
		riscv64)
			printmsg "Using configuration for riscv64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="riscv64-linux-musl"
			export XKARCH="riscv"
			export GCCOPTS="--with-arch=rv64imafdc"
			;;
		*)
			printmsgerror "BARCH variable is not set or supported"
	esac
}

setup_environment() {
	printmsg "Setting up build environment"
	export CWD="$(pwd)"
	export KEEP="$CWD/KEEP"
	export BUILD="$CWD/build"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export PACKAGES="$BUILD/packages"
	export IMAGE="$BUILD/image"
	export INITRD="$BUILD/initrd"
	export STAGE="$BUILD/stage"

	export LC_ALL="POSIX"
	export PATH="$KEEP/bin:$TOOLS/bin:$PATH"
	export HOSTCC="gcc"
	export HOSTCXX="g++"
	export MKOPTS="-j$(expr $(nproc) + 1)"

	export CFLAGS="-Os -g0 -s -pipe"
	export CXXFLAGS="$CFLAGS"
}

make_environment() {
	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $INITRD $STAGE $TOOLS $PACKAGES $IMAGE

	initdb $ROOTFS $TOOLS $INITRD $STAGE
}

build_toolchain() {
	printmsg "Building cross-toolchain for $BARCH"
	pkginstall filesystem
	toolpkginstall file
	toolpkginstall pkgconf
	toolpkginstall binutils
	toolpkginstall gcc-static
	pkginstall linux-headers musl
	toolpkginstall gcc

	printmsg "Cleaning"
	rmpkg file pkgconf binutils gcc-static gcc
}

bootstrap_rootfs() {
	printmsg "Bootstraping root filesystem"
	pkginstall zlib m4 bison flex binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux libnl wpa_supplicant curl libarchive git npkg prt-get
}

generate_stage_archive() {
	printmsg "Building stage archive"

	pkginstallstage filesystem linux-headers musl zlib m4 bison flex binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux curl libarchive git npkg prt-get

	chown -R root:root $STAGE

	cd $STAGE
	tar jcfv $CWD/januslinux-1.0-beta4-$BARCH.tar.bz2 *
}

OPT="$1"
JPKG="$2"

case "$OPT" in
	toolchain)
		check_for_root
		setup_architecture
		setup_environment
		make_environment
		build_toolchain
		;;
	bootstrap)
		check_for_root
		setup_architecture
		setup_environment
		make_environment
		build_toolchain
		bootstrap_rootfs
		;;
	stage)
		check_for_root
		setup_architecture
		setup_environment
		generate_stage_archive
		;;
	package)
		check_for_root
		setup_architecture
		setup_environment
		pkginstall $JPKG
		;;
	host-package)
		check_for_root
		setup_architecture
		setup_environment
		toolpkginstall $JPKG
		;;
	package-update)
		check_for_root
		setup_architecture
		setup_environment
		pkgupdate $JPKG
		;;
	host-package-update)
		check_for_root
		setup_architecture
		setup_environment
		toolpkgupdate $JPKG
		;;
	usage|*)
		mkusage
esac

exit 0

