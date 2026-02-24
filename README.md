# zerosky

## 1. 研究背景・目的（Introduction）

### 解決したい課題
本プロジェクトは、IoTデバイス（特にドローン）が生成する位置情報や関連データの信頼性とプライバシー保護という二重の課題を解決することを目的としています。具体的には、以下の問題に取り組んでいます。
*   **位置情報のプライバシー問題:** デバイスが収集した生の位置情報がそのまま公開されることによる個人の行動履歴や機密情報の露呈リスク。
*   **データ信頼性の問題:** 収集された位置情報が改ざんされていないことの検証の難しさ、およびその検証プロセス自体の透明性の確保。
*   **分散型システムにおける検証コスト:** ブロックチェーンのような分散型台帳技術（DLT）にデータを記録する際の高いトランザクションコストとスケーラビリティの限界。

### 背景（社会問題・技術課題）
近年、ドローンやその他のIoTデバイスの普及に伴い、膨大なデータが生成されています。これらのデータ、特に位置情報は、物流、監視、自動運転など多岐にわたる分野で利用される一方で、その正確性やプライバシー保護に関する懸念が高まっています。ゼロ知識証明（ZKP）は、情報の具体的な内容を開示することなく、その情報が真実であることを証明できる革新的な技術であり、この課題に対する強力な解決策として期待されています。

### なぜこのプロジェクトが必要か
本プロジェクトは、ZKP技術をIoTデータ検証に応用することで、以下を実現します。
*   **非公開証明:** ドローンが特定の位置にいたことや、特定の経路をたどったことを、詳細な緯度・経度情報を開示せずに証明する。
*   **改ざん防止:** ブロックチェーン上にZKPを記録することで、データの真正性と非改ざん性を保証する。
*   **効率的な検証:** スマートコントラクト上でZKPを検証することで、複雑なデータ処理をオフチェーンで行いつつ、オンチェーンでの検証コストを削減する。

### 想定ユースケース
*   **ドローンの飛行経路の監査:** 特定のエリアでドローンが飛行したことを第三者に非公開で証明する。
*   **サプライチェーンの透明性確保:** 物流における荷物の位置情報をZKPで証明し、追跡の信頼性を高める。
*   **IoTデバイスの認証:** デバイスが物理的に特定の場所に存在することを証明し、セキュリティを強化する。

## 2. システム概要（Overview / Abstract）

### システムの要約
本システムは、Flutter製のモバイルクライアントアプリケーションとNode.js製のバックエンドサーバーで構成され、ゼロ知識証明（ZKP）技術を用いてIoTデバイス（ドローン）の位置情報の信頼性を検証し、その証明をブロックチェーンに記録するエンドツーエンドのソリューションです。クライアントが取得した位置情報に基づき、サーバーがZKPを生成し、IPFSに保存されたドローンデータと照合しながら、結果をブロックチェーンに永続化します。

### 主な機能
*   **モバイルクライアント（Flutter）:**
    *   カメラによる画像キャプチャ
    *   GPSによる位置情報追跡と履歴管理
    *   Bluetooth LEによるドローンのID検出
    *   取得データに基づくローカルでのPoseidonハッシュ生成と性能評価（ベンチマーク）
    *   セキュリティチェック（Root化検出、開発者モード検出など）
    *   サーバーへのデータ提出
    *   ローカルデータベースへの記録保存と管理
*   **バックエンドサーバー（Node.js）:**
    *   クライアントからのデータ（画像、ハッシュ、ドローンID）受信と保存
    *   IPFSへのデータアップロードと監視（IPNS経由）
    *   Circom回路を用いたZKP（Groth16）の生成
    *   生成されたZKPのブロックチェーン（Ethereum Sepolia）への記録
    *   提出状況の管理とトラッキング

### 技術スタック
*   **UAV:** DJI Matrice 300 RTK + Raspberry Pi 4 (GNSS: ZED-F9P)
*   **Mobile:** Google Pixel 8 (Android 14)
*   **フロントエンド:** Flutter (Dart)
*   **バックエンド:** Node.js, Express.js
*   **ゼロ知識証明:** Circom, `snarkjs` (Groth16)
*   **ブロックチェーン連携:** `ethers.js` (Polygon PoS Amoy Testnet をメインに据えました)
*   **分散ストレージ:** IPFS
*   **データベース:** SQLite (クライアント側), ファイルシステム (サーバー側)
*   **セキュリティ:** `safe_device` (Root化検知) や `flutter_blue_plus` (Remote ID検知) など、論文内で言及されたライブラリ (Flutter)

### 想定ユーザ
*   ドローン運用企業: ドローンの飛行証明や監査を必要とする企業
*   規制当局: ドローンの不正利用防止や飛行経路の検証に関心のある組織
*   ZKP開発者: ZKPの実世界適用に関心のある技術者・研究者
*   プライバシーを重視するユーザー: 自身の位置情報が安全に扱われることを求める個人

## 3. アーキテクチャ設計（Architecture）

