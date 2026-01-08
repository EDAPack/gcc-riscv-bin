#!/bin/bash -ex

root=$(pwd)

#********************************************************************
#* Install required packages
#********************************************************************
if test $(uname -s) = "Linux"; then
    yum update -y
    yum install -y wget bison flex texinfo help2man \
        make gcc gcc-c++ git gawk sed \
        python3 patchelf file

    if test -z $image; then
        image=linux
    fi
    export PATH=/opt/python/cp312-cp312/bin:$PATH
    
    rls_plat=${image}
fi

#********************************************************************
#* Validate environment variables
#********************************************************************
if test -z "$gcc_version"; then
  echo "gcc_version not set"
  env
  exit 1
fi

if test -z "$binutils_version"; then
  echo "binutils_version not set"
  env
  exit 1
fi

if test -z "$newlib_version"; then
  echo "newlib_version not set"
  env
  exit 1
fi

#********************************************************************
#* Calculate version information
#********************************************************************
rls_version=${gcc_version}

if test "x${BUILD_NUM}" != "x"; then
    rls_version="${rls_version}.${BUILD_NUM}"
fi

#********************************************************************
#* Setup directories
#********************************************************************
PREFIX=${root}/install
SYSROOT=${PREFIX}/riscv64-unknown-elf
TARGET=riscv64-unknown-elf

rm -rf build install
mkdir -p build install

#********************************************************************
#* Download sources
#********************************************************************
cd ${root}/build

# Function to download with retry
download_with_retry() {
    local url=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: Downloading from $url"
        if wget -q "$url"; then
            echo "Download successful!"
            return 0
        else
            echo "Download failed (exit code $?)"
            if [ $attempt -lt $max_attempts ]; then
                echo "Retrying in 5 seconds..."
                sleep 5
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    echo "ERROR: Failed to download $url after $max_attempts attempts"
    return 1
}

echo "Downloading binutils ${binutils_version}..."
download_with_retry https://ftp.gnu.org/gnu/binutils/binutils-${binutils_version}.tar.xz || exit 1
tar xf binutils-${binutils_version}.tar.xz

echo "Downloading GCC ${gcc_version}..."
download_with_retry https://ftp.gnu.org/gnu/gcc/gcc-${gcc_version}/gcc-${gcc_version}.tar.xz || exit 1
tar xf gcc-${gcc_version}.tar.xz

echo "Downloading newlib ${newlib_version}..."
download_with_retry https://sourceware.org/pub/newlib/newlib-${newlib_version}.tar.gz || exit 1
tar xf newlib-${newlib_version}.tar.gz

#********************************************************************
#* Download GCC prerequisites
#********************************************************************
cd ${root}/build/gcc-${gcc_version}
./contrib/download_prerequisites

#********************************************************************
#* Build binutils
#********************************************************************
echo "Building binutils..."
cd ${root}/build
mkdir -p build-binutils
cd build-binutils

../binutils-${binutils_version}/configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --with-sysroot=${SYSROOT} \
    --disable-nls \
    --disable-werror \
    --disable-gdb \
    --with-expat=yes

make -j$(nproc)
make install

#********************************************************************
#* Build GCC (stage 1 - without libc)
#********************************************************************
echo "Building GCC stage 1..."
cd ${root}/build
mkdir -p build-gcc-stage1
cd build-gcc-stage1

../gcc-${gcc_version}/configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --with-sysroot=${SYSROOT} \
    --with-newlib \
    --without-headers \
    --disable-shared \
    --enable-languages=c \
    --disable-werror \
    --disable-libatomic \
    --disable-libmudflap \
    --disable-libssp \
    --disable-libquadmath \
    --disable-libgomp \
    --disable-nls \
    --disable-bootstrap \
    --enable-multilib \
    --with-arch=rv64gc \
    --with-abi=lp64d

make -j$(nproc) all-gcc
make install-gcc

#********************************************************************
#* Build newlib
#********************************************************************
echo "Building newlib..."
cd ${root}/build
mkdir -p build-newlib
cd build-newlib

export PATH=${PREFIX}/bin:$PATH

../newlib-${newlib_version}/configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-multilib \
    --enable-newlib-io-long-long \
    --enable-newlib-register-fini \
    --disable-newlib-supplied-syscalls \
    --disable-nls

make -j$(nproc)
make install

#********************************************************************
#* Build GCC (stage 2 - with libc)
#********************************************************************
echo "Building GCC stage 2..."
cd ${root}/build
mkdir -p build-gcc-stage2
cd build-gcc-stage2

