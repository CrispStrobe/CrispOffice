// Quds Office Arabic morphology adapter (MIT). The analyzer itself is the
// pinned CrispEmbed native Camel Morph port (crispembed_ar_morph_* C ABI,
// MIT, see ../../licenses); this file only adds buffers for callers without a
// C allocator of their own (Dart FFI on every platform, including Windows
// where the process CRT is not reachable) and an adapter version.
#include <cstddef>
#include <cstdint>
#include <new>

#if defined(_WIN32)
#define QUDS_EXPORT extern "C" __declspec(dllexport)
#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#define QUDS_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE __attribute__((visibility("default")))
#else
#define QUDS_EXPORT extern "C" __attribute__((visibility("default")))
#endif

QUDS_EXPORT std::uint32_t quds_arabic_morph_adapter_version() { return 1; }

QUDS_EXPORT void * quds_arabic_morph_alloc(std::size_t bytes) {
    return bytes == 0 || bytes > (1u << 20) ? nullptr : ::operator new(bytes, std::nothrow);
}

QUDS_EXPORT void quds_arabic_morph_free(void * pointer) { ::operator delete(pointer); }
