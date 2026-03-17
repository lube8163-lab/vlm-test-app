# On-device VLM テストアプリ方針（2026-03-03）

## 1. ゴール
- 1つのテストUIから複数VLMを切り替え、画像1枚 + テキスト指示で応答品質/速度/メモリを比較する。
- 初期対象:
  - `Qwen/Qwen3.5-0.8B`
  - `vikhyatk/moondream2`

## 2. 結論（先に）
- **Phase 1 は CoreML 変換なし**で進める。
- 理由:
  - Qwen3.5-0.8B は公開直後で、iOS CoreML 向けの安定済み変換レシピがまだ固定化していない。
  - moondream2 も公式配布は Transformers 前提で、CoreML 配布物が標準で同梱されていない。
- まずはモデルDLと推論経路を分離して、変換は Phase 2 で実験する。

## 3. 推奨アーキテクチャ
- UI層: SwiftUI（既存 `vlm_test`）
- 推論層:
  - Qwen: `llama.cpp` 系（Metal/GGUF）を優先
  - moondream2: まずは原本モデル（Python/Transformers）でベンチマーク基準を作る
- 計測層:
  - TTFT（first token）
  - tokens/sec
  - peak memory
  - 画像解像度別の応答差分

## 4. 実装フェーズ
- Phase 1（今やる）
  - モデル取得スクリプトを整備
  - モデル格納規約を固定 (`Models/{model_name}/...`)
  - アプリ側は「モデル切替UI + 入力画像 + プロンプト + 計測表示」を先に実装
- Phase 2
  - moondream2/Qwen の CoreML 変換 PoC
  - unsupported op を洗い出し、分割変換（vision encoder / decoder）を検討
- Phase 3
  - 実運用向け最適化（量子化、解像度戦略、キャッシュ）

## 5. ディレクトリ規約
- `Models/qwen3_5_0_8b/`
- `Models/qwen3_5_0_8b_gguf/`（任意）
- `Models/moondream2/`
- `scripts/download_*.sh`

## 5.1 配布方針
- GitHub リポジトリにはモデル本体を含めない。
- ユーザーは Hugging Face 等から必要な `GGUF + mmproj` を取得する。
- 実機では iPhone の Files アプリに置いたモデルを、アプリ内インポートで `Documents/Models/` にコピーして利用する。
- 既知モデル以外も、`llama.cpp` が対応する形式ならアプリ内で自動検出して候補に追加する。

## 6. 注意点
- ライセンス確認（Qwen系、moondream2 とも配布/組込み条件をリリースごとに確認）。
- iOS 実機ではストレージ圧迫が大きいため、量子化版を優先。
- CoreML 変換はモデル更新で壊れやすいので、変換スクリプトは「再現可能な固定バージョン」を前提にする。
- `GGUF + mmproj` でも必ず動くわけではない。前提は `llama.cpp` 側に当該マルチモーダル実装が入っていること。
