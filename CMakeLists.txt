cmake_minimum_required(VERSION 3.15)

### ======================================================================
###  Portable SWAT (2012-family) Fortran build harness
###
###  Drop this file into any folder that contains a SWAT source directory
###  and configure — nothing in here is specific to one revision, machine
###  or checkout. See COMPILE_GUIDE.md for the full workflow.
###
###  Adapted from the official SWAT CMake build by Dr. Liang-Jun Zhu
###  (https://github.com/crazyzlj/SWAT).
###
###  Layout expected (SWAT_SRC_DIR is configurable):
###      <this folder>/CMakeLists.txt
###      <this folder>/src/*.f  *.f90
### ======================================================================

### ----------------------------------------------------------------------
### Options — override any of these with -D<NAME>=<VALUE> at configure time
### ----------------------------------------------------------------------
set(SWAT_SRC_DIR "src" CACHE STRING
    "Source directory, relative to this file (or an absolute path)")
set(SWAT_VERSION "" CACHE STRING
    "Version tag used in the executable name; auto-detected from main.f when empty")
set(SWAT_EXE_NAME "swat" CACHE STRING
    "Base name of the executable target")
set(SWAT_LEN72_SRCS "grow;tran" CACHE STRING
    "Basenames (no extension) that require strict 72-column fixed form")
set(SWAT_LENLONG_SRCS "subbasin;modparm" CACHE STRING
    "Basenames (no extension) that require unlimited line length")
set(SWAT_EXTRA_FLAGS "" CACHE STRING
    "Extra compiler flags appended to every file, e.g. \"-fcheck=all -fbacktrace\"")
option(SWAT_PREFLIGHT
    "Scan the sources at configure time for known gfortran blockers" ON)
option(SWAT_ZERO_HEAP
    "Zero-fill every malloc (gfortran only) so SWAT's uninitialised ALLOCATE'd arrays read 0, as in the Intel build" ON)

set(CMAKE_VERBOSE_MAKEFILE ON)

### ----------------------------------------------------------------------
### Locate the source directory (before project(), so we can name the project)
### ----------------------------------------------------------------------
if(IS_ABSOLUTE "${SWAT_SRC_DIR}")
    set(SWAT_SRC "${SWAT_SRC_DIR}")
else()
    set(SWAT_SRC "${CMAKE_CURRENT_LIST_DIR}/${SWAT_SRC_DIR}")
endif()

if(NOT IS_DIRECTORY "${SWAT_SRC}")
    message(FATAL_ERROR
        "Source directory not found: ${SWAT_SRC}\n"
        "Put the SWAT sources in '${SWAT_SRC_DIR}\\' next to this CMakeLists.txt, "
        "or configure with -DSWAT_SRC_DIR=<folder>.")
endif()

### Detect the revision from main.f so the executable name matches the code.
### Folder names are not trusted: a folder called rev_692 may hold Rev 693.
if(SWAT_VERSION STREQUAL "")
    set(_swat_ver "unknown")
    if(EXISTS "${SWAT_SRC}/main.f")
        file(READ "${SWAT_SRC}/main.f" _main_txt)
        string(REPLACE "\r" "" _main_txt "${_main_txt}")
        ### Authoritative source: the  prog = "... Rev <n>"  assignment
        if("${_main_txt}" MATCHES "prog[ \t]*=[ \t]*\"[^\"]*[Rr]ev[. \t]*([0-9]+)")
            set(_swat_ver "${CMAKE_MATCH_1}")
        elseif("${_main_txt}" MATCHES "[Rr]ev[.][ \t]*([0-9]+)")
            set(_swat_ver "${CMAKE_MATCH_1}")
        endif()
    endif()
    set(SWAT_VER_STR "${_swat_ver}")
else()
    set(SWAT_VER_STR "${SWAT_VERSION}")
endif()

project(SWAT_rev${SWAT_VER_STR} Fortran)

### Default to Release when no build type was requested
if(CMAKE_GENERATOR MATCHES "Makefiles|Ninja" AND "${CMAKE_BUILD_TYPE}" STREQUAL "")
    set(CMAKE_BUILD_TYPE "Release")
endif()

### Install into the build tree rather than a system folder needing admin rights
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE PATH
        "Install prefix" FORCE)
endif()

### ----------------------------------------------------------------------
### Compiler detection: line-length flags, warning flags, toolchain tag
### Each compiler spells the same concepts differently.
### ----------------------------------------------------------------------
get_filename_component(Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER} NAME)

