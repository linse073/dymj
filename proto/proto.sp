.user_info {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    create_time 3 : integer
    room_card 4 : integer
    nick_name 5 : string
    head_img 6 : string
    ip 7 : string
    day_card 8 : boolean
    last_login_time 9 : integer
    login_time 10 : integer
    invite_code 11 : integer
}

.other_all {
    other 0 : *user_info
}

.weave_card {
    op 0 : integer
    card 1 : integer
    index 2 : integer
    out_card 3 : integer
    old 4 : integer
}

.show_card {
    own_card 0 : *integer
    score 1 : integer
    last_deal 2 : integer
    hu 3 : integer
    last_index 4 : integer
    weave_card 5 : *weave_card
    give_up 6 : boolean
    grab_score 7 : integer
    line_score 8 : integer
    alone_award 9 : boolean
}

.chess_user {
    account 0 : string
    id 1 : integer
    sex 2 : integer
    nick_name 3 : string
    head_img 4 : string
    ip 5 : string
    index 6 : integer
    score 7 : integer
    ready 8 : boolean
    own_card 9 : *integer
    out_card 10 : *integer
    weave_card 11 : *weave_card
    last_deal 12 : integer
    out_index 13 : integer
    action 14 : integer
    agree 15 : boolean
    show_card 16 : show_card
    own_count 17 : integer
    out_magic 18 : boolean
    chi_count 19 : *integer
    top_score 20 : integer
    hu_count 21 : integer
    status 22 : integer
    chat_text 23 : string
    chat_audio 24 : binary
    deal_end 25 : boolean
    pass 26 : boolean
    give_up 27 : boolean
    location 28 : binary
    grab_score 29 : integer
    line_score 30 : integer
    last_index 31 : integer
}

.chess_info {
    name 0 : string
    number 1 : integer
    rule 2 : string
    banker 3 : integer
    status 4 : integer
    left 5 : integer
    deal_index 6 : integer
    count 7 : integer
    pause 8 : boolean
    rand 9 : integer
    out_card 10 : integer
    out_index 11 : integer
    old_banker 12 : integer
    close_index 13 : integer
    close_time 14 : integer
    record_id 15 : integer
    pass_status 16 : integer
    can_out 17 : integer
    gang_card 18 : integer
    gang_index 19 : integer
    win 20 : integer
    score 21 : integer
    club 22 : integer
}

.chess_all {
    info 0 : chess_info
    user 1 : *chess_user
    start_session 2 : integer
    session 3 : integer
}

.record_info {
    .chess_action {
        index 0 : integer
        op 1 : integer
        card 2 : integer
        out_index 3 : integer
        deal_card 4 : integer
    }

    id 0 : integer
    time 1 : integer
    info 2 : chess_info
    user 3 : *chess_user
    aciton 4 : *chess_action
    club 5 : integer
}

.chess_record {
    .record_detail {
        id 0 : integer
        time 1 : integer
        show_card 2 : *show_card
        banker 3 : integer
    }

    id 0 : integer
    time 1 : integer
    info 2 : chess_info
    user 3 : *chess_user
    record 4 : *record_detail
    read 5 : boolean
    winner 6 : integer
    club 7 : integer
}

.record_all {
    record 0 : *chess_record
}

.get_club_user_record {
    id 0 : integer
}

.club_user_record {
    id 0 : integer
    record 1 : *chess_record
}

.get_club_record {
    id 0 : integer
    begin_time 1 : integer
    end_time 2 : integer
}

.club_record {
    id 0 : integer
    record 1 : *chess_record
}

.read_club_record {
    id 0 : integer
    read 2 : boolean
}

.club_info {
    id 0 : integer
    name 1 : string
    time 2 : integer
    chief_id 3 : integer
    chief 4 : string
    member_count 5 : integer
    pos 6 : integer
    del 7 : boolean
}

.club_member {
    id 0 : integer
    name 1 : string
    head_img 2 : string
    pos 3 : integer
    time 4 : integer
    sex 5 : integer
    del 6 : boolean
    online 7 : boolean
}

.club_member_list {
    id 0 : integer
    list 1 : *club_member
}

.update_club_member {
    id 0 : integer
    member 1 : club_member
}

.club_apply {
    id 0 : integer
    name 1 : string
    head_img 2 : string
    time 3 : integer
    sex 4 : integer
    del 5 : boolean
}

.club_apply_list {
    id 0 : integer
    list 1 : *club_apply
}

.update_club_apply {
    id 0 : integer
    apply 1 : club_apply
}

.room_user {
    id 0 : integer
    name 1 : string
    head_img 2 : string
    sex 3 : integer
}

.room_info {
    name 0 : string
    number 1 : integer
    rule 2 : string
    user 3 : integer
    role 4 : *room_user
    time 5 : integer
}

