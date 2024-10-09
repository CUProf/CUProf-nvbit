#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <map>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>

/* every tool needs to include this once */
#include "nvbit_tool.h"

/* nvbit interface file */
#include "nvbit.h"

/* for channel */
#include "utils/channel.hpp"

/* contains definition of the mem_access_t structure */
#include "common.h"

#include "analyzer.h"

#define CHANNEL_SIZE (1l << 20)

enum class RecvThreadState {
    WORKING,
    STOP,
    FINISHED,
};

struct CTXstate {
    /* context id */
    int id;

    /* Channel used to communicate from GPU to CPU receiving thread */
    ChannelDev* channel_dev;
    ChannelHost channel_host;

    // After initialization, set it to WORKING to make recv thread get data,
    // parent thread sets it to STOP to make recv thread stop working.
    // recv thread sets it to FINISHED when it cleans up.
    // parent thread should wait until the state becomes FINISHED to clean up.
    volatile RecvThreadState recv_thread_done = RecvThreadState::STOP;
};

/* lock */
pthread_mutex_t mutex;
pthread_mutex_t cuda_event_mutex;

/* map to store context state */
std::unordered_map<CUcontext, CTXstate*> ctx_state_map;

/* skip flag used to avoid re-entry on the nvbit_callback when issuing
 * flush_channel kernel call */
bool skip_callback_flag = false;

/* global control variables for this tool */
uint32_t instr_begin_interval = 0;
uint32_t instr_end_interval = UINT32_MAX;
int verbose = 1;

/* opcode to id map and reverse map  */
std::map<std::string, int> opcode_to_id_map;
std::map<int, std::string> id_to_opcode_map;

/* grid launch id, incremented at every launch */
uint64_t grid_launch_id = 0;

void* recv_thread_fun(void* args);

void nvbit_at_init() {
    setenv("CUDA_MANAGED_FORCE_DEVICE_ALLOC", "1", 1);
    GET_VAR_INT(
        instr_begin_interval, "INSTR_BEGIN", 0,
        "Beginning of the instruction interval where to apply instrumentation");
    GET_VAR_INT(
        instr_end_interval, "INSTR_END", UINT32_MAX,
        "End of the instruction interval where to apply instrumentation");
    GET_VAR_INT(verbose, "TOOL_VERBOSE", 0, "Enable verbosity inside the tool");
    std::string pad(100, '-');
    printf("%s\n", pad.c_str());

    /* set mutex as recursive */
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&mutex, &attr);

    pthread_mutex_init(&cuda_event_mutex, &attr);
}

/* Set used to avoid re-instrumenting the same functions multiple times */
std::unordered_set<CUfunction> already_instrumented;

