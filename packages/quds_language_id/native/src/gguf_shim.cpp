// A bounded GGUF (v2/v3) reader that implements the small ggml/gguf surface
// CrispASR's lid_cld3.cpp uses for loading (see native/shim/). It replaces
// the whole ggml library in this build: CLD3's forward pass is plain C++.
//
// Every length, count, offset and tensor extent is checked against the
// input size before use. Only F32 and F16 tensors are accepted, which is all
// the pinned cld3-f16.gguf contains. MIT, part of quds_language_id.

#include "gguf_shim.h"

#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <string>
#include <vector>

#include "core/gguf_loader.h"
#include "ggml.h"
#include "gguf.h"

namespace {

thread_local const uint8_t* g_memory = nullptr;
thread_local size_t g_memory_size = 0;

constexpr uint64_t kMaxStringBytes = 1u << 20;
constexpr uint64_t kMaxArray = 1u << 20;
constexpr uint64_t kMaxCount = 1u << 16;
constexpr uint64_t kMaxElements = uint64_t(1) << 31;

enum ValueType : uint32_t {
    kU8 = 0, kI8, kU16, kI16, kU32, kI32, kF32, kBool, kString, kArray, kU64, kI64, kF64,
};

struct Kv {
    std::string key;
    uint32_t type = 0;
    uint32_t array_type = 0;
    std::string str;
    std::vector<std::string> strings;
    uint64_t array_n = 0;
    uint64_t uint_value = 0;
};

struct TensorInfo {
    std::string name;
    uint64_t n_elements = 1;
    uint32_t type = 0;
    uint64_t offset = 0;
};

struct Parsed {
    std::vector<Kv> kvs;
    std::vector<TensorInfo> tensors;
    uint64_t data_start = 0;
};

class Reader {
  public:
    Reader(const uint8_t* data, size_t size) : data_(data), size_(size) {}

    bool bytes(void* out, size_t n) {
        if (n > size_ - pos_) return false;
        std::memcpy(out, data_ + pos_, n);
        pos_ += n;
        return true;
    }
    bool skip(uint64_t n) {
        if (n > size_ - pos_) return false;
        pos_ += static_cast<size_t>(n);
        return true;
    }
    template <typename T> bool get(T& out) { return bytes(&out, sizeof(T)); }
    bool string(std::string& out) {
        uint64_t n = 0;
        if (!get(n) || n > kMaxStringBytes || n > size_ - pos_) return false;
        out.assign(reinterpret_cast<const char*>(data_ + pos_), static_cast<size_t>(n));
        pos_ += static_cast<size_t>(n);
        return true;
    }
    size_t pos() const { return pos_; }

  private:
    const uint8_t* data_;
    size_t size_;
    size_t pos_ = 0;
};

uint64_t scalar_size(uint32_t type) {
    switch (type) {
    case kU8: case kI8: case kBool: return 1;
    case kU16: case kI16: return 2;
    case kU32: case kI32: case kF32: return 4;
    case kU64: case kI64: case kF64: return 8;
    default: return 0;
    }
}

bool parse(const uint8_t* data, size_t size, Parsed& out) {
    // Little-endian hosts only (all Quds targets: arm64, x86-64, wasm32).
    Reader r(data, size);
    char magic[4];
    uint32_t version = 0;
    uint64_t n_tensors = 0, n_kv = 0;
    if (!r.bytes(magic, 4) || std::memcmp(magic, "GGUF", 4) != 0) return false;
    if (!r.get(version) || (version != 2 && version != 3)) return false;
    if (!r.get(n_tensors) || !r.get(n_kv) || n_tensors > kMaxCount || n_kv > kMaxCount) return false;
    uint64_t alignment = 32;
    for (uint64_t i = 0; i < n_kv; ++i) {
        Kv kv;
        if (!r.string(kv.key) || !r.get(kv.type)) return false;
        if (kv.type == kString) {
            if (!r.string(kv.str)) return false;
        } else if (kv.type == kArray) {
            if (!r.get(kv.array_type) || !r.get(kv.array_n) || kv.array_n > kMaxArray) return false;
            if (kv.array_type == kString) {
                kv.strings.resize(static_cast<size_t>(kv.array_n));
                for (auto& s : kv.strings)
                    if (!r.string(s)) return false;
            } else {
                const uint64_t width = scalar_size(kv.array_type);
                if (width == 0 || !r.skip(width * kv.array_n)) return false;
            }
        } else {
            const uint64_t width = scalar_size(kv.type);
            if (width == 0) return false;
            uint64_t value = 0;
            if (!r.bytes(&value, static_cast<size_t>(width))) return false;
            kv.uint_value = value;
        }
        if (kv.key == "general.alignment") {
            if (kv.type != kU32 || kv.uint_value == 0 || kv.uint_value > 4096 ||
                (kv.uint_value & (kv.uint_value - 1)) != 0)
                return false;
            alignment = kv.uint_value;
        }
        out.kvs.push_back(std::move(kv));
    }
    for (uint64_t i = 0; i < n_tensors; ++i) {
        TensorInfo t;
        uint32_t n_dims = 0;
        if (!r.string(t.name) || !r.get(n_dims) || n_dims == 0 || n_dims > 4) return false;
        for (uint32_t d = 0; d < n_dims; ++d) {
            uint64_t dim = 0;
            if (!r.get(dim) || dim == 0 || dim > kMaxElements || t.n_elements > kMaxElements / dim) return false;
            t.n_elements *= dim;
        }
        if (!r.get(t.type) || !r.get(t.offset)) return false;
        if (t.type != GGML_TYPE_F32 && t.type != GGML_TYPE_F16) return false;
        out.tensors.push_back(std::move(t));
    }
    const uint64_t pos = r.pos();
    out.data_start = (pos + alignment - 1) / alignment * alignment;
    for (const auto& t : out.tensors) {
        const uint64_t bytes = t.n_elements * (t.type == GGML_TYPE_F32 ? 4 : 2);
        if (out.data_start > size || t.offset > size - out.data_start ||
            bytes > size - out.data_start - t.offset)
            return false;
    }
    return true;
}

bool read_source(const char* path, std::vector<uint8_t>& out) {
    if (path && std::strcmp(path, quds_gguf_memory_path) == 0) {
        if (!g_memory) return false;
        out.assign(g_memory, g_memory + g_memory_size);
        return true;
    }
    if (!path) return false;
    FILE* f = std::fopen(path, "rb");
    if (!f) return false;
    std::vector<uint8_t> data;
    uint8_t chunk[65536];
    size_t n = 0;
    while ((n = std::fread(chunk, 1, sizeof(chunk), f)) > 0) {
        data.insert(data.end(), chunk, chunk + n);
        if (data.size() > (size_t(64) << 20)) {
            std::fclose(f);
            return false;
        }
    }
    std::fclose(f);
    out.swap(data);
    return true;
}

} // namespace

