// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal view of the SPACE ID Agent ID registry (ERC-721).
/// @dev AgentBoard only ever needs to know whether an address holds an
///      Agent ID, which is exactly `balanceOf(address) > 0`. The Agent ID
///      NFT is non-transferable (soulbound), so a positive balance is a
///      stable, Sybil-resistant proof of a registered agent identity.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentBoard — an on-chain daily check-in board for Agent ID holders
/// @notice Any address that holds a Binance Agent ID (SPACE ID Agent ID,
///         registry 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F on BNB Chain)
///         may post one short message per UTC day to a public, append-only
///         board. The Agent ID is the core gate: without one, `checkIn`
///         always reverts.
/// @dev Safety properties, by design:
///      - No payable functions, no owner, no admin functions.
///      - The contract can never hold, receive, or move funds.
///      - The registry address is immutable, set once in the constructor.
contract AgentBoard {
    /// @notice One board entry: who checked in, when, and what they said.
    struct Entry {
        address agent;
        uint64 timestamp;
        string message;
    }

    /// @notice The Agent ID registry this board gates on. Immutable.
    IAgentIdRegistry public immutable registry;

    /// @notice Every check-in ever made, in order. Append-only.
    Entry[] public entries;

    /// @notice Total number of check-ins across all agents and days.
    uint256 public totalCheckIns;

    /// @notice Number of distinct agents that have ever checked in.
    uint256 public uniqueAgents;

    /// @notice Last UTC day (block.timestamp / 86400) each address checked in.
    mapping(address => uint256) public lastCheckInDay;

    /// @notice Whether an address has ever checked in (drives uniqueAgents).
    mapping(address => bool) public hasCheckedIn;

    /// @notice Emitted on every successful check-in.
    event CheckedIn(address indexed agent, uint256 indexed day, string message);

    /// @param registry_ Address of the Agent ID registry (ERC-721).
    constructor(address registry_) {
        require(registry_ != address(0), "Registry required");
        registry = IAgentIdRegistry(registry_);
    }

    /// @notice Post today's check-in to the board.
    /// @dev The Agent ID gate is enforced here: `registry.balanceOf` must be
    ///      greater than zero for `msg.sender`, otherwise the call reverts.
    ///      One check-in per address per UTC day; message capped at 280 bytes
    ///      (bytes, not characters — multi-byte UTF-8 counts fully).
    /// @param message Optional short message (may be empty, max 280 bytes).
    function checkIn(string calldata message) external {
        // --- Agent ID gate -------------------------------------------------
        require(registry.balanceOf(msg.sender) > 0, "Agent ID required");

        // --- One check-in per UTC day --------------------------------------
        uint256 today = block.timestamp / 86400;
        require(lastCheckInDay[msg.sender] != today, "Already checked in today");

        // --- Message length cap --------------------------------------------
        require(bytes(message).length <= 280, "Message too long");

        // --- Bookkeeping ----------------------------------------------------
        if (!hasCheckedIn[msg.sender]) {
            hasCheckedIn[msg.sender] = true;
            uniqueAgents += 1;
        }
        lastCheckInDay[msg.sender] = today;
        totalCheckIns += 1;
        entries.push(Entry({agent: msg.sender, timestamp: uint64(block.timestamp), message: message}));

        emit CheckedIn(msg.sender, today, message);
    }

    /// @notice How many distinct agents have ever checked in.
    function uniqueAgentCount() external view returns (uint256) {
        return uniqueAgents;
    }

    /// @notice Whether `agent` has already checked in on the current UTC day.
    function checkedInToday(address agent) external view returns (bool) {
        return lastCheckInDay[agent] == block.timestamp / 86400;
    }

    /// @notice Total number of entries on the board.
    function entriesCount() external view returns (uint256) {
        return entries.length;
    }

    /// @notice The most recent `n` entries, oldest-to-newest within the window.
    /// @dev Returns fewer than `n` entries if the board holds less than `n`.
    function getRecent(uint256 n) external view returns (Entry[] memory) {
        uint256 total = entries.length;
        uint256 count = n < total ? n : total;
        Entry[] memory recent = new Entry[](count);
        for (uint256 i = 0; i < count; i++) {
            recent[i] = entries[total - count + i];
        }
        return recent;
    }
}
