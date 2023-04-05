#[test_only]
module seapad::project_test {
    use std::vector;

    use seapad::project::{Self, AdminCap, Project};
    use seapad::spt::{Self, SPT};
    use sui::coin::{Self, CoinMetadata, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock;
    use sui::clock::Clock;

    const ADMIN: address = @0xC0FFEE;
    const TOKEN_MINT_TEST: u64 = 1000000000000000;
    const SWAP_RATIO_SUI: u64 = 1;
    const SWAP_RATIO_TOKEN: u64 = 2;
    //1000sui
    const SOFT_CAP: u64 = 1000000000000;
    //2000 SPT
    const HARD_CAP: u64 = 2000000000000;
    const MAX_ALLOCATE: u64 = 500000000000;
    const OWNER_PROJECT: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    const USER4: address = @0x4;
    const USER5: address = @0x5;
    const USER6: address = @0x6;
    const USER7: address = @0x7;
    const USER8: address = @0x8;
    const USER9: address = @0x9;

    const USE_WHITELIST: bool = false;


    fun scenario(): Scenario { test_scenario::begin(@0xC0FFEE) }


    #[test]
    fun test_create_project() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_project_(scenario);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_update_project() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);
        let clock = test_scenario::take_shared<Clock>(scenario);
        create_project_(scenario);
        setup_launch_state_(scenario, 1, true, &clock);
        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_add_milestone() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);
        create_project_(scenario);
        setup_launch_state_(scenario, 1, true, &clock);

        add_milestone_(3500, 750, scenario, &clock);//alway pass
        add_milestone_(4000, 250, scenario, &clock);//must pass

        reset_milestone_(scenario);
        add_milestone_(3500, 1000, scenario, &clock);//alway pass

        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    fun test_add_milestone_must_failure() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);
        create_project_(scenario);
        setup_launch_state_(scenario, 1, true, &clock);

        add_milestone_(1000, 750, scenario, &clock);//alway pass
        add_milestone_(2000, 250, scenario, &clock);//must pass
        add_milestone_(900, 250, scenario, &clock);//must failed
        add_milestone_(2000, 300, scenario, &clock);//must failed

        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_fundraising_project() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);
        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);

        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_buy_token() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);
        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);

        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);
        buy_token_(OWNER_PROJECT, 500000000000, scenario, &clock);//pass
        buy_token_(USER2, 500000000000, scenario, &clock);//pass

        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    fun test_buy_token_out_of_hardcap() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);
        start_fund_raising_(scenario, &clock);

        buy_token_(USER2, 500000000000, scenario, &clock);//pass
        buy_token_(USER3, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER4, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER5, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER6, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER7, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER8, 500000000000, scenario, &clock);//failed out of hard_card
        buy_token_(USER9, 500000000000, scenario, &clock);//failed out of hard_card

        test_scenario::return_shared(clock);

        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    fun test_buy_token_exceed_max_allocate() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);
        start_fund_raising_(scenario, &clock);

        add_max_allocate_(USER2, MAX_ALLOCATE * 2, scenario);
        remove_max_allocate_(USER2, scenario);
        buy_token_(OWNER_PROJECT, 500000000000, scenario, &clock);//pass
        buy_token_(OWNER_PROJECT, 500000000000, scenario, &clock);//failed cause max allocate

        test_scenario::return_shared(clock);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_buy_token_max_allocate() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);

        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);

        add_max_allocate_(USER2, MAX_ALLOCATE * 2, scenario);

        buy_token_(USER2, MAX_ALLOCATE, scenario, &clock);//pass
        buy_token_(USER2, MAX_ALLOCATE, scenario, &clock);//pass

        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    // #[expected_failure]
    fun test_buy_token_use_whitelist() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, true, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);

        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);
        add_whitelist_(USER2, scenario);
        buy_token_(USER2, 500000000000, scenario, &clock);

        test_scenario::return_shared(clock);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_claim_project() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);

        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);
        deposit_to_project_(OWNER_PROJECT, 5000000000000, scenario);

        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);

        // add_whitelist_(USER1, scenario);
        let sui_buy = 500000000000;
        buy_token_(USER2, sui_buy, scenario, &clock);
        buy_token_(USER3, sui_buy, scenario, &clock);
        end_fund_raising_(scenario, &clock);

        let percent = 500;
        add_milestone_(4000, percent, scenario, &clock);

        clock::increment_for_testing(&mut clock, 5000);
        receive_token_(USER2, scenario, &clock);

        test_scenario::next_tx(scenario, USER2);
        {
            let spt = test_scenario::take_from_sender<Coin<SPT>>(scenario);
            let spt_value = coin::value(&spt);

            let spt_value_expected = (sui_buy / SWAP_RATIO_SUI) * SWAP_RATIO_TOKEN;
            let spt_value_actual = spt_value_expected / 1000 * (percent);

            assert!(spt_value_actual == spt_value, 0);

            test_scenario::return_to_sender(scenario, spt);
        };

        test_scenario::next_tx(scenario, ADMIN);
        {
            let project = test_scenario::take_shared<Project<SPT>>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let ctx = test_scenario::ctx(scenario);

            project::distribute_raised_fund(&admin_cap, &mut project, ctx);
            test_scenario::return_shared(project);
            test_scenario::return_to_sender(scenario, admin_cap);

            test_scenario::next_tx(scenario, OWNER_PROJECT);
            let sui_raised = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            let sui_value = coin::value(&sui_raised);

            assert!(sui_value == 500000000000 * 2, 0);
            test_scenario::return_to_sender(scenario, sui_raised);
        };
        test_scenario::return_shared(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_refund_project() {
        let scenario_val = scenario();
        let scenario = &mut scenario_val;
        create_clock_time_(scenario);
        test_scenario::next_tx(scenario, ADMIN);

        let clock = test_scenario::take_shared<Clock>(scenario);
        create_project_(scenario);
        setup_launch_state_(scenario, 1, false, &clock);

        let deposit_value = 5000000000000;
        deposit_to_project_(OWNER_PROJECT, deposit_value, scenario);
        clock::increment_for_testing(&mut clock, 1000);
        start_fund_raising_(scenario, &clock);

        // add_whitelist_(USER1, scenario);
        let sui_buy = 500000000000;
        clock::increment_for_testing(&mut clock, 1000);
        buy_token_(USER2, sui_buy, scenario, &clock);
        end_fund_raising_(scenario,&clock);

        //refund sui to user
        test_scenario::next_tx(scenario, USER2);
        {
            let project = test_scenario::take_shared<Project<SPT>>(scenario);
            let ctx = test_scenario::ctx(scenario);

            project::claim_refund(&mut project, ctx);

            test_scenario::next_tx(scenario, USER2);
            let sui_bought = test_scenario::take_from_address<Coin<SUI>>(scenario, USER2);
            assert!(coin::value(&sui_bought) == sui_buy, 0);

            test_scenario::return_shared(project);
            test_scenario::return_to_address(USER2, sui_bought);
        };

        end_refund_(scenario);

        test_scenario::next_tx(scenario, ADMIN);
        {
            //refund token to owner
            let project = test_scenario::take_shared<Project<SPT>>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let ctx = test_scenario::ctx(scenario);
            project::refund_token_to_owner(&admin_cap, &mut project, ctx);
            test_scenario::return_shared(project);
            test_scenario::return_to_sender(scenario, admin_cap);

            test_scenario::next_tx(scenario, OWNER_PROJECT);
            let stp_from_refund = test_scenario::take_from_sender<Coin<SPT>>(scenario);
            let value = coin::value(&stp_from_refund);
            assert!(deposit_value == value, 0);
            test_scenario::return_to_sender(scenario, stp_from_refund);
        };

        test_scenario::return_shared(clock);

        test_scenario::end(scenario_val);
    }

    fun create_project_(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        {
            let ctx = test_scenario::ctx(scenario);
            project::init_for_testing(ctx);
            spt::init_for_testing(ctx);
        };

        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let coin_metadata = test_scenario::take_immutable<CoinMetadata<spt::SPT>>(scenario);
            let ctx = test_scenario::ctx(scenario);
            project::create_project<SPT>(
                &admin_cap,
                OWNER_PROJECT,
                1,
                &coin_metadata,
                ctx
            );
            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_immutable(coin_metadata);
        };
    }

    fun setup_launch_state_(scenario: &mut Scenario, round: u8, usewhitelist: bool, clock: &Clock) {
        create_project_(scenario);

        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let project = test_scenario::take_shared<Project<SPT>>(scenario);

            project::setup_project<SPT>(
                &admin_cap,
                &mut project,
                round,
                usewhitelist,
                SWAP_RATIO_SUI,
                SWAP_RATIO_TOKEN,
                MAX_ALLOCATE,
                1000,
                3000,
                SOFT_CAP,
                HARD_CAP,
                clock);

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(project);
        };
    }

    fun add_milestone_(time: u64, percent: u64, scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        project::add_milestone(&admin_cap, &mut ido, time, percent, clock);
        test_scenario::return_to_sender(scenario, admin_cap);
        test_scenario::return_shared(ido);
    }

    fun reset_milestone_(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        project::reset_milestone(&admin_cap, &mut ido);
        test_scenario::return_to_sender(scenario, admin_cap);
        test_scenario::return_shared(ido);
    }

    fun start_fund_raising_(scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        let ctx = test_scenario::ctx(scenario);

        project::start_fund_raising(&admin_cap, &mut ido, clock, ctx);

        test_scenario::return_to_sender(scenario, admin_cap);
        test_scenario::return_shared(ido);
    }

    fun end_fund_raising_(scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        let ctx = test_scenario::ctx(scenario);

        project::end_fund_raising(&admin_cap, &mut ido, clock, ctx);

        test_scenario::return_to_sender(scenario, admin_cap);
        test_scenario::return_shared(ido);
    }

    fun end_refund_(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        let ctx = test_scenario::ctx(scenario);

        project::end_refund(&admin_cap, &mut ido, ctx);

        test_scenario::return_to_sender(scenario, admin_cap);
        test_scenario::return_shared(ido);
    }

    fun deposit_to_project_(owner: address, value: u64, scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, owner);
        {
            //deposit
            let ido = test_scenario::take_shared<Project<SPT>>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let spt1 = coin::mint_for_testing<SPT>(value / 2, ctx);
            let spt2 = coin::mint_for_testing<SPT>(value / 2, ctx);
            let spt3 = coin::mint_for_testing<SPT>(value / 2, ctx);

            let spts = vector::empty<Coin<SPT>>();
            vector::push_back(&mut spts, spt1);
            vector::push_back(&mut spts, spt2);
            vector::push_back(&mut spts, spt3);

            //expect 5k
            project::deposit_by_owner(spts, value, &mut ido, ctx);

            test_scenario::return_shared(ido);
        };
    }

    fun buy_token_(user: address, value: u64, scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, user);
        {
            let project = test_scenario::take_shared<Project<SPT>>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let suis = vector::empty<Coin<SUI>>();
            vector::push_back(&mut suis, coin::mint_for_testing<SUI>(TOKEN_MINT_TEST, ctx));
            vector::push_back(&mut suis, coin::mint_for_testing<SUI>(0, ctx));

            project::buy(suis, value, &mut project, clock, ctx);

            test_scenario::return_shared(project);
        };
    }

    fun add_whitelist_(user: address, scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        {
            let project = test_scenario::take_shared<Project<SPT>>(scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);

            let ctx = test_scenario::ctx(scenario);

            let users = vector::empty<address>();
            vector::push_back(&mut users, user);
            project::add_whitelist(&admin_cap, &mut project, users, ctx);

            test_scenario::return_shared(project);
            test_scenario::return_to_sender(scenario, admin_cap);
        }
    }

    fun receive_token_(user: address, scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, user);
        let ido = test_scenario::take_shared<Project<SPT>>(scenario);
        let ctx = test_scenario::ctx(scenario);

        project::claim_token(&mut ido, clock, ctx);

        test_scenario::return_shared(ido);
    }

    fun add_max_allocate_(user: address, max_allocate: u64, scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let project = test_scenario::take_shared<Project<SPT>>(scenario);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);

        let ctx = test_scenario::ctx(scenario);
        project::set_max_allocate(&admin_cap, user, max_allocate, &mut project, ctx);

        test_scenario::return_shared(project);
        test_scenario::return_to_sender(scenario, admin_cap);
    }

    fun remove_max_allocate_(user: address, scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let project = test_scenario::take_shared<Project<SPT>>(scenario);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);

        let ctx = test_scenario::ctx(scenario);
        project::clear_max_allocate(&admin_cap, user, &mut project, ctx);

        test_scenario::return_shared(project);
        test_scenario::return_to_sender(scenario, admin_cap);
    }

    fun create_clock_time_(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let ctx = test_scenario::ctx(scenario);
        clock::create_for_testing(ctx);
    }
}

