# Scripts

このリポジトリは、モデル本体を Git に含めず、ユーザーが Hugging Face などから取得したファイルを iPhone の Files アプリ経由でインポートする前提です。

使えるモデルの条件:
- `llama.cpp` 互換のメイン `GGUF`
- 画像入力が必要な場合は対応する `mmproj`
- モデル固有の追加前処理を要求しないこと

既知モデル以外でも、アプリの `Import Custom GGUF/mmproj from Files` から読み込めます。
ただし「どのモデルでも必ず動く」わけではありません。`GGUF + mmproj` であっても、`llama.cpp` 側がそのアーキテクチャやマルチモーダル実装を未対応なら動作しません。

## 1) モデル取得の補助
```bash
cd /Users/tasuku/Desktop/vlm_test
bash scripts/download_models.sh
```

任意で GGUF も同時取得:
```bash
cd /Users/tasuku/Desktop/vlm_test
QWEN_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF bash scripts/download_models.sh
```

Qwen3.5-VL-0.8B 用 GGUF + mmproj も取得する場合:
```bash
cd /Users/tasuku/Desktop/vlm_test
QWEN_VL_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF bash scripts/download_models.sh
```

注意:
- これらのダウンロード先 `Models/` はローカル作業用です。Git 管理対象ではありません。
- 実機では、必要ファイルを Files アプリに保存してから、アプリ内の `Import Required Files from Files` で取り込みます。
- 未登録モデルは `Import Custom GGUF/mmproj from Files` を使います。

## 2) CoreML 変換 PoC（任意）
```bash
python3 scripts/coreml_convert_poc.py \
  --model-dir /Users/tasuku/Desktop/vlm_test/Models/moondream2 \
  --out /Users/tasuku/Desktop/vlm_test/Models/moondream2/moondream2_text_poc.mlpackage
```

## 3) llama.cpp iOS native ライブラリを再生成
前提:
```bash
cd /Users/tasuku/Desktop/vlm_test
git clone https://github.com/ggml-org/llama.cpp third_party/llama.cpp
```

その後:
```bash
cd /Users/tasuku/Desktop/vlm_test
bash scripts/build_llama_ios_libs.sh
```

出力先:
- `/Users/tasuku/Desktop/vlm_test/vlm_test/vendor/llama/iphonesimulator/libllama.a`
- `/Users/tasuku/Desktop/vlm_test/vlm_test/vendor/llama/iphoneos/libllama.a`

## 4) moondream2 テキストモデルを量子化（Q4_K_M）
前提:
```bash
cd /Users/tasuku/Desktop/vlm_test
git clone https://github.com/ggml-org/llama.cpp third_party/llama.cpp
```

その後:
```bash
cd /Users/tasuku/Desktop/vlm_test
bash scripts/quantize_moondream2.sh
```

出力先(既定):
- `/Users/tasuku/Desktop/vlm_test/Models/moondream2/moondream2-text-model-q4_k_m.gguf`

注意:
- `coreml_convert_poc.py` は「まず変換できるか」を確認するための PoC です。
- VLM 全体（画像入力含む）をそのまま CoreML 化できることは保証しません。
- native bridge は `mmproj` があるモデルで画像入力を処理します（`libmtmd` 経由）。

ベンチマーク記録テンプレート:
- `/Users/tasuku/Desktop/vlm_test/docs/benchmark_template.md`
- `/Users/tasuku/Desktop/vlm_test/docs/benchmark_results_template.csv`
