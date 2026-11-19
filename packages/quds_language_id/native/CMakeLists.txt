# Builds the Quds language identifier as one shared library (or an
# Emscripten module): the MIT adapter and GGUF shim plus CrispASR's CLD3
# runtime (crisp_lid/src/lid_cld3.cpp, MIT) from the pinned, verified tree
# made by tool/build.py. No ggml is built: lid_cld3 computes in plain C++
# and the shim provides the few loading calls it makes. This file never
# downloads anything.
cmake_minimum_required(VERSION 3.16)
project(quds_language_id CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
if(NOT CRISPASR_SOURCE_DIR)
  message(FATAL_ERROR "Set CRISPASR_SOURCE_DIR (use tool/build.py)")
endif()
set(LID ${CRISPASR_SOURCE_DIR}/crisp_lid/src)
set(LID_SOURCES
  src/quds_language_id.cpp
  src/gguf_shim.cpp
  ${LID}/lid_cld3.cpp)
if(EMSCRIPTEN)
  add_executable(quds_language_id ${LID_SOURCES})
  set_target_properties(quds_language_id PROPERTIES SUFFIX ".mjs")
  target_link_options(quds_language_id PRIVATE
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createLanguageIdModule
    -sENVIRONMENT=worker,node -sALLOW_MEMORY_GROWTH=1
    -sINITIAL_MEMORY=16MB -sFILESYSTEM=0
    -sGROWABLE_ARRAYBUFFERS=0
    -sEXPORTED_FUNCTIONS=_quds_language_id_abi_version,_quds_language_id_alloc,_quds_language_id_free_buffer,_quds_language_id_open,_quds_language_id_close,_quds_language_id_detect
    -sEXPORTED_RUNTIME_METHODS=HEAPU8
    -sINCOMING_MODULE_JS_API=print,printErr)
else()
  add_library(quds_language_id SHARED ${LID_SOURCES})
endif()
# The shim directory comes first so lid_cld3.cpp's ggml.h, gguf.h and
# core/gguf_loader.h resolve to the shim, never to a ggml checkout.
target_include_directories(quds_language_id PRIVATE shim src ${LID})
if(MSVC)
  target_compile_options(quds_language_id PRIVATE /utf-8 /EHsc)
endif()
