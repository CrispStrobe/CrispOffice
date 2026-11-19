# Builds the Quds Arabic morphology backend as one shared library (or an
# Emscripten module): the MIT adapter plus the pinned CrispEmbed native
# Camel Morph analyzer (MIT, a port of MIT camel_tools) and Ryu (Apache-2.0
# option). CRISPEMBED_SOURCE_DIR must point at the verified file tree made by
# tool/build.py; this file never downloads anything.
cmake_minimum_required(VERSION 3.16)
project(quds_arabic_morph C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CRISPEMBED_SOURCE_DIR)
  message(FATAL_ERROR "Set CRISPEMBED_SOURCE_DIR (use tool/build.py)")
endif()
set(CE ${CRISPEMBED_SOURCE_DIR}/src)
set(MORPH_SOURCES
  src/quds_arabic_morph.cpp
  ${CE}/arabic_morph.cpp
  ${CE}/core/shortest_double.c)
if(EMSCRIPTEN)
  add_executable(quds_arabic_morph ${MORPH_SOURCES})
  set_target_properties(quds_arabic_morph PROPERTIES SUFFIX ".mjs")
  # The parsed database needs a few hundred MB; wasm32 allows up to 4 GB.
  target_link_options(quds_arabic_morph PRIVATE
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createArabicMorphModule
    -sENVIRONMENT=worker,node -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB
    -sINITIAL_MEMORY=64MB -sFORCE_FILESYSTEM=1
    -sEXPORTED_FUNCTIONS=_quds_arabic_morph_adapter_version,_crispembed_ar_morph_abi_version,_crispembed_ar_morph_open,_crispembed_ar_morph_analyze,_crispembed_ar_morph_string_free,_crispembed_ar_morph_info,_crispembed_ar_morph_free,_malloc,_free
    -sEXPORTED_RUNTIME_METHODS=FS,UTF8ToString,stringToNewUTF8,lengthBytesUTF8,HEAPU32
    -sINCOMING_MODULE_JS_API=locateFile,print,printErr)
  # The analyzer reports errors through C++ exceptions caught at the ABI;
  # native Wasm exception handling (all current browsers) keeps them cheap.
  target_compile_options(quds_arabic_morph PRIVATE -fwasm-exceptions)
  target_link_options(quds_arabic_morph PRIVATE -fwasm-exceptions)
else()
  add_library(quds_arabic_morph SHARED ${MORPH_SOURCES})
  target_compile_definitions(quds_arabic_morph PRIVATE
    CRISPEMBED_AR_MORPH_BUILD CRISPEMBED_AR_MORPH_SHARED)
endif()
target_include_directories(quds_arabic_morph PRIVATE ${CE} ${CE}/core/third_party)
if(MSVC)
  target_compile_options(quds_arabic_morph PRIVATE /utf-8 /EHsc)
endif()
