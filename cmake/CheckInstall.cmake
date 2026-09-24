# Validate all existing bundles before copying any files.
set(root "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}")
if(EXISTS "${root}")
  execute_process(COMMAND /bin/bash -c
    "source \"$1\"; axial_check \"$2\"" axial-install
    "${CMAKE_CURRENT_LIST_DIR}/../tools/install-guard.sh" "${root}"
    COMMAND_ERROR_IS_FATAL ANY)
endif()
