// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "solmate/auth/Owned.sol";
import "solady/src/utils/ECDSA.sol";

using ECDSA for bytes32;

contract RevShare is Owned {
    mapping(uint => mapping(address => bool)) public claims;
    address public claimSigner;
    bool public claimEnabled = true;

    uint public currentId = 1;

    constructor(address _claimSigner) Owned(msg.sender) public {
        claimSigner = _claimSigner;
    }

    function claim(uint id, uint amount, bytes memory signature) payable public {
        require(claimEnabled, "Claiming is not live");
        require(id == currentId, "Invalid claim id");
        require(!claims[id][msg.sender], "ETH already claimed");

        // Verify signature
        bytes32 hashed = keccak256(abi.encodePacked(msg.sender, id, amount));
        bytes32 message = ECDSA.toEthSignedMessageHash(hashed);
        address recovered_address = ECDSA.recover(message, signature);
        require(recovered_address == claimSigner, "Invalid signer");

        claims[id][msg.sender] = true;

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function setClaimSigner(address _claimSigner) onlyOwner external {
        claimSigner = _claimSigner;
    }

    function setId(uint _currentId) onlyOwner external {
        currentId = _currentId;
    }

    function increaseId() onlyOwner external {
        currentId++;
    }

    function deposit() onlyOwner payable external {
        // 
    }

    function withdraw() onlyOwner external {
        (bool sent,) = owner.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }
}
