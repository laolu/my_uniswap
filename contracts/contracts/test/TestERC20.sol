// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TestERC20
 * @dev 用于测试的ERC20代币合约
 */
contract TestERC20 is ERC20, Ownable {
    // 小数位数
    uint8 private immutable _decimals;
    // 最大供应量
    uint256 public immutable maxSupply;
    // 铸造暂停状态
    bool public mintingPaused;
    
    // 事件
    event MintingPaused(address indexed account);
    event MintingUnpaused(address indexed account);
    
    /**
     * @dev 构造函数
     * @param name 代币名称
     * @param symbol 代币符号
     * @param initialSupply 初始供应量
     * @param tokenDecimals 小数位数
     * @param maxTokenSupply 最大供应量
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint8 tokenDecimals,
        uint256 maxTokenSupply
    ) ERC20(name, symbol) {
        require(initialSupply <= maxTokenSupply, "Initial supply exceeds max supply");
        _decimals = tokenDecimals;
        maxSupply = maxTokenSupply;
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev 返回代币小数位数
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev 暂停铸造
     */
    function pauseMinting() external onlyOwner {
        mintingPaused = true;
        emit MintingPaused(msg.sender);
    }

    /**
     * @dev 恢复铸造
     */
    function unpauseMinting() external onlyOwner {
        mintingPaused = false;
        emit MintingUnpaused(msg.sender);
    }

    /**
     * @dev 铸造代币
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(!mintingPaused, "Minting is paused");
        require(totalSupply() + amount <= maxSupply, "Exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @dev 批量铸造代币
     * @param recipients 接收地址数组
     * @param amounts 对应的铸造数量数组
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(!mintingPaused, "Minting is paused");
        require(recipients.length == amounts.length, "Arrays length mismatch");
        
        uint256 totalAmount;
        for(uint i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(totalSupply() + totalAmount <= maxSupply, "Exceeds max supply");
        
        for(uint i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @dev 销毁代币
     * @param amount 销毁数量
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @dev 从指定地址销毁代币
     * @param account 要销毁代币的地址
     * @param amount 销毁数量
     */
    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
    }

    /**
     * @dev 批量转账
     * @param recipients 接收地址数组
     * @param amounts 对应的转账数量数组
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        
        for(uint i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amounts[i]);
        }
    }

    /**
     * @dev 批量授权
     * @param spenders 被授权地址数组
     * @param amounts 对应的授权数量数组
     */
    function batchApprove(
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external {
        require(spenders.length == amounts.length, "Arrays length mismatch");
        
        for(uint i = 0; i < spenders.length; i++) {
            approve(spenders[i], amounts[i]);
        }
    }

    /**
     * @dev 检查地址是否为合约
     * @param account 要检查的地址
     */
    function isContract(address account) external view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
} 