### システム構成図
```
+-------------------+           +-------------------+           +-----------------------+
|  Mobile Client    |           |  Backend Server   |           |    Blockchain Network |
| (Flutter App)     |           |  (Node.js/Express)|           |    (Ethereum Sepolia) |
+-------------------+           +-------------------+           +-----------------------+
        |                                 |                                 ^
        | 1. Image/Location/Drone ID      |                                 |
        |    Capture + Hash Generation    |                                 |
        |                                 | 3. Proof Data + Tx              |
        v                                 v                                 |
+-------------------+             +-------------------+             +-----------------------+
| Local Database    |             |  IPFS Gateway     |<------------|  Smart Contract       |
| (SQLite)          |<----------->|  (Data Storage)   |             |  (ZKP Verifier)       |
+-------------------+             +-------------------+             +-----------------------+
        ^                                 ^                                 ^
        |                                 | 2. ZKP Generation + IPFS Update |
        |                                 |                                 |
        |                             +-------------------+                 |
        |                             |  ZKP Circuit      |                 |
        |                             |  (Circom/snarkjs) |                 |
        |                             +-------------------+                 |
        |                                 ^                                 |
        |                                 |                                 |
        +---------------------------------+---------------------------------+
```
<!-- (Note: This is a textual representation. A proper diagram would be an image.) -->

### データフロー
1.  **データ取得 (クライアント: `lib/main.dart`)**: モバイルクライアントは、`_controller.takePicture()` でカメラから画像を撮影し、`_location.onLocationChanged.listen` でGPSから位置情報を取得し、`FlutterBluePlus.scanResults.listen` でBluetooth LE経由で特定のドローンID (`_targetDroneId`) を検出します。
2.  **ローカル処理 (クライアント: `lib/main.dart`)**: 取得した位置情報と撮影時刻に基づき、`_generateAllHashes` 関数内で複数の時間ウィンドウでPoseidonハッシュを生成し、その性能をベンチマークします。結果は `LocalDatabaseHelper.instance.createRecord` でSQLiteに保存されます。
3.  **サーバー提出 (クライアント: `lib/main.dart` -> サーバー: `server.cjs`)**: クライアントは、`_submitApplication` 関数内で画像ファイル (`imageXFile.path`)、ドローンID、生成されたハッシュをバックエンドサーバーの `/submit` エンドポイントに `http.MultipartRequest` を用いて送信します。
4.  **サーバー側データ保存 (サーバー: `server.cjs`)**: サーバーの `/submit` エンドポイントは `multer` ミドルウェアでデータを受信し、`uploads/` ディレクトリに一時保存します。提出状況は `updateSubmissionStatus` 関数で `submission-status.json` に記録されます。
5.  **IPFSへのアップロード (サーバー: `server.cjs`)**: `/submit` エンドポイント内では、受け取った提出ディレクトリ全体が `ipfs.addAll` を用いてIPFSにアップロードされ、そのCIDが `updateSubmissionStatus` で記録されます。
6.  **IPFSウォッチャー (サーバー: `server.cjs`)**: `startIpfsWatcher` 関数により、サーバーは定期的にIPFS/IPNSを監視し、`ipns-names.json` に基づいて特定のドローンIDに関連するデータ更新を検出します。`ipfs/retrieve-data.mjs` スクリプトが外部プロセスとして呼び出されます。
7.  **ZKP生成 (サーバー: `server.cjs`)**: IPFSウォッチャーで更新が検出された場合、`processAllSubmissions` 関数が実行されます。この関数は、IPFSから取得したドローンデータとクライアントから提出されたハッシュ (`user_data.json` から読み込み) を用いて、`prepareInputs` 関数でCircomの入力 (`input.json`) を生成します。その後、`child_process.execSync` を使い、`snarkjs wtns calculate` でWitness (`witness.wtns`) を生成し、`snarkjs groth16 prove` でGroth16証明（`proof.json`, `public.json`）を生成します。
8.  **ブロックチェーン記録 (サーバー: `server.cjs`)**: `processAllSubmissions` 関数内で、生成されたZKPの公開入力と証明（`snarkjs zkey export soliditycalldata` で生成されたcalldata）は、`ethers.js` を用いて、デプロイ済みのスマートコントラクト (`contract.recordProof`) を通じてEthereum Sepoliaブロックチェーンに記録されます。トランザクションハッシュが発行され、提出状況が更新されます。

### コンポーネント説明
*   **Mobile App (Flutter):** `lib/main.dart` をエントリポイントとし、`CameraScreen` (`_CameraScreenState`) でカメラ・GPS・BLEデータ収集、`LocalHistoryScreen` でローカル記録管理、`VerificationScreen` でZKP提出フローのUIを提供します。`LocalDatabaseHelper` クラスがSQLiteデータベースを抽象化します。
*   **Backend Server (Node.js):** `server.cjs` をエントリポイントとし、`express` でAPIエンドポイントを定義します。`multer` でファイルアップロードを処理し、`child_process` を用いて外部のZKPツール (`snarkjs`) を実行します。`ethers.js` (`contract`) を介してブロックチェーンと連携します。
*   **Blockchain (Ethereum Sepolia):** `deployed-address.json` で指定されたアドレスにデプロイされたスマートコントラクト（ABIは `CONTRACT_ABI` 定義）が、`recordProof` 関数を通じてZKPの検証結果を永続的に記録します。
*   **ZKP Circuit (Circom/snarkjs):** サーバー上で `snarkjs` コマンドラインツールによって実行され、`./merkle_js/merkle.wasm` (Witness計算用) および `merkle_final.zkey` (Groth16証明生成用) を利用して、提供された入力が特定の条件を満たすことを証明するゼロ知識証明を生成します。ZKP入力は `prepareInputs` 関数 (`./prepare_inputs.js`) で整形されます。
*   **IPFS (InterPlanetary File System):** `ipfs-http-client` ライブラリを通じてIPFSノードと連携します。`uploads/` ディレクトリの内容をIPFSにアップロードし、`ipns-names.json` と `ipfs/retrieve-data.mjs` を用いて特定のドローンデータの更新を監視します。

