// Quds Office Hunspell adapter (MIT). Links the unmodified Hunspell 1.7.2
// library sources, used under their MPL 1.1 option (see ../../licenses).
//
// C ABI, version 1. All strings are UTF-8. A handle owns one dictionary and a
// result buffer; callers serialize use of a handle.
#include <cstddef>
#include <cstdint>
#include <exception>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include "hunspell.hxx"

namespace {
struct Handle {
    std::unique_ptr<Hunspell> engine;
    std::string buffer;
};
constexpr std::size_t max_word_bytes = 400;
constexpr std::size_t max_suggestions = 32;
}  // namespace

#if defined(_WIN32)
#define QUDS_EXPORT extern "C" __declspec(dllexport)
#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#define QUDS_EXPORT extern "C" EMSCRIPTEN_KEEPALIVE __attribute__((visibility("default")))
#else
#define QUDS_EXPORT extern "C" __attribute__((visibility("default")))
#endif

QUDS_EXPORT std::uint32_t quds_hunspell_abi_version() { return 1; }

// Buffers for callers without a C allocator of their own (Dart FFI on every
// platform, including Windows where the process CRT is not reachable).
QUDS_EXPORT void * quds_hunspell_alloc(std::size_t bytes) {
    return bytes == 0 || bytes > (1u << 20) ? nullptr : ::operator new(bytes, std::nothrow);
}
QUDS_EXPORT void quds_hunspell_free(void * pointer) { ::operator delete(pointer); }

// Opens an .aff/.dic pair. Only UTF-8 dictionaries are admitted, so word
// strings never need re-encoding. Returns null on any failure.
QUDS_EXPORT void * quds_hunspell_open(const char * aff_path, const char * dic_path) {
    if (!aff_path || !dic_path) return nullptr;
    try {
        auto handle = std::make_unique<Handle>();
        handle->engine = std::make_unique<Hunspell>(aff_path, dic_path);
        if (handle->engine->get_dict_encoding() != "UTF-8") return nullptr;
        return handle.release();
    } catch (...) {
        return nullptr;
    }
}

QUDS_EXPORT void quds_hunspell_close(void * handle) { delete static_cast<Handle *>(handle); }

// 1 = correct, 0 = misspelled, -1 = invalid input or engine failure.
QUDS_EXPORT int quds_hunspell_spell(void * handle, const char * word) {
    if (!handle || !word) return -1;
    try {
        const std::string text(word);
        if (text.empty() || text.size() > max_word_bytes) return -1;
        return static_cast<Handle *>(handle)->engine->spell(text) ? 1 : 0;
    } catch (...) {
        return -1;
    }
}

// Suggestions in Hunspell's order, joined by '\n', in the handle's buffer
// (valid until the next call on this handle). Null on failure; *length = 0
// for no suggestions.
QUDS_EXPORT const char * quds_hunspell_suggest(void * handle, const char * word, std::size_t * length) {
    if (!handle || !word || !length) return nullptr;
    auto * h = static_cast<Handle *>(handle);
    try {
        const std::string text(word);
        if (text.empty() || text.size() > max_word_bytes) return nullptr;
        const auto list = h->engine->suggest(text);
        h->buffer.clear();
        for (std::size_t i = 0; i < list.size() && i < max_suggestions; ++i) {
            if (i) h->buffer += '\n';
            h->buffer += list[i];
        }
        *length = h->buffer.size();
        return h->buffer.c_str();
    } catch (...) {
        return nullptr;
    }
}