void instrument_function_if_needed(CUcontext ctx, CUfunction func) {
    assert(ctx_state_map.find(ctx) != ctx_state_map.end());
    CTXstate* ctx_state = ctx_state_map[ctx];

    /* Get related functions of the kernel (device function that can be
     * called by the kernel) */
    std::vector<CUfunction> related_functions =
        nvbit_get_related_functions(ctx, func);

    /* add kernel itself to the related function vector */
    related_functions.push_back(func);

    /* iterate on function */
    for (auto f : related_functions) {
        /* "recording" function was instrumented, if set insertion failed
         * we have already encountered this function */
        if (!already_instrumented.insert(f).second) {
            continue;
        }

        /* get vector of instructions of function "f" */
        const std::vector<Instr*>& instrs = nvbit_get_instrs(ctx, f);

        if (verbose) {
            printf(
                "MEMTRACE: CTX %p, Inspecting CUfunction %p name %s at address "
                "0x%lx\n",
                ctx, f, nvbit_get_func_name(ctx, f), nvbit_get_func_addr(f));
        }

        uint32_t cnt = 0;
        /* iterate on all the static instructions in the function */
        for (auto instr : instrs) {
            if (cnt < instr_begin_interval || cnt >= instr_end_interval ||
                instr->getMemorySpace() == InstrType::MemorySpace::NONE ||
                instr->getMemorySpace() == InstrType::MemorySpace::CONSTANT) {
                cnt++;
                continue;
            }
            if (verbose) {
                instr->print();
            }

            if (opcode_to_id_map.find(instr->getOpcode()) ==
                opcode_to_id_map.end()) {
                int opcode_id = opcode_to_id_map.size();
                opcode_to_id_map[instr->getOpcode()] = opcode_id;
                id_to_opcode_map[opcode_id] = std::string(instr->getOpcode());
            }

            int mem_type = (int)instr->getMemorySpace();
            int is_read = instr->isLoad() ? 1 : 0;
            int is_write = instr->isStore() ? 1 : 0;
            int size = instr->getSize();


            int opcode_id = opcode_to_id_map[instr->getOpcode()];
            int mref_idx = 0;
            /* iterate on the operands */
            for (int i = 0; i < instr->getNumOperands(); i++) {
                /* get the operand "i" */
                const InstrType::operand_t* op = instr->getOperand(i);

                if (op->type == InstrType::OperandType::MREF) {
                    /* insert call to the instrumentation function with its
                     * arguments */
                    nvbit_insert_call(instr, "instrument_mem", IPOINT_BEFORE);
                    /* predicate value */
                    nvbit_add_call_arg_guard_pred_val(instr);
                    /* opcode id */
                    nvbit_add_call_arg_const_val32(instr, opcode_id);
                    /* memory type */
                    nvbit_add_call_arg_const_val32(instr, mem_type);
                    /* size */
                    nvbit_add_call_arg_const_val32(instr, size);
                    /* is read */
                    nvbit_add_call_arg_const_val32(instr, is_read);
                    /* is write */
                    nvbit_add_call_arg_const_val32(instr, is_write);
                    /* memory reference 64 bit address */
                    nvbit_add_call_arg_mref_addr64(instr, mref_idx);
                    /* add "space" for kernel function pointer that will be set
                     * at launch time (64 bit value at offset 0 of the dynamic
                     * arguments)*/
                    nvbit_add_call_arg_launch_val64(instr, 0);
                    /* add pointer to channel_dev*/
                    nvbit_add_call_arg_const_val64(
                        instr, (uint64_t)ctx_state->channel_dev);
                    mref_idx++;
                }
            }
            cnt++;
        }
    }
}

/* flush channel */
__global__ void flush_channel(ChannelDev* ch_dev) { ch_dev->flush(); }

void init_context_state(CUcontext ctx) {
    CTXstate* ctx_state = ctx_state_map[ctx];
    ctx_state->recv_thread_done = RecvThreadState::WORKING;
    skip_callback_flag = true;
    cudaMallocManaged(&ctx_state->channel_dev, sizeof(ChannelDev));
    ctx_state->channel_host.init((int)ctx_state_map.size() - 1, CHANNEL_SIZE,
                                 ctx_state->channel_dev, recv_thread_fun, ctx);
    skip_callback_flag = false;
    nvbit_set_tool_pthread(ctx_state->channel_host.get_thread());
}

