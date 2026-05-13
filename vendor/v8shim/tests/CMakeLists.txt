cmake_minimum_required(VERSION 3.20)
project(v8shim_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- FetchContent: Google Test ---
include(FetchContent)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
    GIT_SHALLOW TRUE
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

# V8 headers (compile-time only — no V8 libs needed for TMP tests)
set(V8_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../v8/include"
    CACHE PATH "Path to V8 headers")

if(NOT EXISTS "${V8_INCLUDE_DIR}/v8.h")
    find_path(V8_SYSTEM_INCLUDE v8.h PATHS /usr/include/v8 /usr/local/include/v8)
    if(V8_SYSTEM_INCLUDE)
        set(V8_INCLUDE_DIR "${V8_SYSTEM_INCLUDE}")
    else()
        message(WARNING "V8 headers not found — skipping V8-dependent tests")
        set(V8_HEADERS_AVAILABLE OFF)
    endif()
endif()

if(NOT DEFINED V8_HEADERS_AVAILABLE)
    set(V8_HEADERS_AVAILABLE ON)
endif()

enable_testing()

# --- Test 1: ABI / FFI contract (links against stubs, no V8 needed) ---
add_executable(test_abi test_abi.cpp test_stubs.cpp)
target_include_directories(test_abi PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(test_abi GTest::gtest_main)
target_compile_options(test_abi PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall -Wextra -Wno-unused-parameter>
)
add_test(NAME v8shim_abi COMMAND test_abi)

# --- Test 2: TMP bridge (needs V8 headers for template instantiation) ---
if(V8_HEADERS_AVAILABLE)
    add_executable(test_tmpl test_tmpl.cpp)
    target_include_directories(test_tmpl PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${V8_INCLUDE_DIR}
    )
    target_link_libraries(test_tmpl GTest::gtest_main)
    target_compile_options(test_tmpl PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall -Wextra -Wno-unused-parameter>
    )
    add_test(NAME v8shim_tmpl COMMAND test_tmpl)
    message(STATUS "V8 headers found — TMP tests enabled")
else()
    message(STATUS "V8 headers not found — TMP tests disabled (ABI tests still run)")
endif()
