#include "torch_interface.h"

#include "torch_prof.h"

namespace yosemite {

void torch_prof_enable() {
    TorchProf& torch_prof = TorchProf::getInstance();
    torch_prof.enable_torch_callback();
}

} // namespace yosemite