cmake_minimum_required(VERSION 3.15)
project(v8shim LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# V8 headers: vendored (preferred) or system
set(V8_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../v8/include"
    CACHE PATH "Path to V8 headers (v8.h, libplatform/)")

if(NOT EXISTS "${V8_INCLUDE_DIR}/v8.h")
    # Fallback: system headers
    find_path(V8_SYSTEM_INCLUDE v8.h PATHS /usr/include/v8 /usr/local/include/v8)
    if(V8_SYSTEM_INCLUDE)
        set(V8_INCLUDE_DIR "${V8_SYSTEM_INCLUDE}")
    else()
        message(FATAL_ERROR
            "V8 headers not found. Either:\n"
            "  1. Run: rdmd build.d --backend=v8  (downloads headers automatically)\n"
            "  2. Set -DV8_INCLUDE_DIR=/path/to/v8/include")
    endif()
endif()

message(STATUS "V8 headers: ${V8_INCLUDE_DIR}")

option(V8_POINTER_COMPRESSION "Enable V8 pointer compression defines" OFF)

# DUN_VERSION is the canonical app version pulled from source/dun/app.d.
# Embedded into the v8shim::Diagnostics::shimVersion() return so the
# Diagnostics smoke fixture can't silently regress when app.d bumps.
# build.d strips and passes -DDUN_VERSION_STR="...". Falls back to "dev"
# if invoked outside the orchestrator.
set(DUN_VERSION_STR "dev" CACHE STRING "App version embedded in v8shim::Diagnostics")
add_definitions(-DDUN_VERSION_STR="${DUN_VERSION_STR}")

add_library(v8shim STATIC
    v8shim.cpp
)

target_include_directories(v8shim PRIVATE
    ${V8_INCLUDE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_options(v8shim PRIVATE
    # Aggressive optimization for the FFI boundary — every Buffer.from /
    # crypto.* / fetch call goes through this shim, so inlining the
    # withContext template + Persistent::Reset pays back fast. -O3 +
    # -fvisibility=hidden tells the linker most symbols are internal
    # so it can DCE / inline across function boundaries. -fno-exceptions
    # / -fno-rtti remove the (unused) C++ EH+RTTI metadata from per-call
    # epilogues.
    #
    # Note: -flto=thin was tested but doesn't carry across the D/C boundary
    # in static linking — LDC and LLVM C++ produce incompatible LTO blobs
    # for our --link-internally mode. The non-LTO -O3 already inlines
    # withContext at the C++ level.
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-O3 -fvisibility=hidden -fno-exceptions -fno-rtti -Wall -Wextra -Wno-unused-parameter>
    $<$<CXX_COMPILER_ID:MSVC>:/O2 /W3 /EHsc>
)

if(V8_POINTER_COMPRESSION)
    target_compile_definitions(v8shim PRIVATE
        V8_COMPRESS_POINTERS
        V8_31BIT_SMIS_ON_64BIT_ARCH
    )
    message(STATUS "V8 pointer compression: ON")
endif()

install(TARGETS v8shim ARCHIVE DESTINATION lib)
install(FILES v8shim.h DESTINATION include)
