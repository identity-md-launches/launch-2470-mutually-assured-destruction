// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Performs a whole launch in one call, the way a factory does in one transaction: CREATE2 the
/// token, then move the swarm share, the pool share and the remainder, checking each arrives whole.
contract OneCallLauncher {
    function launch(bytes32 salt, address distributor, address pool, address remainder, uint256 poolBps)
        external
        returns (MADToken token, uint256 swarm, uint256 seeded, uint256 rest)
    {
        token = new MADToken{salt: salt}();
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "factory does not hold the supply");
        swarm = supply * 1_000 / 10_000;
        seeded = supply * poolBps / 10_000;
        rest = supply - swarm - seeded;
        require(token.transfer(distributor, swarm), "swarm transfer");
        require(token.transfer(pool, seeded), "pool transfer");
        require(token.transfer(remainder, rest), "remainder transfer");
    }
}

/// @dev Contract holder that can be the sender of transfers and approvals.
contract ContractHolder {
    function send(MADToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function allow(MADToken token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }
}

contract MADTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADToken internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MADToken();
    }

    // ---------------------------------------------------------------- fixed facts

    function test_supplyIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- calls that must fail

    function test_plainEtherTransferIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    function test_unknownSelectorIsRejected() public {
        (bool ok,) = address(token).call(abi.encodeWithSelector(bytes4(0xdeadbeef), alice, 1));
        assertFalse(ok);
        (ok,) = address(token).call(hex"01");
        assertFalse(ok);
    }

    function test_valueOnNonPayableFunctionsIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (alice, 1)));
        assertFalse(ok);
        (ok,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (alice, 1)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), alice), 0);
    }

    function test_zeroAddressCannotSend() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_zeroAddressCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(alice, 1);
        assertEq(token.allowance(address(0), alice), 0);
    }

    function test_transferFromZeroAddressWithZeroAmountStillReverts() public {
        // A zero allowance covers a zero amount; spending it rewrites the zero address's allowance,
        // and that approver check is what stops the call before the sender check is reached.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_transferFromZeroAddressWithAmountFailsOnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
    }

    function test_ownerNeedsAllowanceToTransferFromItself() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_spenderCannotDrainMoreThanAllowanceAcrossCalls() public {
        token.approve(spender, 10);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, 6);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 4, 5));
        token.transferFrom(address(this), alice, 5);
        token.transferFrom(address(this), bob, 4);
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 6);
        assertEq(token.balanceOf(bob), 4);
    }

    function test_allowanceOneBelowMaxIsFinite() public {
        uint256 almost = type(uint256).max - 1;
        token.approve(spender, almost);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), almost - 1);
    }

    function test_unlimitedApprovalEmitsOnlyOnApprove() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, type(uint256).max);
        token.approve(spender, type(uint256).max);
        // OZ v5 does not emit Approval when allowance is spent through transferFrom.
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 5);
        assertEq(vm.getRecordedLogs().length, 1);
    }

    function test_contractHolderTransfersAndApprovesLikeAnEOA() public {
        ContractHolder holder = new ContractHolder();
        token.transfer(address(holder), 100);
        assertTrue(holder.send(token, alice, 40));
        assertTrue(holder.allow(token, spender, 60));
        vm.prank(spender);
        token.transferFrom(address(holder), bob, 60);
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(alice), 40);
        assertEq(token.balanceOf(bob), 60);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(holder), 0, 1));
        holder.send(token, alice, 1);
    }

    function test_holderCanSendToTokenAddressButNobodyCanRetrieveIt() public {
        // Tokens sent to the token contract are stuck: it has no rescue path. This is the absence of
        // a privileged hand, which the launch floor requires, not a defect.
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), address(this), 1);
    }

    // ---------------------------------------------------------------- launch in one transaction

    function testFuzz_oneCallLaunchMovesEveryShareWhole(bytes32 salt, uint256 poolBps) public {
        poolBps = bound(poolBps, 0, 9_000);
        OneCallLauncher launcher = new OneCallLauncher();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool-manager");
        address remainder = makeAddr("remainder");
        vm.prank(alice, bob);
        (MADToken launched, uint256 swarm, uint256 seeded, uint256 rest) =
            launcher.launch(salt, distributor, pool, remainder, poolBps);
        assertEq(swarm, SUPPLY / 10);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), seeded);
        assertEq(launched.balanceOf(remainder), rest);
        assertEq(launched.balanceOf(address(launcher)), 0);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(swarm + seeded + rest, launched.totalSupply());
        assertEq(launched.totalSupply(), SUPPLY);

        // The claim from the distributor arrives whole too.
        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        assertEq(launched.balanceOf(alice), swarm);
        assertEq(launched.balanceOf(distributor), 0);
    }

    // ---------------------------------------------------------------- stateless properties

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferSucceedsIffAmountWithinBalance(uint256 funded, uint256 amount, address to) public {
        vm.assume(to != address(0) && to != alice);
        funded = bound(funded, 0, SUPPLY);
        token.transfer(alice, funded);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (amount <= funded) {
            assertTrue(ok);
            assertEq(token.balanceOf(alice), funded - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        } else {
            assertFalse(ok);
            assertEq(token.balanceOf(alice), funded);
            assertEq(token.balanceOf(to), toBefore);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromSucceedsIffWithinAllowanceAndBalance(
        uint256 funded,
        uint256 allowance,
        uint256 amount
    ) public {
        funded = bound(funded, 0, SUPPLY);
        token.transfer(alice, funded);
        vm.prank(alice);
        token.approve(spender, allowance);
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (alice, bob, amount)));
        bool expected = amount <= allowance && amount <= funded;
        assertEq(ok, expected);
        if (expected) {
            assertEq(token.balanceOf(alice), funded - amount);
            assertEq(token.balanceOf(bob), amount);
            assertEq(token.allowance(alice, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        } else {
            assertEq(token.balanceOf(alice), funded);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.allowance(alice, spender), allowance);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approveSetsExactValueAndTouchesNothingElse(address owner, address who, uint256 amount) public {
        vm.assume(owner != address(0) && who != address(0));
        uint256 ownerBalance = token.balanceOf(owner);
        vm.prank(owner);
        assertTrue(token.approve(who, amount));
        assertEq(token.allowance(owner, who), amount);
        assertEq(token.balanceOf(owner), ownerBalance);
        assertEq(token.totalSupply(), SUPPLY);
        if (owner != who) assertEq(token.allowance(who, owner), 0);
    }

    function testFuzz_roundTripTransferRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(bob, amount);
        vm.prank(bob);
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_splitTransfersEqualOneTransfer(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        token.transfer(alice, a);
        token.transfer(alice, b);
        assertEq(token.balanceOf(alice), a + b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }
}
