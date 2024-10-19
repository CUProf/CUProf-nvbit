#ifndef YOSEMITE_H
#define YOSEMITE_H

#include "backend/common.h"
#include "tools/tool_type.h"

#include <cstddef>
#include <cstdint>
#include <string>

typedef enum {
    YOSEMITE_SUCCESS = 0,
    YOSEMITE_ERROR = 1,
    YOSEMITE_NOT_IMPLEMENTED = 2,
    YOSEMITE_CUDA_MEMFREE_ZERO = 3
} YosemiteResult_t;



typedef unsigned long long DevPtr;

YosemiteResult_t yosemite_alloc_callback(DevPtr ptr, size_t size, int type);

YosemiteResult_t yosemite_free_callback(DevPtr ptr);

YosemiteResult_t yosemite_memcpy_callback();

YosemiteResult_t yosemite_memset_callback();

YosemiteResult_t yosemite_kernel_start_callback(std::string kernel_name);

YosemiteResult_t yosemite_kernel_end_callback(uint64_t mem_accesses = 0);

YosemiteResult_t yosemite_tensor_malloc_callback(DevPtr ptr, int64_t alloc_size,
                                int64_t total_allocated, int64_t total_reserved);

YosemiteResult_t yosemite_tensor_free_callback(DevPtr ptr, int64_t alloc_size,
                                int64_t total_allocated, int64_t total_reserved);

YosemiteResult_t yosemite_memory_access_analysis(mem_access_t* ma);

YosemiteResult_t yosemite_tool_enable(YosemiteAnalysisTool_t& tool);

YosemiteResult_t yosemite_tool_disable();

YosemiteResult_t yosemite_torch_prof_enable();

YosemiteResult_t yosemite_init(YosemiteAnalysisTool_t& tool);

YosemiteResult_t yosemite_flush();


#endif // YOSEMITE_H
