// Test-only C ABI shim: native allocation counters make ownership observable.
// No Hunspell dictionary or linguistic behavior is simulated by these tests.
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>
#include <thread>

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
std::atomic<int> live{0};
std::atomic<int> opened{0};
std::atomic<int> closed{0};
}

EXPORT std::uint32_t quds_hunspell_abi_version() { return 1; }
EXPORT void* quds_hunspell_alloc(std::size_t bytes) {
  return ::operator new(bytes, std::nothrow);
}
EXPORT void quds_hunspell_free(void* pointer) { ::operator delete(pointer); }
EXPORT void* quds_hunspell_open(const char*, const char*) {
  auto* handle = new (std::nothrow) int(1);
  if (handle) { ++live; ++opened; }
  return handle;
}
EXPORT void quds_hunspell_close(void* handle) {
  if (!handle) return;
  // A close acknowledgement must wait for actual native cleanup.
  std::this_thread::sleep_for(std::chrono::milliseconds(20));
  delete static_cast<int*>(handle);
  --live;
  ++closed;
}
EXPORT int quds_hunspell_spell(void* handle, const char* word) {
  if (!handle || !word) return -1;
  if (std::strcmp(word, u8"تعليق") == 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
  }
  return 1;
}
EXPORT const char* quds_hunspell_suggest(void*, const char*, std::size_t* length) {
  if (!length) return nullptr;
  *length = 0;
  return "";
}
EXPORT int quds_hunspell_test_live_handles() { return live.load(); }
EXPORT int quds_hunspell_test_opened_handles() { return opened.load(); }
EXPORT int quds_hunspell_test_closed_handles() { return closed.load(); }
