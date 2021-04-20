find_package(PkgConfig REQUIRED)

cmake_minimum_required(VERSION 2.6)
project(xfswm)

add_compile_options(-Wall -Wextra -Werror)

add_executable(xfswm main.c)

pkg_check_modules(X11 REQUIRED x11)

target_link_libraries(xfswm ${X11_LIBRARIES} ${X11_XFIXES_LIBRARIES}
                      ${X11_XINPUT_LIBRARIES})
target_include_directories(
    xfswm PUBLIC ${X11_INCLUDE_DIRS} ${X11_XFIXES_INCLUDE_DIRS}
                 ${X11_XINPUT_INCLUDE_DIRS})
target_compile_options(xfswm PUBLIC ${X11_CFLAGS_OTHER} ${X11_XFIXES_OTHER}
                                    ${X11_XINPUT_OTHER})

install(TARGETS xfswm DESTINATION bin)
install(
    DIRECTORY lib/
    DESTINATION lib
    USE_SOURCE_PERMISSIONS)
install(
    DIRECTORY share/
    DESTINATION share
    USE_SOURCE_PERMISSIONS)
