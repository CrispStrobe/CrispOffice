// Minimal stand-in for the metadata part of gguf.h used by CrispASR's
// lid_cld3.cpp (see ggml.h in this directory). MIT, part of quds_language_id.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ggml.h"

#ifdef __cplusplus
extern "C" {
#endif

struct gguf_context;

struct gguf_init_params {
    bool no_alloc;
    struct ggml_context** ctx;
};

struct gguf_context* gguf_init_from_file(const char* path, struct gguf_init_params params);
void gguf_free(struct gguf_context* ctx);
int64_t gguf_find_key(const struct gguf_context* ctx, const char* key);
size_t gguf_get_arr_n(const struct gguf_context* ctx, int64_t key_id);
const char* gguf_get_arr_str(const struct gguf_context* ctx, int64_t key_id, size_t i);
const char* gguf_get_val_str(const struct gguf_context* ctx, int64_t key_id);

#ifdef __cplusplus
}
#endif
