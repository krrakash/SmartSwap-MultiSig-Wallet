// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/// @title Multisignature Wallet with ERC20, ERC721, ERC1155, and Uniswap V3 Swap Support
/// @notice This contract implements a multisignature wallet where multiple owners are required to approve transactions, including ERC20, ERC721, and ERC1155 transfers, and can automatically swap MATIC for WETH via Uniswap V3 if needed.
contract MultiSigWallet {
    // Uniswap V3 Router address and WETH address (Polygon example)
    ISwapRouter public immutable swapRouter;
    address public immutable WETH;
    address public immutable MATIC;

    // Custom errors
    error NotAnOwner();
    error TransactionNotExist();
    error TransactionAlreadyExecuted();
    error TransactionAlreadyConfirmed();
    error NotEnoughConfirmations();
    error TransactionNotConfirmed();
    error OwnersRequired();
    error InvalidConfirmationsCount();
    error OwnerNotUnique();

    // Events
    event Deposit(address indexed sender, uint amount);
    event SubmitTransaction(address indexed owner, uint indexed txIndex, address indexed to, uint value, bytes data);
    event ConfirmTransaction(address indexed owner, uint indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint indexed txIndex);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint public numConfirmationsRequired;

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        uint numConfirmations;
    }

    // Array of transactions
    Transaction[] public transactions;

    // Mapping of txIndex => owner => confirmed
    mapping(uint => mapping(address => bool)) public isConfirmed;

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotAnOwner();
        _;
    }

    modifier txExists(uint _txIndex) {
        if (_txIndex >= transactions.length) revert TransactionNotExist();
        _;
    }

    modifier notExecuted(uint _txIndex) {
        if (transactions[_txIndex].executed) revert TransactionAlreadyExecuted();
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        if (isConfirmed[_txIndex][msg.sender]) revert TransactionAlreadyConfirmed();
        _;
    }

    constructor(
        address[] memory _owners,
        uint _numConfirmationsRequired,
        address _swapRouter,
        address _WETH
    ) {
        if (_owners.length == 0) revert OwnersRequired();
        if (_numConfirmationsRequired == 0 || _numConfirmationsRequired > _owners.length) revert InvalidConfirmationsCount();

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) revert OwnersRequired();
            if (isOwner[owner]) revert OwnerNotUnique();

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
        swapRouter = ISwapRouter(_swapRouter);
        WETH = _WETH;
        MATIC = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Native MATIC
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev Swap MATIC for WETH using Uniswap V3
    /// @param amountIn The amount of MATIC to swap
    /// @param amountOutMinimum The minimum amount of WETH to receive
    /// @return amountOut The amount of WETH received
    function swapMaticForWETH(uint256 amountIn, uint256 amountOutMinimum) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: MATIC,
            tokenOut: WETH,
            fee: 3000, // Pool fee, typically 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap
        amountOut = swapRouter.exactInputSingle{value: amountIn}(params);
    }

    /// @dev Submit a transaction to transfer ETH, WETH, or tokens, automatically swapping MATIC to WETH if necessary
    /// @param _to The recipient address
    /// @param _value The amount of ETH or WETH required for the transaction
    /// @param _data The data to call in the transaction (for ERC-20, ERC-721, ERC-1155 transfers)
    function submitTransaction(address _to, uint _value, bytes memory _data)
        public
        onlyOwner
    {
        uint txIndex = transactions.length;

        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        }));

        // Check if the contract needs to swap MATIC to WETH
        uint256 balanceWETH = IERC20(WETH).balanceOf(address(this));
        if (balanceWETH < _value) {
            uint256 amountToSwap = _value - balanceWETH;
            swapMaticForWETH(amountToSwap, 0); // Swap required MATIC for WETH
        }

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    /// @dev Confirm a transaction
    function confirmTransaction(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    /// @dev Revoke a confirmation of a transaction
    function revokeConfirmation(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        if (!isConfirmed[_txIndex][msg.sender]) revert TransactionNotConfirmed();

        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    /// @dev Execute a confirmed transaction (ETH, ERC-20, ERC-721, or ERC-1155 transfer)
    function executeTransaction(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        if (transaction.numConfirmations < numConfirmationsRequired) revert NotEnoughConfirmations();

        transaction.executed = true;

        // Execute the transaction (ETH, WETH, ERC-20, ERC-721, or ERC-1155 transfer)
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    /// @dev Helper function to encode ERC-20 transfer data
    function encodeERC20Transfer(address tokenAddress, address to, uint256 amount) 
        public pure returns (bytes memory) 
    {
        return abi.encodeWithSelector(IERC20(tokenAddress).transfer.selector, to, amount);
    }

    /// @dev Helper function to encode ERC-721 transfer data
    function encodeERC721Transfer(address tokenAddress, address from, address to, uint256 tokenId) 
        public pure returns (bytes memory) 
    {
        return abi.encodeWithSelector(IERC721(tokenAddress).safeTransferFrom.selector, from, to, tokenId);
    }

    /// @dev Helper function to encode ERC-1155 transfer data
    function encodeERC1155Transfer(address tokenAddress, address from, address to, uint256 id, uint256 amount, bytes memory data) 
        public pure returns (bytes memory) 
    {
        return abi.encodeWithSelector(IERC1155(tokenAddress).safeTransferFrom.selector, from, to, id, amount, data);
    }
}
