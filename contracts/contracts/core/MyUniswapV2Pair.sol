// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IMyUniswapV2Pair.sol";
import "../libraries/Math.sol";

/**
 * @title MyUniswapV2Pair
 * @dev 实现Uniswap V2的交易对合约，管理两个ERC20代币之间的流动性和交易
 */
contract MyUniswapV2Pair is IMyUniswapV2Pair, ERC20 {
    // 重入保护状态变量
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // 单重入锁
    uint private unlocked = 1;
    
    // 工厂合约地址
    address public override factory;
    // 交易对中的两个代币地址
    address public override token0;
    address public override token1;
    
    // 储备量变量
    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;
    
    // 价格累加器
    uint public override price0CumulativeLast;
    uint public override price1CumulativeLast;
    uint public override kLast;
    
    uint private constant _MINIMUM_LIQUIDITY = 1000;
    
    // 使用 Math 库
    using Math for uint;

    // permit 相关变量
    bytes32 public override DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant override PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public override nonces;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    constructor() ERC20("Uniswap V2", "UNI-V2") {
        factory = msg.sender;
        _status = _NOT_ENTERED;

        // 计算 DOMAIN_SEPARATOR
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name())),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );
    }
    
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN');
        token0 = _token0;
        token1 = _token1;
    }
    
    /**
     * @dev 获取当前储备量和最后更新时间
     * @return _reserve0 token0的储备量
     * @return _reserve1 token1的储备量
     * @return _blockTimestampLast 最后更新时间
     */
    function getReserves() public view returns (
        uint112 _reserve0, 
        uint112 _reserve1, 
        uint32 _blockTimestampLast
    ) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function mint(address to) external override lock nonReentrant returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;
        
        if (totalSupply() == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - _MINIMUM_LIQUIDITY;
            _mint(address(0), _MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * totalSupply()) / _reserve0,
                (amount1 * totalSupply()) / _reserve1
            );
        }
        
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);
        
        _update(balance0, balance1);
        kLast = uint(reserve0) * uint(reserve1);
        
        emit Mint(msg.sender, amount0, amount1);
    }
    
    function burn(address to) external override lock nonReentrant returns (uint amount0, uint amount1) {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = balanceOf(address(this));
        
        amount0 = (liquidity * balance0) / totalSupply();
        amount1 = (liquidity * balance1) / totalSupply();
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        
        _burn(address(this), liquidity);
        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);
        
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);
        kLast = uint(reserve0) * uint(reserve1);
        
        emit Burn(msg.sender, amount0, amount1, to);
    }
    
    /**
     * @dev 代币交换功能
     */
    function swap(
        uint256 amount0Out, 
        uint256 amount1Out, 
        address to,
        bytes calldata data
    ) external override nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        
        // 获取储备量
        (uint256 _reserve0, uint256 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');
        
        uint256 balance0;
        uint256 balance1;
        { // 使用代码块来限制变量作用域
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
            
            // 转移代币给接收者
            if (amount0Out > 0) IERC20(_token0).transfer(to, amount0Out);
            if (amount1Out > 0) IERC20(_token1).transfer(to, amount1Out);
            
            // 如果有回调数据，执行回调
            if (data.length > 0) {
                IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            }
            
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        
        // 计算输入金额
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        
        { // 使用代码块来限制变量作用域
            // 验证K值
            uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
            require(
                balance0Adjusted * balance1Adjusted >= _reserve0 * _reserve1 * 1000000,
                'UniswapV2: K'
            );
        }
        
        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
    /**
     * @dev 闪电贷功能
     * @param recipient 接收闪电贷的地址
     * @param amount0 借出的token0数量
     * @param amount1 借出的token1数量
     * @param data 回调数据，用于执行闪电贷逻辑
     * @notice 闪电贷必须在同一交易中完成借贷和还款
     */
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external lock nonReentrant {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        // 转移代币给接收者
        if (amount0 > 0) IERC20(token0).transfer(recipient, amount0);
        if (amount1 > 0) IERC20(token1).transfer(recipient, amount1);
        
        // 调用接收者的回调函数，执行闪电贷逻辑
        IUniswapV2Callee(recipient).uniswapV2Call(msg.sender, amount0, amount1, data);
        
        // 验证闪电贷是否已经偿还
        uint256 balance0After = IERC20(token0).balanceOf(address(this));
        uint256 balance1After = IERC20(token1).balanceOf(address(this));
        require(balance0After >= balance0, 'UniswapV2: INSUFFICIENT_FLASH_PAYMENT_0');
        require(balance1After >= balance1, 'UniswapV2: INSUFFICIENT_FLASH_PAYMENT_1');
        
        _update(balance0After, balance1After);
    }
    
    /**
     * @dev 移除超额代币
     * @param to 接收超额代币的地址
     * @notice 当合约中的代币余额超过储备量时，可以提取超额部分
     */
    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).transfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).transfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }
    
    /**
     * @dev 强制使储备量等于当前余额
     * @notice 用于修正储备量与实际余额不一致的情况
     */
    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
    }
    
    /**
     * @dev 内部函数：更新储备量和价格累加器
     * @param balance0 token0的新储备量
     * @param balance1 token1的新储备量
     */
    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'UniswapV2: OVERFLOW');
        
        // 更新价格累加器
        uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            price0CumulativeLast += (reserve1 * 1e18 / reserve0) * timeElapsed;
            price1CumulativeLast += (reserve0 * 1e18 / reserve1) * timeElapsed;
        }
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        
        emit Sync(reserve0, reserve1);
    }

    /**
     * @dev EIP-2612 permit 函数，允许通过签名授权
     */
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');

        _approve(owner, spender, value);
    }
}

/**
 * @title IUniswapV2Callee
 * @dev 闪电贷回调接口，借用方必须实现此接口
 */
interface IUniswapV2Callee {
    /**
     * @dev 闪电贷回调函数
     * @param sender 发起闪电贷的地址
     * @param amount0 借出的token0数量
     * @param amount1 借出的token1数量
     * @param data 附加数据
     */
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}