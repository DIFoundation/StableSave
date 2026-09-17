// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StableSaveVault} from "../src/StableSaveVault.sol";
import {StableSaveTreasury} from "../src/StableSaveTreasury.sol";

contract DeployScript is Script {
    StableSaveVault public stableSaveVault;
    StableSaveTreasury public stableSaveTreasury;

    function setUp() public {}

    function run() public {
        // Read config from .env at run time (not at contract-construction
        // time) so `forge script` can be pointed at different .env files
        // per environment without redeploying the script contract itself.
        address usdtAddress = vm.envAddress("USDT_ADDRESS");
        address initialOwner = msg.sender;

        // TREASURY_ADDRESS is optional. Leave it unset (or blank) to have
        // this script deploy a fresh StableSaveTreasury owned by
        // `initialOwner`; set it to point the vault at an already-deployed
        // treasury (e.g. a multisig, or a treasury deployed in a previous
        // run).
        address existingTreasury = vm.envOr("TREASURY_ADDRESS", address(0));

        vm.startBroadcast();

        address treasury = existingTreasury;

        if (treasury == address(0)) {
            stableSaveTreasury = new StableSaveTreasury(initialOwner);
            treasury = address(stableSaveTreasury);
        }

        stableSaveVault = new StableSaveVault(
            usdtAddress,
            treasury,
            initialOwner
        );

        vm.stopBroadcast();

        console.log("StableSaveVault deployed at:", address(stableSaveVault));
        console.log("USDT:", usdtAddress);
        console.log("Treasury:", treasury);
        if (existingTreasury == address(0)) {
            console.log("  (freshly deployed StableSaveTreasury)");
        } else {
            console.log("  (existing treasury, passed via TREASURY_ADDRESS)");
        }
        console.log("Owner:", initialOwner);
    }
}
