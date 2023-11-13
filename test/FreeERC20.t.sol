// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FreeERC20.sol";
import "solady/src/utils/ECDSA.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import "./../src/IUniswapV2Router01.sol";

using ECDSA for bytes32;

contract FreeTokenTest is Test {
    ERC20Token public token;

    function setUp() public {
        // token = new ERC20Token("kek", "KEK", 4, 1000_0000, 1000_0000, 10_0000, 5, 5, 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    function testUserDeposit() public {
        // console.log(address(token));
        // // Deposit
        // address depositor = token.owner();
        // console.log(depositor);
        // console.log(token.balanceOf(depositor));
        // uint ethToAdd = 2 ether;
        // uint tokenToAdd = 200_0000; // 200 tokens at 4 decimals
        // vm.startPrank(depositor);
        // vm.deal(depositor, 5 ether);
        // token.addLp{value: ethToAdd}(tokenToAdd);
        // address pair = token.uniV2Pair();
        // ERC20 weth = ERC20(token.weth());
        // assertEq(weth.balanceOf(pair), ethToAdd);
        // assertEq(token.balanceOf(pair), tokenToAdd);
        // assertTrue(ERC20(pair).balanceOf(depositor) != 0);

        // // try buying and seling on god
        // token.enableTrading();

        // uint buyAmountEth = 0.05 ether;
        // uint beforeTokenBalance = token.balanceOf(depositor);

        // // buying
        // address[] memory path = new address[](2);
        // path[0] = address(weth);
        // path[1] = address(token);
        // IUniswapV2Router01(token.uni_router()).swapExactETHForTokens{value: buyAmountEth}(0, path, depositor, 999999999999999);

        // uint afterTokenBalance = token.balanceOf(depositor);

        // uint collectedTaxesAfterBuy = token.balanceOf(address(token));
        // console.log(collectedTaxesAfterBuy);

        // assertTrue(collectedTaxesAfterBuy != 0);
        // assertTrue(afterTokenBalance > beforeTokenBalance);

        // // selling

        // vm.stopPrank();
    }
}
