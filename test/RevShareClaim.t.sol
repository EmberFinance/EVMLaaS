// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FreeERC20.sol";
import "solady/src/utils/ECDSA.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import "./../src/IUniswapV2Router01.sol";
import "solady/src/utils/ECDSA.sol";
import "./../src/RevShareClaim.sol";

using ECDSA for bytes32;

contract FreeTokenTest is Test {
    RevShare public claimManager;

    uint constant presaleSignerPK = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    address public constant presaleSigner = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    function setUp() public {
        claimManager = new RevShare(presaleSigner);
        claimManager.deposit{value: 5 ether}();
    }

    function testUserClaim() public {
        address depositor = address(0x1337);
        vm.deal(depositor, 500 ether);

        vm.startPrank(depositor);

        bytes32 digest = keccak256(abi.encodePacked(depositor, uint(1), uint(5 ether))).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(presaleSignerPK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint balance_before = address(depositor).balance;
        claimManager.claim(1, 5 ether, signature);
        uint balance_after = address(depositor).balance;

        assertEq(balance_after, balance_before + 5 ether);

        vm.expectRevert("ETH already claimed");
        claimManager.claim(1, 5 ether, signature);

        vm.expectRevert("Invalid claim id");
        claimManager.claim(2, 5 ether, signature);
    }
}
