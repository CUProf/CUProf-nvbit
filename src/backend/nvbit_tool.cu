#include "yosemite.h"

#include "backend/nvbit_app_metric.h"
#include "backend/nvbit_mem_trace.h"

/* every tool needs to include this once */
#include "nvbit_tool.h"

YosemiteAnalysisTool_t yosemite_tool;


/* nvbit_at_init() is executed as soon as the nvbit tool is loaded. We
 * typically do initializations in this call. In this case for instance we get
 * some environment variables values which we use as input arguments to the tool
 */
void nvbit_at_init() {
    yosemite_init(yosemite_tool);

    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_at_init();
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_at_init();
    }
}

void nvbit_tool_init(CUcontext ctx) {
    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_tool_init(ctx);
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_tool_init(ctx);
    }
}

void nvbit_at_ctx_init(CUcontext ctx) {
    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_at_ctx_init(ctx);
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_at_ctx_init(ctx);
    }
}

void nvbit_at_ctx_term(CUcontext ctx) {
    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_at_ctx_term(ctx);
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_at_ctx_term(ctx);
    }
}


/* This call-back is triggered every time a CUDA driver call is encountered.
 * Here we can look for a particular CUDA driver call by checking at the
 * call back ids  which are defined in tools_cuda_api_meta.h.
 * This call back is triggered bith at entry and at exit of each CUDA driver
 * call, is_exit=0 is entry, is_exit=1 is exit.
 * */
void nvbit_at_cuda_event(CUcontext ctx, int is_exit, nvbit_api_cuda_t cbid,
                         const char *name, void *params, CUresult *pStatus) {
    
    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_at_cuda_event(ctx, is_exit, cbid, name, params, pStatus);
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_at_cuda_event(ctx, is_exit, cbid, name, params, pStatus);
    }

}

void nvbit_at_term() {
    if (yosemite_tool == YOSEMITE_APP_METRICE) {
        yosemite_app_metric::app_metric_nvbit_at_term();
    } else if (yosemite_tool == YOSEMITE_MEM_TRACE) {
        yosemite_mem_trace::mem_trace_nvbit_at_term();
    }
}