if(Fortran_COMPILER_NAME MATCHES "ifort.*" OR Fortran_COMPILER_NAME MATCHES "icl.*"
   OR CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    if(MSVC)
        set(FLAG_L72 /4L72)
        set(FLAG_L80 /4L80)
        set(FLAG_LLONG /4L132)
        set(SWAT_WARN_FLAGS "/warn:all")
    else()
        set(FLAG_L72 -72)
        set(FLAG_L80 -80)
        set(FLAG_LLONG -132)
        set(SWAT_WARN_FLAGS "-warn all")
    endif()
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "Cray")
    set(FLAG_L72 -N72)
    set(FLAG_L80 -N80)
    set(FLAG_LLONG -N132)
    set(SWAT_WARN_FLAGS "")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "Flang")
    set(FLAG_L72 -Mextend)
    set(FLAG_L80 -Mextend)
    set(FLAG_LLONG -Mextend)
    set(SWAT_WARN_FLAGS "")
else()
    ### gfortran — the reference toolchain for this harness
    set(FLAG_L72 -ffixed-line-length-72)
    set(FLAG_L80 -ffixed-line-length-80)
    set(FLAG_LLONG -ffixed-line-length-none)
    set(SWAT_WARN_FLAGS "-Wall -fmax-errors=5")
endif()

if(MINGW)
    set(TOOL_CHAIN "mingw64")
elseif(MSVC)
    set(TOOL_CHAIN "msvc.ifort")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
    set(TOOL_CHAIN "gfort")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    set(TOOL_CHAIN "ifort")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Flang")
    set(TOOL_CHAIN "flang")
else()
    string(TOLOWER "${CMAKE_Fortran_COMPILER_ID}" TOOL_CHAIN)
endif()

### ----------------------------------------------------------------------
### Base flags. Anything already in CMAKE_Fortran_FLAGS (from the cache or
### the command line) is preserved, so -DCMAKE_Fortran_FLAGS=... works.
### ----------------------------------------------------------------------
string(STRIP "${SWAT_WARN_FLAGS} ${SWAT_EXTRA_FLAGS} ${CMAKE_Fortran_FLAGS}" CMAKE_Fortran_FLAGS)

### Only override the per-config optimisation flags for compilers whose flag
### syntax we know; otherwise keep CMake's own defaults.
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel" AND NOT MSVC)
    set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
    set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g")
endif()

### ----------------------------------------------------------------------
### Collect sources
### CONFIGURE_DEPENDS re-globs on build, so added/removed files are noticed.
### ----------------------------------------------------------------------
file(GLOB F77SRCS CONFIGURE_DEPENDS "${SWAT_SRC}/*.f")
file(GLOB F90SRCS CONFIGURE_DEPENDS "${SWAT_SRC}/*.f90")

list(LENGTH F77SRCS _n_f77)
list(LENGTH F90SRCS _n_f90)
if(_n_f77 EQUAL 0 AND _n_f90 EQUAL 0)
    message(FATAL_ERROR "No .f or .f90 files found in ${SWAT_SRC}")
endif()

### Per-file line length. Returns the flag for a given basename.
function(swat_line_flag _name _out)
    list(FIND SWAT_LEN72_SRCS "${_name}" _i72)
    if(_i72 GREATER -1)
        set(${_out} "${FLAG_L72}" PARENT_SCOPE)
    else()
        ### Unlimited is the safe default: SWAT routinely exceeds 72 columns.
        set(${_out} "${FLAG_LLONG}" PARENT_SCOPE)
    endif()
endfunction()

