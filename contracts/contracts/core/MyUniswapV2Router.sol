// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMyUniswapV2Factory.sol";
import "../interfaces/IMyUniswapV2Pair.sol";
import "../interfaces/IWETH.sol";
import "../libraries/MyUniswapV2Library.sol";
import "../interfaces/IMyUniswapV2Router.sol";

/**
 * @title MyUniswapV2Router
 * @dev 实现Uniswap V2的路由功能，处理用户交互和多跳交易
 * 路由合约是用户与协议交互的主要入口，提供了添加/移除流动性和代币交换的便捷接口
 */
contract MyUniswapV2Router is IMyUniswapV2Router {
    // 工厂合约地址，用于创建和查找交易对
    address public immutable factory;
    // WETH合约地址，用于ETH和WETH之间的转换
    address public immutable WETH;
    
    /**
     * @dev 检查交易是否过期的修饰器
     * @param deadline 交易截止时间戳
     */
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'MyUniswapV2Router: EXPIRED');
        _;
    }
    
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    // 接收ETH
    receive() external payable {
        assert(msg.sender == WETH);
    }
    
    /**
     * @dev 添加流动性
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // 创建交易对（如果不存在）
        address pair = IMyUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IMyUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        
        // 计算最优添加比例
        (amountA, amountB) = _calculateLiquidity(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin
        );
        
        // 转移代币到交易对
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        
        // 铸造LP代币
        liquidity = IMyUniswapV2Pair(pair).mint(to);
    }

    /**
     * @dev 添加ETH流动性
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        // 创建交易对（如果不存在）
        address pair = IMyUniswapV2Factory(factory).getPair(token, WETH);
        if (pair == address(0)) {
            pair = IMyUniswapV2Factory(factory).createPair(token, WETH);
        }
        
        // 计算最优添加比例
        (amountToken, amountETH) = _calculateLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        
        // 转移代币到交易对
        IERC20(token).transferFrom(msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        IWETH(WETH).transfer(pair, amountETH);
        
        // 铸造LP代币
        liquidity = IMyUniswapV2Pair(pair).mint(to);
        
        // 如果有多余的ETH，退还
        if (msg.value > amountETH) {
            payable(msg.sender).transfer(msg.value - amountETH);
        }
    }
    
    /**
     * @dev 移除流动性
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = IMyUniswapV2Factory(factory).getPair(tokenA, tokenB);
        
        // 将LP代币转移到交易对合约
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        
        // 销毁LP代币并获取代币
        (amountA, amountB) = IMyUniswapV2Pair(pair).burn(to);
        
        require(amountA >= amountAMin, 'MyUniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'MyUniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    /**
     * @dev 移除ETH流动性
     */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        IERC20(token).transfer(to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        payable(to).transfer(amountETH);
    }
    
    /**
     * @dev 代币交换：确切输入金额，最小输出金额
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = MyUniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MyUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        
        IERC20(path[0]).transferFrom(
            msg.sender,
            MyUniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        
        _swap(amounts, path, to);
    }

    /**
     * @dev ETH换确切数量的代币
     */
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'MyUniswapV2Router: INVALID_PATH');
        amounts = MyUniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'MyUniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        
        IWETH(WETH).deposit{value: amounts[0]}();
        IWETH(WETH).transfer(MyUniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
        
        // 退还多余的ETH
        if (msg.value > amounts[0]) {
            payable(msg.sender).transfer(msg.value - amounts[0]);
        }
    }
    
    /**
     * @dev 内部函数：执行代币交换
     */
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = MyUniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            
            (uint amount0Out, uint amount1Out) = input == token0 
                ? (uint(0), amountOut) 
                : (amountOut, uint(0));
                
            address to = i < path.length - 2 
                ? MyUniswapV2Library.pairFor(factory, output, path[i + 2]) 
                : _to;
                
            IMyUniswapV2Pair(MyUniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    
    /**
     * @dev 内部函数：计算最优添加流动性比例
     */
    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal view returns (uint amountA, uint amountB) {
        (uint reserveA, uint reserveB) = MyUniswapV2Library.getReserves(factory, tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = MyUniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'MyUniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = MyUniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, 'MyUniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
                require(amountAOptimal >= amountAMin, 'MyUniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
     * @dev 带签名的移除流动性
     */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountA, uint amountB) {
        address pair = IMyUniswapV2Factory(factory).getPair(tokenA, tokenB);
        
        // 处理permit签名
        {
            uint value = approveMax ? type(uint).max : liquidity;
            IMyUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        }
        
        // 移除流动性
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /**
     * @dev 带签名的移除ETH流动性
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {
        address pair = IMyUniswapV2Factory(factory).getPair(token, WETH);
        
        // 处理permit签名
        {
            uint value = approveMax ? type(uint).max : liquidity;
            IMyUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        }
        
        // 移除流动性
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /**
     * @dev 计算等价数量
     */
    function quote(uint amountA, uint reserveA, uint reserveB) external pure override returns (uint amountB) {
        return MyUniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    /**
     * @dev 计算输出金额
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure override returns (uint amountOut) {
        return MyUniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @dev 计算输入金额
     */
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure override returns (uint amountIn) {
        return MyUniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /**
     * @dev 计算多跳路径的输出金额
     */
    function getAmountsOut(uint amountIn, address[] calldata path) external view override returns (uint[] memory amounts) {
        return MyUniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    /**
     * @dev 计算多跳路径的输入金额
     */
    function getAmountsIn(uint amountOut, address[] calldata path) external view override returns (uint[] memory amounts) {
        return MyUniswapV2Library.getAmountsIn(factory, amountOut, path);
    }

    /**
     * @dev ETH换确切数量的代币
     */
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable override ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'MyUniswapV2Router: INVALID_PATH');
        amounts = MyUniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MyUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(MyUniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /**
     * @dev 确切代币换ETH
     */
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'MyUniswapV2Router: INVALID_PATH');
        amounts = MyUniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'MyUniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        
        IERC20(path[0]).transferFrom(msg.sender, MyUniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        payable(to).transfer(amounts[amounts.length - 1]);
    }

    /**
     * @dev 确切数量的代币换ETH
     */
    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'MyUniswapV2Router: INVALID_PATH');
        amounts = MyUniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'MyUniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        
        IERC20(path[0]).transferFrom(msg.sender, MyUniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        payable(to).transfer(amounts[amounts.length - 1]);
    }

    /**
     * @dev 代币换确切数量的代币
     */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = MyUniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'MyUniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        
        IERC20(path[0]).transferFrom(msg.sender, MyUniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
} 