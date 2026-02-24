require("dotenv").config();
const express = require('express');
const https = require('https');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const cors = require('cors');
const { execSync, exec } = require('child_process');
const { ethers } = require('ethers');
const fsPromises = require('fs/promises');

const { prepareInputs } = require('./prepare_inputs.js');

// --- 初期設定 ---
const app = express();
const PORT = 3000;
app.use(cors());
app.use(express.json());

// --- SSL証明書の読み込み ---
const options = {
  key: fs.readFileSync('key.pem'),
  cert: fs.readFileSync('cert.pem')
};

// --- Multerの設定 ---
const uploadDir = 'uploads';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir);
}
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    cb(null, Date.now() + '-' + file.originalname);
  }
});
const upload = multer({ storage: storage });


// =================================================================
// --- IPFSとブロックチェーン設定 ---
// =================================================================
let ipfs;
let globSource;

const contractJson = require('./deployed-address.json'); 
const CONTRACT_ABI = [
    "function recordProof(uint256[2] memory _pA, uint256[2][2] memory _pB, uint256[2] memory _pC, uint256[4] memory _pubSignals)",
    "event ProofRecorded(uint256[4] pubSignals, uint256 timestamp)"
];
let contract;
try {
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    contract = new ethers.Contract(contractJson.address, CONTRACT_ABI, wallet);
    console.log("Ethers.js initialized successfully. Connected to contract at:", contractJson.address);
} catch (error) {
    console.error("Ethers.js initialization failed:", error.message);
    console.error("Please ensure SEPOLIA_RPC_URL and PRIVATE_KEY are set correctly in .env file.");
}


// =================================================================
// --- グローバル変数 ---
// =================================================================
const watchedRemoteIds = {};
let isProcessing = false;
const SUBMISSION_STATUS_FILE = 'submission-status.json';

// =================================================================
// --- ヘルパー関数 ---
// =================================================================
/**
 * 申請ステータスを読み書きする関数
 */
async function readStatusFile() {
    if (!fs.existsSync(SUBMISSION_STATUS_FILE)) {
        return {};
    }
    const content = await fsPromises.readFile(SUBMISSION_STATUS_FILE, 'utf-8');
    return JSON.parse(content);
}

async function writeStatusFile(data) {
    await fsPromises.writeFile(SUBMISSION_STATUS_FILE, JSON.stringify(data, null, 2));
}

async function updateSubmissionStatus(submissionId, statusUpdate) {
    const statuses = await readStatusFile();
    statuses[submissionId] = { ...(statuses[submissionId] || {}), ...statusUpdate, lastUpdated: new Date().toISOString() };
    await writeStatusFile(statuses);
}


// =================================================================
// --- エンドポイント定義 ---
// =================================================================
app.get('/', (req, res) => {
  res.send('Poseidon Report Server is running securely on HTTPS!');
});

app.post('/submit', upload.single('image'), async (req, res) => {
  console.log('--- [/submit] Received Submission ---');

  // --- デバッグ用コード ---
  console.log("--- DEBUG INFO (SERVER) ---");
  console.log("req.body:", req.body);
  console.log("req.file:", req.file ? req.file.originalname : "No file received");
  console.log("---------------------------");
  // ------------------------

  if (!req.file || !req.body.hash || !req.body.droneId) {
    return res.status(400).send('エラー: 不正なリクエストです。画像、ハッシュ、droneIdを含めてください。');
  }

  const submissionId = Date.now().toString();

  try {
    const submissionDir = path.join(uploadDir, submissionId);
    const droneId = req.body.droneId;
    
    if (!fs.existsSync(submissionDir)) fs.mkdirSync(submissionDir, { recursive: true });

    fs.renameSync(req.file.path, path.join(submissionDir, 'image.jpg'));
    
    const userData = { hashes: req.body.hash.trim().split('\n'), droneId: droneId };
    fs.writeFileSync(path.join(submissionDir, 'user_data.json'), JSON.stringify(userData, null, 2));

    if (!watchedRemoteIds.hasOwnProperty(droneId)) {
      watchedRemoteIds[droneId] = null; 
      console.log(`New remoteId [${droneId}] added to watch list.`);
    }

    await updateSubmissionStatus(submissionId, { status: 'submitted' });
    console.log(`Submission ${submissionId} for drone [${droneId}] saved successfully.`);

    // --- IPFSへのアップロード処理はprocessAllSubmissions内で行う方が一貫性があるかもしれないが、一旦このまま
    if (ipfs && globSource) {
        console.log(`[${submissionId}] Uploading submission directory to IPFS...`);
        const source = globSource(submissionDir, '**/*');
        let rootCid;
        for await (const file of ipfs.addAll(source, { wrapWithDirectory: true })) {
          rootCid = file.cid;
        }
        if (!rootCid) throw new Error("Failed to get CID from IPFS upload.");
        
        const cid = rootCid.toString();
        console.log(`[${submissionId}] Successfully uploaded to IPFS. Root CID: ${cid}`);
        await updateSubmissionStatus(submissionId, { ipfsCid: cid });
    }
    // ------------------------------------

    res.status(200).json({
      message: '申請を受け付けました。',
      submissionId: submissionId
    });

  } catch (error) {
    console.error('[/submit] Failed to save submission:', error);
    await updateSubmissionStatus(submissionId, { status: 'failed', error: error.message });
    res.status(500).send(`サーバーエラー: ${error.message}`);
  }
});

