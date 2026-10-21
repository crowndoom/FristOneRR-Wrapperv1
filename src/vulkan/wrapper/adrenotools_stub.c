/* Copyright 2025
 * SPDX-License-Identifier: MIT
 *
 * Minimal stand-in for libadrenotools' custom driver loader.
 *
 * Upstream links the wrapper against libadrenotools.so, which loads a
 * custom Adreno driver through a hook library and redirects file access.
 * That library is not available in this tree, so degrade gracefully to a
 * plain dlopen() of either the requested custom driver or the system
 * Vulkan driver. This is sufficient for PanVK/Mali where no hook
 * injection is required.
 */

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#if defined(__aarch64__)
#define WRAPPER_DEFAULT_VULKAN_PATH "/system/lib64/libvulkan.so"
#else
#define WRAPPER_DEFAULT_VULKAN_PATH "/system/lib/libvulkan.so"
#endif

void *adrenotools_open_libvulkan(int dlopenMode, int featureFlags,
                                 const char *tmpLibDir, const char *hookLibDir,
                                 const char *customDriverDir, const char *customDriverName,
                                 const char *fileRedirectDir, void **userMappingHandle);
bool adrenotools_import_user_mem(void *handle, void *hostPtr, uint64_t size);
bool adrenotools_mem_gpu_allocate(void *handle, uint64_t *size);
bool adrenotools_mem_cpu_map(void *handle, void *hostPtr, uint64_t size);
bool adrenotools_validate_gpu_mapping(void *handle);
void adrenotools_set_turbo(bool turbo);

void *
adrenotools_open_libvulkan(int dlopenMode,
                           int featureFlags,
                           const char *tmpLibDir,
                           const char *hookLibDir,
                           const char *customDriverDir,
                           const char *customDriverName,
                           const char *fileRedirectDir,
                           void **userMappingHandle)
{
   (void)dlopenMode;
   (void)featureFlags;
   (void)tmpLibDir;
   (void)hookLibDir;
   (void)fileRedirectDir;
   (void)userMappingHandle;

   if (customDriverDir && customDriverName) {
      char path[4096];
      snprintf(path, sizeof(path), "%s/%s", customDriverDir, customDriverName);

      void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
      if (handle)
         return handle;
   }

   return dlopen(WRAPPER_DEFAULT_VULKAN_PATH, RTLD_NOW | RTLD_LOCAL);
}

bool
adrenotools_import_user_mem(void *handle, void *hostPtr, uint64_t size)
{
   (void)handle;
   (void)hostPtr;
   (void)size;
   return false;
}

bool
adrenotools_mem_gpu_allocate(void *handle, uint64_t *size)
{
   (void)handle;
   (void)size;
   return false;
}

bool
adrenotools_mem_cpu_map(void *handle, void *hostPtr, uint64_t size)
{
   (void)handle;
   (void)hostPtr;
   (void)size;
   return false;
}

bool
adrenotools_validate_gpu_mapping(void *handle)
{
   (void)handle;
   return false;
}

void
adrenotools_set_turbo(bool turbo)
{
   (void)turbo;
}
