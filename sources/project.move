// Copyright (c) Web3 Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

///This module provide fund raising functions:
/// - support whitelist, soft cap, hardcap, refund
/// - support vesting token, claim token
/// - many round
module seapad::project {
    use std::option::{Self, Option};
    use std::vector;

    use w3libs::payment;

    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::event;
    use sui::object::{Self, UID, id_address};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::vec_map;
    use sui::vec_set::{Self, VecSet};

    ///Define model first

    struct SPT_PAD has drop {}

    struct PROJECT has drop {}

    const EInvalidVestingType: u64 = 1000;
    const EInvalidRound: u64 = 1001;
    const EInvalidRoundState: u64 = 1002;
    const EMaxAllocate: u64 = 1003;
    const EOutOfHardCap: u64 = 1004;
    const EVoted: u64 = 1005;
    const EClaimDone: u64 = 1006;
    const EProjectNotWhitelist: u64 = 1007;
    const EExistsInWhitelist: u64 = 1008;
    const ENotWhitelist: u64 = 1009;
    const EInvalidPercent: u64 = 1010;
    const EExceedPercent: u64 = 1011;
    const ETimeGENext: u64 = 1012;
    const EInvalidTimeVest: u64 = 1013;
    const EInvalidSwapRatioToken: u64 = 1014;
    const EInvalidSwapRatioSui: u64 = 1015;
    const ENotEnoughTokenFund: u64 = 1016;
    const ENoOrder: u64 = 1017;
    const ENotOwner: u64 = 1018;
    const ENotMeetExpect: u64 = 1019;


    const ROUND_SEED: u8 = 1;
    const ROUND_PRIVATE: u8 = 2;
    const ROUND_PUBLIC: u8 = 3;
    const ROUND_STATE_INIT: u8 = 10;
    const ROUND_STATE_PREPARE: u8 = 2;
    const ROUND_STATE_RASING: u8 = 3;
    const ROUND_STATE_REFUNDING: u8 = 4;
    //complete & start refunding
    const ROUND_STATE_END_REFUND: u8 = 5;
    //refund completed & stop
    const ROUND_STATE_CLAIMING: u8 = 6; //complete & ready to claim token


    ///lives in launchpad domain
    ///use dynamic field to add likes, votes, and watch
    const LIKES: vector<u8> = b"likes";
    //likes: VecSet<address>
    const WATCHS: vector<u8> = b"watchs";
    //watchs: VecSet<address>,
    const VOTES: vector<u8> = b"votes"; //votes: VecSet<address>

    const VESTING_TYPE_MILESTONE: u8 = 1;
    const VESTING_TYPE_LINEAR: u8 = 2;
    const VESTING: vector<u8> = b"vesting";
    const ORDERS: vector<u8> = b"orders";
    const WHITELIST: vector<u8> = b"whitelist";
    const PROFILE: vector<u8> = b"profile";

    struct ProjectProfile has store, copy, drop {
        name: vector<u8>,
        twitter: vector<u8>,
        discord: vector<u8>,
        telegram: vector<u8>,
        website: vector<u8>,
    }

    struct OrderBook has key, store {
        id: UID,
    }

    struct Order  has store {
        buyer: address,
        sui_amount: u64,
        token_amount: u64,
        token_released: u64,
    }

    struct LaunchState<phantom COIN> has key, store {
        id: UID,
        soft_cap: u64,
        hard_cap: u64,
        round: u8,
        //which round ?
        state: u8,
        total_sold: u64,
        //for each round
        swap_ratio_sui: u64,
        swap_ratio_token: u64,
        participants: u64,
        max_allocate: u64,
        //in sui
        start_time: u64,
        end_time: u64,
        //when project stop fund-raising and decide to refund or payout token(ready to claim)
        token_fund: Option<Coin<COIN>>,
        //owner of project deposit token fund enough to raising fund
        raised_sui: Option<Coin<SUI>>,
        order_book: OrderBook
    }

    ///should refer to object
    struct Contract has key, store {
        id: UID,
        coin_metadata: address,
        symbol: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        url: Option<vector<u8>>,
        decimals: u8,
    }

    struct Community has key, store {
        id: UID,
        like: u128,
        vote: u128,
        watch: u128,
    }

    struct VestingMileStone has copy, drop, store {
        time: u64,
        percent: u8
    }

    struct Vesting has key, store {
        id: UID,
        type: u8,
        init_release_time: u64,
        //must be shorted list
        milestones: Option<vector<VestingMileStone>>
    }

