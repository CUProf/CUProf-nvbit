#ifndef YOSEMITE_TOOL_H
#define YOSEMITE_TOOL_H

#include "utils/event.h"
#include "tools/tool_type.h"
#include "backend/common.h"

namespace yosemite {

class Tool {
public:
    Tool(YosemiteAnalysisTool_t tool) {_tool = tool;}

    virtual ~Tool() = default;

    virtual void evt_callback(EventPtr_t evt) = 0;

    virtual void mem_access_analysis(mem_access_t* ma) = 0;

    virtual void flush() = 0;
protected:
    YosemiteAnalysisTool_t _tool;

};

}   // yosemite
#endif // YOSEMITE_TOOL_H