#include <map>
#include <vector>
#include <string>
#include <fstream>
#include <cstdlib>
#include <algorithm>

#include "analyzer.h"
#include "analyzer_utils.h"
#include "analyzer_helper.hpp"

using namespace yosemite;

typedef struct Stats{
    uint64_t num_allocs;
    uint64_t num_kernels;
    uint64_t cur_mem_usage;
    uint64_t max_mem_usage;
    uint64_t max_mem_accesses_per_kernel;
    uint64_t avg_mem_accesses;
    uint64_t tot_mem_accesses;
    std::string max_mem_accesses_kernel;

    Stats() = default;

    ~Stats() = default;
} Stats_t;

static Stats_t _stats;

static uint64_t _timer = 0;

std::map<uint64_t, KernelEvent_t> kernel_events;
std::map<uint64_t, AllocEvent_t> alloc_events;
std::map<DevPtr, AllocEvent_t> active_memories;

std::map<std::string, uint32_t> kernel_invocations;


YosemiteResult yosemite_alloc_callback(DevPtr ptr, size_t size, int type) {
    AllocEvent_t event;
    event.addr = ptr;
    event.size = size;
    event.alloc_type = type;
    alloc_events.emplace(_timer, event);
    active_memories.emplace(ptr, event);

    _stats.num_allocs++;
    _stats.cur_mem_usage += size;
    _stats.max_mem_usage = std::max(_stats.max_mem_usage, _stats.cur_mem_usage);
    _timer++;
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_free_callback(DevPtr ptr) {
    auto it = active_memories.find(ptr);
    if (it == active_memories.end()) {
        return YOSEMITE_ERROR;
    }
    _stats.cur_mem_usage -= it->second.size;
    active_memories.erase(it);

    _timer++;
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_memcpy_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_memset_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_kernel_start_callback(std::string kernel_name) {
    KernelEvent_t event;
    event.kernel_name = kernel_name;
    kernel_events.emplace(_timer, event);

    if (kernel_invocations.find(kernel_name) == kernel_invocations.end()) {
        kernel_invocations.emplace(kernel_name, 1);
    } else {
        kernel_invocations[kernel_name]++;
    }

    _stats.num_kernels++;
    _timer++;
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_kernel_end_callback(uint64_t mem_accesses) {
    KernelEvent_t& event = std::prev(kernel_events.end())->second;
    event.mem_accesses = mem_accesses;

    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_dump_stats() {
    const char* env_filename = std::getenv("METRICS_FILE_NAME");
    std::string filename;
    if (env_filename) {
        fprintf(stdout, "METRICS_FILE_NAME: %s\n", env_filename);
        filename = std::string(env_filename) + "_" + getCurrentDateTime();
    } else {
        filename = "metrics_" + getCurrentDateTime();
        fprintf(stdout, "No filename specified. Using default filename: %s\n", filename.c_str());
    }
    filename += ".log";
    printf("Dumping traces to %s\n", filename.c_str());

    std::ofstream out(filename);
    int count = 0;
    for (auto event : alloc_events) {
        out << "Alloc(" << event.second.alloc_type << ") " << count << ":\t" << event.second.addr << " " << event.second.size << " (" << format_size(event.second.size) << ")" << std::endl;
        count++;
    }
    out << std::endl;

    count = 0;
    for (auto event : kernel_events) {
        out << "Kernel " << count << " (refs=" << event.second.mem_accesses << "):\t" << event.second.kernel_name << std::endl;
        _stats.tot_mem_accesses += event.second.mem_accesses;
        if (_stats.max_mem_accesses_per_kernel < event.second.mem_accesses) {
            _stats.max_mem_accesses_kernel = event.second.kernel_name;
            _stats.max_mem_accesses_per_kernel = event.second.mem_accesses;
        }
        count++;
    }
    out << std::endl;

    // sort kernel_invocations by number of invocations in descending order
    std::vector<std::pair<std::string, uint32_t>> sorted_kernel_invocations(kernel_invocations.begin(), kernel_invocations.end());
    std::sort(sorted_kernel_invocations.begin(), sorted_kernel_invocations.end(), [](const std::pair<std::string, uint32_t>& a, const std::pair<std::string, uint32_t>& b) {
        return a.second > b.second;
    });
    for (auto kernel : sorted_kernel_invocations) {
        out << "InvCount=" << kernel.second << "\t" << kernel.first << std::endl;
    }
    out << std::endl;

    _stats.avg_mem_accesses = _stats.tot_mem_accesses / _stats.num_kernels;
    out << "Number of allocations: " << _stats.num_allocs << std::endl;
    out << "Number of kernels: " << _stats.num_kernels << std::endl;
    out << "Maximum memory usage: " << _stats.max_mem_usage << "B (" << format_size(_stats.max_mem_usage) << ")" << std::endl;
    out << "Maximum memory accesses kernel: " << _stats.max_mem_accesses_kernel << std::endl;
    out << "Maximum memory accesses per kernel: " << _stats.max_mem_accesses_per_kernel << " (" << format_number(_stats.max_mem_accesses_per_kernel) << ")" << std::endl;
    out << "Average memory accesses per kernel: " << _stats.avg_mem_accesses << " (" << format_number(_stats.avg_mem_accesses) << ")"  << std::endl;
    out << "Total memory accesses: " << _stats.tot_mem_accesses << " (" << format_number(_stats.tot_mem_accesses) << ")"  << std::endl;
    out.close();

    return YOSEMITE_SUCCESS;
}