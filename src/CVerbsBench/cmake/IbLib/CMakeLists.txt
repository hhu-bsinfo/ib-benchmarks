project(IbLib)
message(STATUS "Project " ${PROJECT_NAME})

include_directories(${CVERBSBENCH_SRC_DIR})

set(SOURCE_FILES
        ${CVERBSBENCH_SRC_DIR}/IbLib/ib_device.c
        ${CVERBSBENCH_SRC_DIR}/IbLib/ib_perf_counter.c
        ${CVERBSBENCH_SRC_DIR}/IbLib/ib_perf_counter_compat.c
        ${CVERBSBENCH_SRC_DIR}/IbLib/ib_mem_reg.c)

add_library(${PROJECT_NAME} STATIC ${SOURCE_FILES})

target_link_libraries(${PROJECT_NAME} -libverbs -libmad)