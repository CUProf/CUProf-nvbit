#pragma once
#include <cstdint>
#include <string>

typedef enum {
    YOSEMITE_SUCCESS = 0,
    YOSEMITE_ERROR = 1
} YosemiteResult;

typedef unsigned long long DevPtr;

YosemiteResult yosemite_alloc_callback(DevPtr ptr, size_t size, int type);

YosemiteResult yosemite_free_callback(DevPtr ptr);

YosemiteResult yosemite_memcpy_callback();

YosemiteResult yosemite_memset_callback();

YosemiteResult yosemite_kernel_start_callback(std::string kernel_name);

YosemiteResult yosemite_kernel_end_callback(uint64_t mem_accesses);

YosemiteResult yosemite_dump_stats();