void nvbit_at_cuda_event(CUcontext ctx, int is_exit, nvbit_api_cuda_t cbid,
                         const char* name, void* params, CUresult* pStatus) {
    pthread_mutex_lock(&cuda_event_mutex);

    /* we prevent re-entry on this callback when issuing CUDA functions inside
     * this function */
    if (skip_callback_flag) {
        pthread_mutex_unlock(&cuda_event_mutex);
        return;
    }
    skip_callback_flag = true;

    if (cbid == API_CUDA_cuLaunchKernel_ptsz ||
        cbid == API_CUDA_cuLaunchKernel ||
        cbid == API_CUDA_cuLaunchCooperativeKernel ||
        cbid == API_CUDA_cuLaunchCooperativeKernel_ptsz ||
        cbid == API_CUDA_cuLaunchKernelEx ||
        cbid == API_CUDA_cuLaunchKernelEx_ptsz) {
        CTXstate* ctx_state = ctx_state_map[ctx];

        CUfunction func;
        if (cbid == API_CUDA_cuLaunchKernelEx_ptsz ||
            cbid == API_CUDA_cuLaunchKernelEx) {
            cuLaunchKernelEx_params* p = (cuLaunchKernelEx_params*)params;
            func = p->f;
        } else {
            cuLaunchKernel_params* p = (cuLaunchKernel_params*)params;
            func = p->f;
        }

        if (!is_exit) {
            /* Make sure GPU is idle */
            cudaDeviceSynchronize();
            assert(cudaGetLastError() == cudaSuccess);

            /* instrument */
            instrument_function_if_needed(ctx, func);

            int nregs = 0;
            CUDA_SAFECALL(
                cuFuncGetAttribute(&nregs, CU_FUNC_ATTRIBUTE_NUM_REGS, func));

            int shmem_static_nbytes = 0;
            CUDA_SAFECALL(
                cuFuncGetAttribute(&shmem_static_nbytes,
                                   CU_FUNC_ATTRIBUTE_SHARED_SIZE_BYTES, func));

            /* get function name and pc */
            const char* func_name = nvbit_get_func_name(ctx, func);
            uint64_t pc = nvbit_get_func_addr(func);

            /* set grid launch id at launch time */
            nvbit_set_at_launch(ctx, func, (uint64_t)&grid_launch_id);

            /* enable instrumented code to run */
            nvbit_enable_instrumented(ctx, func, true);

            yosemite_kernel_start_callback(func_name, grid_launch_id);

            if (cbid == API_CUDA_cuLaunchKernelEx_ptsz ||
                cbid == API_CUDA_cuLaunchKernelEx) {
                cuLaunchKernelEx_params* p = (cuLaunchKernelEx_params*)params;
                printf(
                    "LAUNCH KERNEL: %s - grid launch id %ld\n"
                    " - grid size (%d,%d,%d) - block size (%d,%d,%d) - nregs %d - shmem %d\n"
                    " - CTX 0x%016lx - stream id %ld - Kernel pc 0x%016lx\n",
                    func_name, grid_launch_id, 
                    p->config->gridDimX, p->config->gridDimY, p->config->gridDimZ,
                    p->config->blockDimX, p->config->blockDimY, p->config->blockDimZ,
                    nregs, shmem_static_nbytes + p->config->sharedMemBytes,
                    (uint64_t)ctx, (uint64_t)p->config->hStream, pc);
                fflush(stdout);
            } else {
                cuLaunchKernel_params* p = (cuLaunchKernel_params*)params;
                printf(
                    "LAUNCH KERNEL: %s - grid launch id %ld\n"
                    " - grid size (%d,%d,%d) - block size (%d,%d,%d) - nregs %d - shmem %d\n"
                    " - CTX 0x%016lx - stream id %ld - Kernel pc 0x%016lx\n",
                    func_name, grid_launch_id, 
                    p->gridDimX, p->gridDimY, p->gridDimZ,
                    p->blockDimX, p->blockDimY, p->blockDimZ,
                    nregs, shmem_static_nbytes + p->sharedMemBytes,
                    (uint64_t)ctx, (uint64_t)p->hStream, pc);
                fflush(stdout);
            }

        } else {
            // make sure user kernel finishes to avoid deadlock
            cudaDeviceSynchronize();
            /* push a flush channel kernel */
            flush_channel<<<1, 1>>>(ctx_state->channel_dev);

            /* Make sure GPU is idle */
            cudaDeviceSynchronize();
            assert(cudaGetLastError() == cudaSuccess);

            /* increment grid launch id for next launch */
            grid_launch_id++;
        }
    } else if (cbid == API_CUDA_cuMemAlloc ||
               cbid == API_CUDA_cuMemAlloc_v2 ||
               cbid == API_CUDA_cuMemAllocManaged ||
               cbid == API_CUDA_cuMemHostAlloc ||
               cbid == API_CUDA_cuMemHostAlloc_v2 ||
               cbid == API_CUDA_cuMemAllocHost ||
               cbid == API_CUDA_cuMemAllocHost_v2 ||
               cbid == API_CUDA_cuMemAllocAsync) {
        if (!is_exit) {
            skip_callback_flag = false;
            pthread_mutex_unlock(&cuda_event_mutex);
            return;
        }
        printf("ALLOC EVENT: %s - ", name);
        if (cbid == API_CUDA_cuMemAlloc) {
            cuMemAlloc_params* p = (cuMemAlloc_params*)params;
            printf("ptr %p, size %u\n", p->dptr, p->bytesize);
            yosemite_alloc_callback((CUdeviceptr)p->dptr, p->bytesize, API_CUDA_cuMemAlloc);
        } else if (cbid == API_CUDA_cuMemAlloc_v2) {    // cudaMalloc
            cuMemAlloc_v2_params* p = (cuMemAlloc_v2_params*)params;
            printf("ptr %llu, size %lu\n", *((unsigned long long*)p->dptr), p->bytesize);
            yosemite_alloc_callback(*(p->dptr), p->bytesize, API_CUDA_cuMemAlloc_v2);
        } else if (cbid == API_CUDA_cuMemAllocManaged) {    // cudaMallocManaged
            cuMemAllocManaged_params* p = (cuMemAllocManaged_params*)params;
            printf("ptr %p, flag %d, size %ld\n", p->dptr, p->flags, p->bytesize);
            yosemite_alloc_callback(*(p->dptr), p->bytesize, API_CUDA_cuMemAllocManaged);
        } else if (cbid == API_CUDA_cuMemHostAlloc || cbid == API_CUDA_cuMemHostAlloc_v2) {
            cuMemHostAlloc_params* p = (cuMemHostAlloc_params*)params;
            printf("ptr %p, flag %d, size %ld\n", p->pp, p->Flags, p->bytesize);
        } else if (cbid == API_CUDA_cuMemAllocAsync) {
            cuMemAllocAsync_params* p = (cuMemAllocAsync_params*)params;
            printf("ptr %p, size %ld\n", p->dptr, p->bytesize);
            yosemite_alloc_callback(*(p->dptr), p->bytesize, API_CUDA_cuMemAllocAsync);
        } else if (cbid == API_CUDA_cuMemAllocHost) {
            cuMemAllocHost_params* p = (cuMemAllocHost_params*)params;
            printf("ptr %p, size %u\n", p->pp, p->bytesize);
            yosemite_alloc_callback((CUdeviceptr)p->pp, p->bytesize, API_CUDA_cuMemAllocHost);
        } else if (cbid == API_CUDA_cuMemAllocHost_v2) {
            cuMemAllocHost_v2_params* p = (cuMemAllocHost_v2_params*)params;
            printf("ptr %p, size %ld\n", p->pp, p->bytesize);
            yosemite_alloc_callback((CUdeviceptr)p->pp, p->bytesize, API_CUDA_cuMemAllocHost_v2);
        } else {
            printf("Not supported\n");
        }
        fflush(stdout);
    } else if (cbid == API_CUDA_cuMemFree ||
               cbid == API_CUDA_cuMemFree_v2 ||
               cbid == API_CUDA_cuMemFreeHost ||
               cbid == API_CUDA_cuMemFreeAsync) {
        if (is_exit) {
            skip_callback_flag = false;
            pthread_mutex_unlock(&cuda_event_mutex);
            return;
        }

        printf("FREE EVENT: %s - ", name);
        if (cbid == API_CUDA_cuMemFree) {
            cuMemFree_params* p = (cuMemFree_params*)params;
            printf("ptr %u\n", p->dptr);
            yosemite_free_callback(p->dptr);
        } else if (cbid == API_CUDA_cuMemFree_v2) {   // cudaFree
            cuMemFree_v2_params* p = (cuMemFree_v2_params*)params;
            printf("v2 ptr %llu\n", p->dptr);
            yosemite_free_callback(p->dptr);
        } else if (cbid == API_CUDA_cuMemFreeHost) {
            cuMemFreeHost_params* p = (cuMemFreeHost_params*)params;
            printf("ptr %p\n", p->p);
            yosemite_free_callback((CUdeviceptr)p->p);
        } else if (cbid == API_CUDA_cuMemFreeAsync) {
            cuMemFreeAsync_params* p = (cuMemFreeAsync_params*)params;
            printf("ptr %llu\n", p->dptr);
            yosemite_free_callback(p->dptr);
        } else {
            printf("Not supported\n");
        }
        fflush(stdout);
    }

    skip_callback_flag = false;
    pthread_mutex_unlock(&cuda_event_mutex);
}

