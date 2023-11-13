// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/GenericERC20Token.sol";
import "solady/src/utils/ECDSA.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import "./../src/IUniswapV2Router02.sol";
import "./../src/IWETH.sol";
import "../src/EmberVault.sol";
import "../src/EMBR.sol";
import "../src/EsEMBR.sol";
import "../src/EsEMBRRewardsDistributor.sol";

contract EmberVaultTest is Test {
    using ECDSA for bytes32;
    
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    address UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    GenericERC20Token.ConstructorCalldata params =
        GenericERC20Token.ConstructorCalldata({
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

    uint mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
    }

    function test_TransferFailsFirstMinute() public {
        vm.selectFork(mainnetFork);

        (, GenericERC20Token token,) = setupVault(params);
        address swap_router = token.swapRouter();
        token.approve(swap_router, type(uint).max);

        address[] memory buyPath = getBuyPath(token);
        address[] memory sellPath = getSellPath(token);

        vm.expectRevert();
        IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, address(this), block.timestamp); // Buy 1 ether worth

        // Buying should work now
        vm.warp(block.timestamp + 1 minutes + 1 seconds);
        IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, address(this), block.timestamp); // Buy 1 ether worth

        // Sell all tokens
        IUniswapV2Router02(swap_router).swapExactTokensForETHSupportingFeeOnTransferTokens(token.balanceOf(address(this)), 0, sellPath, address(this), block.timestamp);
    }

    function test_PayupAccessControl() public {
        vm.selectFork(mainnetFork);

        (EmberVault vault, GenericERC20Token token,) = setupVault(params);

        // Test that you can't call payup if you aren't owner
        vm.startPrank(address(0x1337));
        vm.expectRevert("Vault: Only token deployer can claim fees");
        vault.payup(token);
        vm.stopPrank();

        // Test that you can't call payup on random addresses
        vm.expectRevert("Vault: Only token deployer can claim fees");
        vault.payup(GenericERC20Token(payable(address(0x13374242912992))));

        vm.expectRevert("Vault: Only token deployer can claim fees");
        vault.payup(GenericERC20Token(payable(address(0))));
    }

    // Tests that tokens are sold after every sell when threshold is reached
    function test_BuySellTax() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1000 ether);

        params.SellThreshold = 30_000 * 1e18;
        (EmberVault vault, GenericERC20Token token,) = setupVault(params);
        address swap_router = token.swapRouter();

        address[] memory buyPath = getBuyPath(token);
        address[] memory sellPath = getSellPath(token);

        // Approve our tokens for selling
        token.approve(swap_router, type(uint).max);

        // Trading should not be enabled yet
        vm.expectRevert();
        IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, address(this), block.timestamp); // Buy 1 ether worth

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        // Buy 100eth worth of tokens
        for (uint256 i = 0; i < 100; i++) {
            IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, address(this), block.timestamp); // Buy 1 ether worth
        }

        uint token_balance = token.balanceOf(address(this));

        // Sell almost all of our tokens in chunks
        for (uint256 i = 0; i < 100; i++) {
            uint contract_eth_balance = address(token).balance;
            uint contract_token_balance = token.balanceOf(address(token));

            IUniswapV2Router02(swap_router).swapExactTokensForETHSupportingFeeOnTransferTokens(token_balance / 100, 0, sellPath, address(this), block.timestamp);

            if (contract_token_balance > params.SellThreshold) {
                assertGt(address(token).balance, contract_eth_balance); // Token contract should've sold tokens for eth
            } else {
                assertEq(address(token).balance, contract_eth_balance); // Token contract should have the same amount of eth as before the sale
            }
        }

        // Test paying off debt
        vault.tokens(address(token));

        for (uint256 i = 0; i < 13; i++) {
            (, uint80 newDebt,,) = vault.payup(token);
            if (newDebt == 0) {
                // Should throw this error because the debt has been paid off and the token owner/info has been deleted `delete tokenDeployers[address(token)];`
                vm.expectRevert("Vault: Only token deployer can claim fees");
                vault.payup(token);

                break;
            }

            // Buy 1 ether worth
            IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 20 ether}(0, buyPath, address(this), block.timestamp); 

            // Sell it all
            IUniswapV2Router02(swap_router).swapExactTokensForETHSupportingFeeOnTransferTokens(token.balanceOf(address(this)), 0, sellPath, address(this), block.timestamp);

            vm.warp(block.timestamp + 1 weeks + 1 hours); // travel 1 week into the future
        }
    }

    // Tests pulling liq after a project fails to meet the volume/payoff requirements
    function test_FailedProject_PullLiq() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1_000 ether);

        params.SellThreshold = 0;
        (EmberVault vault, GenericERC20Token token,) = setupVault(params);
        address swap_router = token.swapRouter();

        address[] memory buyPath = getBuyPath(token);
        address[] memory sellPath = getSellPath(token);

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        // random user will now buy 1 eth worth
        address rando = address(0x4200000000000000100);
        vm.deal(rando, 1 ether);
        vm.startPrank(rando);

        token.approve(swap_router, type(uint).max);

        // Buy 1 ether worth
        IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, rando, block.timestamp); 

        // Sell it all
        IUniswapV2Router02(swap_router).swapExactTokensForETHSupportingFeeOnTransferTokens(token.balanceOf(rando), 0, sellPath, rando, block.timestamp); 

        vm.stopPrank();

        // Payup whatever amount was made from fees
        vault.payup(token);

        // Random user will try to pull liq everyday for the next 6 days
        for (uint i = 0; i < 7; i++) {
            vm.startPrank(address(0x6966666666666));

            vm.expectRevert("Vault: Only unhealthy tokens can be liquidated");
            vault.tryPullLiq(token, 0);

            vm.stopPrank();
            vm.warp(block.timestamp + 1 days);
        }

        // We on the 7th day here, pulling liq should work
        address puller = address(0x1333333333337);
        vm.prank(puller);
        vault.tryPullLiq(token, 0);
        assert(IERC20(vault.esEmbr()).balanceOf(puller) != 0);
    }

    // Tests claiming share from claims after a project fails (using LP token)
    function test_FailedProject_ClaimingUsingLPToken() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1_000 ether);

        params.SellThreshold = 0;
        (EmberVault vault, GenericERC20Token token,) = setupVault(params);
        address swap_router = token.swapRouter();

        address[] memory buyPath = getBuyPath(token);

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        address lp_provider = address(0x1337420696969);
        vm.deal(lp_provider, 2 ether);
        vm.startPrank(lp_provider);

        // Buy 1eth worth of tokens
        IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, lp_provider, block.timestamp); // Buy 1 ether worth

        // Add to LP
        token.approve(swap_router, type(uint).max);
        IUniswapV2Router01(swap_router).addLiquidityETH{value: 1 ether}(
            address(token),
            token.balanceOf(lp_provider),
            0,
            0,
            lp_provider,
            block.timestamp
        );

        vm.warp(block.timestamp + 1 weeks + 1 days);

        vm.stopPrank();

        // rando will pull liq
        vm.prank(address(0x1923710588119));
        vault.tryPullLiq(token, 0);

        // LP provider will now try to claim their eth after liq is pulled
        vm.startPrank(lp_provider);

        uint eth_balance_before_redeeming = lp_provider.balance;

        IUniswapV2Pair lp_token = IUniswapV2Pair(token.initial_liquidity_pool());
        lp_token.approve(address(vault), type(uint).max);

        uint redeemed_eth = vault.redeemLPToken(token, lp_token.balanceOf(lp_provider));

        assertGt(address(lp_provider).balance, eth_balance_before_redeeming); // New user balance should be higher than before redeeming
        assertEq(address(lp_provider).balance, eth_balance_before_redeeming + redeemed_eth); // New user balance should be increased by the returned value
    }

    // Tests claiming share from claims after a project fails (using token)
    function test_FailedProject_ClaimingUsingToken() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1000 ether);

        params.SellThreshold = 0;
        (EmberVault vault, GenericERC20Token token,) = setupVault(params);
        address swap_router = token.swapRouter();

        address[] memory buyPath = getBuyPath(token);
        // address[] memory sellPath = getSellPath(token);

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        // 100 random users will buy 1 eth worth (address(1-101)
        uint160 start = 0x1337420696969;
        for (uint i = 0; i < 100; i++) {
            address rando = address(uint160(start + i));
            vm.deal(rando, 1 ether);

            vm.prank(rando);
            IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, rando, block.timestamp); // Buy 1 ether worth
        }

        vm.warp(block.timestamp + 1 weeks + 1 days);
        vault.tryPullLiq(token, 0);

        // Users will now try to claim their eth after liq is pulled
        for (uint i = 0; i < 100; i++) {
            address rando = address(uint160(start + i));
            uint token_balance = token.balanceOf(rando);
            uint eth_balance_before_redeeming = rando.balance;

            vm.prank(rando);
            uint redeemed_eth = vault.redeemToken(token, token_balance);

            assertGt(address(rando).balance, eth_balance_before_redeeming); // New user balance should be higher than before redeeming
            assertEq(address(rando).balance, eth_balance_before_redeeming + redeemed_eth); // New user balance should be increased by the returned value
            assertEq(token.balanceOf(rando), 0); // Make sure the tokens were yoinked from the user
        }
    }

    // Tests that esEMBR is rewarded properly to the user that successfully calls tryPullLiq
    // Tests claiming share from claims after a project fails
    function test_FailedProject_PullLiqRewards() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1000 ether);

        params.SellThreshold = 0;
        (EmberVault vault, GenericERC20Token token,) = setupVault(params);

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        vm.warp(block.timestamp + 1 weeks + 1 days);

        // Some rando will now try to pull liq
        address rando = address(0x12937142041);

        vm.startPrank(rando);
        vault.tryPullLiq(token, 0);
        assertGt(EsEMBR(vault.esEmbr()).balanceOf(rando), 0);
    }

    // Tests that ownership is transferred properly after debt is fully paid off
    function test_SuccessfulProject_OwnershipTransferred() public {
        vm.selectFork(mainnetFork);

        vm.deal(address(this), 1000 ether);

        params.SellThreshold = 0;
        (EmberVault vault, GenericERC20Token token, EmberVault.Package memory package) = setupVault(params);
        address swap_router = token.swapRouter();

        address[] memory buyPath = getBuyPath(token);
        address[] memory sellPath = getSellPath(token);

		IERC20 lp = IERC20(vault.liquidityPools(address(token)));
		uint256 vault_lp_balance = lp.balanceOf(address(vault));

        // Approve our tokens for selling
        token.approve(swap_router, type(uint).max);

        // Forward 2 minutes into the future when trading is enabled
        vm.warp(block.timestamp + 2 minutes);

        // Buy 100eth worth of tokens
        uint160 start = 4178298361240123;
        for (uint i = 0; i < package.Duration; i++) {
            // Every week, simulate lots of buy and sell volume
            for (uint160 j = 0; j < 100; j++) {
                address him = address(start + j);

                vm.deal(him, 1 ether);
                vm.startPrank(him);

                token.approve(swap_router, type(uint).max);
                IUniswapV2Router02(swap_router).swapExactETHForTokens{value: 1 ether}(0, buyPath, him, block.timestamp); // Buy 1 ether worth
                IUniswapV2Router02(swap_router).swapExactTokensForETHSupportingFeeOnTransferTokens(token.balanceOf(him), 0, sellPath, address(this), block.timestamp);

                vm.stopPrank();
            }

			console.log(vault_lp_balance, lp.balanceOf(address(vault)));
            (, uint80 debtLeft,,) = vault.payup(token);
            if (debtLeft == 0) {
                break;
            }

            vm.warp(block.timestamp + 1 weeks);
        }

        assertEq(token.owner(), address(this)); 
        assertEq(uint(token.emberStatus()), uint(GenericERC20Token.EmberDebtStatus.PAID_OFF));
		assertEq(lp.balanceOf(address(this)), vault_lp_balance); // make sure lp token was transfered
		assertEq(lp.balanceOf(address(vault)), 0); // make sure lp token was transfered
    }

    function setupVault(GenericERC20Token.ConstructorCalldata memory tokenParams) public returns(EmberVault, GenericERC20Token, EmberVault.Package memory) {
        EMBRToken embr = new EMBRToken();
        embr.mint(15_000_000 * 1e18);
        embr.enableTrading();

        EmberVault vault = new EmberVault(tokenParams.UniV2SwapRouter, tokenParams.UniV2Factory);

        EsEMBRRewardsDistributor distributor = new EsEMBRRewardsDistributor();

        EsEMBR esEmbr = new EsEMBR(payable(address(embr)), address(distributor), payable(address(vault)));
        embr.excludeWhale(address(esEmbr));
        embr.transfer(address(esEmbr), 15_000_000 * 1e18);

        distributor.setEsEMBR(payable(address(esEmbr)));
        vault.setEsEMBR(payable(address(esEmbr)));

        EmberVault.Package memory package = EmberVault.Package({
            Enabled: 1,
            Price: 0.02 ether,
            BorrowedLiquidity: 10 ether,
            Duration: 13,
            DebtGrowthPerWeek: 65
        });

        vault.addPackage(package);

        {
            // Random nice staker will now stake 10k eth
            address randomStaker = address(0x128371924b12311);
            vm.deal(randomStaker, 10_000 ether);

            vm.prank(randomStaker);
            esEmbr.stakeEth{value: 10_000 ether}();
        }

        address payable tokenAddress = payable(address(vault.create{value: package.Price}(tokenParams, 0)));
        GenericERC20Token token = GenericERC20Token(tokenAddress);

        // Set rate to 1 esEMBR per hour
        vault.setRewardSettings(vault.pullingBaseReward(), vault.pullingMaxHoursReward(), 1 * 1e18);

        return (vault, token, package);
    }

    function getSellPath(GenericERC20Token token) internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = token.WETH();

        return path;
    }

    function getBuyPath(GenericERC20Token token) internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = token.WETH();
        path[1] = address(token);

        return path;
    }


    receive() external payable {
        console.log("[Test] Received ether:", msg.value, "eth");
    }
}