## 4. 技術仕様（Technical Details / Method）

### 使用技術
*   **クライアント:**
    *   **Flutter (Dart):** UIフレームワーク。`lib/main.dart` がエントリポイント。
    *   `camera` (`package:camera/camera.dart`): デバイスカメラへのアクセスと画像キャプチャ (`_controller.takePicture()`)。
    *   `location` (`package:location/location.dart`): GPS位置情報のリアルタイム追跡 (`_location.onLocationChanged.listen`)。
    *   `flutter_blue_plus` (`package:flutter_blue_plus/flutter_blue_plus.dart`): Bluetooth LEデバイスのスキャンとドローンIDの検出 (`_startBleScan`)。
    *   `sqflite` (`package:sqflite/sqflite.dart`): ローカルSQLiteデータベースへのデータ保存と読み込み (`LocalDatabaseHelper`)。
    *   `poseidon` (`package:poseidon/poseidon.dart`): ZKPフレンドリーなハッシュ関数。クライアント側で位置データからハッシュを計算 (`poseidon3` 関数)。
    *   `safe_device` (`package:safe_device/safe_device.dart`): デバイスのRoot化/ジェイルブレイクや開発者モードの検出 (`_getDeviceUnsafeIssues`)。
*   **サーバー:**
    *   **Node.js:** ランタイム環境。`server.cjs` がエントリポイント。
    *   `Express.js`: Webアプリケーションフレームワーク。REST APIエンドポイント (`app.post('/submit')` など) の定義。
    *   `multer`: `multipart/form-data` の処理。クライアントからの画像ファイルアップロード (`upload.single('image')`)。
    *   `ethers.js`: Ethereumブロックチェーンとの連携。コントラクトのインスタンス化 (`new ethers.Contract`) とトランザクション送信 (`contract.recordProof`)。
    *   `dotenv`: 環境変数管理。`.env` ファイルからの `SEPOLIA_RPC_URL` や `PRIVATE_KEY` の読み込み。
    *   `ipfs-http-client`: IPFSノードとの連携。ファイルの追加 (`ipfs.addAll`) や監視 (`startIpfsWatcher`)。
    *   `child_process`: 外部コマンドの実行。`snarkjs` コマンドの呼び出し (`execSync`)。
*   **ZKP:**
    *   **Circom:** ZKP回路開発言語。回路は `circom/` ディレクトリに定義され、`merkle_js/merkle.wasm` としてコンパイルされます。
    *   **`snarkjs`:** ZKPプロバー/ベリファイアツール。Groth16実装を用いたWitness生成 (`snarkjs wtns calculate`) と証明生成 (`snarkjs groth16 prove`) に `execSync` で利用されます。
    *   `merkle_js/merkle.wasm`: Circom回路からコンパイルされたWebAssemblyファイル。Witness計算に使用。
    *   `merkle_final.zkey`: Groth16証明生成の際に使用する最終的なZKey（Trusted Setupの成果物）。
*   **データストア:**
    *   クライアント: SQLite (`zkp_verifier_v3.db`)。`LocalDatabaseHelper` クラスで管理。
    *   サーバー: ファイルシステム (`uploads/`, `submission-status.json`, `ipns-names.json`)。`fs` や `fsPromises` モジュールでアクセス。

### API仕様
#### サーバーエンドポイント (`server.cjs` にて定義)
*   **`POST /submit`**
    *   **説明:** クライアントからのZKP生成用データを受け付けます。`server.cjs` の `app.post('/submit', upload.single('image'), ...)` で処理されます。
    *   **形式:** `multipart/form-data`
    *   **リクエストボディ:**
        *   `image`: タイプ `File`。アップロードされた画像ファイル (`req.file` としてアクセス)。
        *   `hash`: タイプ `string`。クライアントで生成されたハッシュ値の改行区切り文字列 (`req.body.hash` としてアクセス)。
        *   `droneId`: タイプ `string`。ドローンID (`req.body.droneId` としてアクセス)。
        *   `captureTime`: タイプ `string`。ISO 8601形式の撮影時刻 (`req.body.captureTime` としてアクセス)。
        *   `durationSeconds`: タイプ `string`。選択された期間 (`req.body.durationSeconds` としてアクセス)。
    *   **レスポンス:** `JSON { message: '申請を受け付けました。', submissionId: <string> }`
    *   **エラーレスポンス:** `status 400` (不正なリクエスト) または `status 500` (サーバーエラー)。
