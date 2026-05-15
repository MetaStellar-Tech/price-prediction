// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IERC20} from "../interfaces/IERC20.sol";

library SafeERC20 {
    error SafeERC20CallFailed();
    error SafeERC20OperationFailed();

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, amount)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, amount)));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success) revert SafeERC20CallFailed();
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20OperationFailed();
        }
    }
}
