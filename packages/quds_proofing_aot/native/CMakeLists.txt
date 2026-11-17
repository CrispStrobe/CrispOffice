cmake_minimum_required(VERSION 3.24)
project(quds_aot_native LANGUAGES C CXX)

# Deliberately configure only AOT's analysis libraries and data generators.
# The upstream top-level project also requires Qt and configures GUI/server
# applications. None of those are required by this stdin/stdout worker.
set(QUDS_AOT_SOURCE "" CACHE PATH "Pinned sokirko74/aot checkout")
if(NOT EXISTS "${QUDS_AOT_SOURCE}/Source/nlp_base/CMakeLists.txt")
  message(FATAL_ERROR "Set QUDS_AOT_SOURCE to an AOT checkout with its nlp_base submodule")
endif()
get_filename_component(QUDS_AOT_SOURCE "${QUDS_AOT_SOURCE}" REALPATH)
set(QUDS_AOT_REVISION "0d591d972c7bb2729f4764d3bc32611ea6fd142a")
set(QUDS_NLP_BASE_REVISION "244b3d1f9a09e4a81e75ea83c3b55b209c663503")
find_package(Git REQUIRED)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${QUDS_AOT_SOURCE}" rev-parse HEAD
  OUTPUT_VARIABLE actual_aot OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${QUDS_AOT_SOURCE}/Source/nlp_base" rev-parse HEAD
  OUTPUT_VARIABLE actual_nlp OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
if(NOT actual_aot STREQUAL QUDS_AOT_REVISION OR NOT actual_nlp STREQUAL QUDS_NLP_BASE_REVISION)
  message(FATAL_ERROR "Native AOT sources do not match the pinned revisions")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(BUILD_DICTS 1)
set(BUILD_HTTP_SERVERS 0)
set(DICTS_FOLDER "${QUDS_AOT_SOURCE}/Dicts")
set(RML "${QUDS_AOT_SOURCE}")
set(ENV{RML} "${RML}")
set(INSTALL_BIN_FOLDER "Bin")
find_package(Threads REQUIRED)
find_program(FLEX_TOOL NAMES flex win_flex REQUIRED)
find_program(BISON_TOOL NAMES bison win_bison REQUIRED)
find_path(FLEX_INCLUDE_DIR FlexLexer.h REQUIRED)
include_directories("${FLEX_INCLUDE_DIR}")
if(WIN32)
  get_filename_component(WIN_FLEX_FOLDER "${FLEX_TOOL}" DIRECTORY)
  add_compile_options("$<$<COMPILE_LANG_AND_ID:CXX,MSVC>:/utf-8>")
endif()

macro(declare_cmake_min_version)
  cmake_minimum_required(VERSION 3.24)
endmacro()

# Upstream's dictionary subprojects call this build recipe. Generated files
# remain inside the explicitly supplied source/build cache, never in Quds.
macro(ConvertStructDict name)
  add_custom_command(
    OUTPUT "${PROJECT_SOURCE_DIR}/units.bin"
           "${PROJECT_SOURCE_DIR}/cortege.bin"
           "${PROJECT_SOURCE_DIR}/comments.bin"
    COMMAND StructDictLoader --action from_txt --input-file ross.txt --output-ross-folder .
    DEPENDS StructDictLoader "${PROJECT_SOURCE_DIR}/ross.txt"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    VERBATIM)
  add_custom_target(${name} DEPENDS "${PROJECT_SOURCE_DIR}/units.bin")
endmacro()

include_directories("${QUDS_AOT_SOURCE}/Source"
                    "${QUDS_AOT_SOURCE}/Source/nlp_base/contrib/plog"
                    "${QUDS_AOT_SOURCE}/Source/nlp_base/contrib/libzip/lib")
add_subdirectory("${QUDS_AOT_SOURCE}/Source/nlp_base" upstream/nlp_base)
add_subdirectory("${QUDS_AOT_SOURCE}/Source/common" upstream/common)
add_subdirectory("${QUDS_AOT_SOURCE}/Source/dicts/RmlThesLib" upstream/RmlThesLib)
add_subdirectory("${QUDS_AOT_SOURCE}/Source/morphan/LemmatizerLib" upstream/LemmatizerLib)
add_subdirectory("${QUDS_AOT_SOURCE}/Source/synan" upstream/synan)
add_subdirectory("${QUDS_AOT_SOURCE}/Dicts" upstream/Dicts)
add_subdirectory("${QUDS_AOT_SOURCE}/Thes" upstream/Thes)

add_executable(quds_aot_worker
  worker.cpp
  "${QUDS_AOT_SOURCE}/Source/www/SynanDaemon/JVisualSynAnParamBuilder.cpp")
target_link_libraries(quds_aot_worker PRIVATE SynanLib Threads::Threads)
target_compile_definitions(quds_aot_worker PRIVATE
  QUDS_AOT_REVISION="${QUDS_AOT_REVISION}"
  QUDS_NLP_BASE_REVISION="${QUDS_NLP_BASE_REVISION}")
add_dependencies(quds_aot_worker MorphDicts GraphanDicts GermanGLRSynan Ross ThesRosses)
set_target_properties(quds_aot_worker PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(quds_aot_worker PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin")
endforeach()
install(TARGETS quds_aot_worker RUNTIME DESTINATION Bin)
