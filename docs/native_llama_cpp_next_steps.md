# Native llama.cpp Integration Next Steps

## Goal
Enable `InferenceRuntime.nativeLlamaCpp` in iOS app for GGUF-based models.

## Current state
- UI and engine routing are implemented.
- Native path currently returns `InferenceError.llamaCppNotLinked`.

## Step plan
1. Add llama.cpp as native dependency (submodule or vendored source).
2. Create a tiny C bridge layer exposing only required functions:
   - init runtime
   - load model (+ mmproj when needed)
   - run prompt + image path
   - stream token callback
   - free runtime
3. Expose C bridge to Swift via bridging header.
4. Replace `runNativeLlamaCpp` implementation to call bridge.
5. Record real metrics:
   - TTFT = first token callback time
   - tokens/sec = generated token count / decode duration
6. Add timeout + cancellation handling.

## Minimal API sketch
```c
// vlm_bridge.h
void* vlm_create_context(const char* model_path, const char* mmproj_path);
int vlm_run(
  void* ctx,
  const char* prompt,
  const char* image_path,
  void (*on_token)(const char* token, void* user_data),
  void* user_data
);
void vlm_destroy_context(void* ctx);
```

## Notes
- Qwen3.5-0.8B GGUF currently covers text-only unless VL-specific GGUF + mmproj pair is prepared.
- moondream2 GGUF has both text model and mmproj artifacts and should be first target.
