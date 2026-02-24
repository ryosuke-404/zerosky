const { execSync } = require("child_process");
const fs = require("fs");

async function main() {
  const circuitName = "circuit";
  const ptauName = "pot18";

  console.log(`🛠️  Setting up ZKP circuit for local verification: ${circuitName}`);

  // Create directories if they don't exist
  if (!fs.existsSync("circuits")) fs.mkdirSync("circuits");
  if (!fs.existsSync("keys")) fs.mkdirSync("keys");

  // 1. Compile the circuit
  console.log("\n[1] Compiling circuit...");
  execSync(`circom circuits/${circuitName}.circom --r1cs --wasm --sym -o ./keys`, { stdio: "inherit" });

  // 2. Powers of Tau (Trusted Setup Phase 1)
  console.log("\n[2] Starting Powers of Tau...");
  if (!fs.existsSync(`keys/${ptauName}_final.ptau`)) {
    console.log(`  -> Setting up ${ptauName}...`);
    execSync(`snarkjs powersoftau new bn128 18 keys/${ptauName}_0000.ptau -v`, { stdio: "inherit" });
    execSync(`snarkjs powersoftau contribute keys/${ptauName}_0000.ptau keys/${ptauName}_0001.ptau --name="First contribution" -v -e="random text"`, { stdio: "inherit" });
    execSync(`snarkjs powersoftau prepare phase2 keys/${ptauName}_0001.ptau keys/${ptauName}_final.ptau -v`, { stdio: "inherit" });
    console.log(`  -> ${ptauName} setup complete.`);
  } else {
    console.log(`  -> Found existing keys/${ptauName}_final.ptau. Skipping.`);
  }

  // 3. Circuit-specific setup (Trusted Setup Phase 2)
  console.log("\n[3] Starting circuit-specific setup (Groth16)...");
  execSync(`snarkjs groth16 setup keys/${circuitName}.r1cs keys/${ptauName}_final.ptau keys/${circuitName}_0000.zkey`, { stdio: "inherit" });
  execSync(`snarkjs zkey contribute keys/${circuitName}_0000.zkey keys/${circuitName}_final.zkey --name="Second contribution" -v -e="more random text"`, { stdio: "inherit" });
  console.log("  -> Circuit-specific setup complete.");

  // 4. Export Verification Key for local verification
  console.log("\n[4] Exporting verification key...");
  execSync(`snarkjs zkey export verificationkey keys/${circuitName}_final.zkey keys/verification_key.json`, { stdio: "inherit" });
  console.log("  -> Export complete.");

  console.log("\n✅ ZKP setup for local verification finished successfully!");
}

main().catch((error) => {
  console.error("\n❌ An error occurred during setup:", error);
  process.exit(1);
});