struct gguf_context {
    std::vector<Kv> kvs;
};

struct ggml_context {
    std::vector<uint8_t> bytes;
    std::deque<ggml_tensor> tensors;
};

extern "C" void quds_gguf_set_memory(const uint8_t* data, size_t size) {
    g_memory = data;
    g_memory_size = data ? size : 0;
}

extern "C" int64_t ggml_nelements(const ggml_tensor* tensor) { return tensor ? tensor->n_elements : 0; }

extern "C" float ggml_fp16_to_fp32(ggml_fp16_t h) {
    const uint32_t sign = (h & 0x8000u) << 16;
    uint32_t exponent = (h >> 10) & 0x1Fu;
    uint32_t mantissa = h & 0x3FFu;
    uint32_t bits;
    if (exponent == 0) {
        if (mantissa == 0) {
            bits = sign;
        } else {
            // Subnormal half: normalize.
            exponent = 127 - 15 + 1;
            while ((mantissa & 0x400u) == 0) {
                mantissa <<= 1;
                --exponent;
            }
            mantissa &= 0x3FFu;
            bits = sign | (exponent << 23) | (mantissa << 13);
        }
    } else if (exponent == 0x1F) {
        bits = sign | 0x7F800000u | (mantissa << 13);
    } else {
        bits = sign | ((exponent + 127 - 15) << 23) | (mantissa << 13);
    }
    float out;
    std::memcpy(&out, &bits, sizeof(out));
    return out;
}

extern "C" void ggml_free(ggml_context* ctx) { delete ctx; }

extern "C" ggml_backend_t ggml_backend_init_by_name(const char*, const char*) {
    static int token;
    return reinterpret_cast<ggml_backend_t>(&token);
}

extern "C" void ggml_backend_free(ggml_backend_t) {}

extern "C" gguf_context* gguf_init_from_file(const char* path, gguf_init_params) {
    std::vector<uint8_t> data;
    Parsed parsed;
    if (!read_source(path, data) || !parse(data.data(), data.size(), parsed)) return nullptr;
    auto* ctx = new gguf_context;
    ctx->kvs = std::move(parsed.kvs);
    return ctx;
}

extern "C" void gguf_free(gguf_context* ctx) { delete ctx; }

extern "C" int64_t gguf_find_key(const gguf_context* ctx, const char* key) {
    if (!ctx || !key) return -1;
    for (size_t i = 0; i < ctx->kvs.size(); ++i)
        if (ctx->kvs[i].key == key) return static_cast<int64_t>(i);
    return -1;
}

extern "C" size_t gguf_get_arr_n(const gguf_context* ctx, int64_t id) {
    if (!ctx || id < 0 || static_cast<size_t>(id) >= ctx->kvs.size()) return 0;
    const Kv& kv = ctx->kvs[static_cast<size_t>(id)];
    return kv.type == kArray ? static_cast<size_t>(kv.array_n) : 0;
}

extern "C" const char* gguf_get_arr_str(const gguf_context* ctx, int64_t id, size_t i) {
    if (!ctx || id < 0 || static_cast<size_t>(id) >= ctx->kvs.size()) return "";
    const Kv& kv = ctx->kvs[static_cast<size_t>(id)];
    return i < kv.strings.size() ? kv.strings[i].c_str() : "";
}

extern "C" const char* gguf_get_val_str(const gguf_context* ctx, int64_t id) {
    if (!ctx || id < 0 || static_cast<size_t>(id) >= ctx->kvs.size()) return nullptr;
    const Kv& kv = ctx->kvs[static_cast<size_t>(id)];
    return kv.type == kString ? kv.str.c_str() : nullptr;
}

namespace core_gguf {

bool load_weights(const char* path, ggml_backend_t, const char* tag, WeightLoad& out) {
    auto ctx = std::make_unique<ggml_context>();
    Parsed parsed;
    if (!read_source(path, ctx->bytes) || !parse(ctx->bytes.data(), ctx->bytes.size(), parsed)) {
        std::fprintf(stderr, "%s: invalid or unreadable GGUF\n", tag ? tag : "gguf");
        return false;
    }
    tensor_map tensors;
    for (const auto& info : parsed.tensors) {
        ctx->tensors.push_back({static_cast<ggml_type>(info.type), static_cast<int64_t>(info.n_elements),
                                ctx->bytes.data() + parsed.data_start + info.offset});
        tensors[info.name] = &ctx->tensors.back();
    }
    out.ctx = ctx.release();
    out.buf = nullptr;
    out.tensors = std::move(tensors);
    return true;
}

void release_weight_buffer(ggml_backend_buffer_t) {}

} // namespace core_gguf