### ----------------------------------------------------------------------
### Preflight: scan for the two source defects that stop a stock SWAT tree
### from building or running under gfortran. Warnings only — nothing is
### modified. Disable with -DSWAT_PREFLIGHT=OFF.
### ----------------------------------------------------------------------
if(SWAT_PREFLIGHT)
    ### Map lowercase basename -> real path, so lookups survive case
    ### differences such as HQDAV.f90.
    set(_lc_names "")
    set(_lc_paths "")
    foreach(_f IN LISTS F77SRCS F90SRCS)
        get_filename_component(_bn "${_f}" NAME_WE)
        string(TOLOWER "${_bn}" _bnl)
        list(APPEND _lc_names "${_bnl}")
        list(APPEND _lc_paths "${_f}")
    endforeach()

    ### --- Check 1: procedures that collide with the parm INTERFACE block ---
    ### modparm.f declares explicit interfaces for a handful of procedures.
    ### A file implementing one of them cannot say a bare `use parm`: it would
    ### import an interface for itself, which gfortran rejects (Intel allows it).
    set(_collisions "")
    if(EXISTS "${SWAT_SRC}/modparm.f")
        file(READ "${SWAT_SRC}/modparm.f" _mp_txt)
        string(REPLACE "\r" "" _mp_txt "${_mp_txt}")
        string(TOLOWER "${_mp_txt}" _mp_low)

        string(REGEX MATCH "\n[ \t]*interface[ \t]*\n(.*)\n[ \t]*end[ \t]*interface" _ignored "${_mp_low}")
        set(_if_body "${CMAKE_MATCH_1}")

        if(NOT "${_if_body}" STREQUAL "")
            string(REGEX MATCHALL
                "\n[ \t]*(real\\*8[ \t]+)?(function|subroutine)[ \t]+[a-z0-9_]+"
                _decls "${_if_body}")
            set(_if_names "")
            foreach(_d IN LISTS _decls)
                if("${_d}" MATCHES "(function|subroutine)[ \t]+([a-z0-9_]+)")
                    list(APPEND _if_names "${CMAKE_MATCH_2}")
                endif()
            endforeach()
            if(_if_names)
                list(REMOVE_DUPLICATES _if_names)
            endif()

            foreach(_nm IN LISTS _if_names)
                list(FIND _lc_names "${_nm}" _idx)
                if(_idx GREATER -1)
                    list(GET _lc_paths ${_idx} _path)
                    file(READ "${_path}" _src_txt)
                    string(REPLACE "\r" "" _src_txt "${_src_txt}")
                    string(TOLOWER "${_src_txt}" _src_low)
                    ### a bare `use parm` on its own line (no rename clause)
                    if("${_src_low}" MATCHES "(^|\n)[ \t]*use[ \t]+parm[ \t]*(\n|$)")
                        get_filename_component(_bn2 "${_path}" NAME)
                        get_filename_component(_sym "${_path}" NAME_WE)
                        list(APPEND _collisions "${_bn2}|${_sym}")
                    endif()
                endif()
            endforeach()
        endif()
    endif()

    ### --- Check 2: FORMAT statements missing a comma after a tN descriptor ---
    ### e.g.  t97'----'  instead of  t97,'----'  . gfortran's runtime format
    ### parser aborts on this; Intel's accepts it.
    set(_badfmt "")
    foreach(_f IN LISTS F77SRCS F90SRCS)
        file(READ "${_f}" _txt)
        string(REGEX MATCHALL "[,(][tT][0-9]+'" _hits "${_txt}")
        if(_hits)
            ### Only now pay for line splitting, to report a line number
            string(REPLACE "\r" "" _txt "${_txt}")
            string(REPLACE ";" "\\;" _txt "${_txt}")
            string(REPLACE "\n" ";" _lines "${_txt}")
            set(_ln 0)
            foreach(_line IN LISTS _lines)
                math(EXPR _ln "${_ln}+1")
                ### skip comment lines (fixed-form c/C/*/! in column 1, or any !)
                if(NOT "${_line}" MATCHES "^[cC*!]" AND "${_line}" MATCHES "[,(][tT][0-9]+'")
                    get_filename_component(_bn3 "${_f}" NAME)
                    list(APPEND _badfmt "${_bn3}:${_ln}")
                endif()
            endforeach()
        endif()
    endforeach()

    if(_collisions)
        list(LENGTH _collisions _nc)
        ### built as ONE string: message() joins list elements with ';'
        set(_msg "Preflight: ${_nc} file(s) collide with the parm INTERFACE block.\n")
        string(APPEND _msg "These will fail to compile under gfortran. Replace the bare\n")
        string(APPEND _msg "'use parm' in each file with a renaming import, so the local\n")
        string(APPEND _msg "procedure name stays free:\n")
        foreach(_c IN LISTS _collisions)
            string(REPLACE "|" ";" _parts "${_c}")
            list(GET _parts 0 _file)
            list(GET _parts 1 _sym)
            string(APPEND _msg "      ${_file}:  use parm, except_this_one => ${_sym}\n")
        endforeach()
        message(WARNING "${_msg}")
    endif()

    if(_badfmt)
        list(JOIN _badfmt ", " _bf)
        message(WARNING
            "Preflight: malformed FORMAT descriptor (missing comma after tN) at: ${_bf}\n"
            "gfortran aborts at runtime with 'Missing comma between descriptors'.\n"
            "Insert the comma, e.g.  t97,'---'  instead of  t97'---' .")
    endif()

    if(NOT _collisions AND NOT _badfmt)
        message(STATUS "  Preflight:        no known gfortran blockers found")
    endif()
