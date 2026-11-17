// SPDX-License-Identifier: MIT
// Evaluation only. In-process ORT C API transport; no daemon or child process.
#include "onnxruntime_c_api.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct { const OrtApi *api; OrtEnv *env; OrtSession *session; OrtMemoryInfo *memory; } Probe;
static int check(const OrtApi *api, OrtStatus *status, char *error, size_t capacity) {
  if (!status) return 0;
  if (capacity) snprintf(error, capacity, "%s", api->GetErrorMessage(status));
  api->ReleaseStatus(status);
  return 1;
}
void quds_ort_close(void *raw) {
  Probe *p = raw;
  if (!p) return;
  if (p->memory) p->api->ReleaseMemoryInfo(p->memory);
  if (p->session) p->api->ReleaseSession(p->session);
  if (p->env) p->api->ReleaseEnv(p->env);
  free(p);
}
void *quds_ort_open(const char *model, char *error, size_t capacity) {
  const OrtApi *api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  if (!api) { if (capacity) snprintf(error, capacity, "Unsupported ORT API"); return NULL; }
  Probe *p = calloc(1, sizeof(Probe));
  if (!p) return NULL;
  p->api = api;
  OrtSessionOptions *options = NULL;
#define OPEN(call) if (check(api, (call), error, capacity)) goto failed
  OPEN(api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "quds-evaluation", &p->env));
  OPEN(api->CreateSessionOptions(&options));
  OPEN(api->SetIntraOpNumThreads(options, 2));
  OPEN(api->SetInterOpNumThreads(options, 1));
  OPEN(api->SetSessionExecutionMode(options, ORT_SEQUENTIAL));
  OPEN(api->DisableCpuMemArena(options));
  OPEN(api->DisableMemPattern(options));
  OPEN(api->CreateSession(p->env, model, options, &p->session));
  OPEN(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &p->memory));
  api->ReleaseSessionOptions(options);
  return p;
failed:
  if (options) api->ReleaseSessionOptions(options);
  quds_ort_close(p);
  return NULL;
#undef OPEN
}

int quds_ort_forward(void *raw, const int64_t *ids, int64_t tokens,
    float *labels, size_t label_count, float *detection, size_t detection_count,
    char *error, size_t capacity) {
  Probe *p = raw;
  if (!p || !ids || !labels || !detection || tokens < 2 || tokens > 512 ||
      label_count != (size_t)tokens * 5000 || detection_count != (size_t)tokens * 2) return 1;
  for (int64_t i = 0; i < tokens; ++i) if (ids[i] < 0 || ids[i] >= 31102) return 1;
  const OrtApi *api = p->api;
  OrtValue *inputs[2] = {NULL, NULL}, *outputs[2] = {NULL, NULL};
  OrtTensorTypeAndShapeInfo *shape_info = NULL;
  int64_t *mask = malloc((size_t)tokens * sizeof(int64_t));
  if (!mask) return 1;
  for (int64_t i = 0; i < tokens; ++i) mask[i] = 1;
  int64_t shape[2] = {1, tokens};
  const char *input_names[2] = {"input_ids", "attention_mask"};
  const char *output_names[2] = {"logits_labels", "logits_d"};
  int failed = 1;
#define RUN(call) if (check(api, (call), error, capacity)) goto cleanup
  RUN(api->CreateTensorWithDataAsOrtValue(p->memory, (void *)ids, (size_t)tokens * 8,
      shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &inputs[0]));
  RUN(api->CreateTensorWithDataAsOrtValue(p->memory, mask, (size_t)tokens * 8,
      shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &inputs[1]));
  RUN(api->Run(p->session, NULL, input_names, (const OrtValue *const *)inputs, 2,
      output_names, 2, outputs));
  // Check both outputs before touching either caller buffer.
  for (int i = 0; i < 2; ++i) {
    size_t count = 0, dimensions = 0;
    ONNXTensorElementDataType type;
    int64_t actual_shape[3];
    RUN(api->GetTensorTypeAndShape(outputs[i], &shape_info));
    RUN(api->GetTensorElementType(shape_info, &type));
    RUN(api->GetTensorShapeElementCount(shape_info, &count));
    RUN(api->GetDimensionsCount(shape_info, &dimensions));
    if (dimensions != 3) goto cleanup;
    RUN(api->GetDimensions(shape_info, actual_shape, 3));
    if (type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || actual_shape[0] != 1 ||
        actual_shape[1] != tokens || actual_shape[2] != (i == 0 ? 5000 : 2) ||
        count != (i == 0 ? label_count : detection_count)) goto cleanup;
    api->ReleaseTensorTypeAndShapeInfo(shape_info); shape_info = NULL;
  }
  void *data[2] = {NULL, NULL};
  RUN(api->GetTensorMutableData(outputs[0], &data[0]));
  RUN(api->GetTensorMutableData(outputs[1], &data[1]));
  memcpy(labels, data[0], label_count * sizeof(float));
  memcpy(detection, data[1], detection_count * sizeof(float));
  failed = 0;
cleanup:
  if (shape_info) api->ReleaseTensorTypeAndShapeInfo(shape_info);
  for (int i = 0; i < 2; ++i) {
    if (inputs[i]) api->ReleaseValue(inputs[i]);
    if (outputs[i]) api->ReleaseValue(outputs[i]);
  }
  free(mask);
  return failed;
#undef RUN
}
