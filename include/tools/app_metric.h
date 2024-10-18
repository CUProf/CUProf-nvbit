#ifndef YOSEMITE_TOOL_APP_METRICS_H
#define YOSEMITE_TOOL_APP_METRICS_H


#include "yosemite.h"
#include "tools/tool.h"
#include "utils/event.h"

namespace yosemite {

class AppMetrics final : public Tool {
public:
    AppMetrics() : Tool(YOSEMITE_APP_METRICE) {}

    ~AppMetrics() {}

    void kernel_start_callback(std::shared_ptr<KernelLauch_t> kernel);

    void kernel_end_callback(std::shared_ptr<KernelEnd_t> kernel);

    void mem_alloc_callback(std::shared_ptr<MemAlloc_t> mem);

    void mem_free_callback(std::shared_ptr<MemFree_t> mem);

    void evt_callback(EventPtr_t evt);

    void flush();
};

}   // yosemite
#endif // YOSEMITE_TOOL_APP_METRICS_H