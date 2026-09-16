# Build-time converters use the host architecture, including Intel cross-builds.
foreach(tool IN ITEMS make-icon convert-toycar)
  add_executable(${tool} EXCLUDE_FROM_ALL "tools/${tool}.swift")
  axial_swift_platform(${tool} "${CMAKE_HOST_SYSTEM_PROCESSOR}")
  target_compile_options(${tool} PRIVATE -parse-as-library)
  set_target_properties(${tool} PROPERTIES OSX_ARCHITECTURES "${CMAKE_HOST_SYSTEM_PROCESSOR}" FOLDER "Build tools")
endforeach()
file(GLOB toycar_sources CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/third_party/toycar/source/*")
set(asset_dir "${CMAKE_BINARY_DIR}/generated")
add_custom_command(OUTPUT "${asset_dir}/Axial.icns" "${asset_dir}/ToyCar.scn"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${asset_dir}"
  COMMAND $<TARGET_FILE:make-icon> "${asset_dir}/Axial.iconset"
  COMMAND /usr/bin/xcrun iconutil --convert icns --output "${asset_dir}/Axial.icns" "${asset_dir}/Axial.iconset"
  COMMAND "${CMAKE_COMMAND}" -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -P "${CMAKE_SOURCE_DIR}/cmake/VerifyAssets.cmake"
  COMMAND $<TARGET_FILE:convert-toycar> "${CMAKE_SOURCE_DIR}/third_party/toycar/source" "${asset_dir}/ToyCar.scn"
  DEPENDS make-icon convert-toycar ${toycar_sources} "${CMAKE_SOURCE_DIR}/third_party/toycar/SHA256SUMS"
    "${CMAKE_SOURCE_DIR}/cmake/VerifyAssets.cmake" VERBATIM)
add_custom_target(axial-assets DEPENDS "${asset_dir}/Axial.icns" "${asset_dir}/ToyCar.scn")
set(axial_resources "${asset_dir}/Axial.icns" "${asset_dir}/ToyCar.scn")
set_source_files_properties(${axial_resources} PROPERTIES GENERATED TRUE MACOSX_PACKAGE_LOCATION Resources)
