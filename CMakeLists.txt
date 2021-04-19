find_package(PkgConfig REQUIRED)

cmake_minimum_required(VERSION 2.6)
project(XFsWm)

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    add_compile_options(
        -Werror
        -Weverything
        -Wno-weak-vtables
        -Wno-padded
        -Wno-disabled-macro-expansion)
elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    add_compile_options(
        -Wall
        -Wextra # reasonable and standard
        -Wshadow # warn the user if a variable declaration shadows one from a
                 # parent context
        -Wnon-virtual-dtor # warn the user if a class with virtual functions has
                           # a non- virtual destructor. This helps catch hard to
                           # track down memory errors
        -Wold-style-cast # warn for c-style casts
        -Wcast-align # warn for potential performance problem casts
        -Wunused # warn on anything being unused
        -Woverloaded-virtual # warn if you overload (not override) a virtual
                             # function
        -Wpedantic # warn if non-standard C++ is used
        -Wconversion # warn on type conversions that may lose data
        -Wsign-conversion # warn on sign conversions
        -Wnull-dereference # warn if a null dereference is detected
        -Wdouble-promotion # warn if float is implicit promoted to double
        -Wformat=2 # warn on security issues around functions that format output
                   # (ie printf) Warn if identation implies blocks where blocks
                   # do not exist.
        -Wmisleading-indentation
        # Warn if if / else chain has duplicated conditions.
        -Wduplicated-cond
        # Warn about logical operations being used where bitwise were probably
        # wanted.
        -Wlogical-op
        # Warn if you perform a cast to the same type.
        -Wuseless-cast
        # Warn if if / else branches have duplicated code.
        -Wduplicated-branches)
else()
    add_compile_options(-Wall -Wextra)
endif()
add_compile_options(-Werror)

add_executable(
    xfswm
    main.c)

pkg_check_modules(XCB REQUIRED xcb)

target_link_libraries(xfswm ${XCB_LIBRARIES}
                      ${XCB_XFIXES_LIBRARIES} ${XCB_XINPUT_LIBRARIES})
target_include_directories(
    xfswm
    PUBLIC ${XCB_INCLUDE_DIRS} ${XCB_XFIXES_INCLUDE_DIRS}
           ${XCB_XINPUT_INCLUDE_DIRS})
target_compile_options(
    xfswm PUBLIC ${XCB_CFLAGS_OTHER} ${XCB_XFIXES_OTHER}
                                     ${XCB_XINPUT_OTHER})

install(TARGETS xfswm DESTINATION bin)