.room_list {
    id 0 : integer
    name 1 : string
    member_count 2 : integer
    online_count 3 : integer
    quick_game 4 : string
    quick_rule 5 : string
    room 6 : *room_info
}

.club_all {
    id 0 : integer
    name 1 : string
    chief_id 2 : integer
    chief 3 : string
    time 4 : integer
    room_card 5 : integer
    quick_game 6 : string
    quick_rule 7 : string
    member_count 8 : integer
    online_count 9 : integer
    day_card 10 : integer
    notify_card 11 : integer
    admin 12 : *club_member
}

.user_all {
    user 0 : user_info
    chess 1 : chess_all
    first_charge 2 : *integer
    club 3 : *club_info
}

.info_all {
    user 0 : user_all
    start_time 1 : integer
    code 2 : integer
}

.update_user {
    update 0 : user_all
    iap_index 1 : integer
    roulette_index 2 : integer
}

.heart_beat {
    time 0 : integer
}

.heart_beat_response {
    time 0 : integer
    server_time 1 : integer
}

.error_code {
    code 0 : integer
}

.logout {
    id 0 : integer
}

.get_role {
    id 0 : integer
}

.role_info {
    info 0 : user_all
}

.add_room_card {
    num 0 : integer
}

.new_chess {
    name 0 : string
    rule 1 : string
    location 2 : binary
    club 3 : integer
}

.join {
    number 0 : integer
    location 1 : binary
}

.out_card {
    card 0 : integer
    index 1 : integer
}

.chi {
    card 0 : integer
}

.hide_gang {
    card 0 : integer
}

.reply {
    agree 0 : boolean
}

.dymj_card {
    card 0 : *integer
}

.jdmj_card {
    card 0 : *integer
}

.jd13_card {
    card 0 : *integer
}

.dy13_card {
    card 0 : *integer
}

.dy4_card {
    card 0 : *integer
}

.jhbj_card {
    card 0 : *integer
}

.enter_game {
    number 0 : integer
}

.review_record {
    id 0 : integer
}

.chat_info {
    text 0 : string
    audio 1 : binary
}

.iap {
    index 0 : integer
    receipt 1 : string
    sandbox 2 : boolean
}

.thirteen_out {
    card 0 : *integer
}

.bj_out {
    card 0 : *integer
}

.invite_code {
    url 0 : string
    code 1 : integer
}

.charge {
    num 0 : integer
    url 1 : string
}

.charge_ret {
    url 0 : string
}

.location_info {
    location 0 : binary
}

.query_club {
    id 0 : integer
}

.found_club {
    name 0 : string
}

.apply_club {
    id 0 : integer
}

.accept_club_apply {
    id 0 : integer
    roleid 1 : integer
}

.refuse_club_apply {
    id 0 : integer
    roleid 1 : integer
}

.query_club_apply {
    id 0 : integer
}

.query_club_member {
    id 0 : integer
}

.club_top {
    id 0 : integer
}

.club_top_ret {
    id 0 : integer
}

.remove_club_member {
    id 0 : integer
    roleid 1 : integer
}

.charge_club {
    id 0 : integer
    room_card 1 : integer
}

.config_club {
    id 0 : integer
    name 1 : string
    day_card 2 : integer
    notify_card 3 : integer
}

.promote_club_member {
    id 0 : integer
    roleid 1 : integer
}

.demote_club_member {
    id 0 : integer
    roleid 1 : integer
}

.query_club_room {
    id 0 : integer
}

.config_quick_start {
    id 0 : integer
    game 1 : string
    rule 2 : string
}

.accept_all_club_apply {
    id 0 : integer
}

.refuse_all_club_apply {
    id 0 : integer
}

.leave_club {
    id 0 : integer
}

.query_club_all {
    id 0 : integer
}

.check_agent_ret {
    agent 0 : boolean
}

.invited_user_detail {
    name 0 : string
    play_count 1 : integer
    invite_time 2 : string
}

.invite_record {
    index 0 : integer
    status 1 : string
}

.invite_info {
    done_times 0 : integer
    curr_times 1 : integer
    record_detail 2 : *invited_user_detail
    award_diamond 3 : integer

    mine_done 4 : string
    reward_off 5 : boolean
    invite_count 6: integer
    pay_total 7:integer
    reward_invite_r 8: *invite_record
    reward_pay_r 9: *invite_record

    roulette_cur 10:integer
    roulette_total 11 :integer
    roulette_r 12: *invite_record

    mine_play 13:integer
    bind_gzh 14 : boolean
}

.reward_award{
    diamond_award 0 : integer
}

.reward_money {
    award_type 0 : string
    award_idx 1 : integer
    award_num 2 : integer
}

.act_pay {
    id 0:integer
    num 1:integer
}

.update_gzh {
    bind_gzh 0 : boolean
}

.p4_out {
    out_card 0 : *integer
}
