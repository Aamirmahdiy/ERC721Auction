// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PublicBidERC721Auction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract AuctionFullTest is Test {
    PublicBidERC721Auction auction;
    MockNFT nft;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob   = address(0x3);
    address eve   = address(0x4);

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(eve, 100 ether);

        nft = new MockNFT();
        vm.prank(owner);
        nft.mint(owner, 1);

        vm.prank(owner);
        nft.approve(address(this), 1);

        vm.prank(owner);
        auction = new PublicBidERC721Auction(address(nft), 1, 1 days);

        vm.prank(owner);
        nft.approve(address(auction), 1);
    }

    function testConstructorOwnershipRequirement() public {
    // Eve mints the NFT, not `owner`
    vm.prank(eve);
    nft.mint(eve, 99);

    vm.prank(owner);
    vm.expectRevert("Seller must own the NFT");
    new PublicBidERC721Auction(address(nft), 99, 1 days);
}


    function testInitialTopBid() public view {
        (address bidder, uint256 amount) = auction.topBid();
        assertEq(bidder, address(0));
        assertEq(amount, 0);
    }

    function testBid() public {
        vm.prank(alice);
        auction.bid{value: 2 ether}();
        assertEq(auction.bids(alice), 2 ether);
    }

    function testUpdateBid() public {
        vm.prank(alice);
        auction.bid{value: 2 ether}();
        vm.prank(alice);
        auction.updateBid{value: 1 ether}(3 ether);
        assertEq(auction.bids(alice), 3 ether);
    }

    function testUpdateBidInvalid() public {
        vm.prank(alice);
        auction.bid{value: 2 ether}();
        vm.prank(alice);
        vm.expectRevert("New bid must be higher");
        auction.updateBid{value: 0 ether}(2 ether);

        vm.prank(alice);
        vm.expectRevert("Send exact delta");
        auction.updateBid{value: 2 ether}(3 ether);
    }

    function testZeroBidNotAllowed() public {
        vm.prank(alice);
        vm.expectRevert("Zero bid not allowed");
        auction.bid{value: 0}();
    }

    function testCannotBidAfterDeadline() public {
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vm.expectRevert("Bidding period over");
        auction.bid{value: 1 ether}();
    }

    function testFinalizeBeforeDeadlineFails() public {
        vm.prank(alice);
        vm.expectRevert("Auction still ongoing");
        auction.finalize();
    }

    function testFinalizeNoBidsFails() public {
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vm.expectRevert("No bids placed");
        auction.finalize();
    }

    function testFinalizeAndTransfer() public {
        vm.prank(alice);
        auction.bid{value: 5 ether}();

        vm.warp(block.timestamp + 2 days);
        auction.finalize();

        assertEq(nft.ownerOf(1), alice);
        assertEq(owner.balance, 105 ether);
    }

    function testAutoFinalizeOnWithdraw() public {
        vm.prank(alice);
        auction.bid{value: 3 ether}();
        vm.prank(bob);
        auction.bid{value: 4 ether}();

        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        auction.withdraw(); // auto-finalize

        assertEq(nft.ownerOf(1), bob);
        assertEq(owner.balance, 104 ether);
        assertEq(alice.balance, 100 ether);
    }

    function testWithdrawOnlyLosingBidders() public {
    vm.prank(alice);
    auction.bid{value: 6 ether}();
    vm.prank(bob);
    auction.bid{value: 7 ether}();

    vm.warp(block.timestamp + 2 days);
    auction.finalize();

    uint256 aliceBefore = alice.balance;

    vm.prank(alice);
    auction.withdraw();

    uint256 aliceAfter = alice.balance;
    assertEq(aliceAfter, aliceBefore + 6 ether);

    vm.prank(bob);
    vm.expectRevert(); // Don't rely on exact message here
    auction.withdraw();

}


    function testWithdrawNothingFails() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();
        vm.warp(block.timestamp + 2 days);
        auction.finalize();

        vm.prank(bob);
        vm.expectRevert("Nothing to withdraw");
        auction.withdraw();
    }
}
