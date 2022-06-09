// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "./interfaces/IChainConfig.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/ISlashingIndicator.sol";
import "./interfaces/ISystemReward.sol";
import "./interfaces/IValidatorSet.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IRuntimeUpgrade.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjectorContextHolder.sol";
import "./interfaces/IDeployerProxy.sol";

abstract contract InjectorContextHolder is Initializable, Multicall, IInjectorContextHolder {

    // default layout offset, it means that all inherited smart contract's storage layout must start from 100
    uint256 internal constant _LAYOUT_OFFSET = 100;
    uint256 internal constant _SKIP_OFFSET = 10;

    // BSC compatible smart contracts
    IStaking internal immutable _STAKING_CONTRACT;
    ISlashingIndicator internal immutable _SLASHING_INDICATOR_CONTRACT;
    ISystemReward internal immutable _SYSTEM_REWARD_CONTRACT;
    IStakingPool internal immutable _STAKING_POOL_CONTRACT;
    IGovernance internal immutable _GOVERNANCE_CONTRACT;
    IChainConfig internal immutable _CHAIN_CONFIG_CONTRACT;
    IRuntimeUpgrade internal immutable _RUNTIME_UPGRADE_CONTRACT;
    IDeployerProxy internal immutable _DEPLOYER_PROXY_CONTRACT;

    // delayed initializer input data (only for parlia mode)
    bytes internal _delayedInitializer;

    // already used fields
    uint256[_SKIP_OFFSET] private __removed;
    // reserved (2 for init and initializer)
    uint256[_LAYOUT_OFFSET - _SKIP_OFFSET - 2] private __reserved;

    error OnlyCoinbase(address coinbase);
    error OnlySlashingIndicator();
    error OnlyGovernance();
    error OnlyBlock(uint64 blockNumber);

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) {
        _STAKING_CONTRACT = stakingContract;
        _SLASHING_INDICATOR_CONTRACT = slashingIndicatorContract;
        _SYSTEM_REWARD_CONTRACT = systemRewardContract;
        _STAKING_POOL_CONTRACT = stakingPoolContract;
        _GOVERNANCE_CONTRACT = governanceContract;
        _CHAIN_CONFIG_CONTRACT = chainConfigContract;
        _RUNTIME_UPGRADE_CONTRACT = runtimeUpgradeContract;
        _DEPLOYER_PROXY_CONTRACT = deployerProxyContract;
    }

    function useDelayedInitializer(bytes memory delayedInitializer) external onlyBlock(0) {
        _delayedInitializer = delayedInitializer;
    }

    function init() external onlyBlock(1) virtual {
        if (_delayedInitializer.length > 0) {
            _fastDelegateCall(_delayedInitializer);
        }
    }

    function _fastDelegateCall(bytes memory data) internal returns (bytes memory _result) {
        (bool success, bytes memory returnData) = address(this).delegatecall(data);
        if (success) {
            return returnData;
        }
        if (returnData.length > 0) {
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        } else {
            revert();
        }
    }

    function isInitialized() public view override returns (bool) {
        // openzeppelin's class "Initializable" doesnt expose any methods for fetching initialisation status
        StorageSlot.Uint256Slot storage initializedSlot = StorageSlot.getUint256Slot(bytes32(0x0000000000000000000000000000000000000000000000000000000000000001));
        return initializedSlot.value > 0;
    }

    function multicall(bytes[] calldata data) external virtual override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            // this is an optimized a bit multicall w/o using of Address library (it safes a lot of bytecode)
            results[i] = _fastDelegateCall(data[i]);
        }
        return results;
    }

    modifier onlyFromCoinbaseOrSystemReward() virtual {
        if (msg.sender != block.coinbase && ISystemReward(msg.sender) != _SYSTEM_REWARD_CONTRACT) revert OnlyCoinbase(block.coinbase);
        _;
    }

    modifier onlyFromCoinbase() virtual {
        if (msg.sender != block.coinbase) revert OnlyCoinbase(block.coinbase);
        _;
    }

    modifier onlyFromSlashingIndicator() virtual {
        if (ISlashingIndicator(msg.sender) != _SLASHING_INDICATOR_CONTRACT) revert OnlySlashingIndicator();
        _;
    }

    modifier onlyFromGovernance() virtual {
        if (IGovernance(msg.sender) != _GOVERNANCE_CONTRACT) revert OnlyGovernance();
        _;
    }

    modifier onlyBlock(uint64 blockNumber) virtual {
        if (block.number != blockNumber) revert OnlyBlock(blockNumber);
        _;
    }
}