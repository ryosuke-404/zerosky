import { execSync } from 'child_process';
import { promises as fs } from 'fs';
import path from 'path';
// import hre from "hardhat"; // <- 削除
import { fileURLToPath } from 'url';

// ESMでは __dirname が使えないため、import.meta.urlから導出する
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log("🚀 Starting redeployment process...");

  // --- ステップ1: Verifier.solの準備 ---
  console.log("📄 Reading and patching new_verifier.sol...");
  const projectRoot = path.join(__dirname, '..'); // このスクリプトは `scripts/` にあるので、一つ上の階層
  const newVerifierPath = path.join(projectRoot, 'new_verifier.sol');
  let verifierCode = await fs.readFile(newVerifierPath, 'utf-8');

  // コントラクト名を "Groth16Verifier" から "Verifier" に変更
  verifierCode = verifierCode.replace("contract Groth16Verifier", "contract Verifier");

  // recordProof関数とイベントを追加
  const codeToInject = `
    event ProofRecorded(uint256[4] pubSignals, uint256 timestamp);

    function recordProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[4] calldata _pubSignals) public {
        require(verifyProof(_pA, _pB, _pC, _pubSignals), "Invalid proof");
        emit ProofRecorded(_pubSignals, block.timestamp);
    }
`;
  // 最後の '}' の前にコードを挿入
  const lastBraceIndex = verifierCode.lastIndexOf('}');
  if (lastBraceIndex === -1) {
    throw new Error("Could not find closing brace in new_verifier.sol");
  }
  const patchedVerifierCode = 
    verifierCode.slice(0, lastBraceIndex) + 
    codeToInject + 
    verifierCode.slice(lastBraceIndex);

  // --- ステップ2: Hardhatプロジェクトにコピー ---
  const hardhatContractsDir = path.join(projectRoot, 'verifier_hardhat', 'contracts');
  const finalVerifierPath = path.join(hardhatContractsDir, 'Verifier.sol');
  await fs.writeFile(finalVerifierPath, patchedVerifierCode);
  console.log(`✅ Patched verifier written to ${finalVerifierPath}`);

  // --- ステップ3: コンパイル ---
  console.log("⚙️  Compiling contract with Hardhat...");
  const hardhatProjectDir = path.join(projectRoot, 'verifier_hardhat');
  execSync('npx hardhat compile', { cwd: hardhatProjectDir, stdio: 'inherit' });
  console.log("✅ Compilation successful.");

  // --- ステップ4: デプロイ ---
  console.log("📡 Deploying to Sepolia network...");
  // Hardhatのデプロイスクリプトを実行し、アドレスをパース
  const deployOutput = execSync('npx hardhat run scripts/deploy-actual.js --network sepolia', { cwd: hardhatProjectDir }).toString();
  const addressMatch = deployOutput.match(/NEW_CONTRACT_ADDRESS: (0x[a-fA-F0-9]{40})/);
  if (!addressMatch || !addressMatch[1]) {
    throw new Error(`Failed to parse new contract address from Hardhat deployment output: ${deployOutput}`);
  }
  const newAddress = addressMatch[1];
  console.log(`✅ Contract deployed to new address: ${newAddress}`);

  // --- ステップ5: deployed-address.json の更新 ---
  const deployedAddressJsonPath = path.join(projectRoot, 'deployed-address.json');
  const newAddressJson = { address: newAddress };
  await fs.writeFile(deployedAddressJsonPath, JSON.stringify(newAddressJson, null, 2));
  console.log(`✅ Updated ${deployedAddressJsonPath} with new address.`);

  console.log("🎉 Redeployment process finished successfully!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
