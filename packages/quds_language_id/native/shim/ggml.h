// Minimal stand-in for the parts of ggml.h that CrispASR's lid_cld3.cpp
// uses. lid_cld3 runs its forward pass in plain C++ and touches ggml only to
// load the GGUF weights and convert F16 to F32, so Quds does not build ggml:
// this header and gguf_shim.cpp provide exactly that loading surface.
// MIT, part of quds_language_id (not ggml code).
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Same numeric values as ggml's enum for the two types CLD3 ships.
enum ggml_type {
    GGML_TYPE_F32 = 0,
    GGML_TYPE_F16 = 1,
};

typedef uint16_t ggml_fp16_t;

struct ggml_tensor {
    enum ggml_type type;
    int64_t n_elements;
    void* data;
};

struct ggml_context;
struct ggml_backend;
struct ggml_backend_buffer;
typedef struct ggml_backend* ggml_backend_t;
typedef struct ggml_backend_buffer* ggml_backend_buffer_t;

int64_t ggml_nelements(const struct ggml_tensor* tensor);
float ggml_fp16_to_fp32(ggml_fp16_t value);
void ggml_free(struct ggml_context* ctx);

// lid_cld3 asks for a CPU backend only to satisfy the loader's signature;
// no computation runs on it. Returns a non-null token.
ggml_backend_t ggml_backend_init_by_name(const char* name, const char* params);
void ggml_backend_free(ggml_backend_t backend);

#ifdef __cplusplus
}
#endif
