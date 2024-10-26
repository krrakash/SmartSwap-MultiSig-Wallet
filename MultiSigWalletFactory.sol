// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MultiSigWallet.sol";

/// @title MultiSigWalletFactory
/// @notice A factory contract to deploy instances of MultiSigWallet with different owners and confirmation requirements
contract MultiSigWalletFactory {
    // Array to store all deployed MultiSigWallet instances
    address[] public deployedWallets;

    // Mapping to store owners for each deployed wallet
    mapping(address => address[]) public walletOwners;

    // Event emitted when a new MultiSigWallet is deployed
    event WalletDeployed(address indexed walletAddress, address[] owners, uint numConfirmationsRequired);

    /// @notice Deploy a new MultiSigWallet contract
    /// @param _owners The array of addresses that will be the owners of the wallet
    /// @param _numConfirmationsRequired The number of confirmations required to execute a transaction
    function createMultiSigWallet(address[] memory _owners, uint _numConfirmationsRequired) public {
        // Deploy a new instance of MultiSigWallet
        MultiSigWallet wallet = new MultiSigWallet(_owners, _numConfirmationsRequired);

        // Add the wallet's address to the list of deployed wallets
        deployedWallets.push(address(wallet));

        // Store the owners of this wallet in the mapping
        walletOwners[address(wallet)] = _owners;

        // Emit event to notify about the new wallet deployment
        emit WalletDeployed(address(wallet), _owners, _numConfirmationsRequired);
    }

    /// @notice Get the count of all deployed MultiSigWallet contracts
    /// @return The number of MultiSigWallet contracts deployed by this factory
    function getDeployedWalletCount() public view returns (uint) {
        return deployedWallets.length;
    }

    /// @notice Get the address of a deployed wallet by its index
    /// @param index The index of the wallet in the deployedWallets array
    /// @return The address of the deployed wallet
    function getDeployedWallet(uint index) public view returns (address) {
        require(index < deployedWallets.length, "Index out of bounds");
        return deployedWallets[index];
    }

    /// @notice Get the owners of a deployed wallet by the wallet's address
    /// @param wallet The address of the deployed wallet
    /// @return The array of owner addresses of the wallet
    function getWalletOwners(address wallet) public view returns (address[] memory) {
        return walletOwners[wallet];
    }
}
