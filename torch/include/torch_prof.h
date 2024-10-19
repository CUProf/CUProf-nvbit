#ifndef YOSEMITE_TORCH_PROF_H
#define YOSEMITE_TORCH_PROF_H

#include <torch/extension.h>

namespace yosemite {

class TorchProf {
public:
    void enable_torch_callback();

    void tensor_malloc_callback(void* ptr, int64_t alloc_size, int64_t total_allocated,
                                int64_t total_reserved);

    void tensor_free_callback(void* ptr, int64_t alloc_size, int64_t total_allocated,
                                int64_t total_reserved);

    static TorchProf& getInstance();

private:
    TorchProf() {}
    ~TorchProf() {}

    class TensorCallback : public c10::MemoryReportingInfoBase {
    public:
        TensorCallback() {}

        bool memoryProfilingEnabled() const override { return true; }

#if TORCH_VERSION_MAJOR >= 2
        void reportMemoryUsage(void* ptr, int64_t alloc_size, size_t total_allocated,
                                size_t total_reserved, c10::Device device) override;
#else
        void reportMemoryUsage(void* ptr, int64_t alloc_size, int64_t total_allocated,
                                int64_t total_reserved, c10::Device device) override;
#endif
    };  // class TensorCallback

    std::shared_ptr<TensorCallback> new_torch_profiler() {
        return std::make_shared<TensorCallback>();
    }
};  // class TorchProf

} // namespace yosemite

#endif //YOSEMITE_TORCH_PROF_H