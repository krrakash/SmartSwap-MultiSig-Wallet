// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/// @title Multisignature Wallet with ERC20 and ERC721 Support
/// @notice This contract implements a multisignature wallet where multiple owners are required to approve transactions, including ERC20 and ERC721 transfers
contract MultiSigWallet {
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
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier txExists(uint _txIndex) {
        require(_txIndex < transactions.length, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(!transactions[_txIndex].executed, "Transaction already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "Transaction already confirmed");
        _;
    }

    constructor(address[] memory _owners, uint _numConfirmationsRequired) {
        require(_owners.length > 0, "Owners required");
        require(
            _numConfirmationsRequired > 0 && _numConfirmationsRequired <= _owners.length,
            "Invalid number of required confirmations"
        );

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev Submit a transaction to transfer ETH, ERC-20, or ERC-721 tokens
    /// @param _to The recipient address
    /// @param _value The amount of ETH to transfer (set 0 for token transactions)
    /// @param _data The data for calling ERC20 or ERC721 functions (for example, `transfer` or `safeTransferFrom`)
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

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    /// @dev Confirm a transaction
    /// @param _txIndex The index of the transaction to confirm
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
    /// @param _txIndex The index of the transaction to revoke confirmation
    function revokeConfirmation(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(isConfirmed[_txIndex][msg.sender], "Transaction not confirmed");

        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    /// @dev Execute a confirmed transaction (ETH, ERC20, or ERC721 transfer)
    /// @param _txIndex The index of the transaction to execute
    function executeTransaction(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(transaction.numConfirmations >= numConfirmationsRequired, "Cannot execute transaction");

        transaction.executed = true;

        // Execute transaction, either ETH transfer, ERC20 transfer, or ERC721 transfer
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    /// @dev Helper function to encode ERC-20 transfer data
    /// @param tokenAddress The address of the ERC-20 token contract
    /// @param to The recipient of the tokens
    /// @param amount The amount of tokens to send
    /// @return The encoded data for the transaction
    function encodeERC20Transfer(address tokenAddress, address to, uint256 amount) 
        public pure returns (bytes memory) 
    {
        return abi.encodeWithSelector(IERC20(tokenAddress).transfer.selector, to, amount);
    }

    /// @dev Helper function to encode ERC-721 transfer data
    /// @param tokenAddress The address of the ERC-721 token contract
    /// @param from The current owner of the NFT
    /// @param to The recipient of the NFT
    /// @param tokenId The ID of the NFT to transfer
    /// @return The encoded data for the transaction
    function encodeERC721Transfer(address tokenAddress, address from, address to, uint256 tokenId) 
        public pure returns (bytes memory) 
    {
        return abi.encodeWithSelector(IERC721(tokenAddress).safeTransferFrom.selector, from, to, tokenId);
    }
}
