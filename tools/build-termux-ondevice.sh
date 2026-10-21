#!/data/data/com.termux/files/usr/bin/bash
#
# Build libvulkan_wrapper.so natively inside Termux (aarch64 Android).
#
# Why on-device:
#   The CI image cross-compiles with NDK clang and links against the Termux
#   sysroot. That hybrid is rejected by Wine's ELF loader. Building with the
#   Termux clang produces an ELF that matches the reference FristOneRR 2.0
#   wrapper: AArch64 ET_DYN, EI_OSABI 0, and -- critically -- no DT_RELR
#   packed relative relocations.
#
# Why --pack-dyn-relocs=none:
#   NDK/Termux clang enable packed relative relocations by default for
#   API >= 30. Wine (Winlator) cannot apply DT_RELR and reports the
#   misleading "invalid .so library ..., too old?". Always disable it.
#
# Usage:
#   OUTDIR=/storage/EBF9-BC26/tbuild bash tools/build-termux-ondevice.sh
#
# Prerequisites (installed automatically):
#   pkg install clang lld binutils ninja python git glslang spirv-tools \
#               libx11 libxcb libxrandr libxext xorgproto libdrm \
#               libandroid-shmem zlib libexpat libxshmfence patchelf
#   pip install meson mako pyyaml packaging
#
set -e

export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PATH"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
export LANG=C

OUTDIR="${OUTDIR:-$HOME/vkwrapper-out}"
REPO_URL="${REPO_URL:-https://github.com/crowndoom/FristOneRR-Wrapperv1.git}"
REPO_BRANCH="${REPO_BRANCH:-fristonerr-wrapper-v1}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/fwbuild}"
TARGET_ANDROID_API="${TARGET_ANDROID_API:-30}"

mkdir -p "$OUTDIR"
LOG="$OUTDIR/build.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== BUILD START $(date) ==="
echo "outdir=$OUTDIR target-api=$TARGET_ANDROID_API"

echo "=== ensure packages ==="
yes | pkg install -y libxshmfence 2>&1 | tail -3 || true

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

if [ ! -d fw/.git ]; then
   rm -rf fw
   git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" fw
fi
cd fw
git fetch --depth 1 origin "$REPO_BRANCH"
git reset --hard FETCH_HEAD
echo "=== HEAD ==="
git log --oneline -3

echo "=== BCn default check (expect both false => mask 0x0000) ==="
grep -n "needs_bc1_emulation\|needs_bc4_emulation\|FORCE_BCN_EMULATION" \
   src/vulkan/wrapper/wrapper_physical_device.c | head -20

# ---------------------------------------------------------------------------
# Dependencies provided by Termux packages instead of subprojects.
# ---------------------------------------------------------------------------
echo "=== stage SPIRV-Tools (static, from the Termux package) ==="
mkdir -p src/vulkan/wrapper/lib
cp -f "$PREFIX/lib/libSPIRV-Tools.a" "$PREFIX/lib/libSPIRV-Tools-opt.a" \
   src/vulkan/wrapper/lib/
rm -rf src/vulkan/wrapper/include/spirv-tools
mkdir -p src/vulkan/wrapper/include/spirv-tools
# code includes "spirv-tools/spirv-tools/optimizer.hpp"
cp -r "$PREFIX/include/spirv-tools" src/vulkan/wrapper/include/spirv-tools/
ls -la src/vulkan/wrapper/lib

# ---------------------------------------------------------------------------
# Small source adaptations for the Termux/API-24 sysroot.
# ---------------------------------------------------------------------------
echo "=== adapt anon_file.c ==="
sed -i "s|@TERMUX_PREFIX@|$PREFIX|g" src/util/anon_file.c
# memfd_create is API 30; the Termux clang sysroot does not declare it, so use
# the portable mkstemp() path instead of relying on an implicit declaration.
sed -i '/^#include <stdlib.h>$/a #undef HAVE_MEMFD_CREATE' src/util/anon_file.c

echo "=== adapt rand_xor.c ==="
# getrandom is API 28; rand_xor already falls back to /dev/urandom.
sed -i '/^#include "detect_os.h"$/a #undef HAVE_GETRANDOM' src/util/rand_xor.c

# ---------------------------------------------------------------------------
# Configure and build.
# ---------------------------------------------------------------------------
export CFLAGS="--target=aarch64-linux-android${TARGET_ANDROID_API} -D__TERMUX__ -D__USE_GNU -U__ANDROID__"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="--target=aarch64-linux-android${TARGET_ANDROID_API} -Wl,--pack-dyn-relocs=none -L$PREFIX/lib -landroid-shmem"

echo "=== meson setup ==="
rm -rf build
meson setup build --prefix="$PREFIX" \
   -Dcpp_rtti=false -Dgbm=disabled -Dopengl=false -Dllvm=disabled \
   -Dshared-llvm=disabled -Dplatforms=x11 -Dgallium-drivers= \
   -Dxmlconfig=disabled -Dvulkan-drivers=wrapper -Dbuildtype=release \
   --wrap-mode=nodownload

echo "=== ninja ==="
ninja -C build src/vulkan/wrapper/libvulkan_wrapper.so

SO=build/src/vulkan/wrapper/libvulkan_wrapper.so
ls -la "$SO"
cp "$SO" "$OUTDIR/libvulkan_wrapper.so"
"$PREFIX/bin/llvm-strip" --strip-unneeded -o "$OUTDIR/libvulkan_wrapper.so.stripped" "$SO" \
   || cp "$SO" "$OUTDIR/libvulkan_wrapper.so.stripped"

echo "=== verify: no .relr.dyn, no DT_RELR ==="
if readelf -S "$OUTDIR/libvulkan_wrapper.so" | grep -q ".relr.dyn"; then
   echo "FATAL: .relr.dyn present - Wine will reject this binary"
   exit 1
fi
if readelf -d "$OUTDIR/libvulkan_wrapper.so" | grep -qi "RELR"; then
   echo "FATAL: DT_RELR present - Wine will reject this binary"
   exit 1
fi
echo "OK: no packed relative relocations"
readelf -d "$OUTDIR/libvulkan_wrapper.so" | grep NEEDED

ls -la "$OUTDIR"
echo "=== BUILD DONE $(date) ==="
