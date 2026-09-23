# Pinned, source-built dependencies. Static TLS libraries avoid dependencies on a
# user's Homebrew installation and produce every requested Mach-O architecture.
include(FetchContent)
include(ExternalProject)
FetchContent_Declare(axial_boost
  URL https://archives.boost.io/release/1.90.0/source/boost_1_90_0.tar.bz2
  URL_HASH SHA256=49551aff3b22cbc5c5a9ed3dbc92f0e23ea50a0f7325b0d198b705e8ee3fc305
  SOURCE_SUBDIR axial-unused)
FetchContent_MakeAvailable(axial_boost)
set(tls_root "${CMAKE_BINARY_DIR}/tls")
set(tls_archives)
foreach(arch IN LISTS CMAKE_OSX_ARCHITECTURES)
  if(arch STREQUAL "arm64")
    set(tls_platform darwin64-arm64-cc)
  elseif(arch STREQUAL "x86_64")
    set(tls_platform darwin64-x86_64-cc)
  else()
    message(FATAL_ERROR "Unsupported TLS architecture: ${arch}")
  endif()
  set(prefix "${tls_root}/${arch}")
  ExternalProject_Add(axial_tls_${arch}
    URL https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz
    URL_HASH SHA256=a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2
    PREFIX "${prefix}"
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env "CC=${CMAKE_C_COMPILER}" "MACOSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}"
      /usr/bin/perl <SOURCE_DIR>/Configure ${tls_platform} no-shared no-tests no-module
      "--prefix=${prefix}/install" --libdir=lib "-mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}"
    BUILD_COMMAND /usr/bin/make clean COMMAND /usr/bin/make -j4 build_libs
    INSTALL_COMMAND /usr/bin/make install_dev
    LOG_BUILD TRUE LOG_INSTALL TRUE
    BUILD_BYPRODUCTS "${prefix}/install/lib/libssl.a" "${prefix}/install/lib/libcrypto.a")
  list(APPEND tls_archives "${prefix}/install/lib/libssl.a")
  list(APPEND crypto_archives "${prefix}/install/lib/libcrypto.a")
  list(APPEND tls_targets axial_tls_${arch})
endforeach()
list(GET CMAKE_OSX_ARCHITECTURES 0 first_arch)
file(MAKE_DIRECTORY "${tls_root}/${first_arch}/install/include")
add_custom_command(OUTPUT "${tls_root}/libssl.a" "${tls_root}/libcrypto.a"
  COMMAND /usr/bin/lipo -create ${tls_archives} -output "${tls_root}/libssl.a"
  COMMAND /usr/bin/lipo -create ${crypto_archives} -output "${tls_root}/libcrypto.a"
  DEPENDS ${tls_targets} ${tls_archives} ${crypto_archives} VERBATIM)
add_custom_target(axial-tls DEPENDS "${tls_root}/libssl.a" "${tls_root}/libcrypto.a")
add_library(axial-web-dependencies INTERFACE)
add_dependencies(axial-web-dependencies axial-tls)
target_include_directories(axial-web-dependencies SYSTEM INTERFACE "${axial_boost_SOURCE_DIR}" "${tls_root}/${first_arch}/install/include")
target_link_libraries(axial-web-dependencies INTERFACE "${tls_root}/libssl.a" "${tls_root}/libcrypto.a")
target_compile_definitions(axial-web-dependencies INTERFACE BOOST_ASIO_NO_DEPRECATED)
set(AXIAL_TLS_SOURCE "${tls_root}/${first_arch}/src/axial_tls_${first_arch}")