    struct Project<phantom COIN> has key, store {
        id: UID,
        launchstate: LaunchState<COIN>,
        community: Community,
        usewhitelist: bool,
        owner: address,
        //        profile: //use dynamic field
        //        whitelist: VecSet<address> //use dynamic field
        //        vesting: Vesting //use dynamic field
    }

    ///@todo review: when change admin account, should flush all fund to all project
    /// or should have "resource" account!
    struct PadConfig has key, store {
        id: UID,
        adminAddr: address
    }

    struct AdminCap has key, store {
        id: UID
    }

    ///initialize SPT_PAD project
    /// with witness
    /// with admin
    /// share list of projects
    /// share pad config
    fun init(_witness: PROJECT, ctx: &mut TxContext) {
        let adminCap = AdminCap { id: object::new(ctx) };
        transfer::transfer(adminCap, sender(ctx));
    }

    ///change admin
    public entry fun abdicate_admin(adminCap: AdminCap, to: address, _ctx: &mut TxContext) {
        transfer::transfer(adminCap, to);
    }

    /// add one project
    public entry fun create_project<COIN>(_adminCap: &AdminCap,
                                          owner: address,
                                          round: u8,
                                          usewhitelist: bool,
                                          soft_cap: u64,
                                          hard_cap: u64,
                                          swap_ratio_sui: u64,
                                          swap_ratio_token: u64,
                                          max_allocate: u64,
                                          vesting_type: u8,
                                          first_vesting_time: u64,
                                          ctx: &mut TxContext)
    {
        let launchstate = LaunchState<COIN> {
            id: object::new(ctx),
            soft_cap,
            hard_cap,
            round,
            state: ROUND_STATE_INIT,
            total_sold: 0,
            swap_ratio_sui,
            swap_ratio_token,
            participants: 0,
            max_allocate,
            start_time: 0,
            end_time: 0,
            token_fund: option::none<Coin<COIN>>(),
            raised_sui: option::none<Coin<SUI>>(),
            order_book: OrderBook { id: object::new(ctx) }
        };
        dynamic_field::add(&mut launchstate.id, ORDERS, vec_map::empty<address, Order>());


        let community = Community {
            id: object::new(ctx),
            like: 0,
            vote: 0,
            watch: 0
        };
        dynamic_field::add(&mut community.id, LIKES, vec_set::empty<address>());
        dynamic_field::add(&mut community.id, WATCHS, vec_set::empty<address>());
        dynamic_field::add(&mut community.id, VOTES, vec_set::empty<address>());

        let vestingMlsts = vector::empty<VestingMileStone>();

        let vesting = Vesting {
            id: object::new(ctx),
            type: vesting_type,
            init_release_time: first_vesting_time,
            milestones: option::some(vestingMlsts)
        };
        validate_vesting(&vesting, tx_context::epoch(ctx));

        let project = Project {
            id: object::new(ctx),
            owner,
            launchstate,
            community,
            usewhitelist
        };

        dynamic_field::add(&mut project.id, VESTING, vesting);
        if (usewhitelist) {
            dynamic_field::add(&mut project.id, WHITELIST, vec_set::empty<address>());
        };
        //fire event
        let event = build_event_add_project(&project);
        //share project
        transfer::share_object(project);
        event::emit(event);
    }

    /// if you want more milestones
    public entry fun add_milestone<COIN>(_adminCap: &AdminCap,
                                         project: &mut Project<COIN>,
                                         time: u64,
                                         percent: u8,
                                         ctx: &mut TxContext) {
        let vesting = dynamic_field::borrow_mut<vector<u8>, Vesting>(&mut project.id, VESTING);
        assert!(vesting.type == VESTING_TYPE_MILESTONE, EInvalidVestingType);
        let milestones = option::borrow_mut(&mut vesting.milestones);
        vector::push_back(milestones, VestingMileStone { time, percent });
        validate_mile_stones(milestones, tx_context::epoch(ctx));
    }

