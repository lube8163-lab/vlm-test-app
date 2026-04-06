#include "vlm_bridge.h"

#include "llama.h"
#include "mtmd-helper.h"
#include "mtmd.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct vlm_context {
    struct llama_model * model;
    struct llama_context * lctx;
    mtmd_context * mctx;
    const struct llama_vocab * vocab;
    struct llama_sampler * sampler;
    char last_error[512];
    int32_t n_ctx;
} vlm_context;

static char g_last_error[512];

static const int32_t k_default_n_ctx = 1024;
static const int32_t k_default_n_batch = 256;
static const int32_t k_default_n_threads = 4;
static const int32_t k_max_first_token_eog_retries = 8;
static const int32_t k_min_generated_tokens = 24;

static void set_error(vlm_context * ctx, const char * msg) {
    if (msg == NULL) {
        msg = "unknown error";
    }
    snprintf(g_last_error, sizeof(g_last_error), "%s", msg);
    if (ctx == NULL) {
        return;
    }
    snprintf(ctx->last_error, sizeof(ctx->last_error), "%s", msg);
}

static void batch_clear(struct llama_batch * batch) {
    batch->n_tokens = 0;
}

static void batch_add(struct llama_batch * batch, llama_token id, llama_pos pos, bool logits) {
    const int i = batch->n_tokens;
    batch->token[i] = id;
    batch->pos[i] = pos;
    batch->n_seq_id[i] = 1;
    batch->seq_id[i][0] = 0;
    batch->logits[i] = logits ? 1 : 0;
    batch->n_tokens += 1;
}

static int tokenize_prompt(
    const struct llama_vocab * vocab,
    const char * prompt,
    llama_token ** out_tokens,
    int32_t * out_n_tokens,
    vlm_context * ctx
) {
    const int32_t prompt_len = (int32_t)strlen(prompt);
    int32_t cap = prompt_len + 32;
    if (cap < 64) {
        cap = 64;
    }

    llama_token * tokens = (llama_token *)malloc(sizeof(llama_token) * (size_t)cap);
    if (tokens == NULL) {
        set_error(ctx, "failed to allocate token buffer");
        return -1;
    }

    int32_t n = llama_tokenize(vocab, prompt, prompt_len, tokens, cap, true, true);
    if (n < 0) {
        cap = -n;
        llama_token * bigger = (llama_token *)realloc(tokens, sizeof(llama_token) * (size_t)cap);
        if (bigger == NULL) {
            free(tokens);
            set_error(ctx, "failed to resize token buffer");
            return -1;
        }
        tokens = bigger;
        n = llama_tokenize(vocab, prompt, prompt_len, tokens, cap, true, true);
    }

    if (n <= 0) {
        free(tokens);
        set_error(ctx, "tokenization failed");
        return -1;
    }

    *out_tokens = tokens;
    *out_n_tokens = n;
    return 0;
}

static bool has_non_empty(const char * s) {
    return s != NULL && s[0] != '\0';
}

static int build_mm_prompt(const char * prompt, char ** out_prompt, vlm_context * ctx) {
    const char * marker = mtmd_default_marker();
    if (strstr(prompt, marker) != NULL) {
        *out_prompt = strdup(prompt);
    } else {
        const size_t marker_len = strlen(marker);
        const size_t prompt_len = strlen(prompt);
        const size_t total = marker_len + prompt_len + 1;
        char * buf = (char *)malloc(total);
        if (buf == NULL) {
            set_error(ctx, "failed to allocate multimodal prompt buffer");
            return -1;
        }
        memcpy(buf, marker, marker_len);
        memcpy(buf + marker_len, prompt, prompt_len + 1);
        *out_prompt = buf;
    }

    if (*out_prompt == NULL) {
        set_error(ctx, "failed to build multimodal prompt");
        return -1;
    }

    return 0;
}