// 新しいステータス確認エンドポイント
app.get('/submission-status/:submissionId', async (req, res) => {
    const { submissionId } = req.params;
    const statuses = await readStatusFile();
    const statusInfo = statuses[submissionId];

    if (statusInfo) {
        res.status(200).json(statusInfo);
    } else {
        res.status(404).json({ status: 'not_found', message: '指定された申請IDは見つかりません。' });
    }
});

app.get('/get-proof-events', async (req, res) => {
    // (変更なし)
    console.log('--- [/get-proof-events] Received Request ---');
    if (!contract) {
        return res.status(500).send('サーバーエラー: ブロックチェーンに接続できません。');
    }
    try {
        const events = await contract.queryFilter('ProofRecorded');
        const formattedEvents = events.map(event => ({
            transactionHash: event.transactionHash,
            blockNumber: event.blockNumber,
            timestamp: new Date(Number(event.args.timestamp) * 1000).toLocaleString('ja-JP'),
            pubSignals: event.args.pubSignals.map(signal => signal.toString())
        })).reverse();
        res.status(200).json(formattedEvents);
    } catch (error) {
        console.error('[/get-proof-events] Failed to fetch events:', error);
        res.status(500).send(`サーバーエラー: ${error.message}`);
    }
});


// =================================================================
// --- バックグラウンド処理 ---
// =================================================================
/**
 * IPFSを定期的に監視し、データが更新されたら証明生成をトリガーする
 */
function startIpfsWatcher() {
  console.log('IPFS Watcher started. Checking for updates on watched IDs every 30 seconds...');
  
  setInterval(async () => {
    if (isProcessing) return;
    const remoteIdsToWatch = Object.keys(watchedRemoteIds);
    if (remoteIdsToWatch.length === 0) return;

    console.log(`Watcher: Checking for IPFS updates on [${remoteIdsToWatch.join(', ')}]...`);
    isProcessing = true;

    try {
      let ipnsNames = {};
      try {
        ipnsNames = JSON.parse(await fsPromises.readFile('ipns-names.json', 'utf-8'));
      } catch (readErr) {
        console.log(`Watcher: ipns-names.json not found or empty. Skipping IPNS watch.`);
        isProcessing = false;
        return;
      }

      for (const remoteId of remoteIdsToWatch) {
        const lastKnownCid = watchedRemoteIds[remoteId];
        const ipnsName = ipnsNames[remoteId];
        if (!ipnsName) continue;

        const stdout = await new Promise((resolve, reject) => {
          exec(`node ipfs/retrieve-data.mjs ${ipnsName} ${remoteId}`, (error, stdout, stderr) => {
            if (error) { return reject(new Error(`Failed to retrieve data for ${remoteId}: ${stderr}`)); }
            resolve(stdout);
          });
        });
        
        const mappingCidMatch = stdout.match(/New CID for mapping: (\S+)/);
        const currentCid = mappingCidMatch ? mappingCidMatch[1] : null;

        if (currentCid && currentCid !== lastKnownCid) {
          console.log(`New CID detected for [${remoteId}]: ${currentCid}. Old CID: ${lastKnownCid}`);
          
          const droneDataMatch = stdout.match(/Retrieved data: (\{[\s\S]*\})/);
          if (droneDataMatch && droneDataMatch[1]) {
              const droneData = JSON.parse(droneDataMatch[1]);
              await processAllSubmissions(droneData); // 自動実行
              watchedRemoteIds[remoteId] = currentCid;
          } else {
              console.error(`Could not parse drone data from IPFS script output for [${remoteId}].`);
          }
          break; 
        }
      }
    } catch (error) {
      console.error('Error in IPFS watcher cycle:', error.message);
    } finally {
      isProcessing = false;
    }
  }, 30000);
}

/**
 * 保留中のすべての申請に対して証明生成とブロックチェーン記録を自動実行する
 */