    public entry fun update_project<COIN>(_adminCap: &AdminCap,
                                          project: &mut Project<COIN>,
                                          round: u8,
                                          usewhitelist: bool,
                                          swap_ratio_sui: u64,
                                          swap_ratio_token: u64,
                                          max_allocate: u64,
                                          start_time: u64,
                                          end_time: u64,
                                          soft_cap: u64,
                                          hard_cap: u64,
                                          _ctx: &mut TxContext) {
        project.usewhitelist = usewhitelist;
        let launchstate = &mut project.launchstate;

        launchstate.round = round;
        launchstate.swap_ratio_sui = swap_ratio_sui;
        launchstate.swap_ratio_token = swap_ratio_token;
        launchstate.max_allocate = max_allocate;
        launchstate.start_time = start_time;
        launchstate.end_time = end_time;
        launchstate.soft_cap = soft_cap;
        launchstate.hard_cap = hard_cap;

        event::emit(UpdateStateProjectEvent {
            project: id_address(project),
            usewhitelist,
            round,
            swap_ratio_sui,
            swap_ratio_token,
            max_allocate,
            start_time,
            end_time,
            soft_cap,
            hard_cap
        });
    }

    public entry fun save_profile<COIN>(_adminCap: &AdminCap,
                                        project: &mut Project<COIN>,
                                        name: vector<u8>,
                                        twitter: vector<u8>,
                                        discord: vector<u8>,
                                        telegram: vector<u8>,
                                        website: vector<u8>,
                                        _ctx: &mut TxContext) {
        let exists = dynamic_field::exists_with_type<vector<u8>, ProjectProfile>(&project.id, PROFILE);
        if (exists) {
            let profile = dynamic_field::borrow_mut<vector<u8>, ProjectProfile>(&mut project.id, PROFILE);
            profile.name = name;
            profile.twitter = twitter;
            profile.discord = discord;
            profile.telegram = telegram;
            profile.website = website;
        }else {
            dynamic_field::add(&mut project.id, PROFILE, ProjectProfile {
                name,
                twitter,
                discord,
                telegram,
                website
            })
        }
    }

