// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StableSaveVault} from "../src/StableSaveVault.sol";

contract DeployScript is Script {
    StableSaveVault public stableSaveVault;

    function setUp() public {}

    function run() public {
        // Read config from .env at run time (not at contract-construction
        // time) so `forge script` can be pointed at different .env files
        // per environment without redeploying the script contract itself.
        address usdtAddress = vm.envAddress("USDT_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address initialOwner = msg.sender;

        vm.startBroadcast();

        stableSaveVault = new StableSaveVault(
            usdtAddress,
            treasury,
            initialOwner
        );

        vm.stopBroadcast();

        console.log("StableSaveVault deployed at:", address(stableSaveVault));
        console.log("USDT:", usdtAddress);
        console.log("Treasury:", treasury);
        console.log("Owner:", initialOwner);
    }
}