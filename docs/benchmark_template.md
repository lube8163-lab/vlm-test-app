# On-device VLM Benchmark Template

このテンプレートは、同一条件で `moondream2` と `Qwen3.5-VL-0.8B` を比較するための記録フォーマットです。  
記入先CSV: `/Users/tasuku/Desktop/vlm_test/docs/benchmark_results_template.csv`

## 1) テスト固定条件
- Device: (例) iPhone 16, iOS 26.x
- Build: Debug / Release
- App commit: (git hash)
- Runtime: Native (llama.cpp)
- 画像: 同一画像を固定（例: `desk_setup.png`）
- Prompt: 同一プロンプトを固定
- 最大生成トークン: 現状実装値（128）
- 各ケース試行回数: 3回
- バックグラウンドアプリ: 可能なら最小化
- 端末状態: 充電/非充電、低電力モードON/OFFを記録

## 2) 比較対象（推奨）
- moondream2 F16 + mmproj
- moondream2 Q4_K_M + mmproj
- Qwen3.5-VL-0.8B Q4_K_M + mmproj

## 3) 記録項目
- TTFT (s)
- Tokens/sec
- Elapsed (s)
- Resident RAM (MB)
- 出力品質メモ（日本語指示への追従、幻覚、要約の冗長さ）

## 4) 実行手順（1ケース）
1. アプリで対象モデルを選択
2. 同一画像・同一プロンプトを設定
3. 3回連続で実行
4. `docs/benchmark_results_template.csv` に1行ずつ記録

## 5) 判定の目安（暫定）
- 実用速度: `Tokens/sec >= 8`
- 許容TTFT: `<= 3.0s`
- メモリ警戒: `Resident RAM >= 2800MB`
- 端末安定性: 連続5回でクラッシュなし

## 6) 備考
- Resident RAMは「瞬間スパイク」を取り切れない場合があるため、Xcode Instruments (Memory) でも確認推奨。
- CoreML比較を行う場合は、同一ケースを別列 `runtime=coreml` で追加する。