    public entry fun add_whitelist<COIN>(_adminCap: &AdminCap,
                                         project: &mut Project<COIN>,
                                         user: address,
                                         _ctx: &mut TxContext) {
        assert!(project.usewhitelist, EProjectNotWhitelist);
        let whitelist = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut project.id, WHITELIST);
        assert!(!vec_set::contains(whitelist, &user), EExistsInWhitelist);
        vec_set::insert(whitelist, user);
        event::emit(AddWhiteListEvent {
            project: id_address(project),
            whitelist: user
        })
    }

    public entry fun start_fund_raising<COIN>(_adminCap: &AdminCap, project: &mut Project<COIN>, ctx: &mut TxContext) {
        validate_start_fund_raising(project);

        project.launchstate.start_time = tx_context::epoch(ctx);
        project.launchstate.total_sold = 0;
        project.launchstate.participants = 0;
        project.launchstate.state = ROUND_STATE_RASING;

        event::emit(StartFundRaisingEvent {
            project: id_address(project),
            start_time: project.launchstate.start_time
        })
    }

    public entry fun buy<COIN>(suis: vector<Coin<SUI>>, amount: u64, project: &mut Project<COIN>, ctx: &mut TxContext) {
        let sui_amt = payment::take_from(suis, amount, ctx);
        let sender = sender(ctx);
        validate_state_for_buy(project, sender);
        let launchstate = &mut project.launchstate;
        let more_sui = coin::value(&sui_amt);
        let more_token = (more_sui / launchstate.swap_ratio_sui) * launchstate.swap_ratio_token ;

        launchstate.total_sold = launchstate.total_sold + more_token;
        let tokens_allow = launchstate.hard_cap / launchstate.swap_ratio_sui * launchstate.swap_ratio_token;
        assert!(tokens_allow >= launchstate.total_sold, EOutOfHardCap);
        let order_book = &mut launchstate.order_book;
        // let buy_orders = dynamic_field::borrow_mut<vector<u8>, VecMap<address, Order>>(&mut launchstate.id, ORDERS);
        let exists_order = dynamic_field::exists_with_type<address, Order>(&mut order_book.id, sender);

        if (!exists_order) {
            let newBuyOrder = Order {
                buyer: sender,
                sui_amount: 0,
                token_amount: 0, //not distributed
                token_released: 0, //not released
            };
            dynamic_field::add(&mut order_book.id, sender, newBuyOrder);
            // vec_map::insert(buy_orders, sender(ctx), newBuyOrder);
            launchstate.participants = launchstate.participants + 1;
        };
        let order = dynamic_field::borrow_mut<address, Order>(&mut order_book.id, sender);
        // let order = vec_map::get_mut(buy_orders, &sender(ctx));
        order.sui_amount = order.sui_amount + more_sui;
        order.token_amount = order.token_amount + more_token;

        let bought_amt = order.sui_amount;
        assert!(bought_amt <= launchstate.max_allocate, EMaxAllocate);

        if (option::is_none(&launchstate.raised_sui)) {
            option::fill(&mut launchstate.raised_sui, sui_amt);
        }else {
            coin::join(option::borrow_mut(&mut launchstate.raised_sui), sui_amt);
        };

        event::emit(BuyEvent {
            project: id_address(project),
            buyer: sender,
            total_sui_amt: bought_amt,
            epoch: tx_context::epoch(ctx)
        })
    }

    public entry fun end_fund_raising<COIN>(_adminCap: &AdminCap, project: &mut Project<COIN>, ctx: &mut TxContext) {
        project.launchstate.end_time = tx_context::epoch(ctx);

        let total_sui_raised = project.launchstate.total_sold / project.launchstate.swap_ratio_token * project.launchstate.swap_ratio_sui;
        if (total_sui_raised < project.launchstate.soft_cap) {
            project.launchstate.state = ROUND_STATE_REFUNDING; //start refund
        }else {
            project.launchstate.state = ROUND_STATE_CLAIMING;
        };

        event::emit(LaunchStateEvent {
            project: id_address(project),
            total_sold: project.launchstate.total_sold,
            epoch: tx_context::epoch(ctx),
            state: project.launchstate.state
        })
    }

    ///@todo
    /// - stop refund process
    /// - set state to end with refund
    /// - clear state ?
    public entry fun end_refund<COIN>(_adminCap: &AdminCap, project: &mut Project<COIN>, ctx: &mut TxContext) {
        project.launchstate.state = ROUND_STATE_END_REFUND;
        event::emit(RefundClosedEvent {
            project: id_address(project),
            sui_refunded: project.launchstate.total_sold,
            epoch: tx_context::epoch(ctx)
        })
    }

    ///@todo
    /// - allocate raised budget, maybe:
    ///     *transfer all to project owner
    ///     *charge fee
    ///     *add liquidity
    public entry fun distribute_raised_fund<COIN>(_adminCap: &AdminCap,
                                                  project: &mut Project<COIN>,
                                                  project_owner: address,
                                                  ctx: &mut TxContext) {
        validate_allocate_budget(project);
        let budget = option::extract(&mut project.launchstate.raised_sui);
        transfer::transfer(budget, project_owner);

        event::emit(DistributeRaisedFundEvent {
            project: id_address(project),
            epoch: tx_context::epoch(ctx)
        })
    }

    ///@todo
    /// - refund token to owner when failed to make fund-raising
    public entry fun refund_token_to_owner<COIN>(_cap: &AdminCap,
                                                 project: &mut Project<COIN>,
                                                 project_owner: address,
                                                 _ctx: &mut TxContext) {
        validate_allocate_budget(project);
        let budget = option::extract(&mut project.launchstate.token_fund);
        transfer::transfer(budget, project_owner);
    }


    ///@todo
    /// - make sure coin merged
    /// - should limit to the one that register project ?
    /// - make sure token deposit match the market cap & swap ratio
    public entry fun deposit_project<COIN>(coins: vector<Coin<COIN>>,
                                           project: &mut Project<COIN>,
                                           ctx: &mut TxContext) {
        let depositer = sender(ctx);
        assert!(depositer == project.owner, ENotOwner);

        let launchstate = &mut project.launchstate;
        let token_expect = (launchstate.soft_cap / launchstate.swap_ratio_sui) * launchstate.swap_ratio_token;
        let token_fund = payment::take_from(coins, token_expect, ctx);

        if (option::is_some(&launchstate.token_fund)) {
            let before = option::borrow_mut(&mut launchstate.token_fund);
            coin::join(before, token_fund);
        }else {
            option::fill(&mut launchstate.token_fund, token_fund);
        };

        event::emit(ProjectDepositFundEvent {
            project: id_address(project),
            depositor: sender(ctx),
            token_amount: token_expect
        })
    }

    public entry fun receive_token<COIN>(project: &mut Project<COIN>, ctx: &mut TxContext) {
        validate_vest_token(project);
        let sender = sender(ctx);
        let launchstate = &mut project.launchstate;
        let order_book = &mut launchstate.order_book;

        // let buy_orders = dynamic_field::borrow_mut<vector<u8>, VecMap<address, Order>>(&mut launchstate.id, ORDERS);

        assert!(dynamic_field::exists_with_type<address, Order>(&mut order_book.id, sender), ENoOrder);
        let order = dynamic_field::borrow_mut<address, Order>(&mut order_book.id, sender);
        // let order = vec_map::get_mut(buy_orders, &sender);

        let vesting = dynamic_field::borrow_mut<vector<u8>, Vesting>(&mut project.id, VESTING);
        let milestones = option::borrow(&vesting.milestones);


        let total_percent = if (vector::is_empty(milestones)) {
            100
        }else {
            let i = 0;
            let n = vector::length(milestones);
            let sum = 0;

            while (i < n) {
                let milestone = vector::borrow(milestones, i);
                if (tx_context::epoch(ctx) >= milestone.time) {
                    sum = sum + milestone.percent;
                }else {
                    break
                };
                i = i + 1;
            };
            sum
        };

        let more_token = order.token_amount / 100 * (total_percent as u64);
        let more_token_actual = more_token - order.token_released;

        assert!(more_token_actual > 0, EClaimDone);
        order.token_released = order.token_released + more_token_actual;
        let token = coin::split<COIN>(option::borrow_mut(&mut launchstate.token_fund), more_token_actual, ctx);
        transfer::transfer(token, sender);
    }

    public entry fun claim_refund<COIN>(project: &mut Project<COIN>, ctx: &mut TxContext) {
        validate_refund(project);
        let sender = sender(ctx);
        let order_book = &mut project.launchstate.order_book;
        // let buy_orders = dynamic_field::borrow_mut<vector<u8>, VecMap<address, Order>>(&mut project.launchstate.id, ORDERS);
        // let order = vec_map::get_mut(buy_orders, &sender(ctx));
        let order = dynamic_field::borrow_mut<address, Order>(&mut order_book.id, sender);
        let amount_fund = order.sui_amount;
        let coin_fund = coin::split(option::borrow_mut(&mut project.launchstate.raised_sui), amount_fund, ctx);
        transfer::transfer(coin_fund, sender);
    }

    //==========================================Start Community Area=========================================

    public entry fun vote<COIN>(project: &mut Project<COIN>, ctx: &mut TxContext) {
        let com = &mut project.community;
        let senderAddr = sender(ctx);
        let votes = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut com.id, VOTES);

        assert!(vec_set::contains(votes, &senderAddr), EVoted);

        com.vote = com.vote + 1;
        vec_set::insert(votes, senderAddr);
    }

    public entry fun like<COIN>(project: &mut Project<COIN>, ctx: &mut TxContext) {
        let com = &mut project.community;
        let senderAddr = sender(ctx);
        let likes = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut com.id, LIKES);

        assert!(vec_set::contains(likes, &senderAddr), EVoted);

        com.like = com.like + 1;
        vec_set::insert(likes, senderAddr);
    }

    public entry fun watch<COIN>(project: &mut Project<COIN>, ctx: &mut TxContext) {
        let com = &mut project.community;
        let senderAddr = sender(ctx);
        let watch = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut com.id, WATCHS);

        assert!(vec_set::contains(watch, &senderAddr), EVoted);

        com.watch = com.watch + 1;
        vec_set::insert(watch, senderAddr);
    }
    //==========================================End Community Area=========================================


    //==========================================Start Validate Area=========================================
    fun validate_start_fund_raising<COIN>(project: &mut Project<COIN>) {
        let launchstate = &project.launchstate;
        let state = launchstate.state;

        assert!(
            (state >= ROUND_STATE_INIT && state < ROUND_STATE_RASING)
                || state >= ROUND_STATE_CLAIMING
                || state == ROUND_STATE_END_REFUND,
            EInvalidRoundState
        );

        let total_token = if (option::is_none(&project.launchstate.token_fund)) {
            0
        }else {
            coin::value(option::borrow(&project.launchstate.token_fund))
        };
        let token_amt_expect = (launchstate.soft_cap / launchstate.swap_ratio_sui) * launchstate.swap_ratio_token;
        assert!(total_token >= token_amt_expect, ENotEnoughTokenFund);
    }

    /// -make sure that sum of all milestone is <= 100%
    /// -time is ordered min --> max, is valid, should be offset
    fun validate_mile_stones(milestones: &vector<VestingMileStone>, now: u64) {
        let i = 0;
        let n = vector::length(milestones);
        let total_percent = 0;

        while (i < n) {
            let milestone = vector::borrow(milestones, i);
            assert!(milestone.percent <= 100, EInvalidPercent);
            assert!(milestone.time >= now, EInvalidTimeVest);
            if (i < n - 1) {
                let next = vector::borrow(milestones, i + 1);
                assert!(milestone.time < next.time, ETimeGENext);
            };
            total_percent = total_percent + milestone.percent;
            i = i + 1;
        };
        assert!(total_percent <= 100, EExceedPercent);
    }

    fun validate_state_for_buy<COIN>(project: &mut Project<COIN>, senderAddr: address) {
        assert!(project.launchstate.state == ROUND_STATE_RASING, EInvalidRoundState);
        if (project.usewhitelist) {
            let whitelist = dynamic_field::borrow<vector<u8>, VecSet<address>>(&project.id, WHITELIST);
            assert!(vec_set::contains(whitelist, &senderAddr), ENotWhitelist);
        }else {
            assert!(!project.usewhitelist, ENotWhitelist);
        }
    }

    fun validate_vest_token<COIN>(project: &mut Project<COIN>) {
        assert!(project.launchstate.state == ROUND_STATE_CLAIMING, EInvalidRoundState);
    }

    fun validate_refund<COIN>(project: &mut Project<COIN>) {
        assert!(project.launchstate.state == ROUND_STATE_REFUNDING, EInvalidRoundState);
    }

    fun validate_allocate_budget<COIN>(project: &mut Project<COIN>) {
        let state = project.launchstate.state;
        assert!(state == ROUND_STATE_END_REFUND || state == ROUND_STATE_CLAIMING, EInvalidRoundState);
    }

    fun validate_vesting(vesting: &Vesting, now: u64) {
        assert!(vesting.init_release_time > now, EInvalidRoundState);
    }
    //==========================================End Validate Area==========================================


    //==========================================Start Event Area===========================================
    fun build_event_add_project<COIN>(project: &Project<COIN>): ProjectCreatedEvent {
        let event = ProjectCreatedEvent {
            project: id_address(project),
            soft_cap: project.launchstate.soft_cap,
            hard_cap: project.launchstate.hard_cap,
            round: project.launchstate.round, //which round ?
            state: project.launchstate.state,
            total_sold: project.launchstate.total_sold, //for each round
            swap_ratio_sui: project.launchstate.swap_ratio_sui,
            swap_ratio_token: project.launchstate.swap_ratio_token,
            participants: project.launchstate.participants,
            max_allocate: project.launchstate.max_allocate, //in sui
            start_time: project.launchstate.start_time,
            end_time: project.launchstate.end_time,
            usewhitelist: project.usewhitelist,
            vesting_type: dynamic_field::borrow<vector<u8>, Vesting>(&project.id, VESTING).type,
            vesting_init_release_time: dynamic_field::borrow<vector<u8>, Vesting>(
                &project.id,
                VESTING
            ).init_release_time,
            vesting_milestones: dynamic_field::borrow<vector<u8>, Vesting>(&project.id, VESTING).milestones
        };

        event
    }

    struct UpdateStateProjectEvent has copy, drop {
        project: address,
        usewhitelist: bool,
        round: u8,
        swap_ratio_sui: u64,
        swap_ratio_token: u64,
        max_allocate: u64,
        start_time: u64,
        end_time: u64,
        soft_cap: u64,
        hard_cap: u64,
    }

    struct StartFundRaisingEvent has copy, drop {
        project: address,
        start_time: u64
    }

    struct BuyEvent has copy, drop {
        project: address,
        buyer: address,
        total_sui_amt: u64,
        epoch: u64
    }

    struct LaunchStateEvent has copy, drop {
        project: address,
        total_sold: u64,
        epoch: u64,
        state: u8
    }

    struct AddWhiteListEvent has copy, drop {
        project: address,
        whitelist: address
    }

    struct DistributeRaisedFundEvent has copy, drop {
        project: address,
        epoch: u64
    }

    struct RefundClosedEvent has copy, drop {
        project: address,
        sui_refunded: u64,
        epoch: u64
    }

    struct ProjectDepositFundEvent has copy, drop {
        project: address,
        depositor: address,
        token_amount: u64
    }

    struct ProjectCreatedEvent has copy, drop {
        project: address,
        soft_cap: u64,
        hard_cap: u64,
        round: u8,
        //which round ?
        state: u8,
        total_sold: u64,
        //for each round
        swap_ratio_sui: u64,
        swap_ratio_token: u64,
        participants: u64,
        max_allocate: u64,
        //in sui
        start_time: u64,
        end_time: u64,
        usewhitelist: bool,
        vesting_type: u8,
        vesting_init_release_time: u64,
        vesting_milestones: Option<vector<VestingMileStone>>
    }
    //==========================================Start Event Area==========================================

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(PROJECT {}, ctx);
    }
}