../gcc-${gcc_version}/configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --with-sysroot=${SYSROOT} \
    --with-native-system-header-dir=/include \
    --with-newlib \
    --disable-shared \
    --enable-languages=c,c++ \
    --enable-tls \
    --disable-werror \
    --disable-libmudflap \
    --disable-libssp \
    --disable-libquadmath \
    --disable-nls \
    --disable-bootstrap \
    --enable-multilib \
    --with-arch=rv64gc \
    --with-abi=lp64d

make -j$(nproc)
make install

#********************************************************************
#* Check for hardcoded paths and fix rpath
#********************************************************************
echo "Checking for binaries with hardcoded library paths..."

# Find all ELF binaries and shared libraries
find ${PREFIX} -type f -executable -o -name "*.so*" | while read file; do
    # Check if it's an ELF file
    if file "$file" | grep -q ELF; then
        echo "Checking: $file"
        
        # Check for rpath/runpath
        rpath=$(patchelf --print-rpath "$file" 2>/dev/null || true)
        
        if [ -n "$rpath" ]; then
            echo "  Found RPATH: $rpath"
            
            # Check if rpath contains absolute paths from build
            if echo "$rpath" | grep -q "${PREFIX}"; then
                echo "  WARNING: RPATH contains build prefix"
            fi
            
            # Set RPATH to $ORIGIN relative paths for portability
            # This allows binaries to find libraries relative to their location
            if echo "$file" | grep -q "${PREFIX}/bin/"; then
                # Binaries in bin/ should look in ../lib
                new_rpath='$ORIGIN/../lib:$ORIGIN/../riscv64-unknown-elf/lib'
                echo "  Setting RPATH to: $new_rpath"
                patchelf --set-rpath "$new_rpath" "$file" 2>/dev/null || true
            elif echo "$file" | grep -q "${PREFIX}/libexec/"; then
                # Binaries in libexec/gcc/* should look up to lib
                new_rpath='$ORIGIN/../../../lib:$ORIGIN/../../../riscv64-unknown-elf/lib'
                echo "  Setting RPATH to: $new_rpath"
                patchelf --set-rpath "$new_rpath" "$file" 2>/dev/null || true
            fi
        fi
        
        # Check for hardcoded paths in the binary
        if strings "$file" | grep -q "^${PREFIX}"; then
            echo "  WARNING: Found hardcoded paths in binary"
            strings "$file" | grep "^${PREFIX}" | head -5
        fi
    fi
done

#********************************************************************
#* Verify installation
#********************************************************************
echo "Verifying installation..."
${PREFIX}/bin/${TARGET}-gcc --version
${PREFIX}/bin/${TARGET}-g++ --version
${PREFIX}/bin/${TARGET}-as --version
${PREFIX}/bin/${TARGET}-ld --version

# Test compilation of a simple program
cat > ${root}/build/test.c << 'EOF'
int main() {
    return 0;
}
EOF

${PREFIX}/bin/${TARGET}-gcc -o ${root}/build/test.elf ${root}/build/test.c
if [ $? -eq 0 ]; then
    echo "Test compilation successful!"
else
    echo "Test compilation failed!"
    exit 1
fi

#********************************************************************
#* Strip binaries to reduce size
#********************************************************************
echo "Stripping binaries..."
find ${PREFIX}/bin -type f -executable | xargs strip 2>/dev/null || true
find ${PREFIX}/libexec -type f -executable | xargs strip 2>/dev/null || true
find ${PREFIX}/${TARGET}/bin -type f -executable | xargs strip 2>/dev/null || true

#********************************************************************
#* Create release tarball
#********************************************************************
cd ${root}
mkdir -p release

# Rename install directory to include target name
mv install gcc-riscv

cd ${root}
tar czf release/gcc-riscv-${rls_plat}-${rls_version}.tar.gz gcc-riscv

echo "Build complete: gcc-riscv-${rls_plat}-${rls_version}.tar.gz"

#********************************************************************
#* Final verification of portability
#********************************************************************
echo ""
echo "Final portability check:"
find gcc-riscv -type f \( -executable -o -name "*.so*" \) | while read file; do
    if file "$file" | grep -q ELF; then
        deps=$(ldd "$file" 2>/dev/null | grep "not found" || true)
        if [ -n "$deps" ]; then
            echo "WARNING: $file has missing dependencies:"
            echo "$deps"
        fi
        
        # Check if any dependency has absolute path outside standard locations
        abs_deps=$(ldd "$file" 2>/dev/null | grep -v "not found" | grep "/" | grep -v "^[[:space:]]*/lib" | grep -v "^[[:space:]]*/usr/lib" || true)
        if [ -n "$abs_deps" ]; then
            echo "INFO: $file dependencies:"
            echo "$abs_deps"
        fi
    fi
done

echo ""
echo "Build completed successfully!"
