// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PublicBidERC721Auction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract Deploy is Script {
    function run() external {
        // Start sending transactions with your wallet
        vm.startBroadcast();

        // 1. Deploy MockNFT
        MockNFT nft = new MockNFT();

        // 2. Mint tokenId=1 to your address
        address sender = msg.sender;
        nft.mint(sender, 1);

        // 3. Approve the auction contract
        // We'll deploy the auction first and then approve

        // 4. Deploy the auction contract
        PublicBidERC721Auction auction = new PublicBidERC721Auction(
            address(nft),
            1,
            1 days
        );

        // 5. Approve the auction contract to transfer the NFT
        nft.approve(address(auction), 1);

        vm.stopBroadcast();
    }
}
