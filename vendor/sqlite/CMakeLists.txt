cmake_minimum_required(VERSION 3.14)
project(sqlite3_vendor C)

set(SQLITE_VERSION "3530100" CACHE STRING "SQLite amalgamation version")
set(SQLITE_YEAR "2026" CACHE STRING "SQLite release year")

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Resolution order: local sqlite3.c → find_package → FetchContent download
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.c")
    message(STATUS "[sqlite] Using local sqlite3.c")
    set(SQLITE3_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.c")
    set(SQLITE3_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}")
    set(SQLITE3_USE_LOCAL TRUE)
else()
    find_package(SQLite3 QUIET)
    if(SQLite3_FOUND)
        message(STATUS "[sqlite] Found system SQLite3 ${SQLite3_VERSION}")
        set(SQLITE3_USE_SYSTEM TRUE)
    else()
        message(STATUS "[sqlite] System SQLite3 not found, downloading via FetchContent")
        include(FetchContent)
        FetchContent_Declare(
            sqlite3_src
            URL "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip"
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        )
        FetchContent_MakeAvailable(sqlite3_src)
        set(SQLITE3_SOURCE "${sqlite3_src_SOURCE_DIR}/sqlite3.c")
        set(SQLITE3_INCLUDE "${sqlite3_src_SOURCE_DIR}")

        # Copy header to vendor/sqlite/ for D ImportC
        add_custom_command(OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.h"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${sqlite3_src_SOURCE_DIR}/sqlite3.h"
                "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.h"
            DEPENDS "${sqlite3_src_SOURCE_DIR}/sqlite3.h"
            COMMENT "Copying sqlite3.h to vendor/sqlite/"
        )
        add_custom_target(copy_sqlite3_header ALL
            DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.h")
        set(SQLITE3_USE_LOCAL TRUE)
    endif()
endif()

if(SQLITE3_USE_SYSTEM)
    add_library(sqlite3 ALIAS SQLite::SQLite3)
elseif(SQLITE3_USE_LOCAL)
    add_library(sqlite3 STATIC ${SQLITE3_SOURCE})

    target_include_directories(sqlite3 PUBLIC ${SQLITE3_INCLUDE})

    target_compile_definitions(sqlite3 PRIVATE
        SQLITE_THREADSAFE=0
        SQLITE_OMIT_LOAD_EXTENSION
    )

    target_compile_options(sqlite3 PRIVATE
        $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-O2 -w>
        $<$<C_COMPILER_ID:MSVC>:/O2 /W0>
    )

    install(TARGETS sqlite3 ARCHIVE DESTINATION lib)
endif()
