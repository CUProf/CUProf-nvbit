#include <cstdint>
#include <map>
#include <list>
#include <fstream>

#include "analyzer.h"
#include "analyzer_utils.h"

using namespace yosemite;

typedef struct Timer{
    uint64_t access_timer;
    uint64_t event_timer;

    Timer() {
        access_timer = 0;
        event_timer = 0;
    }

    void increment(bool is_event) {
        if (is_event) {
            event_timer++;
        } else {
            access_timer++;
        }
    }

    uint64_t get() {
        return access_timer + event_timer;
    }
} Timer_t;

static Timer_t _timer;

static bool first_kernel_finished = false;

std::map<uint64_t, KernelEvent_t> kernel_events;
std::map<uint64_t, AllocEvent_t> alloc_events;

std::map<DevPtr, AllocEvent_t> active_memories;

std::map<KernelEvent_t, std::list<TraceEntry>> _traces;


YosemiteResult yosemite_alloc_callback(DevPtr ptr, size_t size) {
    AllocEvent_t event;
    event.timestamp = _timer.get();
    event.addr = ptr;
    event.size = size;
    event.alloc_type = 1;
    alloc_events.emplace(_timer.get(), event);
    active_memories.emplace(ptr, event);

    _timer.increment(true);
    return YOSEMITE_SUCCESS;

}


YosemiteResult yosemite_free_callback(DevPtr ptr) {
    auto it = active_memories.find(ptr);
    if (it == active_memories.end()) {
        return YOSEMITE_ERROR;
    }
    active_memories.erase(it);
    _timer.increment(true);
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_memcpy_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_memset_callback() {
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_kernel_start_callback(std::string kernel_name, uint64_t grid_id) {
    if (first_kernel_finished) {
        yosemite_kernel_end_callback();
    } else {
        first_kernel_finished = true;
    }

    KernelEvent_t event;
    event.timestamp = _timer.get();
    event.kernel_name = kernel_name;
    event.grid_id = grid_id;
    kernel_events.emplace(_timer.get(), event);
    _traces.emplace(event, std::list<TraceEntry>());

    _timer.increment(true);
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_kernel_end_callback() {
    KernelEvent_t& event = std::prev(kernel_events.end())->second;
    event.end_time = _timer.get();

    _timer.increment(true);

    return YOSEMITE_SUCCESS;
    
}


YosemiteResult yosemite_memory_trace_analysis(mem_access_t* ma) {
    KernelEvent_t kernel_event = std::prev(kernel_events.end())->second;
    auto& traces = _traces[kernel_event];

    for (int i = 0; i < GPU_WARP_SIZE; i++) {
        TraceEntry entry;
        if (ma->addrs[i] != 0) {
            entry.addr = ma->addrs[i];
            entry.page_no = entry.addr >> 12;
            entry.size = ma->size;
            entry.timestampe = _timer.get();
            entry.access_type = ma->is_write ? 1 : 0;
            // entry.sm_id = ma->sm_id;
            // entry.warp_id = ma->warp_id;
            traces.push_back(entry);
        }
    }

    _timer.increment(false);
    return YOSEMITE_SUCCESS;
}


YosemiteResult yosemite_dump_traces(std::string filename) {
    std::ofstream out(filename);

    for (auto kernel : _traces) {
        for (auto& trace : kernel.second) {
            out << trace.page_no << " "
                << trace.addr << " "
                << trace.size << " "
                << trace.timestampe << " "
                << trace.access_type << " "
                << "0 0"
                << std::endl;
        }
    }


    for (auto event : alloc_events) {
        out << "ALLOCATION: " << " " << event.second.addr << " " << event.second.size << std::endl;
    }

    for (auto event : kernel_events) {
        out << "KERNEL: " << event.second.timestamp << " " << event.second.end_time << std::endl;
    }


    out.close();
    return YOSEMITE_SUCCESS;
}