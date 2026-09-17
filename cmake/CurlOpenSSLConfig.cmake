# Package config shipped inside each release zip (copied to share/cmake/CurlOpenSSL/).
# Consumers: list(APPEND CMAKE_PREFIX_PATH <unzip_root>) ; find_package(CurlOpenSSL REQUIRED)
# Note: this file is copied as-is (not via configure_package_config_file), so do not use @PACKAGE_INIT@.

set(_CurlOpenSSL_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../..")
get_filename_component(_CurlOpenSSL_ROOT "${_CurlOpenSSL_ROOT}" ABSOLUTE)

set(CurlOpenSSL_INCLUDE_DIR "${_CurlOpenSSL_ROOT}/include")
set(CurlOpenSSL_LIB_DIR "${_CurlOpenSSL_ROOT}/lib")
set(CurlOpenSSL_BIN_DIR "${_CurlOpenSSL_ROOT}/bin")

include(CMakeFindDependencyMacro)

function(_curl_openssl_find_dll _outvar)
  foreach(_c IN LISTS ARGN)
    if(EXISTS "${CurlOpenSSL_BIN_DIR}/${_c}")
      set(${_outvar} "${CurlOpenSSL_BIN_DIR}/${_c}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
  set(${_outvar} "" PARENT_SCOPE)
endfunction()

if(NOT TARGET CurlOpenSSL::crypto)
  if(EXISTS "${CurlOpenSSL_LIB_DIR}/libcrypto.dll.a")
    add_library(CurlOpenSSL::crypto SHARED IMPORTED)
    _curl_openssl_find_dll(_crypto_dll libcrypto-3-x64.dll libcrypto-3.dll)
    set_target_properties(CurlOpenSSL::crypto PROPERTIES
      IMPORTED_IMPLIB "${CurlOpenSSL_LIB_DIR}/libcrypto.dll.a"
      IMPORTED_LOCATION "${_crypto_dll}"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}")
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libcrypto.lib")
    add_library(CurlOpenSSL::crypto STATIC IMPORTED)
    set_target_properties(CurlOpenSSL::crypto PROPERTIES
      IMPORTED_LOCATION "${CurlOpenSSL_LIB_DIR}/libcrypto.lib"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}")
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libcrypto.a")
    add_library(CurlOpenSSL::crypto STATIC IMPORTED)
    set_target_properties(CurlOpenSSL::crypto PROPERTIES
      IMPORTED_LOCATION "${CurlOpenSSL_LIB_DIR}/libcrypto.a"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}")
  else()
    message(FATAL_ERROR "CurlOpenSSL: libcrypto not found under ${CurlOpenSSL_LIB_DIR}")
  endif()
endif()

if(NOT TARGET CurlOpenSSL::ssl)
  if(EXISTS "${CurlOpenSSL_LIB_DIR}/libssl.dll.a")
    add_library(CurlOpenSSL::ssl SHARED IMPORTED)
    _curl_openssl_find_dll(_ssl_dll libssl-3-x64.dll libssl-3.dll)
    set_target_properties(CurlOpenSSL::ssl PROPERTIES
      IMPORTED_IMPLIB "${CurlOpenSSL_LIB_DIR}/libssl.dll.a"
      IMPORTED_LOCATION "${_ssl_dll}"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES CurlOpenSSL::crypto)
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libssl.lib")
    add_library(CurlOpenSSL::ssl STATIC IMPORTED)
    set_target_properties(CurlOpenSSL::ssl PROPERTIES
      IMPORTED_LOCATION "${CurlOpenSSL_LIB_DIR}/libssl.lib"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES CurlOpenSSL::crypto)
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libssl.a")
    add_library(CurlOpenSSL::ssl STATIC IMPORTED)
    set_target_properties(CurlOpenSSL::ssl PROPERTIES
      IMPORTED_LOCATION "${CurlOpenSSL_LIB_DIR}/libssl.a"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES CurlOpenSSL::crypto)
  else()
    message(FATAL_ERROR "CurlOpenSSL: libssl not found under ${CurlOpenSSL_LIB_DIR}")
  endif()
endif()

if(NOT TARGET CurlOpenSSL::curl)
  if(EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl.dll.a")
    add_library(CurlOpenSSL::curl SHARED IMPORTED)
    _curl_openssl_find_dll(_curl_dll libcurl-x64.dll libcurl.dll)
    set_target_properties(CurlOpenSSL::curl PROPERTIES
      IMPORTED_IMPLIB "${CurlOpenSSL_LIB_DIR}/libcurl.dll.a"
      IMPORTED_LOCATION "${_curl_dll}"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES "CurlOpenSSL::ssl;CurlOpenSSL::crypto")
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl_imp.lib")
    add_library(CurlOpenSSL::curl SHARED IMPORTED)
    set_target_properties(CurlOpenSSL::curl PROPERTIES
      IMPORTED_IMPLIB "${CurlOpenSSL_LIB_DIR}/libcurl_imp.lib"
      IMPORTED_LOCATION "${CurlOpenSSL_BIN_DIR}/libcurl.dll"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_LINK_LIBRARIES "CurlOpenSSL::ssl;CurlOpenSSL::crypto")
  elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl.lib" OR EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl_a.lib" OR EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl.a")
    if(EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl.lib")
      set(_curl_loc "${CurlOpenSSL_LIB_DIR}/libcurl.lib")
    elseif(EXISTS "${CurlOpenSSL_LIB_DIR}/libcurl_a.lib")
      set(_curl_loc "${CurlOpenSSL_LIB_DIR}/libcurl_a.lib")
    else()
      set(_curl_loc "${CurlOpenSSL_LIB_DIR}/libcurl.a")
    endif()
    add_library(CurlOpenSSL::curl STATIC IMPORTED)
    set_target_properties(CurlOpenSSL::curl PROPERTIES
      IMPORTED_LOCATION "${_curl_loc}"
      INTERFACE_INCLUDE_DIRECTORIES "${CurlOpenSSL_INCLUDE_DIR}"
      INTERFACE_COMPILE_DEFINITIONS "CURL_STATICLIB"
      INTERFACE_LINK_LIBRARIES "CurlOpenSSL::ssl;CurlOpenSSL::crypto")
    if(WIN32)
      set_property(TARGET CurlOpenSSL::curl APPEND PROPERTY
        INTERFACE_LINK_LIBRARIES "ws2_32;bcrypt;normaliz;iphlpapi;crypt32;advapi32")
    endif()
  else()
    message(FATAL_ERROR "CurlOpenSSL: libcurl not found under ${CurlOpenSSL_LIB_DIR}")
  endif()
endif()

if(NOT TARGET CURL::libcurl)
  add_library(CURL::libcurl ALIAS CurlOpenSSL::curl)
endif()

set(CurlOpenSSL_FOUND TRUE)