async function processAllSubmissions(droneData) {
    const submissions = fs.readdirSync(uploadDir, { withFileTypes: true })
        .filter(dirent => dirent.isDirectory())
        .map(dirent => dirent.name);

    for (const submissionId of submissions) {
        const flagFilePath = path.join(uploadDir, submissionId, 'processed.flag');
        if (fs.existsSync(flagFilePath)) continue;

        console.log(`--- Processing submission: ${submissionId} ---`);
        await updateSubmissionStatus(submissionId, { status: 'processing' });

        try {
            const inputJsonPath = path.join(uploadDir, submissionId, 'input.json');
            const witnessPath = path.join(uploadDir, submissionId, 'witness.wtns');
            const proofPath = path.join(uploadDir, submissionId, 'proof.json');
            const publicPath = path.join(uploadDir, submissionId, 'public.json');
            
            const userData = JSON.parse(fs.readFileSync(path.join(uploadDir, submissionId, 'user_data.json'), 'utf8'));

            // 1. Input生成
            const circomInput = await prepareInputs(userData.hashes, droneData);
            fs.writeFileSync(inputJsonPath, JSON.stringify(circomInput, null, 2));

            // 2. Witness生成
            execSync(`snarkjs wtns calculate ./merkle_js/merkle.wasm ${inputJsonPath} ${witnessPath}`, { stdio: 'inherit' });

            // 3. Proof生成
            execSync(`snarkjs groth16 prove merkle_final.zkey ${witnessPath} ${proofPath} ${publicPath}`, { stdio: 'inherit' });
            await updateSubmissionStatus(submissionId, { status: 'proof_generated' });

            // 4. Calldata生成
            console.log(`[${submissionId}] Exporting calldata...`);
            const rawCalldata = execSync(`snarkjs zkey export soliditycalldata ${publicPath} ${proofPath}`).toString();
            
            // snarkjsの出力はカンマ区切りの配列文字列なので、全体を`[`と`]`で囲んで有効なJSON配列にする
            const calldataJson = `[${rawCalldata}]`;
            const [pA, pB, pC, pubSignals] = JSON.parse(calldataJson);


            // 5. スマートコントラクト呼び出し
            if (!contract) throw new Error("Contract not initialized.");
            console.log(`[${submissionId}] Sending transaction to recordProof...`);
            const tx = await contract.recordProof(pA, pB, pC, pubSignals);
            await updateSubmissionStatus(submissionId, { status: 'tx_sent', transactionHash: tx.hash });
            
                                    console.log(`[${submissionId}] Waiting for transaction to be mined...`);
            
                                    const receipt = await tx.wait();
            
                                    
            
                                    // 6. 結果と性能情報を保存
            
                                    const gasUsed = receipt.gasUsed;
            
                                    // effectiveGasPrice がなければ gasPrice を使うようにフォールバック
            
                                    const gasPrice = receipt.effectiveGasPrice || receipt.gasPrice;
            
                                    
            
                                    // BigInt型であることを保証してから計算
            
                                    const txFee = BigInt(gasUsed) * BigInt(gasPrice);
            
                        
            
                                    const performanceData = {
            
                                        gasUsed: gasUsed.toString(),
            
                                        gasPriceGwei: ethers.formatUnits(gasPrice, 'gwei'),
            
                                        transactionFeeEth: ethers.formatEther(txFee)
            
                                    };
            
                                    
            
                                    await updateSubmissionStatus(submissionId, { 
            
                                        status: 'completed',
            
                                        blockNumber: receipt.blockNumber,
            
                                        transactionHash: receipt.hash, // レシートからtxHashを保存
            
                                        performance: performanceData
            
                                    });
            
                        
            
                                    console.log(`[${submissionId}] Transaction mined successfully!`);
            
                                    console.log(`[${submissionId}] Performance Metrics:`, performanceData);
            
                        
            
                                    fs.writeFileSync(flagFilePath, new Date().toISOString());

        } catch (error) {
            console.error(`Failed to process submission ${submissionId}:`, error);
            await updateSubmissionStatus(submissionId, { status: 'failed', error: error.message });
        }
    }
}


// =================================================================
// --- サーバー起動処理 ---
// =================================================================
async function startServer() {
    try {
        const ipfsClientModule = await import('ipfs-http-client');
        const create = ipfsClientModule.create;
        globSource = ipfsClientModule.globSource;
        try {
            ipfs = create();
            await ipfs.version();
            console.log("IPFS client initialized and connected successfully.");
        } catch (error) {
            console.error("IPFS client initialization failed:", error.message);
        }
        
        https.createServer(options, app).listen(PORT, () => {
            console.log(` Server is listening securely on https://localhost:${PORT}`);
            startIpfsWatcher();
        });
    } catch (error) {
        console.error('Failed to start server:', error.message);
        process.exit(1);
    }
}

// --- サーバー起動 ---
startServer();