void* recv_thread_fun(void* args) {
    CUcontext ctx = (CUcontext)args;

    pthread_mutex_lock(&mutex);
    /* get context state from map */
    assert(ctx_state_map.find(ctx) != ctx_state_map.end());
    CTXstate* ctx_state = ctx_state_map[ctx];

    ChannelHost* ch_host = &ctx_state->channel_host;
    pthread_mutex_unlock(&mutex);
    char* recv_buffer = (char*)malloc(CHANNEL_SIZE);

    while (ctx_state->recv_thread_done == RecvThreadState::WORKING) {
        /* receive buffer from channel */
        uint32_t num_recv_bytes = ch_host->recv(recv_buffer, CHANNEL_SIZE);
        if (num_recv_bytes > 0) {
            uint32_t num_processed_bytes = 0;
            while (num_processed_bytes < num_recv_bytes) {
                mem_access_t* ma =
                    (mem_access_t*)&recv_buffer[num_processed_bytes];

                yosemite_memory_trace_analysis(ma);
                /*
                std::stringstream ss;
                ss << "CTX " << HEX(ctx) << " - grid_launch_id "
                   << ma->grid_launch_id << " - CTA " << ma->cta_id_x << ","
                   << ma->cta_id_y << "," << ma->cta_id_z << " - warp "
                   << ma->warp_id << " - " << id_to_opcode_map[ma->opcode_id] << " - "
                   << (ma->is_read ? "READ" : "WRITE") << " - "
                   << "size " << ma->size << " - "
                   << "mem_type " << (int)ma->mem_type
                   << " - addrs: ";


                for (int i = 0; i < 32; i++) {
                    ss << HEX(ma->addrs[i]) << " ";
                }
                printf("MEMTRACE: %s\n", ss.str().c_str());
                */

                num_processed_bytes += sizeof(mem_access_t);
            }
        }
    }
    free(recv_buffer);
    ctx_state->recv_thread_done = RecvThreadState::FINISHED;
    return NULL;
}

