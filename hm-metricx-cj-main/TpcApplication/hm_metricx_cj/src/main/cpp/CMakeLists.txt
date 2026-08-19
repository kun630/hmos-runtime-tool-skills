# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(TpcApplication)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(hm_metricx_cj SHARED napi_init.cpp crash.cpp oom.cpp KOOM/elf_reader.cpp freeze.cpp common.cpp
bytehook/bytesig.c
xhook/xh_core.c xhook/xh_elf.c xhook/xh_util.c xhook/xh_version.c xhook/xhook.c
xdl/xdl.c xdl/xdl_iterate.c xdl/xdl_lzma.c xdl/xdl_util.c
memory/hook_helper.cpp memory/memory_monitor.cpp memory/backtrace_64.cpp
traffic.cpp traffic/netutil.cpp traffic/hook.cpp traffic/data.cpp traffic/socket_info.cpp)
target_link_libraries(hm_metricx_cj PUBLIC libace_napi.z.so libhilog_ndk.z.so libohhicollie.so libhiappevent_ndk.z.so libohhidebug.so
    libbundle_ndk.z.so libc++.a)
