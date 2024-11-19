const hre = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // 部署 WETH
    console.log("Deploying WETH...");
    const WETH = await ethers.getContractFactory("WETH");
    const weth = await WETH.deploy();
    await weth.waitForDeployment();
    console.log("WETH deployed to:", weth.target);

    // 部署 Factory
    console.log("Deploying Factory...");
    const Factory = await ethers.getContractFactory("MyUniswapV2Factory");
    const factory = await Factory.deploy();
    await factory.waitForDeployment();
    console.log("Factory deployed to:", factory.target);

    // 部署 Router
    console.log("Deploying Router...");
    const Router = await ethers.getContractFactory("MyUniswapV2Router");
    const router = await Router.deploy(factory.target, weth.target);
    await router.waitForDeployment();
    console.log("Router deployed to:", router.target);

    // 部署测试代币
    console.log("Deploying Test Tokens...");
    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const tokenA = await TestERC20.deploy("Token A", "TKA");
    await tokenA.waitForDeployment();
    console.log("Token A deployed to:", tokenA.target);

    const tokenB = await TestERC20.deploy("Token B", "TKB");
    await tokenB.waitForDeployment();
    console.log("Token B deployed to:", tokenB.target);

    // 创建交易对
    console.log("Creating pairs...");
    await factory.createPair(tokenA.target, tokenB.target);
    console.log("TokenA-TokenB pair created");

    await factory.createPair(tokenA.target, weth.target);
    console.log("TokenA-WETH pair created");

    await factory.createPair(tokenB.target, weth.target);
    console.log("TokenB-WETH pair created");

    // 验证合约
    if (hre.network.name !== "hardhat") {
        console.log("Verifying contracts...");
        
        await hre.run("verify:verify", {
            address: weth.target,
            constructorArguments: [],
        });

        await hre.run("verify:verify", {
            address: factory.target,
            constructorArguments: [],
        });

        await hre.run("verify:verify", {
            address: router.target,
            constructorArguments: [factory.target, weth.target],
        });

        await hre.run("verify:verify", {
            address: tokenA.target,
            constructorArguments: ["Token A", "TKA"],
        });

        await hre.run("verify:verify", {
            address: tokenB.target,
            constructorArguments: ["Token B", "TKB"],
        });
    }

    // 保存部署信息
    const deployInfo = {
        network: hre.network.name,
        weth: weth.target,
        factory: factory.target,
        router: router.target,
        tokenA: tokenA.target,
        tokenB: tokenB.target,
        timestamp: new Date().toISOString()
    };

    // 将部署信息写入文件
    const fs = require("fs");
    const deploymentPath = `deployments/${hre.network.name}.json`;
    fs.mkdirSync("deployments", { recursive: true });
    fs.writeFileSync(deploymentPath, JSON.stringify(deployInfo, null, 2));
    console.log(`Deployment info saved to ${deploymentPath}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 