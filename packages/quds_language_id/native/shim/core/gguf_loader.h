// Minimal stand-in for CrispASR's src/core/gguf_loader.h: the weight-loading
// calls lid_cld3.cpp makes. Tensors point into one owned copy of the GGUF
// bytes. MIT, part of quds_language_id.
#pragma once

#include <map>
#include <string>

#include "../ggml.h"
#include "../gguf.h"

namespace core_gguf {

using tensor_map = std::map<std::string, ggml_tensor*>;

struct WeightLoad {
    ggml_context* ctx = nullptr;
    ggml_backend_buffer_t buf = nullptr;
    tensor_map tensors;
};

// Parses the GGUF at `path` (or the in-memory model, see gguf_shim.h) and
// fills `out`. F32 and F16 tensors only. Returns false on any malformed or
// out-of-bounds field.
bool load_weights(const char* path, ggml_backend_t backend, const char* tag, WeightLoad& out);

// The shim never allocates a backend buffer; kept for the call site.
void release_weight_buffer(ggml_backend_buffer_t buf);

} // namespace core_gguf
