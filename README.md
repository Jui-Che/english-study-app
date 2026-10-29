# 單字學習 (vocab_app)

英文單字查詢、收藏、每組 20 字配對練習。Flutter 開發，支援 Windows / macOS / Android / iOS。

## 開發

```bash
flutter run -d windows   # 執行（按 r 熱重載）
flutter test             # 測試
```

## 迷你模式（Windows）

- 左側導覽列最下方的按鈕：視窗縮小到螢幕右下角、拿掉標題列並固定在所有視窗最上層，以字卡方式複習「我的收藏」。
- 上方列按住可拖曳視窗，右邊只有「離開迷你模式」與「關閉程式」。
- 鍵盤：← → 換字、空白鍵顯示解釋；▶ 自動播放（每 5 秒先顯示解釋、再換下一個）。
- 直接以迷你模式啟動：`vocab_app.exe --mini`（可做成桌面捷徑）。
- 置頂與縮放由 `windows/runner/flutter_window.cpp` 的 `vocab_app/window` channel 處理（不用外掛，因此不需開啟 Windows 開發人員模式）。

## 網頁版

- 網址：<https://jui-che.github.io/english-study-app/>（iPhone 用 Safari 開啟 →「分享」→「加入主畫面」）
- 推到 `main` 後，`.github/workflows/deploy.yml` 會自動測試、建置並部署到 GitHub Pages。
- 網頁版的收藏、待調整、成績存在瀏覽器的 localStorage，與桌面版不同步。

## 字庫

- `assets/words.json`：手動整理的主題單字組（每組 20 字，附例句）。
- `assets/dictionary.tsv.gz`：由 `tool/build_dictionary.dart` 產生的英漢字庫（約 3.7 萬字 + 2 千個片語），不要手動修改。
  - 片語：ECDICT 中有考試標籤、牛津、柯林斯標記的片語，加上在 Tatoeba 日常例句中出現 3 句以上的片語
    （會比對動詞變化與 one's / sb / sth，例如 made up my mind ↔ make up one's mind）。

重新產生字庫：

1. 把下列檔案放到同一個資料夾（例如 `raw/`）：
   - `ecdict.csv`：<https://github.com/skywind3000/ECDICT>
   - `STCharacters.txt`、`STPhrases.txt`、`TWPhrases.txt`、`TWVariants.txt`：<https://github.com/BYVoid/OpenCC/tree/master/data/dictionary>
   - `cmn-eng/cmn.txt`：解壓 <https://www.manythings.org/anki/cmn-eng.zip>
2. 在本資料夾執行：`dart run tool/build_dictionary.dart raw`

收錄規則、繁體轉換的例外字詞都寫在 `tool/build_dictionary.dart` 開頭。

## 修正中文解釋（待調整）

1. 在 App 單字頁點右上角 🚩（或例句下方的「回報需要例句」），勾選要處理的項目（中文解釋／補例句）並寫下備註。
2. 待調整清單存在 `%APPDATA%\vocab_app\user_data.json` 的 `toFix` 欄位；也可以在「收藏 → 待調整 → 複製清單」複製成文字。
3. 修正寫進 `assets/corrections.json`（格式見檔案內的 `_說明`），重新執行 App 即生效；
   填了 meaning／definitions／pos 算處理「中文解釋」，填了 example 算處理「補例句」；
   回報的項目都處理完，待調整清單才會顯示「已修正」，可一鍵清除。
   修正與字典分開存放，重新產生字庫也不會被蓋掉。

## 資料來源與授權

- 字典：[ECDICT](https://github.com/skywind3000/ECDICT)，MIT
- 簡轉繁：[OpenCC](https://github.com/BYVoid/OpenCC)，Apache 2.0
- 例句：[Tatoeba](https://tatoeba.org)，CC-BY 2.0 FR（經 [manythings.org](https://www.manythings.org/anki/) 整理）
