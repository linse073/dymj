
local define = {
    shop_item = {
        [600] = 6,
        [3000] = 30,
        [10800] = 108,
        [32800] = 328,
    },

    shop_item_2 = {
        [600] = 6,
        [3000] = 35,
        [10800] = 128,
        [32800] = 398,
    },

    share_reward = 2,
    invite_reward = 5,
    init_card = 5,

    syn_user_url = "http://web.dyzx7.cn/dy/g/uinfo",
    intercommunion={
      sys_id = "dymj", --本游戏标识
      -- query_invite_url = "http://web.dyzx7.cn/act/god/invite", --查询邀请者
      -- activity_approval_url = "http://web.dyzx7.cn/act/god/uinfo", --活动审批(领取红包)
      query_invite_url = "http://192.168.1.120/act/god/invite", --查询邀请者
      activity_approval_url = "http://192.168.1.120/act/god/approval", --活动审批(领取红包)        
    },    

    
    activity_maxtrix = {--活动推广信息
        share2invite_max = 7, --活动分享邀请最多次(天)数
        diamond={ --分享次数与所得砖石数
            [1]=5,
            [2]=2,
            [3]=2,
            [4]=2,
            [5]=2,
            [6]=2,
            [7]=2,
        },
        done_count=8,--有效、成功的基准局数
        invite_succ_diamond=2,--成功邀请好友得砖石
        play_probability={1500,4000,6500,8500,9500,10000}, --15,25,25,20,10,5
        play_prize={3,4,5,6,7},
        limit_hour=24, --新用户在N小时内完成M局游戏，有奖
        money_invite={--邀请好友成功数送红包
            [1]=5,
            [4]=10,
            [7]=15,
            [10]=20,
            [15]=168,
        },
        -- money_pay_section={--送红包充值额
        --     10,50,100,500
        -- },
        money_pay={ -- 满充值额应该送红包
            [10]=5,
            [50]=20,
            [100]=30,
            [500]=1000,
        },
        roulette={
            conditions={ -- 获得转盘一次抽奖人条件
                [1]=8, --完成牌局
                [2]=10, --创建有效房间
                [3]=6, --大赢家
            },
            probability_1={ --初次抽奖概率
                3000,
                4000,
                4300,
                4400,
                4420,
                4430,
                8400,
                9400,
                9800,
                10000,
            },
            probability_2={ --抽奖概率
                1000,
                1500,
                1650,
                1700,
                1710,
                1715,
                7600,
                9100,
                9700,
                10000,
            },            
            prize={ --奖
                {t="m",v=88},
                {t="m",v=188},
                {t="m",v=588},
                {t="m",v=1880},
                {t="m",v=8880},
                {t="m",v=18800},
                {t="d",v=1},
                {t="d",v=2},
                {t="d",v=5},
                {t="d",v=10},
            }, 
        },       
    },

}

return define
