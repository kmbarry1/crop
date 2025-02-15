pragma solidity 0.6.12;

import "dss-interfaces/Interfaces.sol";

import "./base.sol";
import "../crop.sol";

contract MockVat {
    mapping (bytes32 => mapping (address => uint)) public gem;
    function urns(bytes32,address) external returns (uint256, uint256) {
        return (0, 0);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x, "vat/add-fail");
        require(y <= 0 || z >= x, "vat/add-fail");
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "vat/add-fail");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "vat/sub-fail");
    }
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}
}

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    constructor(uint8 dec, uint wad) public {
        decimals = dec;
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public returns (bool) {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
        return true;
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    function mint(address dst, uint wad) public returns (uint) {
        balanceOf[dst] += wad;
    }
    function approve(address usr, uint wad) public returns (bool) {
    }
    function mint(uint wad) public returns (uint) {
        mint(msg.sender, wad);
    }
}

contract Usr {

    CropJoin adapter;

    constructor(CropJoin adapter_) public {
        adapter = adapter_;
    }

    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(uint wad) public {
        adapter.join(wad);
    }
    function exit(uint wad) public {
        adapter.exit(wad);
    }
    function crops() public view returns (uint256) {
        return adapter.crops(address(this));
    }
    function stake() public view returns (uint256) {
        return adapter.stake(address(this));
    }
    function reap() public {
        adapter.join(0);
    }
    function flee() public {
        adapter.flee();
    }
    function tack(address src, address dst, uint256 wad) public {
        adapter.tack(src, dst, wad);
    }
    function hope(address vat, address usr) public {
        MockVat(vat).hope(usr);
    }

    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_call(address addr, bytes memory data) internal returns (bool) {
        (bool ok, bytes memory success) = address(this).call(
                                            abi.encodeWithSignature(
                                                "try_call(address,bytes)"
                                                , addr
                                                , data
                                                ));
        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(uint256)", val);
        return can_call(address(adapter), call);
    }

}

contract CropUnitTest is TestBase {

    Token     gem;
    Token     bonus;
    MockVat   vat;
    address   self;
    bytes32   ilk = "TOKEN-A";
    CropJoin  adapter;

    function setUp() public virtual {
        self = address(this);
        gem = new Token(6, 1000 * 1e6);
        bonus = new Token(18, 0);
        vat = new MockVat();
        adapter = new CropJoin(address(vat), ilk, address(gem), address(bonus));
    }

    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint cash) internal returns (Usr a, Usr b) {
        a = new Usr(adapter);
        b = new Usr(adapter);

        gem.transfer(address(a), cash);
        gem.transfer(address(b), cash);

        a.approve(address(gem), address(adapter));
        b.approve(address(gem), address(adapter));

        a.hope(address(vat), address(this));
    }

    function reward(address usr, uint wad) internal virtual {
        bonus.mint(usr, wad);
    }

    function test_reward() public virtual {
        reward(self, 100 ether);
        assertEq(bonus.balanceOf(self), 100 ether);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_multi_reap() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_join_exit() public {
        gem.approve(address(adapter), uint(-1));

        adapter.join(100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        adapter.join(100 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        adapter.exit(200 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        adapter.join(50 * 1e6);

        assertEq(bonus.balanceOf(self), 10 * 1e18);
        reward(address(adapter), 10 * 1e18);
        adapter.join(10 * 1e6);
        assertEq(bonus.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        reward(address(adapter), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 60 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 40 * 1e18);

        reward(address(adapter), 30 * 1e18);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 80 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 50 * 1e18);

        b.exit(20 * 1e6);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    function test_flux_transfer() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }
    // if the users's balance has been altered with flux, check that
    // all parties can still exit
    function test_flux_exit() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);

        assertEq(gem.balanceOf(address(a)), 100e6,  "a balance before exit");
        assertEq(adapter.stake(address(a)),     100e18, "a join balance before");
        a.exit(50 * 1e6);
        assertEq(gem.balanceOf(address(a)), 150e6,  "a balance after exit");
        assertEq(adapter.stake(address(a)),      50e18, "a join balance after");

        assertEq(gem.balanceOf(address(b)), 200e6,  "b balance before exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance before");
        adapter.tack(address(a), address(b),     50e18);
        b.flee();
        assertEq(gem.balanceOf(address(b)), 250e6,  "b balance after exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance after");
    }
    function test_reap_after_flux() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        assertTrue( a.can_exit( 50e6), "can exit before flux");
        vat.flux(ilk, address(a), address(b), 100e18);
        reward(address(adapter), 50e18);

        // if x gems are transferred from a to b, a will continue to earn
        // rewards on x, while b will not earn anything on x, until we
        // reset balances with `tack`
        assertTrue(!a.can_exit(100e6), "can't full exit after flux");
        assertEq(adapter.stake(address(a)),     100e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 100e18, "can claim remaining rewards");

        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards continue to accrue");

        assertEq(adapter.stake(address(a)),     100e18, "balance is unchanged");

        adapter.tack(address(a), address(b),    100e18);
        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards no longer increase");

        assertEq(adapter.stake(address(a)),       0e18, "balance is zeroed");
        assertEq(bonus.balanceOf(address(b)),   0e18, "b has no rewards yet");
        b.join(0);
        assertEq(bonus.balanceOf(address(b)),  50e18, "b now receives rewards");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        gem.approve(address(adapter), uint(-1));

        adapter.join(100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(adapter), 10 * 1e18);
        adapter.exit(50 * 1e6);
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(adapter), 10 * 1e18);
        assertEq(gem.balanceOf(self),  950e6, "balance before flee");
        adapter.flee();
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
        assertEq(gem.balanceOf(self), 1000e6, "balance after flee");
    }

    function test_tack() public {
        /*
           A user's pending rewards, assuming no further crop income, is
           given by
               stake[usr] * share - crops[usr]
           After join/exit we set
               crops[usr] = stake[usr] * share
           Such that the pending rewards are zero.
           With `tack` we transfer stake from one user to another, but
           we must ensure that we also either (a) transfer crops or
           (b) reap the rewards concurrently.
           Here we check that tack accounts for rewards appropriately,
           regardless of whether we use (a) or (b).
        */
        (Usr a, Usr b) = init_user();

        // concurrent reap
        a.join(100e6);
        reward(address(adapter), 50e18);

        a.join(0);
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);
        b.join(0);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
        assertEq(bonus.balanceOf(address(a)), 50e18, "a rewards");
        assertEq(bonus.balanceOf(address(b)), 50e18, "b rewards");

        // crop transfer
        a.join(100e6);
        reward(address(adapter), 50e18);

        // a doesn't reap their rewards before flux so all their pending
        // rewards go to b
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
        assertEq(bonus.balanceOf(address(a)),  50e18, "a rewards alt");
        assertEq(bonus.balanceOf(address(b)), 150e18, "b rewards alt");
    }
}
