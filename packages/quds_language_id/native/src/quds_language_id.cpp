// Quds Office language identification: a small C ABI over CrispASR's CLD3
// runtime (crisp_lid/src/lid_cld3.cpp, compiled unchanged from a pinned
// commit). The model bytes come from the host (the app's bundled,
// SHA-256-verified cld3-f16.gguf); nothing is read from or sent to the
// network. MIT, part of quds_language_id.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "gguf_shim.h"
#include "lid_cld3.h"

#if defined(_WIN32)
#define QUDS_LID_API extern "C" __declspec(dllexport)
#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#define QUDS_LID_API extern "C" EMSCRIPTEN_KEEPALIVE
#else
#define QUDS_LID_API extern "C" __attribute__((visibility("default")))
#endif

namespace {

// Texts longer than this are cut (at a UTF-8 boundary) before
// classification: CLD3's n-gram features saturate long before, and the cap
// keeps one call well under a millisecond.
constexpr size_t kMaxTextBytes = 4096;

void set_error(char* error, size_t capacity, const char* message) {
    if (!error || capacity == 0) return;
    std::snprintf(error, capacity, "%s", message);
}

} // namespace

QUDS_LID_API uint32_t quds_language_id_abi_version() { return 1; }

QUDS_LID_API void* quds_language_id_alloc(size_t bytes) { return std::malloc(bytes ? bytes : 1); }

QUDS_LID_API void quds_language_id_free_buffer(void* pointer) { std::free(pointer); }

// Opens the CLD3 model from `model` (`size` bytes of GGUF). Returns null on
// failure with a message in `error`.
QUDS_LID_API void* quds_language_id_open(const uint8_t* model, size_t size, char* error, size_t error_capacity) {
    if (!model || size == 0) {
        set_error(error, error_capacity, "no model bytes");
        return nullptr;
    }
    quds_gguf_set_memory(model, size);
    lid_cld3_context* ctx = lid_cld3_init_from_file(quds_gguf_memory_path, 1);
    quds_gguf_set_memory(nullptr, 0);
    if (!ctx) {
        set_error(error, error_capacity, "the CLD3 model could not be loaded");
        return nullptr;
    }
    if (lid_cld3_n_labels(ctx) != 109) {
        lid_cld3_free(ctx);
        set_error(error, error_capacity, "unexpected CLD3 label count");
        return nullptr;
    }
    return ctx;
}

QUDS_LID_API void quds_language_id_close(void* handle) { lid_cld3_free(static_cast<lid_cld3_context*>(handle)); }

// Classifies `length` bytes of UTF-8 `text` and writes up to `k` results as
// lines "<label> <probability>\n" (probability with 6 decimals, labels in
// CLD3's own codes such as "iw" or "zh-Latn") into `out` (NUL-terminated).
// Returns the number of results, 0 for text without letters, or -1 on error.
QUDS_LID_API int quds_language_id_detect(void* handle, const uint8_t* text, size_t length, int k, char* out,
                                         size_t out_capacity) {
    if (!handle || (!text && length) || k <= 0 || k > 16 || !out || out_capacity == 0) return -1;
    out[0] = 0;
    if (length > kMaxTextBytes) {
        length = kMaxTextBytes;
        while (length > 0 && (text[length] & 0xC0) == 0x80) --length;
    }
    // CLD3 has no answer for text without letters; its fallback classifies
    // the raw bytes, which only yields noise.
    bool has_letter = false;
    for (size_t i = 0; i < length && !has_letter; ++i) {
        const uint8_t b = text[i];
        has_letter = b >= 0x80 || (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z');
    }
    if (!has_letter) return 0;
    std::string input(reinterpret_cast<const char*>(text), length);
    const char* labels[16];
    float scores[16];
    const int n = lid_cld3_predict_topk(static_cast<lid_cld3_context*>(handle), input.c_str(), k, labels, scores);
    if (n <= 0) return n == 0 ? 0 : -1;
    size_t used = 0;
    for (int i = 0; i < n; ++i) {
        const int written = std::snprintf(out + used, out_capacity - used, "%s %.6f\n", labels[i], scores[i]);
        if (written < 0 || static_cast<size_t>(written) >= out_capacity - used) return -1;
        used += static_cast<size_t>(written);
    }
    return n;
}
