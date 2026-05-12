cmake_minimum_required(VERSION 3.14)
project(sqlite3_vendor C)

set(SQLITE_VERSION "3530100" CACHE STRING "SQLite amalgamation version")
set(SQLITE_YEAR "2026" CACHE STRING "SQLite release year")

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Use local sqlite3.c if present, otherwise FetchContent download
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.c")
    message(STATUS "Using local sqlite3.c")
    set(SQLITE3_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.c")
    set(SQLITE3_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}")
else()
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
endif()

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

# musl 1.2.4+ removed LFS64 symbols (open64, stat64, ...) that SQLite
# references via _LARGEFILE64_SOURCE.  Detect musl and provide thin stubs.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    foreach(_musl_path "/lib/ld-musl-x86_64.so.1" "/lib/ld-musl-aarch64.so.1"
                       "/lib/libc.musl-x86_64.so.1" "/lib/libc.musl-aarch64.so.1")
        if(EXISTS "${_musl_path}")
            set(IS_MUSL TRUE)
            break()
        endif()
    endforeach()

    if(IS_MUSL)
        message(STATUS "musl libc detected — adding LFS64 compat stubs")
        file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/musl_lfs_compat.c"
"#include <fcntl.h>\n\
#include <unistd.h>\n\
#include <sys/stat.h>\n\
#include <sys/mman.h>\n\
#include <stdarg.h>\n\
int open64(const char *p,int f,...){va_list a;va_start(a,f);int m=va_arg(a,int);va_end(a);return open(p,f,m);}\n\
int stat64(const char *p,struct stat *b){return stat(p,b);}\n\
int fstat64(int f,struct stat *b){return fstat(f,b);}\n\
int lstat64(const char *p,struct stat *b){return lstat(p,b);}\n\
int ftruncate64(int f,off_t l){return ftruncate(f,l);}\n\
int fcntl64(int f,int c,...){va_list a;va_start(a,c);long v=va_arg(a,long);va_end(a);return fcntl(f,c,v);}\n\
ssize_t pread64(int f,void *b,size_t c,off_t o){return pread(f,b,c,o);}\n\
ssize_t pwrite64(int f,const void *b,size_t c,off_t o){return pwrite(f,b,c,o);}\n\
void *mmap64(void *a,size_t l,int p,int f,int d,off_t o){return mmap(a,l,p,f,d,o);}\n")
        target_sources(sqlite3 PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/musl_lfs_compat.c")
    endif()
endif()

install(TARGETS sqlite3 ARCHIVE DESTINATION lib)
