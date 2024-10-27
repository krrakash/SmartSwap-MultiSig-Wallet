const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

// Function to check and install all dependencies, including inquirer, Hardhat, and Solidity dependencies
async function checkAndInstallAllDependencies(contractPath) {
    try {
        // Check if npm init has been run
        if (!fs.existsSync('package.json')) {
            console.log("Initializing npm...");
            execSync('npm init -y', { stdio: 'inherit' });
        }

        // Check and install inquirer
        try {
            require.resolve('inquirer');
            console.log("Inquirer is already installed.");
        } catch (error) {
            console.log("Installing inquirer...");
            execSync('npm install inquirer --save', { stdio: 'inherit' });
            console.log("Inquirer installed successfully.");
        }

        // Check and install Hardhat and its dependencies
        try {
            execSync('npx hardhat --version', { stdio: 'inherit' });
            console.log("Hardhat is already installed.");
        } catch (error) {
            console.error("Hardhat is not installed. Attempting installation...");
            execSync('npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers', { stdio: 'inherit' });
            console.log("Hardhat and dependencies installed successfully.");
        }

        // Extract and install Solidity dependencies from the contract
        extractAndInstallDependencies(contractPath);
    } catch (installError) {
        console.error("Failed to check or install dependencies.", installError);
        throw installError; // Propagate the error to the main function
    }
}

// Function to extract and install Solidity dependencies from the contract
function extractAndInstallDependencies(contractPath) {
    try {
        const contractContent = fs.readFileSync(contractPath, 'utf8');
        const importRegex = /import ["']([^"']+)["'];/g;
        let match;
        let dependencies = [];

        // Extract all the import paths
        while ((match = importRegex.exec(contractContent)) !== null) {
            const dependency = match[1];

            // For npm-based imports (like @uniswap or other npm packages)
            if (dependency.startsWith('@')) {
                dependencies.push(dependency.split('/')[0]); // Get the main package name
            }
        }

        // Install any found dependencies
        if (dependencies.length > 0) {
            console.log("Installing Solidity dependencies:", dependencies.join(', '));
            execSync(`npm install --save ${dependencies.join(' ')}`, { stdio: 'inherit' });
        } else {
            console.log("No external dependencies found in the contract.");
        }
    } catch (error) {
        console.error("Error extracting or installing dependencies:", error);
        throw error; // Propagate the error to the main function
    }
}

// Function to create a Hardhat config if not present
function createHardhatConfig() {
    try {
        const configFile = './hardhat.config.js';
        if (!fs.existsSync(configFile)) {
            console.log("Creating hardhat.config.js...");
            const configContent = `
              require("@nomiclabs/hardhat-ethers");

              module.exports = {
                solidity: "0.8.4",
                networks: {
                  custom: {
                    url: "", // to be filled with user input
                    accounts: [], // to be filled with user input
                  },
                },
              };
            `;
            fs.writeFileSync(configFile, configContent);
            console.log("Hardhat config created.");
        }
    } catch (error) {
        console.error("Error creating Hardhat config file:", error);
        throw error; // Propagate the error to be handled in the main function
    }
}

// Function to copy the contract to the contracts folder
function copyContract(contractPath) {
    try {
        const contractsDir = './contracts';
        if (!fs.existsSync(contractsDir)) {
            fs.mkdirSync(contractsDir);
        }
        const contractFileName = path.basename(contractPath);
        fs.copyFileSync(contractPath, path.join(contractsDir, contractFileName));
        console.log(`Contract ${contractFileName} copied to contracts directory.`);
    } catch (error) {
        console.error("Error copying the contract file:", error);
        throw error; // Propagate the error to be handled in the main function
    }
}

// Function to prompt for necessary inputs
async function getDeploymentDetails() {
    try {
        const inquirer = require('inquirer'); // Ensure inquirer is available after installation

        const questions = [
            {
                type: 'input',
                name: 'privateKey',
                message: 'Enter your private key for deployment:',
            },
            {
                type: 'input',
                name: 'networkURL',
                message: 'Enter the network URL (e.g., Infura or Alchemy):',
            },
            {
                type: 'input',
                name: 'contractArgs',
                message: 'Enter the constructor arguments for the contract (comma-separated if multiple):',
            }
        ];

        return await inquirer.prompt(questions);
    } catch (error) {
        console.error("Error collecting deployment details:", error);
        throw error; // Propagate the error to be handled in the main function
    }
}

// Function to update the Hardhat config with network details
function updateHardhatConfig(privateKey, networkURL) {
    try {
        let configContent = fs.readFileSync('./hardhat.config.js', 'utf8');
        configContent = configContent.replace('url: ""', `url: "${networkURL}"`);
        configContent = configContent.replace('accounts: []', `accounts: [\`0x${privateKey}\`]`);
        fs.writeFileSync('./hardhat.config.js', configContent);
        console.log("Hardhat config updated with network details.");
    } catch (error) {
        console.error("Error updating Hardhat config:", error);
        throw error; // Propagate the error to be handled in the main function
    }
}

// Function to deploy contract
async function deployContract(contractArgs) {
    try {
        const deployScript = `
          const hre = require("hardhat");

          async function main() {
            const Contract = await hre.ethers.getContractFactory("YourContractName");
            const contract = await Contract.deploy(${contractArgs});
            await contract.deployed();
            console.log("Contract deployed to:", contract.address);
            console.log("Contract owner is:", contract.signer.address);
          }

          main()
            .then(() => process.exit(0))
            .catch((error) => {
              console.error(error);
              process.exit(1);
            });
        `;

        // Write the deploy script to the scripts folder
        const scriptsDir = './scripts';
        if (!fs.existsSync(scriptsDir)) {
            fs.mkdirSync(scriptsDir);
        }
        fs.writeFileSync(path.join(scriptsDir, 'deploy.js'), deployScript);

        console.log("Running deployment script...");
        execSync('npx hardhat run scripts/deploy.js --network custom', { stdio: 'inherit' });
    } catch (error) {
        console.error("Error during contract deployment:", error);
        throw error; // Propagate the error to be handled in the main function
    }
}

// Main function to execute the wrapper
(async function main() {
    try {
        const contractPath = process.argv[2];

        if (!contractPath) {
            console.error("Please provide the path to the .sol contract file.");
            process.exit(1);
        }

        // Ensure all dependencies are installed and ready
        try {
            await checkAndInstallAllDependencies(contractPath); // Install all necessary dependencies
        } catch (error) {
            console.error("Failed to check or install dependencies.");
            process.exit(1);
        }

        // Set up Hardhat configuration
        try {
            createHardhatConfig(); // Create Hardhat config if not present
        } catch (error) {
            console.error("Failed to create Hardhat config.");
            process.exit(1);
        }

        // Copy the contract
        try {
            copyContract(contractPath); // Copy the contract
        } catch (error) {
            console.error("Failed to copy the contract.");
            process.exit(1);
        }

        const { privateKey, networkURL, contractArgs } = await getDeploymentDetails(); // Prompt for user input
        updateHardhatConfig(privateKey, networkURL); // Update the Hardhat config with inputs

        await deployContract(contractArgs); // Deploy the contract
    } catch (error) {
        console.error("An unexpected error occurred:", error);
        process.exit(1);
    }
})();
