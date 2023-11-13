// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/EsEMBR.sol";
import "../src/Vester.sol";
import "../src/EMBR.sol";
import "../src/EsEMBRRewardsDistributor.sol";

contract esEMBRTest is Test {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    EsEMBRRewardsDistributor public distributor;
    EsEMBR public esEmbr;
    EMBRToken public embr;
    EmberVault public vault;
    Vester public oneMonthVester;
    Vester public threeMonthVester;

    address UNI_ROUTER = 0xf164fC0Ec4E93095b804a4795bBe1e041497b92a;
    address UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        vm.selectFork(mainnetFork);

        embr = new EMBRToken();
        embr.enableTrading();
        
        vault = new EmberVault(UNI_ROUTER, UNI_FACTORY);
        vm.deal(address(vault), 1_000 ether);

        distributor = new EsEMBRRewardsDistributor();

        esEmbr = new EsEMBR(payable(address(embr)), address(distributor), payable(address(vault)));
        embr.excludeWhale(address(esEmbr));

        embr.mint(15_000_000 * 1e18); // This is for esEMBR
        embr.transfer(address(esEmbr), 15_000_000 * 1e18);

        vault.setEsEMBR(payable(address(esEmbr)));
        distributor.setEsEMBR(payable(address(esEmbr)));

        oneMonthVester = new Vester(30 days, 2000, address(esEmbr));
        threeMonthVester = new Vester(90 days, 5500, address(esEmbr));

        esEmbr.addVester(oneMonthVester.vestingTime(), IVester(address(oneMonthVester)));
        esEmbr.addVester(threeMonthVester.vestingTime(), IVester(address(threeMonthVester)));
    }

    function test_Distribution() public {
        assertEq(0, distributor.pendingForEmbr());
        assertEq(0, distributor.pendingForEth());

        distributor.setEmissionPerSecondEmbr(1 * 1e18); // set distribution to 1 esembr per second for embr stakers
        distributor.setEmissionPerSecondEth(1 * 1e18); // set distribution to 1 esembr per second for eth stakers

        // warp 10 seconds
        vm.warp(block.timestamp + 10 seconds);

        // make sure the pending reward is 10 esEmbr
        assertEq(10 ether, distributor.pendingForEmbr());
        assertEq(10 ether, distributor.pendingForEth());
    }

    function test_Vesting() public {
        address vesterTester = address(0x13132738);
        vm.deal(vesterTester, 10 ether);

        // set distribution to 1 esEmbr per second
        distributor.setEmissionPerSecondEth(1 * 1e18);

        vm.startPrank(vesterTester);
        assertEq(0, embr.balanceOf(vesterTester));

        // stake 1 eth
        esEmbr.stakeEth{value: 1 ether}();

        // warp 10 seconds into the future
        vm.warp(block.timestamp + 10 seconds);

        // claim the esEmbr
        uint claimed_amount = esEmbr.claim();

        // ensure we got 10 esEmbr pending
        assertEq(10 * 1e18, esEmbr.balanceOf(vesterTester));
        assertEq(10 * 1e18, claimed_amount);

        // Vesting should revert here, vested amount higher than balance
        vm.expectRevert("esEMBR: Amount exceeds your balance");
        esEmbr.vest(30 days, 10 * 1e18 + 1);

        // start vesting
        esEmbr.vest(oneMonthVester.vestingTime(), 10 * 1e18);

        // warp to when vesting is fully finished (+1 month)
        vm.warp(block.timestamp + oneMonthVester.vestingTime());

        // make sure its all vested and we can claim 2 EMBR (20% of 10 esEMBR)
        uint claimed = esEmbr.collectVested(oneMonthVester.vestingTime());
        assertEq(2 * 1e18, claimed);
        assertEq(embr.balanceOf(vesterTester), 2 * 1e18);

        // try claiming again and make sure it's 0
        claimed = esEmbr.collectVested(oneMonthVester.vestingTime());
        assertEq(0, claimed);
        assertEq(embr.balanceOf(vesterTester), 2 * 1e18);

    }

    // test vesting & batch collecting multiple timeframes
    function test_BatchVestCollecting() public {
        address vesterTester = address(0x13132738);
        vm.deal(vesterTester, 10 ether);

        // set distribution to 1 esEmbr per second
        distributor.setEmissionPerSecondEth(1 * 1e18);

        vm.startPrank(vesterTester);
        assertEq(0, embr.balanceOf(vesterTester));

        // stake 1 eth
        esEmbr.stakeEth{value: 1 ether}();

        // warp 20 seconds into the future
        vm.warp(block.timestamp + 20 seconds);

        // claim the esEmbr
        uint claimed_amount = esEmbr.claim();

        // ensure we got 20 esEmbr claimed
        assertEq(20 * 1e18, esEmbr.balanceOf(vesterTester));
        assertEq(20 * 1e18, claimed_amount);

        // vest 10 for 1 month and 10 for 3 months
        esEmbr.vest(oneMonthVester.vestingTime(), 10 * 1e18);
        esEmbr.vest(threeMonthVester.vestingTime(), 10 * 1e18);

        // warp to when both vesting periods are fully finished (+3 months)
        vm.warp(block.timestamp + threeMonthVester.vestingTime());

        // make sure its all vested and we can claim 2 EMBR (1m) + 5.5 EMBR (3m)
        uint[] memory timeframes = new uint[](2);
        timeframes[0] = oneMonthVester.vestingTime();
        timeframes[1] = threeMonthVester.vestingTime();

        uint claimed = esEmbr.batchCollectVested(timeframes);
        assertEq(2 ether + 5.5 ether, claimed); // ether but actually embr

        // try claiming again and make sure it's 0
        claimed = esEmbr.batchCollectVested(timeframes);
        assertEq(0, claimed);
    }

    function test_UnstakingEMBR() public {
        distributor.setEmissionPerSecondEmbr(1 * 1e18); // 1 esEMBR per second for embr stakers
        distributor.setEmissionPerSecondEth(1 * 1e18); // 1 esEMBR per second for eth stakers
        
        // Mint some embr so staker1 & staker2 can stake them
        embr.mint(200_000 * 1e18);

        address staker1 = address(0x138712a839765);
        vm.deal(staker1, 10_000 ether);
        embr.transfer(staker1, 100_000 * 1e18);

        vm.startPrank(staker1);

        embr.approve(address(esEmbr), type(uint).max);

        vm.expectRevert("esEMBR: Staked amount cannot be 0");
        esEmbr.stakeEmbr(0);

        esEmbr.stakeEmbr(embr.balanceOf(staker1)); // Stake all our EMBR
        esEmbr.stakeEth{value: staker1.balance}(); // Stake all our ETH

        vm.warp(block.timestamp + 1 seconds);

        uint claimed = esEmbr.claim();
        assertEq(claimed, 2 ether); // we get 1 esEMBR for the embr stake and 1 esEMBR for the eth stake

        // Test unstaking
        {
            // Test unstaking EMBR
            assertEq(embr.balanceOf(staker1), 0);
            esEmbr.unstakeEmbr(100_000 * 1e18);
            assertEq(embr.balanceOf(staker1), 100_000 * 1e18);

            // Test unstaking ETH
            assertEq(staker1.balance, 0);
            esEmbr.unstakeEth(10_000 ether);
            assertEq(staker1.balance, 10_000 ether);

            // Try claiming again
            claimed = esEmbr.claim();
            assertEq(claimed, 0); // we should get 0 since we just unstaked

            // Unstaking again should fail
            vm.expectRevert("esEMBR: Requested amount exceeds staked amount");
            esEmbr.unstakeEmbr(100_000 * 1e18);

            vm.expectRevert("esEMBR: Requested amount exceeds staked amount");
            esEmbr.unstakeEth(10_000 ether);
        }

        // Stake all our embr/eth again, this time a new staker will join along with staker1
        esEmbr.stakeEmbr(embr.balanceOf(staker1));
        esEmbr.stakeEth{value: staker1.balance}();

        vm.stopPrank();

        // warp 10 seconds into the future
        vm.warp(block.timestamp + 10 seconds);

        // At this point, staker1 should have 20 esEMBR claimable. 10 from embr staking and 10 from eth staking. 
        // Staker1's current rate is 2 esEMBR per second
        assertEq(esEmbr.claimable(staker1), 20 * 1e18);

        // Another staker joins with the same position size as staker1
        address staker2 = address(0x8164959123612);
        vm.deal(staker2, 10_000 ether);
        embr.transfer(staker2, 100_000 * 1e18);

        // Staker2 will now stake and be eligible for 50% of rewards
        {
            vm.startPrank(staker2);
            embr.approve(address(esEmbr), type(uint).max);

            esEmbr.stakeEmbr(embr.balanceOf(staker2)); // Stake all the EMBR
            esEmbr.stakeEth{value: staker2.balance}(); // Stake all the ETH

            // After staker2 staked, staker1 will now be receiving 50% of the rewards instead of 100%
            // Rate is 1 esEMBR for both stakers (0.5 for eth and 0.5 for embr)
            vm.warp(block.timestamp + 10 seconds);

            // 10 seconds after staking, staker2 claims their esEMBR, should be 1 esEMBR * 10s
            claimed = esEmbr.claim();
            assertEq(claimed, 1 ether * 10); // ether = esEMBR

            vm.stopPrank();
        }

        {
            vm.startPrank(staker1);

            // 10 seconds after staker2 staked, staker1 claims their esEMBR, should be 20 esEMBR + (1 esEMBR * 10s)
            claimed = esEmbr.claim();
            assertEq(claimed, 20 ether + (1 ether * 10)); // ether = esEMBR

            vm.stopPrank();
        }

        // Staker1 will now unstake all their assets
        vm.startPrank(staker1);
        esEmbr.unstakeEmbr(100_000 * 1e18);
        esEmbr.unstakeEth(10_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 seconds);

        // Staker2 is now supposed to be receiving 2 esEMBR per second
        vm.startPrank(staker2);
        claimed = esEmbr.claim();
        assertEq(claimed, 20 * 1e18); // 10 seconds passed, so 20 esEMBR

        esEmbr.unstakeEmbr(100_000 * 1e18);
        esEmbr.unstakeEth(10_000 ether);
        vm.stopPrank();
    }

    // Interest made from paid off token should be revshared to esEMBR holders
    function test_RevShare_Interest() public {
        distributor.setEmissionPerSecondEth(1 * 1e18); // 1 esEMBR per second for eth stakers

        // Get some esEMBR to be eligible for revshare
        address rando = address(0x1923891481247);
        vm.deal(rando, 1 ether);

        {
            vm.startPrank(rando);
            esEmbr.stakeEth{value: 0.01 ether}();

            // Warp 20 seconds into the future and claim our 20 esEMBR
            vm.warp(block.timestamp + 20 seconds);
            esEmbr.claim();
            assertEq(esEmbr.balanceOf(rando), 20 * 1e18);
            vm.stopPrank();
        }

        EmberVault.Package memory package = EmberVault.Package({
            Enabled: 1,
            Price: 1 ether,
            BorrowedLiquidity: 10 ether,
            Duration: 13,
            DebtGrowthPerWeek: 65
        });

        vault.addPackage(package);

        // Create a token from vault
        GenericERC20Token.ConstructorCalldata memory tokenParams = GenericERC20Token.ConstructorCalldata({
            Name: "test",
            Symbol: "TEST",
            Decimals: 18,

            MaxSupply: 200_000_000 * 1e18,
            TotalSupply: 133_333_337 * 1e18,

            BuyTax: 50,
            SellTax: 50,
            SellThreshold: 0, // Sell every tx
            TransferBurnTax: 10,
            UniV2Factory: UNI_FACTORY,
            UniV2SwapRouter: UNI_ROUTER,
            MaxSizePerTx: type(uint).max,
            MaxHoldingAmount: type(uint).max
        });

        // This will send 1 ether to the esEMBR contract to be revshared, because someone just bought a package
        address payable tokenAddress = payable(address(vault.create{value: 1 ether}(tokenParams, 0)));
        GenericERC20Token token = GenericERC20Token(tokenAddress);

        // Warp 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        // Then a few days later
        vm.warp(block.timestamp + 6 days);

        // Pay off all the debt
        uint to_pay = 10.065 ether;
        (uint80 collectedEth,,, uint totalPaid) = vault.payup{value: to_pay}(token);
        assertEq(collectedEth, to_pay);
        assertEq(totalPaid, to_pay);

        // 0.065 should have been sent to esEMBR and ready to be revshared to users that were holding esEMBR during that period

        // A new user will join and be eligible for revshare but shouldn't receive any of the revenue made from actions before they joined
        address rando2 = address(0x192471945123);
        vm.deal(rando2, 1 ether);

        {
            vm.startPrank(rando2);
            esEmbr.stakeEth{value: 0.01 ether}();

            // Warp 20 seconds into the future and claim 10 esEMBR
            vm.warp(block.timestamp + 20 seconds);
            esEmbr.claim();
            assertEq(esEmbr.balanceOf(rando2), 10 * 1e18);
            vm.stopPrank();
        }

        // Make sure rando 2 isn't getting any revshare
        {
            vm.startPrank(rando2);

            uint balance_before_claiming = rando2.balance;
            uint claimed_eth = esEmbr.claimRevShare();
            assertEq(claimed_eth, 0);
            assertEq(rando2.balance, balance_before_claiming);

            vm.stopPrank();
        }

        {
            vm.startPrank(rando);

            uint balance_before_claiming = rando.balance;
            uint claimed_eth = esEmbr.claimRevShare();
            assertEq(claimed_eth, 1 ether + 0.065 ether); // 1eth from package cost and 0.065 from interest
            assertEq(rando.balance, balance_before_claiming + claimed_eth);

            vm.stopPrank();
        }
    }

    // Check if package cost fees are revshared
    function test_Revshare_PackageCost() public {
        // Set distribution to 1 esEMBR per second
        distributor.setEmissionPerSecondEth(1 * 1e18);
        distributor.setEmissionPerSecondEmbr(1 * 1e18);

        // give the user some esEmbr
        // send some eth to the esEmbr contract
        // the user should be able to claim it
        address revshareTester = address(0x1239018239213c71238);
        vm.deal(revshareTester, 10 ether); // deal 10eth

        {
            vm.startPrank(revshareTester);

            // stake some eth
            esEmbr.stakeEth{value: 1 ether}(); // stake 1e

            // warp 20 seconds into the future
            vm.warp(block.timestamp + 20 seconds);

            // claim the esEmbr
            uint claimed = esEmbr.claim();

            // ensure we got 20 esEmbr
            assertEq(20 * 1e18, esEmbr.balanceOf(revshareTester));
            assertEq(claimed, 20 * 1e18);

            // Try to claim again and make sure we didn't get any extra token
            claimed = esEmbr.claim();
            assertEq(20 * 1e18, esEmbr.balanceOf(revshareTester));
            assertEq(claimed, 0);

            vm.stopPrank();
        }

        // add a second address
        address revshareTester2 = address(0x0912930123);
        vm.deal(revshareTester2, 10 ether); // deal 10eth

        {
            vm.startPrank(revshareTester2);

            assertEq(0, embr.balanceOf(revshareTester2));

            // stake some eth
            esEmbr.stakeEth{value: 1 ether}(); // stake 1e

            // warp 10 seconds
            vm.warp(block.timestamp + 10 seconds);

            // claim the esEmbr
            uint claimed = esEmbr.claim();

            // ensure we got 5 esEmbr pending, cuz now revshareTester2 accounts for 50% of distribution with his 1e staked
            assertEq(5 * 1e18, esEmbr.balanceOf(revshareTester2));
            assertEq(claimed, 5 * 1e18);

            claimed = esEmbr.claim();
            assertEq(claimed, 0);
            assertEq(5 * 1e18, esEmbr.balanceOf(revshareTester2));

            vm.stopPrank();
        }

        {
            // send eth to esEmbr from vault, as if someone just bought a package
            vm.prank(address(vault));

            (bool success, ) = address(esEmbr).call{value: 1 ether}("");
            require(success);
        }


        // At this point user1 has 20 esEmbr, user2 has 5 esEmbr. User1 will get 80% of revshare, User2 will get 20% of revshare.

        // check if its claimable
        assertEq(0.8 ether, esEmbr.claimableRevShare(revshareTester));
        assertEq(0.2 ether, esEmbr.claimableRevShare(revshareTester2));

        {
            // Claim tester1
            vm.startPrank(revshareTester);

            // check if claiming works correctly
            uint balance_before_claiming = revshareTester.balance;
            uint claimed_amount = esEmbr.claimRevShare();

            assertEq(revshareTester.balance, balance_before_claiming + claimed_amount);
            assertEq(claimed_amount, 0.8 ether);

            // Claim again and make sure we get nothing this time
            claimed_amount = esEmbr.claimRevShare();
            assertEq(claimed_amount, 0);
            assertEq(revshareTester.balance, balance_before_claiming + 0.8 ether); // balance should stay same as before this claim

            vm.stopPrank();
        }

        {
            // Claim tester2
            vm.startPrank(revshareTester2);

            // check if claiming works correctly
            uint balance_before_claiming = revshareTester2.balance;
            uint claimed_amount = esEmbr.claimRevShare();

            assertEq(revshareTester2.balance, balance_before_claiming + claimed_amount);
            assertEq(claimed_amount, 0.2 ether);

            // Remove esEmbr from user2.
            esEmbr.vest(oneMonthVester.vestingTime(), 5 * 1e18);
            assertEq(0, esEmbr.balanceOf(revshareTester2));

            vm.stopPrank();
        }

        {
            // Now user1 is the only user with esEmbr which should now get 100% of revshare, aka 1eth
            vm.prank(address(vault));
            (bool success, ) = address(esEmbr).call{value: 1 ether}("");
            require(success);

            vm.startPrank(revshareTester);
            uint balance_before_claiming = revshareTester.balance;
            assertEq(1 ether, esEmbr.claimableRevShare(revshareTester));

            uint claimed_amount = esEmbr.claimRevShare();
            assertEq(revshareTester.balance, balance_before_claiming + claimed_amount);
            assertEq(claimed_amount, 1 ether);
        }
    }

    receive() external payable {}
}

