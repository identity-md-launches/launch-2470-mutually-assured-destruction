// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Drives valid and invalid calls in random order across a closed actor set, modelling balances
/// and allowances independently. Invalid calls must revert and leave every observed value unchanged.
contract LedgerHandler is Test {
    MADToken internal immutable token;
    address[5] internal actorList;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    mapping(address => uint256) public ghostReceived;
    mapping(address => uint256) public ghostSent;
    uint256 public ghostMoved;
    uint256 public rejectedCalls;
    uint256 public acceptedCalls;
    address public immutable thief = makeAddr("stranger");

    constructor(MADToken token_) {
        token = token_;
        actorList[0] = makeAddr("ledger-0");
        actorList[1] = makeAddr("ledger-1");
        actorList[2] = makeAddr("ledger-2");
        actorList[3] = makeAddr("ledger-3");
        actorList[4] = address(this);
        ghostBalance[actorList[0]] = token_.INITIAL_SUPPLY();
        ghostReceived[actorList[0]] = token_.INITIAL_SUPPLY();
    }

    function actors(uint256 i) external view returns (address) {
        return actorList[i];
    }

    function actorCount() external pure returns (uint256) {
        return 5;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actorList[seed % actorList.length];
    }

    function _move(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostSent[from] += amount;
        ghostReceived[to] += amount;
        ghostMoved += amount;
        acceptedCalls++;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (mode % 4 == 0) amount = type(uint256).max;
        else if (mode % 4 == 1) amount = 0;
        else amount = bound(amount, 0, token.INITIAL_SUPPLY());
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
        acceptedCalls++;
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 spendable = ghostBalance[from] < allowed ? ghostBalance[from] : allowed;
        amount = bound(amount, 0, spendable);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        _move(from, to, amount);
    }

    /// @dev Tries to send more than the sender holds; must revert and change nothing.
    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = ghostBalance[from] + bound(excess, 1, type(uint256).max - ghostBalance[from]);
        vm.prank(from);
        try token.transfer(to, amount) returns (bool) {
            revert("overdraw succeeded");
        } catch {}
        rejectedCalls++;
    }

    /// @dev Tries to spend past the allowance (when the allowance is the binding limit).
    function overspend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool) {
            revert("overspend succeeded");
        } catch {}
        rejectedCalls++;
    }

    /// @dev Tries to burn into, or approve, the zero address; must revert.
    function zeroAddress(uint256 fromSeed, uint256 amount, bool viaApprove) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        if (viaApprove) {
            try token.approve(address(0), amount) returns (bool) {
                revert("approve(0) succeeded");
            } catch {}
        } else {
            try token.transfer(address(0), amount) returns (bool) {
                revert("transfer to 0 succeeded");
            } catch {}
        }
        rejectedCalls++;
    }

    /// @dev A stranger outside the actor set tries every way to obtain tokens without permission.
    function stranger(uint256 victimSeed, uint256 amount) external {
        address victim = _actor(victimSeed);
        amount = bound(amount, 1, token.INITIAL_SUPPLY());
        vm.prank(thief);
        try token.transferFrom(victim, thief, amount) returns (bool) {
            revert("stranger moved funds");
        } catch {}
        vm.prank(thief);
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", thief, amount));
        assertFalse(ok, "stranger reached mint");
        rejectedCalls++;
    }
}

contract MADTokenLedgerInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MADToken internal token;
    LedgerHandler internal handler;

    function setUp() public {
        token = new MADToken();
        handler = new LedgerHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = LedgerHandler.transfer.selector;
        selectors[1] = LedgerHandler.approve.selector;
        selectors[2] = LedgerHandler.transferFrom.selector;
        selectors[3] = LedgerHandler.overdraw.selector;
        selectors[4] = LedgerHandler.overspend.selector;
        selectors[5] = LedgerHandler.zeroAddress.selector;
        selectors[6] = LedgerHandler.stranger.selector;
        selectors[7] = LedgerHandler.transfer.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_balancesMatchModelAndSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.ghostBalance(actor), "balance diverged from model");
            assertEq(balance, handler.ghostReceived(actor) - handler.ghostSent(actor), "flow accounting broken");
            assertLe(balance, SUPPLY);
            sum += balance;
        }
        assertEq(sum, SUPPLY, "tokens escaped the actor set");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
        assertEq(token.balanceOf(handler.thief()), 0, "stranger holds tokens");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_allowancesMatchModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender));
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(handler.actors(i), handler.thief()), 0);
        }
    }
}
