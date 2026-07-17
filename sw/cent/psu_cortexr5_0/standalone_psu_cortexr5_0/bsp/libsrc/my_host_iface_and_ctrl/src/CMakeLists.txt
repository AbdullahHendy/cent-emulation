cmake_minimum_required(VERSION 3.15)
project(my_host_iface_and_ctrl)

find_package(common)

collector_create (PROJECT_LIB_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}")
collector_create (PROJECT_LIB_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}")
include_directories(${CMAKE_BINARY_DIR}/include)

# Tell CMake exactly which files to compile and copy
collect (PROJECT_LIB_SOURCES cent.c)
collect (PROJECT_LIB_SOURCES pnm.c)
collect (PROJECT_LIB_HEADERS cent.h)
collect (PROJECT_LIB_HEADERS pnm.h)

collector_list (_sources PROJECT_LIB_SOURCES)
collector_list (_headers PROJECT_LIB_HEADERS)

# This is the magic line that puts cent.h into the Vitis BSP include folder!
file(COPY ${_headers} DESTINATION ${CMAKE_BINARY_DIR}/include)

add_library(my_host_iface_and_ctrl STATIC ${_sources})
set_target_properties(my_host_iface_and_ctrl PROPERTIES LINKER_LANGUAGE C)