endif()

### ----------------------------------------------------------------------
### Zero-filled heap.
###
### SWAT reads some ALLOCATE'd arrays before ever assigning them (e.g.
### sdnco in readhru.f). Intel's runtime hands back zeroed memory, so the
### bug is invisible there; gfortran hands back whatever the heap held, so
### results change with the runtime DLL, environment size and binary layout.
### gfortran has no flag to zero allocatables, so we intercept malloc at
### link time (ld --wrap) and clear every block. The shim is written in
### Fortran/bind(C), so no C compiler is needed.
### ----------------------------------------------------------------------
set(SWAT_ZERO_HEAP_ACTIVE OFF)
set(SWAT_ZERO_HEAP_SRC "")
if(SWAT_ZERO_HEAP AND CMAKE_Fortran_COMPILER_ID STREQUAL "GNU" AND NOT APPLE)
    set(SWAT_ZERO_HEAP_ACTIVE ON)
    set(SWAT_ZERO_HEAP_SRC "${CMAKE_BINARY_DIR}/swat_zero_malloc.f90")
    set(_zh_content
"! Generated by CMakeLists.txt -- zero-fills every malloc (see SWAT_ZERO_HEAP)
function swat_zero_malloc(n) bind(C, name=\"__wrap_malloc\") result(p)
    use, intrinsic :: iso_c_binding
    implicit none
    integer(c_size_t), value :: n
    type(c_ptr) :: p, q
    interface
        function real_malloc(m) bind(C, name=\"__real_malloc\") result(r)
            import :: c_size_t, c_ptr
            integer(c_size_t), value :: m
            type(c_ptr) :: r
        end function
        function c_memset(s, c, m) bind(C, name=\"memset\") result(r)
            import :: c_size_t, c_ptr, c_int
            type(c_ptr), value :: s
            integer(c_int), value :: c
            integer(c_size_t), value :: m
            type(c_ptr) :: r
        end function
    end interface
    p = real_malloc(n)
    if (c_associated(p)) q = c_memset(p, 0_c_int, n)
end function swat_zero_malloc
")
    ### only rewrite the file when its content changed, to avoid needless rebuilds
    set(_zh_old "")
    if(EXISTS "${SWAT_ZERO_HEAP_SRC}")
        file(READ "${SWAT_ZERO_HEAP_SRC}" _zh_old)
    endif()
    if(NOT "${_zh_old}" STREQUAL "${_zh_content}")
        file(WRITE "${SWAT_ZERO_HEAP_SRC}" "${_zh_content}")
    endif()
endif()

### ----------------------------------------------------------------------
### main.f variant decides how compilation is ordered.
###
### Many SWAT revisions begin main.f with  include 'modparm.f' , so the parm
### module is pulled in textually instead of being its own translation unit.
### CMake cannot see that dependency, so most files would fail with
### "parm.mod not found". When we detect it, we drive the compiler manually.
### ----------------------------------------------------------------------
set(SWAT_MANUAL_ORDER OFF)
if(NOT MSVC AND EXISTS "${SWAT_SRC}/main.f")
    file(READ "${SWAT_SRC}/main.f" _main_head LIMIT 256)
    string(REPLACE "\r" "" _main_head "${_main_head}")
    if("${_main_head}" MATCHES "[ \t]*include[ \t]*'modparm\\.f'")
        set(SWAT_MANUAL_ORDER ON)
    endif()
endif()

if(SWAT_MANUAL_ORDER)
    message(STATUS "  main.f variant:   includes modparm.f — manual ordering active")

    string(TOUPPER "${CMAKE_BUILD_TYPE}" BUILD_TYPE_UPPER)
    if(BUILD_TYPE_UPPER STREQUAL "DEBUG")
        separate_arguments(Compile_Flags_List UNIX_COMMAND
            "${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_DEBUG}")
    else()
        separate_arguments(Compile_Flags_List UNIX_COMMAND
            "${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_RELEASE}")
    endif()

    ### Step 1: modparm.f + main.f in one invocation -> main.o and parm.mod.
    ### DEPENDS lists both sources so editing either triggers a rebuild.
    add_custom_command(OUTPUT main.o
        COMMAND ${CMAKE_Fortran_COMPILER} ${Compile_Flags_List} ${FLAG_LLONG} -c
                "${SWAT_SRC}/modparm.f"
                "${SWAT_SRC}/main.f"
        DEPENDS "${SWAT_SRC}/modparm.f"
                "${SWAT_SRC}/main.f"
        COMMENT "Compiling modparm.f + main.f (produces parm.mod)")

    ### Step 2: every other file, each depending on main.o for parm.mod and
    ### on its own source so edits are picked up.
    set(swat_obj "")
    foreach(SRCFILE IN LISTS F77SRCS F90SRCS)
        get_filename_component(CORENAME ${SRCFILE} NAME_WE)
        if(CORENAME STREQUAL "main" OR CORENAME STREQUAL "modparm")
            continue()
        endif()
        swat_line_flag("${CORENAME}" Format_Flag)
        add_custom_command(OUTPUT ${CORENAME}.o
            COMMAND ${CMAKE_Fortran_COMPILER} ${Compile_Flags_List} ${Format_Flag} -c
                    "${SRCFILE}"
            DEPENDS main.o "${SRCFILE}"
            COMMENT "Compiling ${CORENAME}")
        list(APPEND swat_obj ${CORENAME}.o)
    endforeach()

    list(SORT swat_obj)
    ### modparm.o is produced by step 1 but deliberately NOT linked: main.o
    ### already carries every parm symbol, so linking both is a duplicate-symbol
    ### error.
    add_executable(${SWAT_EXE_NAME} ${swat_obj} main.o ${SWAT_ZERO_HEAP_SRC})
else()
    ### Standard path: CMake resolves Fortran module dependencies itself.
    foreach(SRCFILE IN LISTS F77SRCS)
        get_filename_component(CORENAME ${SRCFILE} NAME_WE)
        swat_line_flag("${CORENAME}" Format_Flag)
        set_source_files_properties(${SRCFILE} PROPERTIES COMPILE_FLAGS ${Format_Flag})
    endforeach()
    foreach(SRCFILE IN LISTS F90SRCS)
        set_source_files_properties(${SRCFILE} PROPERTIES COMPILE_FLAGS ${FLAG_LLONG})
    endforeach()
    add_executable(${SWAT_EXE_NAME} ${F77SRCS} ${F90SRCS} ${SWAT_ZERO_HEAP_SRC})
endif()

if(SWAT_ZERO_HEAP_ACTIVE)
    target_link_options(${SWAT_EXE_NAME} PRIVATE -Wl,--wrap=malloc)
endif()

### ----------------------------------------------------------------------
### Executable naming: <name><version>.<toolchain>.<rel|dbg>
### e.g. swat695.mingw64.rel.exe
### ----------------------------------------------------------------------
set_target_properties(${SWAT_EXE_NAME} PROPERTIES
    LINKER_LANGUAGE Fortran
    RELEASE_POSTFIX                  "${SWAT_VER_STR}.${TOOL_CHAIN}.rel"
    DEBUG_POSTFIX                    "${SWAT_VER_STR}.${TOOL_CHAIN}.dbg"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/executable"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_BINARY_DIR}/executable"
)

install(TARGETS ${SWAT_EXE_NAME} RUNTIME DESTINATION bin)

### ----------------------------------------------------------------------
### Configuration summary
### ----------------------------------------------------------------------
message(STATUS "")
message(STATUS "  Platform:         ${CMAKE_HOST_SYSTEM_NAME} ${CMAKE_HOST_SYSTEM_PROCESSOR}")
message(STATUS "  CMake:            ${CMAKE_VERSION}")
message(STATUS "  Build type:       ${CMAKE_BUILD_TYPE}")
message(STATUS "  Fortran compiler: ${CMAKE_Fortran_COMPILER} (${CMAKE_Fortran_COMPILER_ID})")
message(STATUS "  SWAT revision:    ${SWAT_VER_STR}")
message(STATUS "  Source directory: ${SWAT_SRC}")
message(STATUS "  Sources found:    ${_n_f77} .f  +  ${_n_f90} .f90")
message(STATUS "  Flags (Release):  ${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_RELEASE}")
message(STATUS "  Flags (Debug):    ${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_DEBUG}")
message(STATUS "  Zero-fill heap:   ${SWAT_ZERO_HEAP_ACTIVE}")
message(STATUS "  72-column files:  ${SWAT_LEN72_SRCS}")
message(STATUS "  Executable:       ${CMAKE_BINARY_DIR}/executable")
message(STATUS "  Install prefix:   ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
