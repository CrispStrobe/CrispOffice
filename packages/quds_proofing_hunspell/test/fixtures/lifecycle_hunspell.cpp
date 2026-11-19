// Deterministic C ABI fixture for the real native Dart transport lifecycle.
// It records ownership and can hold one native call until the test releases it.
#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_set>

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
struct Handle {};
std::mutex mutex;
std::condition_variable released;
std::unordered_set<Handle*> handles;
int opens = 0;
int closes = 0;
int calls = 0;
int invalid = 0;
bool blocking = false;
std::atomic<int> fail_allocations{0};
}

EXPORT std::uint32_t quds_hunspell_abi_version() { return 1; }
EXPORT void* quds_hunspell_alloc(std::size_t size) {
    if (fail_allocations.load() > 0) {
        --fail_allocations;
        return nullptr;
    }
    return std::malloc(size);
}
EXPORT void quds_hunspell_free(void* pointer) { std::free(pointer); }
EXPORT void* quds_hunspell_open(const char* aff, const char*) {
    if (std::strstr(aff, "reject-open.aff") != nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(mutex);
    auto* handle = new Handle();
    handles.insert(handle);
    ++opens;
    return handle;
}
EXPORT void quds_hunspell_close(void* pointer) {
    std::lock_guard<std::mutex> lock(mutex);
    auto* handle = static_cast<Handle*>(pointer);
    if (handles.erase(handle) != 1) {
        ++invalid;
        return;
    }
    ++closes;
    delete handle;
}
EXPORT int quds_hunspell_spell(void* pointer, const char*) {
    std::unique_lock<std::mutex> lock(mutex);
    auto* handle = static_cast<Handle*>(pointer);
    if (handles.count(handle) != 1) {
        ++invalid;
        return -1;
    }
    ++calls;
    released.wait(lock, [] { return !blocking; });
    if (handles.count(handle) != 1) {
        ++invalid;
        return -1;
    }
    return 1;
}
EXPORT const char* quds_hunspell_suggest(void*, const char*, std::size_t* size) {
    *size = 0;
    return "";
}

// 0=open calls; 1=closed handles; 2=live handles; 3=spell entries;
// 4=double-close or use-after-close attempts.
EXPORT int lifecycle_counter(int index) {
    std::lock_guard<std::mutex> lock(mutex);
    switch (index) {
        case 0: return opens;
        case 1: return closes;
        case 2: return static_cast<int>(handles.size());
        case 3: return calls;
        case 4: return invalid;
        default: return -1;
    }
}
EXPORT void lifecycle_block(int value) {
    std::lock_guard<std::mutex> lock(mutex);
    blocking = value != 0;
    released.notify_all();
}
EXPORT void lifecycle_fail_allocations(int count) { fail_allocations = count; }
EXPORT int lifecycle_reset() {
    std::lock_guard<std::mutex> lock(mutex);
    if (!handles.empty()) return -1;
    opens = closes = calls = invalid = 0;
    blocking = false;
    fail_allocations = 0;
    return 0;
}