int vlm_create_context(const char * model_path, const char * mmproj_path, void ** out_ctx) {
    if (model_path == NULL || out_ctx == NULL) {
        return -1;
    }

    *out_ctx = NULL;
    g_last_error[0] = '\0';

    vlm_context * ctx = (vlm_context *)calloc(1, sizeof(vlm_context));
    if (ctx == NULL) {
        return -2;
    }

    llama_backend_init();

    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = -1;

    ctx->model = llama_model_load_from_file(model_path, mparams);
    if (ctx->model == NULL) {
        set_error(ctx, "failed to load model file. This app's bundled llama.cpp likely does not support this model architecture yet (for example: gemma4).");
        vlm_destroy_context(ctx);
        return -3;
    }

    struct llama_context_params cparams = llama_context_default_params();
    ctx->n_ctx = k_default_n_ctx;
    cparams.n_ctx = (uint32_t)ctx->n_ctx;
    cparams.n_batch = k_default_n_batch;
    cparams.n_ubatch = k_default_n_batch;
    cparams.n_threads = k_default_n_threads;
    cparams.n_threads_batch = k_default_n_threads;

    ctx->lctx = llama_init_from_model(ctx->model, cparams);
    if (ctx->lctx == NULL) {
        set_error(ctx, "failed to create llama context");
        vlm_destroy_context(ctx);
        return -4;
    }

    ctx->vocab = llama_model_get_vocab(ctx->model);
    if (ctx->vocab == NULL) {
        set_error(ctx, "failed to get vocabulary");
        vlm_destroy_context(ctx);
        return -5;
    }

    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    ctx->sampler = llama_sampler_chain_init(sparams);
    if (ctx->sampler == NULL) {
        set_error(ctx, "failed to create sampler chain");
        vlm_destroy_context(ctx);
        return -6;
    }

    // Keep benchmark runs stable enough for comparison while preserving fluency.
    llama_sampler_chain_add(ctx->sampler, llama_sampler_init_top_k(20));
    llama_sampler_chain_add(ctx->sampler, llama_sampler_init_top_p(0.90f, 1));
    llama_sampler_chain_add(ctx->sampler, llama_sampler_init_temp(0.2f));
    llama_sampler_chain_add(ctx->sampler, llama_sampler_init_dist(42));

    if (has_non_empty(mmproj_path)) {
        struct mtmd_context_params mmparams = mtmd_context_params_default();
        mmparams.use_gpu = true;
        mmparams.n_threads = k_default_n_threads;
        mmparams.warmup = false;
        mmparams.image_max_tokens = 576;
        ctx->mctx = mtmd_init_from_file(mmproj_path, ctx->model, mmparams);
        if (ctx->mctx == NULL) {
            set_error(ctx, "failed to initialize mtmd context from mmproj");
            vlm_destroy_context(ctx);
            return -7;
        }
    }

    *out_ctx = ctx;
    return 0;
}

