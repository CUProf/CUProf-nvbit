#include "tools/mem_trace.h"
#include "utils/helper.h"
#include "utils/event.h"
#include "utils/python_frame.h"
#include "utils/cxx_backtrace.h"

#include <cstdint>
#include <map>
#include <list>
#include <fstream>
#include <memory>
#include <cassert>


using namespace yosemite;


typedef struct TraceEntry
{
    uint64_t addr;
    uint64_t page_no;
    uint32_t size;
    uint64_t timestampe;
    uint32_t access_type; // 0: read 1: write
    InstrType::MemorySpace mem_type;

    TraceEntry() = default;

    ~TraceEntry() = default;

    TraceEntry(uint64_t addr, uint32_t size, uint32_t access_type)
        : addr(addr), size(size), access_type(access_type) {
            timestampe = 0;
            page_no = addr >> 12;
    }
}TraceEntry_t;


static Timer_t _timer;

static bool first_kernel_finished = false;
std::string trace_folder_name;
uint32_t kernel_id = 0;

std::map<uint64_t, std::shared_ptr<KernelLauch_t>> kernel_events;
std::map<uint64_t, std::shared_ptr<MemAlloc_t>> alloc_events;
std::map<DevPtr, std::shared_ptr<MemAlloc_t>> active_memories;

std::map<uint64_t, std::shared_ptr<TenAlloc>> tensor_events;
std::map<DevPtr, std::shared_ptr<TenAlloc>> active_tensors;

std::list<TraceEntry> _traces;


MemTrace::MemTrace() : Tool(YOSEMITE_MEM_TRACE) {
    const char* torch_prof = std::getenv("YOSEMITE_TORCH_PROFILE");
    if (torch_prof && std::string(torch_prof) == "1") {
        fprintf(stdout, "Enabling torch profiler in MemTrace.\n");
        _torch_enabled = true;
    }
}


MemTrace::~MemTrace() {}


void MemTrace::kernel_start_callback(std::shared_ptr<KernelLauch_t> kernel) {
    if (!first_kernel_finished) {
        const char* env_trace_folder_name = std::getenv("APP_NAME");
        if (env_trace_folder_name != nullptr) {
            fprintf(stdout, "APP_NAME: %s\n", env_trace_folder_name);
            trace_folder_name = "traces_" + std::string(env_trace_folder_name)
                                + "_" + get_current_date_n_time();
        } else {
            fprintf(stdout, "No trace_folder_name specified.\n");
            trace_folder_name = "traces_" + get_current_date_n_time();
        }
        check_folder_existance(trace_folder_name);
        first_kernel_finished = true;
    } else {
        kernel_end_callback(nullptr);
    }

    kernel->kernel_id = kernel_id++;
    kernel_events.emplace(_timer.get(), kernel);
    _traces = std::list<TraceEntry>();

    _timer.increment(true);
}


void MemTrace::kernel_trace_flush(std::shared_ptr<KernelLauch_t> kernel) {
    std::string filename = trace_folder_name + "/kernel_"
                            + std::to_string(kernel->kernel_id) + ".txt";
    printf("Dumping traces to %s\n", filename.c_str());

    std::ofstream out(filename);

    for (auto& trace : _traces) {
        out << trace.page_no << " "
            << trace.addr << " "
            << trace.size << " "
            << trace.timestampe << " "
            << trace.access_type << " "
            << (int)trace.mem_type
            << std::endl;
    }

    for (auto evt : active_memories) {
        out << "ALLOCATION: " << " " << evt.second->addr
            << " " << evt.second->size << std::endl;
    }

    for (auto evt : active_tensors) {
        out << "TENSOR: " << " " << evt.second->addr
            << " " << evt.second->size << std::endl;
    }

    out << "KERNEL: " << kernel->timestamp << " " << kernel->end_time << std::endl;

    out.close();
}


void MemTrace::kernel_end_callback(std::shared_ptr<KernelEnd_t> kernel) {
    auto evt = std::prev(kernel_events.end())->second;
    evt->end_time = _timer.get();

    kernel_trace_flush(evt);

    _timer.increment(true);
}


void MemTrace::mem_alloc_callback(std::shared_ptr<MemAlloc_t> mem) {
    alloc_events.emplace(_timer.get(), mem);
    active_memories.emplace(mem->addr, mem);

    std::cout << get_cxx_backtrace() << std::endl;
    // std::cout << "-----------------------------------" << std::endl;
    std::cout << get_cxx_backtrace(true) << std::endl;

    _timer.increment(true);
}


void MemTrace::mem_free_callback(std::shared_ptr<MemFree_t> mem) {
    auto it = active_memories.find(mem->addr);
    assert(it != active_memories.end());
    active_memories.erase(it);

    _timer.increment(true);
}


void MemTrace::ten_alloc_callback(std::shared_ptr<TenAlloc_t> ten) {
    tensor_events.emplace(_timer.get(), ten);
    active_tensors.emplace(ten->addr, ten);

    // std::cout << get_cxx_backtrace(true) << std::endl;
    std::cout << get_frame_string() << std::endl;

    _timer.increment(true);
}


void MemTrace::ten_free_callback(std::shared_ptr<TenFree_t> ten) {
    auto it = active_tensors.find(ten->addr);
    assert(it != active_tensors.end());
    active_tensors.erase(it);

    _timer.increment(true);
}


void MemTrace::mem_access_analysis(mem_access_t* ma) {
    for (int i = 0; i < GPU_WARP_SIZE; i++) {
        TraceEntry entry;
        if (ma->addrs[i] != 0) {
            entry.addr = ma->addrs[i];
            entry.page_no = entry.addr >> 12;
            entry.size = ma->size;
            entry.timestampe = _timer.get();
            entry.access_type = ma->is_write ? 1 : 0;
            entry.mem_type = ma->mem_type;
            _traces.push_back(entry);
        }
    }

    _timer.increment(false);
}


void MemTrace::evt_callback(EventPtr_t evt) {
    switch (evt->evt_type) {
        case EventType_KERNEL_LAUNCH:
            kernel_start_callback(std::dynamic_pointer_cast<KernelLauch_t>(evt));
            break;
        case EventType_KERNEL_END:
            kernel_end_callback(std::dynamic_pointer_cast<KernelEnd_t>(evt));
            break;
        case EventType_MEM_ALLOC:
            mem_alloc_callback(std::dynamic_pointer_cast<MemAlloc_t>(evt));
            break;
        case EventType_MEM_FREE:
            mem_free_callback(std::dynamic_pointer_cast<MemFree_t>(evt));
            break;
        case EventType_TEN_ALLOC:
            ten_alloc_callback(std::dynamic_pointer_cast<TenAlloc_t>(evt));
            break;
        case EventType_TEN_FREE:
            ten_free_callback(std::dynamic_pointer_cast<TenFree_t>(evt));
            break;
        default:
            break;
    }
}


void MemTrace::flush() {
    kernel_end_callback(nullptr);

}