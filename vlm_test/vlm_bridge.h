#ifndef VLM_BRIDGE_H
#define VLM_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*vlm_token_callback)(const char* token, void* user_data);

int vlm_create_context(const char* model_path, const char* mmproj_path, void** out_ctx);
int vlm_run(void* ctx, const char* prompt, const char* image_path, vlm_token_callback callback, void* user_data);
void vlm_destroy_context(void* ctx);
const char* vlm_last_error_message(void* ctx);

#ifdef __cplusplus
}
#endif

#endif
