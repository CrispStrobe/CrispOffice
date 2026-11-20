// Quds Office Arabic morphology adapter (MIT). The analyzer itself is the
// pinned CrispEmbed native Camel Morph port (crispembed_ar_morph_* C ABI,
// MIT, see ../../licenses); this file only adds buffers for callers without a
// C allocator of their own (Dart FFI on every platform, including Windows
// where the process CRT is not reachable), an adapter version, and the
// switch for CrispEmbed's default-off context disambiguator.
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <new>

#if defined(_WIN32)
#define QUDS_EXPORT extern "C" __declspec(dllexport)
#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#define QUDS_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE __attribute__((visibility("default")))
#else
#define QUDS_EXPORT extern "C" __attribute__((visibility("default")))
#endif

// Version 2 adds quds_arabic_morph_enable_disambiguation.
QUDS_EXPORT std::uint32_t quds_arabic_morph_adapter_version() { return 2; }

QUDS_EXPORT void * quds_arabic_morph_alloc(std::size_t bytes) {
    return bytes == 0 || bytes > (1u << 20) ? nullptr : ::operator new(bytes, std::nothrow);
}

QUDS_EXPORT void quds_arabic_morph_free(void * pointer) { ::operator delete(pointer); }

// CrispEmbed's context disambiguator is gated default-off by the
// CRISPEMBED_AR_MORPH_DISAMBIG environment variable. The host calls this
// before opening a model it chose to use; an existing value (for example an
// operator's CRISPEMBED_AR_MORPH_DISAMBIG=0) is kept. Returns 1 when the
// variable is set afterwards.
QUDS_EXPORT std::int32_t quds_arabic_morph_enable_disambiguation() {
#if defined(_WIN32)
    std::size_t length = 0;
    if (getenv_s(&length, nullptr, 0, "CRISPEMBED_AR_MORPH_DISAMBIG") == 0 && length == 0)
        _putenv_s("CRISPEMBED_AR_MORPH_DISAMBIG", "1");
#else
    setenv("CRISPEMBED_AR_MORPH_DISAMBIG", "1", 0);
#endif
    return std::getenv("CRISPEMBED_AR_MORPH_DISAMBIG") != nullptr ? 1 : 0;
}
