// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMyUniswapV2Factory.sol";
import "./MyUniswapV2Pair.sol";

/**
 * @title MyUniswapV2Factory
 * @dev 工厂合约负责创建和管理交易对
 */
contract MyUniswapV2Factory is IMyUniswapV2Factory {
    // 存储所有交易对的映射
    mapping(address => mapping(address => address)) public override getPair;
    // 所有交易对的数组
    address[] public override allPairs;
    
    /**
     * @dev 创建新的交易对
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @return pair 新创建的交易对地址
     */
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'MyUniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'MyUniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'MyUniswapV2: PAIR_EXISTS');
        
        // 使用CREATE2部署新的交易对合约
        bytes memory bytecode = type(MyUniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        
        // 初始化交易对
        MyUniswapV2Pair(pair).initialize(token0, token1);
        
        // 更新映射和数组
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    /**
     * @dev 返回所有交易对的数量
     * @return 交易对数量
     */
    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }
} 