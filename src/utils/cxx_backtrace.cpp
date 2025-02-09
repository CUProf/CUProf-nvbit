#define UNW_LOCAL_ONLY
#include <libunwind.h>
#include <cxxabi.h>  // for __cxa_demangle
#include <sstream>

#include "utils/cxx_backtrace.h"

namespace yosemite {

std::string get_cxx_backtrace(bool demangled) {
    unw_cursor_t cursor;
    unw_context_t context;

    // Initialize cursor to current frame for local unwinding.
    unw_getcontext(&context);
    unw_init_local(&cursor, &context);

    std::stringstream ss;

    // Unwind frames one by one, going up the frame stack.
    while (unw_step(&cursor) > 0) {
        unw_word_t offset, pc;
        unw_get_reg(&cursor, UNW_REG_IP, &pc);
        if (pc == 0) {
            break;
        }
        // std::printf("0x%lx:", pc);
        ss << "0x" << std::hex << pc << ":" << std::dec;

        char sym[256];
        if (unw_get_proc_name(&cursor, sym, sizeof(sym), &offset) == 0) {
            if (demangled) {
                char* nameptr = sym;
                int status;
                char* demangled_sym = abi::__cxa_demangle(sym, nullptr, nullptr, &status);
                if (status == 0) {
                    nameptr = demangled_sym;
                }
                // std::printf(" (%s+0x%lx)\n", nameptr, offset);
                ss << " (" << nameptr << "+0x" << std::hex << offset << std::dec << ")\n";
                std::free(demangled_sym);
            } else {
                // std::printf(" (%s+0x%lx)\n", sym, offset);
                ss << " (" << sym << "+0x" << std::hex << offset << std::dec << ")\n";
            }
        } else {
            // std::printf(" -- error: unable to obtain symbol name for this frame\n");
            ss << " -- error: unable to obtain symbol name for this frame\n";
        }
    }

    return ss.str();
}

}  // namespace yosemite
