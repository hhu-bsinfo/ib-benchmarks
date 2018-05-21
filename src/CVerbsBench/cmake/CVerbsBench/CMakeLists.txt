project(CVerbsBench)
message(STATUS "Project " ${PROJECT_NAME})

include_directories(${CVERBSBENCH_SRC_DIR})

set(SOURCE_FILES
        ${CVERBSBENCH_SRC_DIR}/threads.c)

add_executable(${PROJECT_NAME} ${SOURCE_FILES})

target_link_libraries(${PROJECT_NAME} IbLib -lpthread)