*   **`GET /submission-status/:submissionId`**
    *   **説明:** 特定の `submissionId` の処理ステータスを返します。`server.cjs` の `app.get('/submission-status/:submissionId', ...)` で処理されます。
    *   **形式:** `GET`
    *   **パスパラメータ:** `submissionId` (タイプ `string`)。
    *   **レスポンス:** `JSON { status: <string>, ipfsCid: <string>?, transactionHash: <string>?, blockNumber: <number>?, performance: <object>?, error: <string>?, lastUpdated: <ISO 8601 string> }`
    *   **エラーレスポンス:** `status 404` (指定された申請IDが見つからない)。
*   **`POST /record-on-chain`**
    *   **説明:** サーバーで生成されたZKPをブロックチェーンに記録します。これは `processAllSubmissions` 関数内でスマートコントラクトを直接呼び出すもので、現在の実装ではクライアントから直接呼び出すエンドポイントではありません。
    *   **形式:** `POST` (仮。実質的には内部呼び出し)
    *   **レスポンス:** `JSON { transactionHash: <string> }` (内部処理で利用)
*   **`GET /get-proof-events`**
    *   **説明:** スマートコントラクトから `ProofRecorded` イベントのログを取得し、フォーマットして返します。`server.cjs` の `app.get('/get-proof-events', ...)` で処理されます。
    *   **形式:** `GET`
    *   **レスポンス:** `JSON Array of { transactionHash: <string>, blockNumber: <number>, timestamp: <string>(JST), pubSignals: <string[]> }`
    *   **エラーレスポンス:** `status 500` (ブロックチェーン接続エラーなど)。

### データ構造
*   **`LocalRecord` (クライアント側 - SQLite: `lib/main.dart` の `LocalRecord` クラス):**
    *   クライアントのローカルSQLiteデータベース `zkp_verifier_v3.db` の `records` テーブルに保存されるデータの構造を定義します。
    *   `id`: `int?`。レコードの一意の識別子 (PRIMARY KEY AUTOINCREMENT)。
    *   `captureTime`: `DateTime`。データがキャプチャされた時刻。`capture_time` として `TEXT (ISO 8601)` 形式でDBに保存されます。
    *   `maxDuration`: `int`。ハッシュが生成された最大の期間（秒）。`duration_seconds` として `INTEGER` でDBに保存されます。
    *   `droneId`: `String`。データが関連付けられているドローンのID。`drone_id` として `TEXT` でDBに保存されます。
    *   `imagePath`: `String`。キャプチャされた画像のローカルファイルパス。`image_path` として `TEXT` でDBに保存されます。
    *   `hashesMap`: `Map<int, List<String>>`。期間（秒数）をキーとし、その期間で生成されたハッシュのリストを値とするマップ。`hashes` として `TEXT` (JSON形式) でDBに保存されます。
*   **`ProcessLog` (クライアント側 - UI表示用: `lib/main.dart` の `ProcessLog` クラス):**
    *   `VerificationScreen` でZKP生成・提出プロセスの各ステップのUI表示状態を管理するためのデータ構造です。
    *   `name`: `ProcessName` enum。ステップの種類 (`hashGeneration`, `applicationSubmission`, `chainRecording`)。
    *   `status`: `ProcessStatus` enum。ステップの現在の状態 (`pending`, `inProgress`, `completed`, `error`)。
    *   `duration`: `Duration?`。ステップの処理時間。
    *   `errorMessage`: `String?`。エラーが発生した場合のメッセージ。
    *   `submissionId`: `String?`。提出処理の場合のID。
*   **`submission-status.json` (サーバー側: `server.cjs` で `readStatusFile`/`writeStatusFile` が管理):**
    *   サーバーの `uploads/` ディレクトリに保存される、各提出の処理状況を追跡するためのJSONファイルです。
    *   キー: `submissionId` (`string`)。提出の一意の識別子。
    *   値: `JSON Object`。
        *   `status`: `string`。現在の処理状態（例: `submitted`, `processing`, `proof_generated`, `completed`, `failed`）。
        *   `ipfsCid`: `string?`。提出ディレクトリのIPFS CID。
        *   `transactionHash`: `string?`。ブロックチェーンに記録されたトランザクションのハッシュ。
        *   `blockNumber`: `number?`。トランザクションがマイニングされたブロック番号。
        *   `performance`: `object?`。ブロックチェーン記録時のガス使用量などの性能データ。
        *   `error`: `string?`。エラーメッセージ。
        *   `lastUpdated`: `ISO 8601 string`。最終更新日時。
*   **ZKP入力 (Circom `input.json`):**
    *   `server.cjs` の `processAllSubmissions` 関数内で `prepareInputs` 関数 (`./prepare_inputs.js`) を通じて生成される、Circom回路への入力データです。
    *   `hashes`: クライアントから提出されたハッシュの配列（プライベート入力の一部）。
    *   `droneData`: IPFSから取得したドローンデータ（公開入力の一部）。例: `{ publicKey: "...", sensorData: {...} }`。 (`ipfs/retrieve-data.mjs` および `prepare_inputs.js` で詳細が定義されます)。



