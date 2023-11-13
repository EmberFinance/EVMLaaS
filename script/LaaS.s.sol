// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/EsEMBR.sol";
import "../src/EsEMBRRewardsDistributor.sol";
import "../src/EMBR.sol";
import "../src/Vester.sol";

contract PresaleDeployScript is Script {
    address constant UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    function setUp() public {}

	// https://api-goerli.etherscan.io/api
	// 
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EMBRToken embr = EMBRToken(payable(0x1936aE42b59876192a2E263B3807343c448e3c85));
		// EMBRToken embr = new EMBRToken();
        // embr.enableTrading();

        EmberVault vault = new EmberVault(UNI_ROUTER, UNI_FACTORY);
        EsEMBRRewardsDistributor distributor = new EsEMBRRewardsDistributor();

        EsEMBR esEmbr = new EsEMBR(payable(address(embr)), address(distributor), payable(address(vault)));
        embr.excludeWhale(address(esEmbr));

        embr.mint(15_000_000 * 1e18);
        embr.transfer(address(esEmbr), 15_000_000 * 1e18);

        distributor.setEsEMBR(payable(address(esEmbr)));

        distributor.setEmissionPerSecondEmbr(0.0501543210 ether * 3); // 130k esembr per month to embr stakers
        distributor.setEmissionPerSecondEth(0.0270061728 ether * 3); // 70k esembr per month to eth stakers

        vault.setEsEMBR(payable(address(esEmbr)));

        vault.addPackage(EmberVault.Package({
            Enabled: 1,
            Price: 0.125 ether,
            BorrowedLiquidity: 3 ether,
            Duration: 13,
            DebtGrowthPerWeek: 65
        }));

        vault.addPackage(EmberVault.Package({
            Enabled: 1,
            Price: 0.25 ether,
            BorrowedLiquidity: 7 ether,
            Duration: 13,
            DebtGrowthPerWeek: 65
        }));

        vault.addPackage(EmberVault.Package({
            Enabled: 1,
            Price: 0.4 ether,
            BorrowedLiquidity: 15 ether,
            Duration: 13,
            DebtGrowthPerWeek: 65
        }));

        vault.setRewardSettings(250 * 1e18, 24 * 5, 250 * 1e18); // grows for 5 days

        Vester oneMonthVester = new Vester(30 days, 2000, address(esEmbr));
        Vester threeMonthsVester = new Vester(90 days, 5500, address(esEmbr));
        Vester sixMonthsVester = new Vester(180 days, 10000, address(esEmbr));

        esEmbr.addVester(oneMonthVester.vestingTime(), IVester(address(oneMonthVester)));
        esEmbr.addVester(threeMonthsVester.vestingTime(), IVester(address(threeMonthsVester)));
        esEmbr.addVester(sixMonthsVester.vestingTime(), IVester(address(sixMonthsVester)));

        console.log("Vault:", address(vault));
        console.log("EMBR:", address(embr));
        console.log("esEMBR:", address(esEmbr));
		console.log("1 month vester:", address(oneMonthVester));
		console.log("3 month vester:", address(threeMonthsVester));
		console.log("6 month vester:", address(sixMonthsVester));
		console.log("Distributor", address(distributor));

        vm.stopBroadcast();
    }
}
