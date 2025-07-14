// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Public‑Bid ERC‑721 Auction (Updatable Bids)
 * @notice Transparent ascending auction where every bid is visible on‑chain.
 *         • Users can place **and increase** their bids before the deadline.
 *         • Zero‑value bids are rejected.
 *         • Helper `topBid()` exposes the leading bid.
 *         • Highest bidder at deadline wins the NFT; others can withdraw.
 *         • Extra safety: constructor checks NFT ownership, finalize blocked if no bids, and internal state reset after finalize.
 */

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract PublicBidERC721Auction {
    /* ───────────────────────────────────────────────────────────────
     * Immutable configuration
     * ──────────────────────────────────────────────────────────── */
    address public immutable owner;    // seller / deployer
    IERC721 public immutable nft;      // NFT contract
    uint256 public immutable tokenId;  // Token being auctioned

    uint256 public immutable bidDeadline; // bidding phase end (unix time)

    /* ───────────────────────────────────────────────────────────────
     * Bid state
     * ──────────────────────────────────────────────────────────── */
    mapping(address => uint256) public bids;  // total bid per bidder

    address public highestBidder;
    uint256 public highestBid;
    bool    public finalized;

    /* ───────────────────────────────────────────────────────────────
     * Events
     * ──────────────────────────────────────────────────────────── */
    event BidPlaced(address indexed bidder, uint256 amountAdded, uint256 newTotal);
    event Finalized(address indexed winner, uint256 winningBid);
    event Withdrawn(address indexed bidder, uint256 amount);

    /* ───────────────────────────────────────────────────────────────
     * Constructor
     * ──────────────────────────────────────────────────────────── */
    constructor(
        address _nft,
        uint256 _tokenId,
        uint256 _bidDuration
    ) {
        owner = msg.sender;
        nft = IERC721(_nft);
        tokenId = _tokenId;
        bidDeadline = block.timestamp + _bidDuration;

        // 1️⃣ Ensure the seller actually owns the NFT before auction starts.
        require(nft.ownerOf(tokenId) == owner, "Seller must own the NFT");
    }

    /* ───────────────────────────────────────────────────────────────
     * Helper: current top bid
     * ──────────────────────────────────────────────────────────── */
    function topBid() external view returns (address bidder, uint256 amount) {
        return (highestBidder, highestBid);
    }

    /* ───────────────────────────────────────────────────────────────
     * Place a new bid (initial or additional)
     * ──────────────────────────────────────────────────────────── */
    function bid() external payable {
        _updateBid(bids[msg.sender] + msg.value);
    }

    /* ───────────────────────────────────────────────────────────────
     * Explicitly set a higher total bid (must send the difference)
     * ───────────────────────────────────────────────────────────── */
    function updateBid(uint256 newTotalBid) external payable {
        uint256 current = bids[msg.sender];
        require(newTotalBid > current, "New bid must be higher");
        require(msg.value == newTotalBid - current, "Send exact delta");
        _updateBid(newTotalBid);
    }

    /* ───────────────────────────────────────────────────────────────
     * Internal bid logic (shared)
     * ──────────────────────────────────────────────────────────── */
    function _updateBid(uint256 newTotal) internal {
        require(block.timestamp < bidDeadline, "Bidding period over");
        require(newTotal > 0, "Zero bid not allowed");

        uint256 added = newTotal - bids[msg.sender];
        bids[msg.sender] = newTotal;

        if (newTotal > highestBid) {
            highestBid = newTotal;
            highestBidder = msg.sender;
        }

        emit BidPlaced(msg.sender, added, newTotal);
    }

    /* ───────────────────────────────────────────────────────────────
     * Finalize after deadline
     * ──────────────────────────────────────────────────────────── */
    function finalize() external {
        require(block.timestamp >= bidDeadline, "Auction still ongoing");
        require(!finalized, "Already finalized");
        require(highestBidder != address(0), "No bids placed"); // 3️⃣ Block finalize when no bids
        finalized = true;

        // Transfer NFT to winner.
        nft.transferFrom(owner, highestBidder, tokenId);

        // Pay seller the winning bid.
        (bool ok, ) = owner.call{value: highestBid}("");
        require(ok, "Owner payout failed");

        emit Finalized(highestBidder, highestBid);

        // 2️⃣ Reset state to avoid stale data after finalize
        highestBidder = address(0);
        highestBid = 0;
    }

    /* ───────────────────────────────────────────────────────────────
     * Withdraw for losing bidders
     * ──────────────────────────────────────────────────────────── */
    function withdraw() external {
        require(finalized, "Not finalized");
        require(msg.sender != highestBidder, "Winner cannot withdraw");

        uint256 refund = bids[msg.sender];
        require(refund > 0, "Nothing to withdraw");
        bids[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{value: refund}("");
        require(ok, "Refund failed");

        emit Withdrawn(msg.sender, refund);
    }
}
