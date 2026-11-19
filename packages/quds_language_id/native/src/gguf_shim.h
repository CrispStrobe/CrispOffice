// In-memory model source for the GGUF shim. MIT, part of quds_language_id.
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// While set (on the calling thread), opening this path reads the given
// bytes instead of a file. The bytes must stay alive until the open returns;
// the loader keeps its own copy.
#define quds_gguf_memory_path "<quds-language-id-model>"
void quds_gguf_set_memory(const uint8_t* data, size_t size);

#ifdef __cplusplus
}
#endif