void nvbit_at_ctx_init(CUcontext ctx) {
    pthread_mutex_lock(&mutex);
    if (verbose) {
        printf("MEMTRACE: STARTING CONTEXT %p\n", ctx);
    }
    assert(ctx_state_map.find(ctx) == ctx_state_map.end());
    CTXstate* ctx_state = new CTXstate;
    ctx_state_map[ctx] = ctx_state;
    pthread_mutex_unlock(&mutex);
}

void nvbit_tool_init(CUcontext ctx) {
    pthread_mutex_lock(&mutex);
    assert(ctx_state_map.find(ctx) != ctx_state_map.end());
    init_context_state(ctx);
    pthread_mutex_unlock(&mutex);
}

void nvbit_at_ctx_term(CUcontext ctx) {
    pthread_mutex_lock(&mutex);
    skip_callback_flag = true;
    if (verbose) {
        printf("MEMTRACE: TERMINATING CONTEXT %p\n", ctx);
    }
    /* get context state from map */
    assert(ctx_state_map.find(ctx) != ctx_state_map.end());
    CTXstate* ctx_state = ctx_state_map[ctx];

    /* Notify receiver thread and wait for receiver thread to
     * notify back */
    ctx_state->recv_thread_done = RecvThreadState::STOP;
    while (ctx_state->recv_thread_done != RecvThreadState::FINISHED)
        ;

    yosemite_kernel_end_callback();

    ctx_state->channel_host.destroy(false);
    cudaFree(ctx_state->channel_dev);
    skip_callback_flag = false;
    delete ctx_state;
    pthread_mutex_unlock(&mutex);
}

void nvbit_at_term() {
}
