#include "yosemite.h"
#include "tools/app_metric.h"
#include "tools/tool.h"
#include "utils/event.h"
#include "torch/torch_prof.h"

#include <memory>
#include <map>

using namespace yosemite;

static std::map<YosemiteAnalysisTool_t, std::shared_ptr<Tool>> _tools;


YosemiteResult_t yosemite_alloc_callback(DevPtr ptr, size_t size, int type) {
    for (auto &tool : _tools) {
        auto mem_alloc = std::make_shared<MemAlloc_t>(ptr, size, type);
        tool.second->evt_callback(mem_alloc);
    }
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_free_callback(DevPtr ptr) {
    if (ptr == 0) {
        return YOSEMITE_CUDA_MEMFREE_ZERO;
    }
    for (auto &tool : _tools) {
        auto mem_free = std::make_shared<MemFree_t>(ptr);
        tool.second->evt_callback(mem_free);
    }
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_memcpy_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_memset_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_kernel_start_callback(std::string kernel_name) {
    for (auto &tool : _tools) {
        auto kernel = std::make_shared<KernelLauch_t>(kernel_name); 
        tool.second->evt_callback(kernel);
    }
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_kernel_end_callback(uint64_t mem_accesses) {
    for (auto &tool : _tools) {
        auto kernel = std::make_shared<KernelEnd_t>(mem_accesses);
        tool.second->evt_callback(kernel);
    }
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_memory_access_analysis() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_tool_enable() {
    const char* tool_name = std::getenv("YOSEMITE_TOOL_NAME");
    if (tool_name) {
        fprintf(stdout, "YOSEMITE_TOOL_NAME: %s\n", tool_name);
    } else {
        fprintf(stdout, "No tool name specified.\n");
        return YOSEMITE_NOT_IMPLEMENTED;
    }

    if (std::string(tool_name) == "app_metric") {
        fprintf(stdout, "Enabling app_metric tool.\n");
        _tools.emplace(YOSEMITE_APP_METRICE, std::make_shared<AppMetrics>());
    } else {
        fprintf(stdout, "Tool not found.\n");
        return YOSEMITE_NOT_IMPLEMENTED;
    }
    fflush(stdout);
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_tool_disable() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_init() {
    yosemite_tool_enable();
    yosemite_torch_prof_enable();

    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_flush() {
    for (auto &tool : _tools) {
        tool.second->flush();
    }
    return YOSEMITE_SUCCESS;
}


YosemiteResult_t yosemite_tensor_malloc_callback(DevPtr ptr, int64_t alloc_size,
                                    int64_t total_allocated, int64_t total_reserved) {
    return YOSEMITE_SUCCESS;
}

YosemiteResult_t yosemite_tensor_free_callback(DevPtr ptr, int64_t alloc_size,
                                    int64_t total_allocated, int64_t total_reserved) {
    return YOSEMITE_SUCCESS;
}

YosemiteResult_t yosemite_torch_prof_enable() {
    TorchProf& torch_prof = TorchProf::getInstance();
    torch_prof.enable_torch_callback();
    return YOSEMITE_SUCCESS;
}

