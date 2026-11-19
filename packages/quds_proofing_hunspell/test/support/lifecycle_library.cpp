// Counter-only C ABI fixture for the native Dart transport lifecycle tests.
// Build separately; this is never linked into the production Hunspell library.
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <new>
#include <thread>

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
std::atomic<std::size_t> live{0}, opens{0}, closes{0};
std::atomic<std::size_t> active_open{0}, active_spell{0};
std::atomic<std::uint32_t> open_delay{0}, spell_delay{0};
}

EXPORT std::size_t quds_hunspell_test_live() { return live.load(); }
EXPORT std::size_t quds_hunspell_test_opens() { return opens.load(); }
EXPORT std::size_t quds_hunspell_test_closes() { return closes.load(); }
EXPORT std::size_t quds_hunspell_test_active_open() { return active_open.load(); }
EXPORT std::size_t quds_hunspell_test_active_spell() { return active_spell.load(); }
EXPORT void quds_hunspell_test_delays(std::uint32_t opening, std::uint32_t spelling) {
    open_delay = opening;
    spell_delay = spelling;
}

EXPORT std::uint32_t quds_hunspell_abi_version() { return 1; }
EXPORT void * quds_hunspell_alloc(std::size_t size) { return ::operator new(size, std::nothrow); }
EXPORT void quds_hunspell_free(void * pointer) { ::operator delete(pointer); }

EXPORT void * quds_hunspell_open(const char *, const char *) {
    auto * handle = new int(1);
    ++live;
    ++opens;
    ++active_open;
    std::this_thread::sleep_for(std::chrono::milliseconds(open_delay.load()));
    --active_open;
    return handle;
}

EXPORT void quds_hunspell_close(void * handle) {
    if (!handle) return;
    delete static_cast<int *>(handle);
    --live;
    ++closes;
}

EXPORT int quds_hunspell_spell(void *, const char *) {
    ++active_spell;
    std::this_thread::sleep_for(std::chrono::milliseconds(spell_delay.load()));
    --active_spell;
    return 1;
}

EXPORT const char * quds_hunspell_suggest(void *, const char *, std::size_t * length) {
    *length = 0;
    return "";
}
