# On-device VLM Test

`llama.cpp` ベースのローカル GGUF モデルを iPhone 上で試すための Xcode プロジェクトです。画像を Files アプリから選ぶか、その場でカメラ撮影して、端末内で画像理解を実行できます。

## 今回入っている主な内容

- Gemma 4 E2B-It (`GGUF + mmproj`) の既知モデル対応
- Files アプリからのモデル取り込み改善
  - モデルごとの保存先フォルダにコピー
  - `mmproj-F16.gguf` のような同名ファイルでも混同しにくい構成
  - 未インストール時の参照用 URL 表示
- `llama.cpp` を更新し、Gemma 4 系アーキテクチャに対応
- カメラ撮影からそのまま画像説明を実行する導線を追加
- プロンプトを「画像説明向け」の安定しやすい既定文面に変更

## 対応モデルの例

- Qwen3.5-0.8B (GGUF)
- Qwen3.5-VL-0.8B (GGUF + mmproj)
- moondream2
- Gemma 4 E2B-It (GGUF + mmproj)

注意:
- VLM は通常 `main GGUF` に加えて `mmproj` が必要です。
- Gemma 4 E2B-It は Qwen3.5-VL-0.8B よりかなり重いです。

## 基本的な使い方

1. Hugging Face などから必要な `GGUF` と `mmproj` を iPhone の Files アプリに保存します。
2. アプリで `Use App Documents/Models` を選びます。
3. 既知モデルなら `Import Required Files from Files`、未登録モデルなら `Import Custom GGUF/mmproj from Files` を使います。
4. `Target` でモデルを選び、画像を `Pick Image` または `Take Photo` で指定します。
5. `Describe Image` を押すか、そのまま `Run Test` を実行します。

既定プロンプトは画像説明専用です。`improve this image` のような曖昧な命令より、説明タスクとして安定しやすくしてあります。

## Gemma 4 E2B-It の目安

最初は次の組み合わせが無難です。

- `gemma-4-E2B-it-Q4_K_M.gguf`
- `mmproj-F16.gguf`

参照:
- [Gemma 4 E2B-It GGUF (unsloth)](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF)

## 開発メモ

- iOS 用 `llama.cpp` ライブラリの再生成や補助スクリプトは [scripts/README.md](/Users/tasuku/Desktop/vlm_test/scripts/README.md) を参照してください。
