#ifndef YOSEMITE_TOOL_MEM_TRACE_H
#define YOSEMITE_TOOL_MEM_TRACE_H


#include "tools/tool.h"
#include "utils/event.h"
#include "backend/common.h"

namespace yosemite {

class MemTrace final : public Tool {
public:
    MemTrace();

    ~MemTrace();

    void kernel_start_callback(std::shared_ptr<KernelLauch_t> kernel);

    void kernel_end_callback(std::shared_ptr<KernelEnd_t> kernel);

    void mem_alloc_callback(std::shared_ptr<MemAlloc_t> mem);

    void mem_free_callback(std::shared_ptr<MemFree_t> mem);

    void ten_alloc_callback(std::shared_ptr<TenAlloc_t> ten);

    void ten_free_callback(std::shared_ptr<TenFree_t> ten);

    void mem_access_analysis(mem_access_t* ma);

    void evt_callback(EventPtr_t evt);

    void flush();

private:
    void kernel_trace_flush(std::shared_ptr<KernelLauch_t> kernel);
};

}   // yosemite
#endif // YOSEMITE_TOOL_MEM_TRACE_H