#pragma once

#include "common.h"

typedef enum {
    YOSEMITE_SUCCESS = 0,
    YOSEMITE_ERROR = 1
} YosemiteResult;

typedef unsigned long long DevPtr;

YosemiteResult yosemite_alloc_callback(DevPtr ptr, size_t size, int type);

YosemiteResult yosemite_free_callback(DevPtr ptr);

YosemiteResult yosemite_memcpy_callback();

YosemiteResult yosemite_memset_callback();

YosemiteResult yosemite_kernel_start_callback(std::string kernel_name, uint64_t grid_id);

YosemiteResult yosemite_kernel_end_callback();

YosemiteResult yosemite_memory_trace_analysis(mem_access_t* ma);