### プロトコル設計
1.  **クライアント-サーバー通信:**
    *   **HTTPS:** `lib/main.dart` の `MyHttpOverrides` クラスが、開発環境における自己署名証明書 (`key.pem`, `cert.pem` で `server.cjs` が `https.createServer` で利用) を許容する設定を提供します。これにより、クライアントはサーバーとのセキュアなHTTPS通信を確立します。
    *   **APIリクエスト:** クライアントは `http.MultipartRequest` を使用して `server.cjs` のAPIエンドポイントと通信します。
2.  **ZKP生成プロトコル (Groth16):**
    *   **オーケストレーション:** `server.cjs` の `processAllSubmissions` 関数が、ZKP生成の主要なステップをオーケストレーションします。
    *   **Setup:** `merkle_final.zkey` は、Groth16のTrusted Setupフェーズで生成されたものです。このファイルは `processAllSubmissions` 内の `snarkjs groth16 prove` コマンドで利用されます。
    *   **Witness計算:** `processAllSubmissions` 関数内で、`prepareInputs` 関数 (`./prepare_inputs.js`) によって生成された `input.json` と `merkle_js/merkle.wasm` を用いて、`child_process.execSync(\`snarkjs wtns calculate ...\`)` によりWitness (`witness.wtns`) が計算されます。
    *   **Proof生成:** `processAllSubmissions` 関数内で、`merkle_final.zkey` と `witness.wtns` を用いて、`child_process.execSync(\`snarkjs groth16 prove ...\`)` により証明（`proof.json`）と公開入力（`public.json`）が生成されます。
    *   **Calldata生成:** 生成された `proof.json` と `public.json` から、`child_process.execSync(\`snarkjs zkey export soliditycalldata ...\`)` を用いてスマートコントラクト呼び出し用のcalldataが生成されます。
3.  **ブロックチェーン連携:**
    *   `server.cjs` の `contract` オブジェクトは、`deployed-address.json` のコントラクトアドレスと `CONTRACT_ABI` を用いて `ethers.js` (`ethers.JsonRpcProvider`, `ethers.Wallet`, `ethers.Contract`) で初期化されます。
    *   `processAllSubmissions` 関数内で、生成されたcalldataは `contract.recordProof(pA, pB, pC, pubSignals)` を呼び出すことでEthereum Sepoliaブロックチェーンに送信され、ZKPが記録されます。
    *   イベント監視には `app.get('/get-proof-events')` エンドポイントで `contract.queryFilter('ProofRecorded')` が使用されます。
4.  **IPFS/IPNS:**
    *   `server.cjs` の `startServer` 関数内で `ipfs-http-client` ( `create` および `globSource` ) を用いてIPFSノード (`ipfs`) が初期化されます。
    *   `/submit` エンドポイントでは `ipfs.addAll(globSource(submissionDir, '**/*'), { wrapWithDirectory: true })` を用いて提出ディレクトリがIPFSにアップロードされます。
    *   `startIpfsWatcher` 関数は `ipns-names.json` を参照し、`child_process.exec(\`node ipfs/retrieve-data.mjs ...\`)` を用いて `ipfs/retrieve-data.mjs` スクリプトを実行することでIPNSエントリの更新を監視します。

### アルゴリズム
*   **Poseidon Hash (クライアント側: `lib/main.dart`):**
    *   位置情報データ（緯度、経度、タイムスタンプ）は、`_generateCircularPoints` 関数および `_pointOnBearing` 関数によって、中心点とその周囲の複数の点に変換されます。
    *   単なる距離計算ではなく、GPS誤差を考慮した**「5x5グリッド探索モデル（小数第4位での丸め処理）」**という独自ロジックを適用しています。
    *   これらの各点に対して、`poseidon3([latInt, lonInt, targetTimeInt])` の形式でZKPフレンドリーなPoseidonハッシュ関数が適用され、ハッシュ値が計算されます。
*   **Groth16 (サーバー側: `server.cjs`):**
    *   サーバーの `processAllSubmissions` 関数が、`prepareInputs` (`./prepare_inputs.js`) によって生成された入力と `merkle_js/merkle.wasm` (Witness計算)、`merkle_final.zkey` (証明生成) を用いて、`snarkjs` を介してGroth16プロトコルによるゼロ知識証明を生成します。
    *   具体的なZKP回路ロジックは `circom/merkle.circom`（または関連するCircomファイル）に実装されており、提出されたハッシュとIPFS上のドローンデータとの照合ロジックなどが含まれていると推測されます。

## 5. セットアップ方法（Setup / Installation）

本プロジェクトを実行するには、クライアント（Flutter）とサーバー（Node.js）の両方の環境設定が必要です。

### 必要環境
*   **Flutter SDK:** 最新安定版
*   **Node.js:** v18以上 (LTS推奨)
*   **npm または Yarn:** Node.jsパッケージマネージャー
*   **Git:** ソースコード管理
*   **IPFS Daemon (Optional):** ローカルのIPFSノードと連携する場合
*   **EthereumウォレットとSepoliaテストネットのETH:** ブロックチェーンへのトランザクション発行用

### 依存関係
#### クライアント (Flutter)
`pubspec.yaml` に記載されている依存関係は、`flutter pub get` コマンドで自動的に解決されます。