int vlm_run(void * raw_ctx, const char * prompt, const char * image_path, vlm_token_callback callback, void * user_data) {
    vlm_context * ctx = (vlm_context *)raw_ctx;
    if (ctx == NULL || ctx->lctx == NULL || ctx->model == NULL) {
        return -1;
    }

    if (prompt == NULL || prompt[0] == '\0') {
        set_error(ctx, "prompt is empty");
        return -2;
    }

    // Each run in this app is independent. Clear KV/memory so retries can reuse the same context safely.
    llama_memory_t mem = llama_get_memory(ctx->lctx);
    if (mem != NULL) {
        llama_memory_clear(mem, true);
    }

    struct llama_batch batch = llama_batch_init(1024, 0, 1);
    if (batch.token == NULL) {
        set_error(ctx, "failed to allocate llama batch");
        return -3;
    }

    llama_pos n_cur = 0;
    int rc = 0;

    if (has_non_empty(image_path)) {
        if (ctx->mctx == NULL) {
            llama_batch_free(batch);
            set_error(ctx, "image was provided but mmproj is not configured");
            return -4;
        }

        mtmd_bitmap * bitmap = mtmd_helper_bitmap_init_from_file(ctx->mctx, image_path);
        if (bitmap == NULL) {
            llama_batch_free(batch);
            set_error(ctx, "failed to load image file for mtmd");
            return -5;
        }

        char * prompt_mm = NULL;
        if (build_mm_prompt(prompt, &prompt_mm, ctx) != 0) {
            mtmd_bitmap_free(bitmap);
            llama_batch_free(batch);
            return -6;
        }

        mtmd_input_chunks * chunks = mtmd_input_chunks_init();
        if (chunks == NULL) {
            free(prompt_mm);
            mtmd_bitmap_free(bitmap);
            llama_batch_free(batch);
            set_error(ctx, "failed to allocate mtmd input chunks");
            return -7;
        }

        mtmd_input_text input_text = {
            .text = prompt_mm,
            .add_special = true,
            .parse_special = true,
        };

        const mtmd_bitmap * bitmaps[1] = { bitmap };
        const int32_t tok_res = mtmd_tokenize(ctx->mctx, chunks, &input_text, bitmaps, 1);
        if (tok_res != 0) {
            mtmd_input_chunks_free(chunks);
            free(prompt_mm);
            mtmd_bitmap_free(bitmap);
            llama_batch_free(batch);
            set_error(ctx, "mtmd_tokenize failed");
            return -8;
        }

        llama_pos new_n_past = 0;
        const int32_t eval_res = mtmd_helper_eval_chunks(
            ctx->mctx,
            ctx->lctx,
            chunks,
            0,
            0,
            k_default_n_batch,
            true,
            &new_n_past
        );
        mtmd_input_chunks_free(chunks);
        free(prompt_mm);
        mtmd_bitmap_free(bitmap);
        if (eval_res != 0) {
            llama_batch_free(batch);
            set_error(ctx, "mtmd_helper_eval_chunks failed");
            return -9;
        }
        n_cur = new_n_past;
    } else {
        llama_token * tokens = NULL;
        int32_t n_prompt_tokens = 0;
        if (tokenize_prompt(ctx->vocab, prompt, &tokens, &n_prompt_tokens, ctx) != 0) {
            llama_batch_free(batch);
            return -10;
        }

        batch_clear(&batch);
        for (int i = 0; i < n_prompt_tokens; i++) {
            batch_add(&batch, tokens[i], i, false);
        }
        batch.logits[batch.n_tokens - 1] = 1;

        rc = llama_decode(ctx->lctx, batch);
        free(tokens);
        if (rc != 0) {
            llama_batch_free(batch);
            set_error(ctx, "llama_decode failed on prompt");
            return -11;
        }
        n_cur = n_prompt_tokens;
    }

    llama_sampler_reset(ctx->sampler);
    const int32_t n_predict = 128;

    int32_t n_generated = 0;
    for (int32_t i = 0; i < n_predict; i++) {
        llama_token token = llama_sampler_sample(ctx->sampler, ctx->lctx, -1);

        if (llama_vocab_is_eog(ctx->vocab, token)) {
            if (i == 0) {
                bool found_non_eog = false;
                for (int32_t r = 0; r < k_max_first_token_eog_retries; r++) {
                    token = llama_sampler_sample(ctx->sampler, ctx->lctx, -1);
                    if (!llama_vocab_is_eog(ctx->vocab, token)) {
                        found_non_eog = true;
                        break;
                    }
                }
                if (!found_non_eog) {
                    break;
                }
            } else if (n_generated < k_min_generated_tokens) {
                bool found_non_eog = false;
                for (int32_t r = 0; r < k_max_first_token_eog_retries; r++) {
                    token = llama_sampler_sample(ctx->sampler, ctx->lctx, -1);
                    if (!llama_vocab_is_eog(ctx->vocab, token)) {
                        found_non_eog = true;
                        break;
                    }
                }
                if (!found_non_eog) {
                    break;
                }
            } else {
                break;
            }
        }
        llama_sampler_accept(ctx->sampler, token);

        char piece[1024] = {0};
        int32_t n_piece = llama_token_to_piece(ctx->vocab, token, piece, (int32_t)sizeof(piece), 0, true);
        if (n_piece < 0) {
            const int32_t need = -n_piece;
            char * dyn = (char *)malloc((size_t)need + 1);
            if (dyn != NULL) {
                n_piece = llama_token_to_piece(ctx->vocab, token, dyn, need, 0, true);
                if (n_piece > 0 && callback != NULL) {
                    dyn[n_piece] = '\0';
                    callback(dyn, user_data);
                }
                free(dyn);
            }
        } else if (n_piece > 0 && callback != NULL) {
            piece[n_piece < (int32_t)sizeof(piece) ? n_piece : (int32_t)sizeof(piece) - 1] = '\0';
            callback(piece, user_data);
        }
        n_generated += 1;

        batch_clear(&batch);
        batch_add(&batch, token, n_cur, true);

        n_cur += 1;
        rc = llama_decode(ctx->lctx, batch);
        if (rc != 0) {
            llama_batch_free(batch);
            set_error(ctx, "llama_decode failed during generation");
            return -12;
        }
    }

    if (n_generated == 0) {
        set_error(ctx, "no token generated (first token reached EOG)");
        llama_batch_free(batch);
        return -13;
    }

    llama_batch_free(batch);
    return 0;
}

void vlm_destroy_context(void * raw_ctx) {
    vlm_context * ctx = (vlm_context *)raw_ctx;
    if (ctx == NULL) {
        return;
    }

    if (ctx->sampler != NULL) {
        llama_sampler_free(ctx->sampler);
        ctx->sampler = NULL;
    }

    if (ctx->mctx != NULL) {
        mtmd_free(ctx->mctx);
        ctx->mctx = NULL;
    }

    if (ctx->lctx != NULL) {
        llama_free(ctx->lctx);
        ctx->lctx = NULL;
    }

    if (ctx->model != NULL) {
        llama_model_free(ctx->model);
        ctx->model = NULL;
    }

    llama_backend_free();
    free(ctx);
}

const char * vlm_last_error_message(void * raw_ctx) {
    vlm_context * ctx = (vlm_context *)raw_ctx;
    if (ctx == NULL) {
        if (g_last_error[0] != '\0') {
            return g_last_error;
        }
        return "bridge context is null";
    }

    if (ctx->last_error[0] == '\0') {
        if (g_last_error[0] != '\0') {
            return g_last_error;
        }
        return "unknown bridge error";
    }

    return ctx->last_error;
}
