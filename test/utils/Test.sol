// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

interface Vm {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
    function expectRevert(bytes4 revertData) external;
}

contract Test {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq(uint256) failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "assertEq(address) failed");
    }

    function assertEq(bool actual, bool expected) internal pure {
        require(actual == expected, "assertEq(bool) failed");
    }

    function assertGt(uint256 actual, uint256 expected) internal pure {
        require(actual > expected, "assertGt failed");
    }

    function assertLt(uint256 actual, uint256 expected) internal pure {
        require(actual < expected, "assertLt failed");
    }

    function assertApproxEqAbs(uint256 actual, uint256 expected, uint256 maxDelta) internal pure {
        if (actual > expected) {
            require(actual - expected <= maxDelta, "assertApproxEqAbs failed");
        } else {
            require(expected - actual <= maxDelta, "assertApproxEqAbs failed");
        }
    }
}