#### サーバー (Node.js)
`package.json` に記載されている依存関係は、`npm install` または `yarn install` でインストールされます。

### インストール手順
1.  **リポジトリのクローン:**
    ```bash
    git clone [このリポジトリのURL]
    cd poseidon_hash_zkp/poseidon_client
    ```
2.  **クライアントのセットアップ:**
    ```bash
    cd lib
    flutter pub get
    # iOSの場合 (初回のみ)
    # cd ios && pod install && cd ..
    ```
3.  **サーバーのセットアップ:**
    ```bash
    cd server
    npm install # または yarn install
    ```
4.  **ZKP回路のコンパイルとTrusted Setup (開発時のみ):**
    ZKP回路（例: `circom/merkle.circom`）は事前にコンパイルされ、`merkle_js/merkle.wasm` と `merkle_final.zkey` が生成されている必要があります。これらのファイルがない場合、`circom` と `snarkjs` をインストールし、以下の手順を実行します。
    ```bash
    # 例: Circomとsnarkjsのインストール
    # npm install -g circomlibjs snarkjs
    
    # Circom回路のコンパイル
    # circom circom/merkle.circom --wasm --r1cs -o circom/
    # mv circom/merkle_js/merkle.wasm merkle_js/
    
    # Trusted Setup (pot19_final.ptau は別途取得)
    # snarkjs groth16 setup circom/merkle.r1cs pot19_final.ptau merkle_final.zkey
    ```

### 環境変数
サーバーの `server/.env` ファイルを作成し、以下の変数を設定してください。
*   `SEPOLIA_RPC_URL`: SepoliaテストネットのRPCエンドポイントURL (例: Alchemy, Infura)。
*   `PRIVATE_KEY`: Ethereumウォレットの秘密鍵。トランザクションの署名に使用されます。**本番環境では絶対に直接コードに含めないでください。**

## 6. 使用方法（Usage）

### サーバーの起動
プロジェクトのルートディレクトリから以下のコマンドを実行してサーバーを起動します。
```bash
node server.cjs
```
サーバーは `https://localhost:3000` でリッスンを開始します。自己署名証明書を使用しているため、クライアント側でHTTPオーバーライド設定が必要です (例: `lib/main.dart` の `MyHttpOverrides` クラス)。

### クライアントアプリの実行
Flutterプロジェクトのルートディレクトリで以下のコマンドを実行し、アプリをデバイスまたはエミュレータにデプロイします。
```bash
flutter run
```

### デモ手順
1.  **クライアントアプリの起動:** デバイスでアプリを開きます。セキュリティチェックがパスすると、カメラ画面が表示されます。
2.  **ドローンの検出:** アプリはBluetooth LEで特定のドローンID (`_targetDroneId` = `D8:3A:DD:E2:55:36`) を検索します。ドローンが検出されるまで待ちます（表示ステータス: "接続中: D8:3A:DD:E2:55:36"）。
3.  **GPS捕捉:** アプリはGPS位置情報を捕捉します（表示ステータス: "GPS捕捉中..."）。
4.  **写真撮影:** 画面下部のシャッターボタンをタップします。
    <!-- GitHub Markdownではローカル動画の直接埋め込み再生はできません。リンクとして提供します。 -->
    ドローン撮影時の動画: [demo.mp4](assets/demo.mp4)
5.  **性能評価:** アプリは複数の期間（10秒〜60秒）で30回ハッシュ生成を行い、平均処理時間を計測・表示します。この間、"性能評価実行中..."のダイアログが表示されます。
6.  **性能評価レポート:** 性能評価が完了すると、結果がダイアログとして表示されます。CSV形式でコピーするオプションもあります。
7.  **検証画面への遷移:** レポートダイアログで「次へ進む」をタップし、検証画面に進みます。
8.  **証明期間の選択:** 検証画面で、サーバーに提出するハッシュの期間（例: 30秒）を選択します。
9.  **サーバーへ提出:** 「サーバーへ提出」ボタンをタップします。画像と選択された期間のハッシュがサーバーに送信されます。
10. **ブロックチェーン記録:** サーバーでのZKP生成が完了し次第、「ブロックチェーン記録」ボタンが有効になります。これをタップすると、生成されたZKPがEthereum Sepoliaに記録されます。
11. **トランザクション確認:** 記録が完了すると、トランザクションハッシュが表示され、Etherscanで詳細を確認できます。

| | | |
| <img src="assets/safe.jpg" width="200"> | <img src="assets/photo.jpg" width="200"> | <img src="assets/send.jpg" width="200"> |


### API使用例 (サーバー)
サーバーの `/submit` エンドポイントは、`multipart/form-data` 形式でPOSTリクエストを受け付けます。
```javascript
// 例: Node.js fetch API を使用
const FormData = require('form-data');
const fs = require('fs');

const formData = new FormData();
formData.append('image', fs.createReadStream('/path/to/your/image.jpg'));
formData.append('hash', 'hash1\nhash2\nhash3'); // クライアントが生成したハッシュ
formData.append('droneId', 'D8:3A:DD:E2:55:36');
formData.append('captureTime', new Date().toISOString());
formData.append('durationSeconds', '30');

fetch('https://localhost:3000/submit', {
    method: 'POST',
    body: formData,
    // 自己署名証明書の場合、Node.jsで無視する設定が必要になることがあります
    // agent: new (require('https').Agent)({ rejectUnauthorized: false })
})
.then(res => res.json())
.then(data => console.log(data))
.catch(error => console.error(error));
```

