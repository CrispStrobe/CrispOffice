# Builds the Quds Hunspell adapter as one shared library (or an Emscripten
# module) from the pinned, unmodified Hunspell 1.7.2 library sources.
# HUNSPELL_SOURCE_DIR must point at the verified extraction made by
# tool/build.py; this file never downloads anything.
cmake_minimum_required(VERSION 3.16)
project(quds_proofing_hunspell CXX)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT HUNSPELL_SOURCE_DIR)
  message(FATAL_ERROR "Set HUNSPELL_SOURCE_DIR (use tool/build.py)")
endif()
set(H ${HUNSPELL_SOURCE_DIR}/src/hunspell)
set(HUNSPELL_SOURCES
  ${H}/affentry.cxx ${H}/affixmgr.cxx ${H}/csutil.cxx ${H}/filemgr.cxx
  ${H}/hashmgr.cxx ${H}/hunspell.cxx ${H}/hunzip.cxx ${H}/phonet.cxx
  ${H}/replist.cxx ${H}/suggestmgr.cxx)
if(EMSCRIPTEN)
  add_executable(quds_proofing_hunspell src/quds_hunspell.cpp ${HUNSPELL_SOURCES})
  set_target_properties(quds_proofing_hunspell PROPERTIES SUFFIX ".mjs")
  target_link_options(quds_proofing_hunspell PRIVATE
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createHunspellModule
    -sENVIRONMENT=worker,node -sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1
    -sEXPORTED_FUNCTIONS=_quds_hunspell_abi_version,_quds_hunspell_open,_quds_hunspell_close,_quds_hunspell_spell,_quds_hunspell_suggest,_malloc,_free
    -sEXPORTED_RUNTIME_METHODS=FS,UTF8ToString,stringToNewUTF8,HEAPU32
    -sINCOMING_MODULE_JS_API=locateFile,print,printErr)
else()
  add_library(quds_proofing_hunspell SHARED src/quds_hunspell.cpp ${HUNSPELL_SOURCES})
endif()
target_include_directories(quds_proofing_hunspell PRIVATE ${H})
target_compile_definitions(quds_proofing_hunspell PRIVATE HUNSPELL_STATIC)
if(MSVC)
  target_compile_options(quds_proofing_hunspell PRIVATE /utf-8 /EHsc)
endif()
