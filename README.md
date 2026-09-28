# VinylPlayer for iOS

以黑膠唱盤為靈感嘅 iPhone / iPad 音樂播放器，以 SwiftUI 製作，結合專輯收藏、Cover Flow、動態歌詞，以及 Apple Music / Spotify 整合。

本專案仍在開發中。音樂播放及線上內容取決於服務授權、帳戶、訂閱、地區及曲目可用性；repo 不包含音樂檔案或服務憑證。

## 主要功能

- **黑膠播放介面**：唱盤、唱臂、播放進度、不同外觀主題及 App Icon。
- **專輯收藏**：網格、堆疊及 Cover Flow 瀏覽，音樂庫匯入、收藏及播放清單。
- **播放管理**：播放佇列、隨機／重複、鎖定畫面控制、Widget 與 Live Activity。
- **探索及搜尋**：本機收藏搜尋、Apple Music / Spotify 目錄搜尋及根據聆聽記錄產生嘅推薦。
- **歌詞**：逐行及逐字時間資訊、多來源解析、TTML，以及不同歌詞呈現方式。
- **資料補齊**：MusicBrainz / Cover Art Archive 配對，讀取本機專輯資料夾內嘅 metadata、封面及 LRC。
- **日常工具**：JSON 備份與合併還原、睡眠計時器、聆聽統計及分享卡／影片。

## 開發環境

- macOS 與完整 Xcode；目前整理 repo 時使用 **Xcode 27.0**。
- App 及 Widget target 嘅 deployment target 為 **iOS 26.0**；project 層級設定為 26.5，以 target 設定為準。
- Swift、SwiftUI、SwiftData、MusicKit、WidgetKit、ActivityKit。
- Swift Package Manager 依賴由 Xcode 自動解析；已提交 `Package.resolved`：Spotify iOS SDK 1.2.5、ScreenCorners 1.0.1。

## 開始使用

```sh
git clone https://github.com/edward511chung-meow/VinylPlayer_iOS.git
cd VinylPlayer_iOS
open VinylPlayer.xcodeproj
```

1. 等待 Xcode 完成 Swift Package 解析。
2. 選擇 **VinylPlayer** scheme 及支援嘅 iOS Simulator。
3. 按 **Run**。真機安裝需要在 App 與 Widget target 嘅 **Signing & Capabilities** 選擇自己嘅開發團隊，並設定可用嘅 Bundle Identifier。
4. 如更改 App Group，需同步更新兩個 target 嘅 entitlements 及程式內 `group.com.Vinylplayer.shared` 嘅引用，確保 Widget 共用資料正常。

### 音樂服務設定

設定入口位於 [`APIConfig.swift`](VinylPlayer/Networking/APIConfig.swift)。

- **Apple Music**：透過系統授權／MusicKit 存取；請在真機驗證帳戶權限、音樂庫及播放能力。
- **Spotify**：使用自己嘅 Spotify application client ID，並登記 redirect URI `vinylplayer://spotify-callback`。Client ID 是公開應用識別碼；不要將 client secret 或 access / refresh token 提交到 Git。App Remote 功能需要裝有 Spotify 嘅裝置及有效授權。
- **Discogs**：設定預設為空白；目前 request 使用 `personalAccessToken` 作授權。只在本機設定所需 token，commit 前移除實際值。
- **MusicBrainz / Cover Art Archive**：不需要 API key；服務可用性及請求限制仍然適用。

`.gitignore` 會排除常見 secrets 檔案，但不會排除 Swift 原始碼內寫入嘅憑證。

## Build 與驗證

不需要簽署嘅 Simulator build：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project VinylPlayer.xcodeproj \
  -scheme VinylPlayer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/VinylPlayer-DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

現有測試係獨立 Swift harness，並非統一嘅 XCTest suite：

- [歌詞解析與來源選擇測試](Tests/TimedLyrics/README.md)：包含可直接執行嘅離線測試指令。
- [收藏與播放驗證](Docs/LibraryPlaybackVerification.md)
- [首頁、搜尋、備份與睡眠計時驗證](Docs/HomeSearchUtilitiesVerification.md)
- [專輯資料補齊驗證](Docs/AlbumEnrichmentVerification.md)

以上文件記錄功能實作時嘅驗證及限制，並不代表每次 commit 均已重新跑完。

### 不需音樂帳戶嘅 UI Preview

使用 Xcode Preview 開啟 `HomeDesignPreview.swift` 或 `TimedLyricsPreview.swift`。亦可在 scheme 嘅 **Run → Arguments Passed On Launch** 啟用以下其中一項：

```text
--home-design-preview
--library-design-preview
--search-design-preview
--backup-design-preview
--sleep-design-preview
--metadata-design-preview
```

以上 Debug 入口使用隔離嘅 in-memory 資料。實際音樂播放、背景切歌、Widget 控制及服務登入仍需真機與帳戶驗證。

## 目錄

| 路徑 | 內容 |
| --- | --- |
| `VinylPlayer/` | App、SwiftData models、services、SwiftUI views 及素材 |
| `VinylPlayerWidgets/` | Widget、Live Activity 及 playback intents |
| `VinylPlayer.xcodeproj/` | Xcode project、shared schemes 及 dependency lockfile |
| `Tests/` | 獨立測試 harness |
| `Docs/` | 功能驗證記錄及人工檢查步驟 |
| `Design/` | App Icon 設計素材、生成記錄及處理工具 |
| `ThirdParty/` | 第三方聲明及授權全文 |

## 現有限制

- Apple Music 系統播放目前需要能在裝置音樂庫解析嘅曲目；跨服務連續背景播放仍受各服務能力限制。
- 睡眠計時屬 best effort；App 被暫停時，停止播放可能延至恢復執行。
- 備份不包含音樂檔、登入憑證或設定；本機資料夾讀取主要用於補齊現有曲目資料，不會匯入音訊。
- 歌詞、封面及線上目錄可能缺漏或因來源端改動而無法取得。

## 第三方與授權

Lyrimuse 衍生部分嘅來源及修改範圍見 [`ThirdParty/Lyrimuse/NOTICE.md`](ThirdParty/Lyrimuse/NOTICE.md)，並保留其 [GPL-3.0 授權全文](ThirdParty/Lyrimuse/LICENSE)。Spotify iOS SDK 及 ScreenCorners 依各自上游授權提供。

此 repo 未另外指定專案原創部分嘅授權；現有第三方授權仍適用。