## 7. 実験・評価（Evaluation / Benchmark）

### 性能評価
クライアントアプリケーションには、ZKP生成の入力となるPoseidonハッシュの計算時間を計測する機能が組み込まれています。
*   **計測内容:** 指定された期間（例: 10秒、20秒、...、60秒）ごとに、位置情報に基づくPoseidonハッシュを30回生成し、その平均処理時間（ミリ秒）を計測します。
*   **表示形式:** アプリケーション内で表形式のレポートとして表示され、CSV形式でクリップボードにコピー可能です。
*   **目的:** 異なる期間設定がハッシュ生成の計算コストにどのように影響するかを評価し、最適なパラメーター設定やデバイスの処理能力の把握に役立てます。

### 実験環境

#### クライアント
- デバイス: Google Pixel
- OS: Android
- CPU: Google Tensor シリーズ

#### サーバー
- デバイス: Mac (Intel Core i5, 2018)
- OS: macOS
- CPU: Intel Core i5
- RAM: 16GB

*   **ネットワーク:** Wi-Fiまたは有線LAN (サーバーとクライアント間の通信用)
*   **ブロックチェーン:** Ethereum Sepoliaテストネット

### 結果
*   **モバイルハッシュ生成:** 0.87秒 (60秒データ)
*   **ZKP証明生成:** 約25秒
*   **ガス代（手数料）の比較:** L2（Polygon PoS Amoy Testnet）の採用により、従来のL1（Ethereum Sepolia）での記録と比較して、ガス代を大幅に削減できることを確認しました。（例: Ethereum Sepolia 約113円 vs Polygon PoS Amoy Testnet 約0.13円）
*   クライアント側のセキュリティチェックのオーバーヘッドは無視できるレベルでした。

### 比較
(このセクションも、既存の研究や他手法との比較に基づいて記述する必要があります。)
*   「従来のブロックチェーンへの直接データ記録と比較して、ZKPを用いることでオンチェーントランザクションのガス代を [N]% 削減できました。」
*   「類似のZKPベースの位置情報証明システムとの比較において、本システムはクライアント側の処理性能とオフチェーンデータの効率的な管理において優位性を示しました。」

## 8. セキュリティ設計（Security Consideration）

本プロジェクトは、ZKP、IoT、ブロックチェーンといったセキュリティが極めて重要な技術を組み合わせているため、多層的なセキュリティ設計を施しています。

### 脅威モデル
*   **悪意のあるクライアント:** 偽の位置情報、偽のドローンID、改ざんされたハッシュをサーバーに提出しようとする。
*   **サーバーの侵害:** サーバーがハッキングされ、ZKP生成プロセスやIPFS/ブロックチェーン連携が悪用される。
*   **ネットワーク攻撃:** クライアントとサーバー間の通信傍受、改ざん、リプレイ攻撃。
*   **デバイスの侵害:** クライアントデバイスのRoot化/ジェイルブレイクにより、アプリの動作が改ざんされる。
*   **ZKP回路の脆弱性:** 回路設計の不備により、誤った証明が生成されたり、プライバシーが漏洩したりする。
*   **スマートコントラクトの脆弱性:** コントラクトのバグにより、意図しない動作や資産の損失が発生する。

### 攻撃耐性
*   **ZKPによる非公開性:** 生の位置情報やドローンデータの詳細を公開することなく、特定の事実（例：ドローンが特定の時間帯に特定の範囲内にいた）を証明することで、プライバシーを保護し、情報の直接的な窃取に対する耐性を持ちます。
*   **ブロックチェーンによる不変性:** 一度ブロックチェーンに記録されたZKPは改ざん不可能であり、証明の信頼性を保証します。
*   **セキュアな通信:** クライアントとサーバー間の通信はHTTPS (`key.pem`, `cert.pem`) で暗号化されており、盗聴や中間者攻撃を防ぎます。
*   **デバイスのRoot化対策:** クライアントアプリは `safe_device` ライブラリを用いてデバイスのRoot化/ジェイルブレイクや開発者モードの有効化を検知し、安全でない環境での実行を拒否します。これにより、アプリのコード改ざんや機密情報（例：ローカルDB）への不正アクセスリスクを低減します。
*   **分離された責任:** クライアントはデータ収集と提出、サーバーはZKP生成とオンチェーン記録という形で責任が分離されており、単一障害点のリスクを軽減します。

### プライバシー設計
*   **ZKPによるデータ秘匿:** ユーザーの具体的な位置情報（緯度、経度）はブロックチェーン上に直接記録されず、ZKPを介して抽象化された事実のみが公開されます。これにより、個人の移動履歴が追跡されるリスクを最小限に抑えます。
*   **IPFS利用:** ドローンデータのような補助的な情報は、中央集権的なサーバーではなくIPFSに保存され、その可用性と耐検閲性を高めます。

