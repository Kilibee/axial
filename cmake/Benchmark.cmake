cmake_minimum_required(VERSION 3.29)
string(TIMESTAMP run "%Y%m%d-%H%M%S" UTC)
file(MAKE_DIRECTORY "${OUTPUT_DIR}/${run}")
foreach(load IN ITEMS normal contention)
  set(extra)
  if(load STREQUAL "contention")
    set(extra --contention)
  endif()
  execute_process(COMMAND /bin/bash "${SOURCE_DIR}/tools/run-benchmark.sh"
    "${OUTPUT_DIR}/${run}/${load}.jsonl" "${BENCH}" "${SERVICE}" "${CLIENT}"
    "${SECONDS}" "${RATE}" 5 ${extra} COMMAND_ERROR_IS_FATAL ANY)
endforeach()
message(STATUS "Benchmark results: ${OUTPUT_DIR}/${run}")
