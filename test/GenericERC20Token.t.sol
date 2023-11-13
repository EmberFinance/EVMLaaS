// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/GenericERC20Token.sol";
import "solady/src/utils/ECDSA.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import "./../src/IUniswapV2Router01.sol";
import "./../src/IWETH.sol";
import "solmate/tokens/ERC721.sol";
import "../src/EmberVault.sol";

using ECDSA for bytes32;

contract GenericERC20TokenTest is Test, ERC721TokenReceiver {
    address UNI_ROUTER = 0xf164fC0Ec4E93095b804a4795bBe1e041497b92a;
    address UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    GenericERC20Token.ConstructorCalldata params = GenericERC20Token.ConstructorCalldata({
        Name: "test",
        Symbol: "TEST",
        Decimals: 18,

        MaxSupply: 200_000_000 * 1e18,
        TotalSupply: 133_333_337 * 1e18,

        BuyTax: 50,
        SellTax: 50,
        SellThreshold: 1000 * 1e18,
        TransferBurnTax: 10,
        UniV2Factory: UNI_FACTORY,
        UniV2SwapRouter: UNI_ROUTER,
        MaxSizePerTx: 1_000_000 * 1e18,
        MaxHoldingAmount: 5_000_000 * 1e18
    });

    function setUp() public {

    }

    function test_MintFailsAfterDisabling() public {
        params.TotalSupply = 133_333_337 * 1e18;
        params.MaxSupply = 200_000_000 * 1e18;

        GenericERC20Token token = new GenericERC20Token(params, address(0));

        // Disable minting
        token.disableMinting();

        vm.expectRevert("Total supply cannot exceed max supply");
        token.mint(address(this), 1);
    }

    function test_MintExceedMaxSupply() public {
        params.TotalSupply = 133_333_337 * 1e18;
        params.MaxSupply = 200_000_000 * 1e18;

        GenericERC20Token token = new GenericERC20Token(params, address(0));
        uint maxSupply = token.maxSupply();
        uint totalSupply = token.totalSupply();

        // Mint the rest of the supply
        address rando = address(0x420);
        token.mint(rando, maxSupply - totalSupply);

        assertEq(token.maxSupply(), token.totalSupply());

        vm.expectRevert("Total supply cannot exceed max supply");
        token.mint(rando, 1);
    }

    function test_TransferBurnTax() public {
        params.TransferBurnTax = 50;
        GenericERC20Token token = new GenericERC20Token(params, address(0));
        token.setInitialLiquidityPool(address(0x1337)); // Have to do this to enable transfers

        vm.warp(block.timestamp + 2 minutes);

        assertEq(token.burnTax(), 50);

        uint burn_balance = token.balanceOf(address(0));
        assertEq(burn_balance, 0);

        address user = address(0x141414);
        address user2 = address(0x151515);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(user2), 0);

        uint amount_to_mint = 1_000_000 * 1e18;
        token.mint(user, amount_to_mint);

        vm.startPrank(user);
        token.transfer(user2, amount_to_mint);

        assertEq(token.balanceOf(user2), (amount_to_mint * 95) / 100); // 95% to the user
        assertEq(token.balanceOf(address(0)), (amount_to_mint * 5) / 100); // 5% to burn addy
    }

    function test_TransferAndHoldingLimits() public {
        params.TransferBurnTax = 0;
        params.MaxSizePerTx = 25_000 * 1e18;
        params.MaxHoldingAmount = 30_000 * 1e18;

        GenericERC20Token token = new GenericERC20Token(params, address(0));
        token.setInitialLiquidityPool(address(0x1337)); // Have to do this to enable transfers

        vm.warp(block.timestamp + 2 minutes);

        address alice = address(0x192381241203);
        address bob = address(0x1203812931203);
    
        token.mint(alice, params.MaxSizePerTx);

        vm.prank(alice);
        token.transfer(bob, params.MaxSizePerTx);

        vm.prank(bob);
        token.transfer(alice, params.MaxSizePerTx);

        token.mint(bob, 5_000 * 1e18);
        
        vm.prank(bob);
        token.transfer(alice, 5_000 * 1e18);

        assertEq(token.balanceOf(alice), 30_000 * 1e18);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        vm.expectRevert("Max size per tx exceeded");
        token.transfer(bob, 30_000 * 1e18);
        vm.stopPrank();

        // Test max holding limit by sending 31k tokens to bob in 2 transfers
        token.mint(alice, 1_000 * 1e18);
        vm.startPrank(alice);

        token.transfer(bob, 25_000 * 1e18);

        vm.expectRevert("Max holding per wallet exceeded");
        token.transfer(bob, 6_000 * 1e18);

        vm.stopPrank();
    }

    receive() external payable { }

    function test_WithdrawEthAndTokens() public {
        params.MaxSizePerTx = type(uint).max;
        params.MaxHoldingAmount = type(uint).max;
        params.TotalSupply = 133_333_337 * 1e18;

        // The token already mints params.TotalSupply tokens to itself
        GenericERC20Token token = new GenericERC20Token(params, address(0));
        token.setInitialLiquidityPool(address(0x15451)); // Have to do this to enable transfers

        uint contract_token_balance = token.balanceOf(address(token));

        assertEq(contract_token_balance, params.TotalSupply);
        
        // Test withdrawing tokens
        token.withdrawTokens();
        assertEq(token.balanceOf(address(this)), contract_token_balance);

        // Test withdrawing ETH
        (bool status, ) = address(token).call{value: 1 ether}("");
        assertEq(status, true);

        uint balance_before_withdrawing = address(this).balance;
        token.withdrawEth();

        assertEq(address(this).balance, balance_before_withdrawing + 1 ether); // make sure 1 eth is back into our balance
    }
}
