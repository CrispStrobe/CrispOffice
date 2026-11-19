// Test-only C ABI implementation. Its counters observe native allocations
// across the host and classifier isolate, so disposal regressions are visible.
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <thread>

#if defined(_WIN32)
#define API extern "C" __declspec(dllexport)
#else
#define API extern "C" __attribute__((visibility("default")))
#endif

namespace {
std::atomic<int> handles{0};
std::atomic<int> buffers{0};
std::atomic<int> allocations_before_failure{-1};
std::atomic<int> delay_ms{0};
std::atomic<int> active_calls{0};
}

API uint32_t quds_language_id_abi_version() { return 1; }
API int quds_language_id_test_handles() { return handles.load(); }
API int quds_language_id_test_buffers() { return buffers.load(); }
API int quds_language_id_test_active_calls() { return active_calls.load(); }
API void quds_language_id_test_fail_after(int count) { allocations_before_failure = count; }
API void quds_language_id_test_delay(int milliseconds) { delay_ms = milliseconds; }

API void* quds_language_id_alloc(size_t size) {
    if (allocations_before_failure >= 0 && allocations_before_failure.fetch_sub(1) == 0) return nullptr;
    void* result = std::malloc(size ? size : 1);
    if (result) ++buffers;
    return result;
}

API void quds_language_id_free_buffer(void* pointer) {
    if (!pointer) return;
    --buffers;
    std::free(pointer);
}

API void* quds_language_id_open(const uint8_t*, size_t, char*, size_t) {
    void* result = std::malloc(1);
    if (result) ++handles;
    return result;
}

API void quds_language_id_close(void* handle) {
    if (!handle) return;
    --handles;
    std::free(handle);
}

API int quds_language_id_detect(void* handle, const uint8_t*, size_t, int, char* out, size_t capacity) {
    if (!handle) return -1;
    ++active_calls;
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms.load()));
    const int written = std::snprintf(out, capacity, "en 0.950000\n");
    --active_calls;
    return written > 0 && static_cast<size_t>(written) < capacity ? 1 : -1;
}
