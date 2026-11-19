// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentBoard} from "../contracts/AgentBoard.sol";
import {MockAgentIdRegistry} from "./MockAgentIdRegistry.sol";

/// @dev Minimal cheatcode interface (subset of forge-std's Vm) so the test
///      suite needs no external dependencies at all.
interface Vm {
    function warp(uint256 newTimestamp) external;
    function prank(address msgSender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
}

/// @dev Tiny assertion helpers that revert on failure (forge marks the
///      test as failed when the test function reverts).
contract TestLite {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function assertTrue(bool cond, string memory what) internal pure {
        require(cond, string.concat("assertTrue failed: ", what));
    }

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, string.concat("assertEq failed: ", what));
    }

    function assertEq(address a, address b, string memory what) internal pure {
        require(a == b, string.concat("assertEq failed: ", what));
    }

    function assertEq(string memory a, string memory b, string memory what) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), string.concat("assertEq failed: ", what));
    }
}

contract AgentBoardTest is TestLite {
    event CheckedIn(address indexed agent, uint256 indexed day, string message);

    MockAgentIdRegistry internal registry;
    AgentBoard internal board;

    address internal alice = address(0xA11CE); // Agent ID holder
    address internal bob = address(0xB0B); // Agent ID holder
    address internal stranger = address(0x57A9); // no Agent ID

    uint256 internal constant T0 = 1_800_000_000; // fixed start time

    function setUp() public {
        registry = new MockAgentIdRegistry();
        board = new AgentBoard(address(registry));
        registry.grant(alice);
        registry.grant(bob);
        vm.warp(T0);
    }

    // --- The Agent ID gate ---------------------------------------------------

    function testNonHolderCannotCheckIn() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("Agent ID required"));
        board.checkIn("hello");
    }

    function testHolderCanCheckIn() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit CheckedIn(alice, T0 / 86400, "gm agents");
        board.checkIn("gm agents");

        assertEq(board.totalCheckIns(), 1, "totalCheckIns");
        assertEq(board.entriesCount(), 1, "entriesCount");
        assertTrue(board.checkedInToday(alice), "checkedInToday(alice)");

        (address agent, uint64 ts, string memory msg_) = board.entries(0);
        assertEq(agent, alice, "entry agent");
        assertEq(uint256(ts), T0, "entry timestamp");
        assertEq(msg_, "gm agents", "entry message");
    }

    function testEmptyMessageAllowed() public {
        vm.prank(alice);
        board.checkIn("");
        assertEq(board.entriesCount(), 1, "entriesCount after empty message");
    }

    // --- One per UTC day ------------------------------------------------------

    function testSecondCheckInSameDayReverts() public {
        vm.prank(alice);
        board.checkIn("first");

        vm.prank(alice);
        vm.expectRevert(bytes("Already checked in today"));
        board.checkIn("second");
    }

    function testNextDayCheckInSucceeds() public {
        vm.prank(alice);
        board.checkIn("day one");

        vm.warp(T0 + 86400); // exactly the next UTC day boundary
        assertTrue(!board.checkedInToday(alice), "not checked in on new day");

        vm.prank(alice);
        board.checkIn("day two");
        assertEq(board.totalCheckIns(), 2, "totalCheckIns after day two");
        assertTrue(board.checkedInToday(alice), "checkedInToday on day two");
    }

    function testSameDayLaterStillReverts() public {
        vm.prank(alice);
        board.checkIn("morning");

        vm.warp(T0 + 3600); // one hour later, same UTC day
        vm.prank(alice);
        vm.expectRevert(bytes("Already checked in today"));
        board.checkIn("afternoon");
    }

    // --- Unique agents --------------------------------------------------------

    function testUniqueAgentsCountsEachAddressOnce() public {
        vm.prank(alice);
        board.checkIn("a1");
        vm.prank(bob);
        board.checkIn("b1");
        assertEq(board.uniqueAgentCount(), 2, "two unique agents");

        vm.warp(T0 + 86400);
        vm.prank(alice);
        board.checkIn("a2");
        vm.prank(bob);
        board.checkIn("b2");
        assertEq(board.uniqueAgentCount(), 2, "still two unique agents next day");
        assertEq(board.totalCheckIns(), 4, "four total check-ins");
    }

    // --- Message length -------------------------------------------------------

    function testMessage280BytesOk() public {
        string memory msg280 = _repeat("x", 280);
        vm.prank(alice);
        board.checkIn(msg280);
        assertEq(board.entriesCount(), 1, "280-byte message accepted");
    }

    function testMessageOver280BytesReverts() public {
        string memory msg281 = _repeat("x", 281);
        vm.prank(alice);
        vm.expectRevert(bytes("Message too long"));
        board.checkIn(msg281);
    }

    function testMessageLimitCountsBytesNotChars() public {
        // U+1F600 (😀) is 4 bytes in UTF-8: 71 of them = 284 bytes > 280.
        string memory emojis = _repeat(unicode"😀", 71);
        vm.prank(alice);
        vm.expectRevert(bytes("Message too long"));
        board.checkIn(emojis);
    }

    // --- getRecent --------------------------------------------------------------

    function testGetRecent() public {
        // Empty board: returns zero entries.
        AgentBoard.Entry[] memory none = board.getRecent(5);
        assertEq(none.length, 0, "getRecent on empty board");

        vm.prank(alice);
        board.checkIn("one");
        vm.prank(bob);
        board.checkIn("two");
        vm.warp(T0 + 86400);
        vm.prank(alice);
        board.checkIn("three");

        // Asking for more than exists returns everything, in order.
        AgentBoard.Entry[] memory all = board.getRecent(10);
        assertEq(all.length, 3, "getRecent(10) length");
        assertEq(all[0].message, "one", "oldest first");
        assertEq(all[2].message, "three", "newest last");

        // Asking for the last 2 returns exactly the last 2, in order.
        AgentBoard.Entry[] memory last2 = board.getRecent(2);
        assertEq(last2.length, 2, "getRecent(2) length");
        assertEq(last2[0].message, "two", "getRecent(2)[0]");
        assertEq(last2[1].message, "three", "getRecent(2)[1]");
        assertEq(last2[1].agent, alice, "getRecent(2)[1] agent");

        // Zero requested, zero returned.
        AgentBoard.Entry[] memory zero = board.getRecent(0);
        assertEq(zero.length, 0, "getRecent(0)");
    }

    // --- Registry wiring ---------------------------------------------------------

    function testRegistryIsImmutableTarget() public view {
        assertEq(address(board.registry()), address(registry), "registry address");
    }

    function testRevokedAgentIdLosesAccess() public {
        registry.revoke(alice);
        vm.prank(alice);
        vm.expectRevert(bytes("Agent ID required"));
        board.checkIn("should fail");
    }

    // --- Helpers -------------------------------------------------------------------

    function _repeat(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory out;
        for (uint256 i = 0; i < n; i++) {
            out = bytes.concat(out, bytes(s));
        }
        return string(out);
    }
}
