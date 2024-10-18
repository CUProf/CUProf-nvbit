#ifndef YOSEMITE_TOOL_H
#define YOSEMITE_TOOL_H

#include "yosemite.h"
#include "utils/event.h"

namespace yosemite {

class Tool {
public:
    Tool(YosemiteAnalysisTool_t tool) {_tool = tool;}

    virtual ~Tool() = default;

    virtual void evt_callback(EventPtr_t evt) = 0;

    virtual void flush() = 0;
protected:
    YosemiteAnalysisTool_t _tool;

};

}   // yosemite
#endif // YOSEMITE_TOOL_H