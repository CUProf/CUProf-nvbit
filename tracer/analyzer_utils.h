#ifndef YOSEMITE_ANALYZER_UTILS_H
#define YOSEMITE_ANALYZER_UTILS_H

#include <cstdint>
#include <string>

namespace yosemite {

enum EventType {
    EventType_KERNEL = 0,
    EventType_ALLOC = 1,
    EventType_FREE = 2,
    EventType_COPY = 3,
    EventType_SET = 4,
    EventTypeCount = 5,
};


struct Event
{
    uint64_t timestamp;
    EventType type;

    Event() = default;
    virtual ~Event() = default;

    bool operator<(const Event &other) const { return timestamp < other.timestamp; }
};

typedef struct KernelEvent : public Event {
    uint64_t end_time;
    std::string kernel_name;
    uint64_t grid_id;

    KernelEvent() = default;
    ~KernelEvent() = default;
}KernelEvent_t;

typedef struct AllocEvent : public Event {
    unsigned long long addr;
    uint64_t size;
    uint64_t release_time;
    int alloc_type;

    AllocEvent() = default;
    ~AllocEvent() = default;
}AllocEvent_t;

typedef struct FreeEvent : public Event {
    unsigned long long addr;
    uint64_t size;

    FreeEvent() = default;
    ~FreeEvent() = default;
}FreeEvent_t;

typedef struct MemcpyEvent : public Event {
    uint64_t src_addr;
    uint64_t dst_addr;
    uint64_t size;

    MemcpyEvent() = default;
    ~MemcpyEvent() = default;
}MemcpyEvent_t;

typedef struct MemsetEvent : public Event {

    uint64_t addr;
    uint64_t size;
    uint8_t value;

    MemsetEvent() = default;
    ~MemsetEvent() = default;
}MemsetEvent_t;


typedef struct TraceEntry
{
    uint64_t addr;
    uint64_t page_no;
    uint32_t size;
    uint64_t timestampe;
    uint32_t access_type; // 0: read 1: write
    InstrType::MemorySpace mem_type;

    TraceEntry() = default;

    ~TraceEntry() = default;

    TraceEntry(uint64_t addr, uint32_t size, uint32_t access_type)
        : addr(addr), size(size), access_type(access_type) {
            timestampe = 0;
            page_no = addr >> 12;
    }
}TraceEntry_t;

}   // yosemite

#endif // YOSEMITE_ANALYZER_UTILS_H