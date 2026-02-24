import hardhat from "hardhat";
const { ethers } = hardhat;
import fs from "fs";
import path from "path";
import { fileURLToPath } from 'url';

// ESMでは__dirnameが直接使えないため、import.meta.urlから導出する
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const networkName = hre.network.name;
  console.log(`Deploying to network: ${networkName}`);

  // 1. コントラクトファクトリを取得
  const VerifierFactory = await ethers.getContractFactory("Groth16Verifier");

  // 2. コントラクトをデプロイ
  console.log("Sending deployment transaction...");
  const verifier = await VerifierFactory.deploy();

  // デプロイが完了するのを待つ
  await verifier.waitForDeployment();
  const contractAddress = await verifier.getAddress();

  console.log("-----------------------------------------");
  console.log(`✅ Groth16Verifier deployed successfully on ${networkName}!`);
  console.log("Contract Address:", contractAddress);
  console.log("-----------------------------------------");

  // 3. デプロイされたアドレスをネットワーク別のJSONファイルに保存
  const addressData = {
    address: contractAddress,
  };
  const fileName = `deployed-address-${networkName}.json`;
  const filePath = path.join(__dirname, "..", fileName);
  fs.writeFileSync(filePath, JSON.stringify(addressData, null, 2));
  console.log(`Address saved to ${filePath}`);

  console.log("\nNext steps:");
  console.log(
    `You can now run the measurement script for the '${networkName}' network:`
  );
  console.log(`node measure_contract_gas.js ${networkName}`);
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});
