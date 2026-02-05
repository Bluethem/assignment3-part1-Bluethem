#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    echo "Deep cleaning kernel build tree"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    
    echo "Configuring kernel with defconfig"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    
    echo "Building kernel image"
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    
    echo "Building kernel modules"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    
    echo "Building device tree blobs"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
echo "Creating base directory structure"
mkdir -p ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    # Usar el espejo de GitHub en lugar de busybox.net
    echo "Cloning busybox from GitHub mirror"
    git clone https://github.com/mirror/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO: Configure busybox
    make distclean
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
echo "Building busybox"
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
echo "Installing busybox to rootfs"
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

echo "Library dependencies"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
echo "Sysroot: ${SYSROOT}"

# Copy program interpreter (dynamic linker)
echo "Extracting program interpreter path"
PROGRAM_INTERPRETER=$(${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter" | awk -F: '{print $2}' | tr -d ' []')
echo "Program interpreter: ${PROGRAM_INTERPRETER}"

if [ -n "${PROGRAM_INTERPRETER}" ]; then
    echo "Copying ${SYSROOT}${PROGRAM_INTERPRETER} to ${OUTDIR}/rootfs/lib"
    cp -L ${SYSROOT}${PROGRAM_INTERPRETER} ${OUTDIR}/rootfs/lib
else
    echo "ERROR: Could not extract program interpreter"
    exit 1
fi

# Copy shared libraries
echo "Copying shared libraries"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library" | awk -F: '{print $2}' | tr -d ' []' | while read library
do
    if [ -n "${library}" ]; then
        echo "Looking for library: ${library}"
        if [ -f ${SYSROOT}/lib64/${library} ]; then
            echo "Copying ${library} from lib64"
            cp -L ${SYSROOT}/lib64/${library} ${OUTDIR}/rootfs/lib64
        elif [ -f ${SYSROOT}/lib/${library} ]; then
            echo "Copying ${library} from lib"
            cp -L ${SYSROOT}/lib/${library} ${OUTDIR}/rootfs/lib
        else
            echo "Warning: Could not find ${library}"
        fi
    fi
done

# TODO: Make device nodes
echo "Creating device nodes"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1

# TODO: Clean and build the writer utility
echo "Building writer utility"
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
echo "Copying finder application files to rootfs"

# Verificar que los archivos existen
if [ ! -f ${FINDER_APP_DIR}/writer ]; then
    echo "ERROR: writer executable not found"
    exit 1
fi

if [ ! -f ${FINDER_APP_DIR}/finder.sh ]; then
    echo "ERROR: finder.sh not found"
    exit 1
fi

if [ ! -f ${FINDER_APP_DIR}/finder-test.sh ]; then
    echo "ERROR: finder-test.sh not found"
    exit 1
fi

if [ ! -f ${FINDER_APP_DIR}/autorun-qemu.sh ]; then
    echo "ERROR: autorun-qemu.sh not found"
    exit 1
fi

# Copiar archivos
cp ${FINDER_APP_DIR}/writer ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home/
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home/

# Copiar el directorio conf (seguir enlaces simbólicos con -L)
echo "Copying conf directory"
cp -rL ${FINDER_APP_DIR}/conf ${OUTDIR}/rootfs/home/

# Verificar que conf/username.txt fue copiado
if [ ! -f ${OUTDIR}/rootfs/home/conf/username.txt ]; then
    echo "ERROR: conf/username.txt was not copied successfully"
    ls -la ${OUTDIR}/rootfs/home/
    exit 1
fi

if [ ! -f ${OUTDIR}/rootfs/home/conf/assignment.txt ]; then
    echo "ERROR: conf/assignment.txt was not copied successfully"
    exit 1
fi

echo "Files copied successfully:"
ls -la ${OUTDIR}/rootfs/home/
ls -la ${OUTDIR}/rootfs/home/conf/

# TODO: Chown the root directory
echo "Changing ownership to root"
cd ${OUTDIR}/rootfs
sudo chown -R root:root *

# TODO: Create initramfs.cpio.gz
echo "Creating initramfs"
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd ${OUTDIR}
gzip -f initramfs.cpio

echo "Build complete!"
echo "Kernel: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"