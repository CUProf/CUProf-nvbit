#ifndef YOSEMITE_UTILS_CXX_BACKTRACE_H
#define YOSEMITE_UTILS_CXX_BACKTRACE_H

#include <string>

namespace yosemite {

std::string get_cxx_backtrace(bool demangled = false);


}  // namespace yosemite

#endif  // UNWIND_UTILS_H