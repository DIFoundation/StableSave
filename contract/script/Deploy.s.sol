// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StableSaveVault} from "../src/StableSaveVault.sol";

contract DeployScript is Script {
    StableSaveVault public stableSaveVault;

    address usdtAddress = vm.envAddress("USDT_ADDRESS"); // get from .env 
    address treasury = vm.envAddress("TREASURY_ADDRESS"); // Replace with actual treasury address
    address initialOwner = msg.sender;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        stableSaveVault = new StableSaveVault(usdtAddress, treasury, initialOwner);

        vm.stopBroadcast();
    }
}