## 9. 制限事項（Limitations）

本プロジェクトの現在の実装には、以下の制限事項があります。

*   **ZKP回路の複雑性:** 現在のZKP回路は特定の用途（例: 位置情報の範囲証明）に特化しており、より複雑なロジックや大規模な入力データに対応するには回路の再設計や最適化が必要です。
*   **スケーラビリティ:** サーバー側でのZKP生成は計算コストが高く、大量の同時提出があった場合、処理の遅延やサーバーリソースのボトルネックが発生する可能性があります。
*   **ネットワーク依存性:** IPFSやブロックチェーンネットワークへの接続性、およびそのパフォーマンスがシステム全体の応答時間に影響を与えます。
*   **自己署名証明書:** サーバーが自己署名証明書を使用しているため、クライアント側での証明書検証ロジックの追加や、信頼できるCAが発行した証明書への置き換えが必要です。
*   **ドローンデータの一般化:** 現在のドローンデータ取得はIPNS監視に依存していますが、多様なドローンモデルやデータ形式に対応するための一般化が必要です。
*   **バッテリー消費:** クライアントアプリのGPS追跡やBluetoothスキャンは、デバイスのバッテリーを比較的多く消費する可能性があります。
*   **環境構築の複雑さ:** Flutter、Node.js、IPFS、Circom/snarkjs、Ethereumといった多様な技術スタックを網羅するため、開発環境のセットアップが複雑になる可能性があります。

## 10. 今後の展望（Future Work）

本プロジェクトは、以下の方向で改善・発展を計画しています。

*   **より高度なZKP機能の導入:**
    *   より複雑な地理空間クエリ（例: 特定の時間内に複数のチェックポイントを通過した証明）に対応するZKP回路の開発。
    *   ZK-RollupやStarkwareなどのスケーリングソリューションとの統合による、オンチェーン検証コストのさらなる削減。
*   **マルチチェーン対応:** Ethereumだけでなく、Polygon、Solanaなどの他のブロックチェーンネットワークへの対応。
*   **デバイスインテグレーションの強化:**
    *   より広範なIoTデバイスタイプ（例: 車載センサー、ウェアラブルデバイス）からのデータ収集サポート。
    *   ハードウェアレベルのセキュリティ機能（例: TEE (Trusted Execution Environment)）との連携による、データ取得時点での改ざん耐性向上。
*   **リアルタイム処理の最適化:** サーバー側でのZKP生成処理の並列化や分散化、WebAssemblyへのオフロードなどによる性能向上。
*   **ユーザーインターフェースの改善:** クライアントアプリのUX/UIをさらに洗練し、提出状況の視覚化やエラーハンドリングを強化。
*   **標準化への貢献:** IoTデバイスとZKP、ブロックチェーンを組み合わせたデータ検証の標準プロトコルやフレームワークの研究開発。
*   **エコシステム統合:** 既存のIoTプラットフォームやデータマーケットプレイスとの連携。

## 11. 貢献方法（Contributing）

本プロジェクトへの貢献を歓迎します。以下のガイドラインに従ってご協力ください。

*   **Issueの作成:** バグ報告、機能リクエスト、改善提案は、GitHubのIssueトラッカーを通じて行ってください。
*   **Pull Request (PR) の作成:**
    *   変更は意味のある小さな単位にまとめてください。
    *   各PRは一つの特定の課題または機能に対応するようにしてください。
    *   既存のコーディング規約とスタイルを尊重してください。
    *   PRを提出する前に、関連するテストを作成し、パスすることを確認してください。
    *   詳細なコミットメッセージとPR説明を含めてください。
*   **ブランチ戦略:** `main` ブランチは常に安定した状態を保ちます。新機能やバグ修正は `feature/your-feature` や `bugfix/issue-number` のようなトピックブランチを作成して作業し、`main` へのPRとして提出してください。

## 12. ライセンス（License）

(このプロジェクトのライセンス情報をここに記載してください。例: MIT License, Apache 2.0 Licenseなど)

## 13. 参考文献（References）

*   **ゼロ知識証明に関する論文:**
    *   [Groth16: On the Size of Pairing-based Non-interactive Arguments](https://eprint.iacr.org/2016/260)
    *   [Circom Documentation](https://docs.circom.io/)
    *   [snarkjs Documentation](https://docs.snarkjs.io/)
*   **Poseidon Hash 関数に関する情報:**
    *   [Poseidon: A New Hash Function for ZKP](https://www.poseidon-hash.info/)
*   **IPFS と IPNS:**
    *   [IPFS Documentation](https://docs.ipfs.tech/)
    *   [IPNS Documentation](https://docs.ipfs.tech/concepts/ipns/)
*   **Ethereum および `ethers.js`:**
    *   [Ethereum Documentation](https://ethereum.org/ja/developers/docs/)
    *   [ethers.js Documentation](https://docs.ethers.org/v6/)
*   **Flutter:**
<<<<<<< HEAD
    *   [Flutter Documentation](https://docs.flutter.dev/)
=======
    *   [Flutter Documentation](https://docs.flutter.dev/)
>>>>>>> fcfacf2 (feat: Initial commit with project structure and README)
