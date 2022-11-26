-- ------------------------------- --
local  _, CLM = ...
-- ------ CLM common cache ------- --
local LOG       = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local UTILS     = CLM.UTILS
-- ------------------------------- --

local pairs, ipairs = pairs, ipairs
local tonumber, tostring = tonumber, tostring
local slen, sformat, mceil = string.len, string.format, math.ceil
local SendChatMessage, C_TimerNewTicker, GetServerTime = SendChatMessage, C_Timer.NewTicker, GetServerTime
local typeof, assertType = UTILS.typeof, UTILS.assertType

local whoami = UTILS.whoami()

local AUCTION_COMM_PREFIX = "Auction2"

local AuctionInfo = CLM.MODELS.AuctionInfo

-- Singleton

local AuctionManager = {}

-- Database

local function InitializeDB(self)
    self.db = CLM.MODULES.Database:Personal('auction', {
        autoAssign = true,
        autoTrade = true,
        fillFromCorpse = true,
        fillFromCorpseMLOnly = true,
        fillFromLoot = true,
        fillFromLootGLOnly = true,
        lootThreshold = 4,
        notes = {}
    })
end

-- HOOKING


local function GetModifierCombination()
    local combination = ""

    if IsAltKeyDown() then
        combination = combination .. "a"
    end

    if IsShiftKeyDown() then
        combination = combination .. "s"
    end

    if IsControlKeyDown() then
        combination = combination .. "c"
    end

    return combination
end

local function CheckModifierCombination()
    return (CLM.GlobalConfigs:GetModifierCombination() == GetModifierCombination())
end

local function AddToAuctionListOnClickFromTooltip(frame, button)
    if GameTooltip and CheckModifierCombination() then
        local _, itemLink = GameTooltip:GetItem()
        if itemLink then
            AuctionManager:AddItemByLink(itemLink)
            CLM.GUI.AuctionManager:Show() -- TBD
        end
    end
end

local function HookBagSlots()
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", AddToAuctionListOnClickFromTooltip)
end

local hookedSlots =  {}
local function HookCorpseSlots()
    local UIs = {
        wow = "LootButton",
        elv = "ElvLootSlot"
    }

    local numLootItems = GetNumLootItems()

    for ui, prefix in pairs(UIs) do
        for buttonIndex = 1, numLootItems do
            if not hookedSlots[ui][buttonIndex] then
                local button = getglobal(prefix .. buttonIndex)
                if button then
                    button:HookScript("OnClick", AddToAuctionListOnClickFromTooltip)
                    hookedSlots[ui][buttonIndex] = true
                end
            end
        end
    end
end

local alreadyPostedLoot = {}
local function PostLootToRaidChat()
    if not IsInRaid() then return end
    if not CLM.MODULES.ACL:IsTrusted() then return end
    if not CLM.GlobalConfigs:GetAnnounceLootToRaid() then return end
    if CLM.GlobalConfigs:GetAnnounceLootToRaidOwnerOnly() then
        if not CLM.MODULES.RaidManager:IsRaidOwner(whoami) then return end
    end
    local targetGuid = UnitGUID("target")
    if targetGuid then
        if alreadyPostedLoot[targetGuid] then return end
        alreadyPostedLoot[targetGuid] = true
    end

    local numLootItems = GetNumLootItems()
    local num = 1
    for lootIndex = 1, numLootItems do
        local _, _, _, _, rarity = GetLootSlotInfo(lootIndex)
        local itemLink = GetLootSlotLink(lootIndex)
        if itemLink then
            if (tonumber(rarity) or 0) >= CLM.GlobalConfigs:GetAnnounceLootToRaidLevel() then
                SendChatMessage(num .. ". " .. itemLink, "RAID")
                num = num + 1
            end
        end
    end
end

local function HandleLootOpenedEvent()
    -- Post loot to raid chat
    PostLootToRaidChat()
    -- Hook slots
    HookCorpseSlots()
end

-- local function HandleLootClosedEvent()
-- end

-- CONFIGURATION

local function SetAutoAssign(self, value)
    self.db.autoAssign = value and true or false
end

local function GetAutoAssign(self)
    return self.db.autoAssign
end

local function SetAutoTrade(self, value)
    self.db.autoTrade = value and true or false
end

local function GetAutoTrade(self)
    return self.db.autoTrade
end

local function SetFillAuctionListFromCorpse(self, value)
    self.db.fillFromCorpse = value and true or false
end

local function GetFillAuctionListFromCorpse(self)
    return self.db.fillFromCorpse
end

local function SetFillAuctionListFromCorpseMLOnly(self, value)
    self.db.fillFromCorpseMLOnly = value and true or false
end

local function GetFillAuctionListFromCorpseMLOnly(self)
    return self.db.fillFromCorpseMLOnly
end

local function SetFillAuctionListFromLoot(self, value)
    self.db.fillFromLoot = value and true or false
end

local function GetFillAuctionListFromLoot(self)
    return self.db.fillFromLoot
end

local function SetFillAuctionListFromLootGLOnly(self, value)
    self.db.fillFromLootGLOnly = value and true or false
end

local function GetFillAuctionListFromLootGLOnly(self)
    return self.db.fillFromLootGLOnly
end

local function SetFilledLootRarity(self, value)
    self.db.lootThreshold = tonumber(value)
end

local function GetFilledLootRarity(self)
    return self.db.lootThreshold or 4
end

local function CreateConfigurationOptions(self)
    local options = {
        auctioning_header = {
            type = "header",
            name = CLM.L["Auctioning"],
            order = 30
        },
        auctioning_guild_award_announcement = {
            name = CLM.L["Announce award to Guild"],
            desc = CLM.L["Toggles loot award announcement to guild"],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetAnnounceAwardToGuild(v) end,
            get = function(i) return CLM.GlobalConfigs:GetAnnounceAwardToGuild() end,
            width = "double",
            order = 31
        },
        auctioning_enable_auto_award_from_corpse = {
            name = CLM.L["Auto-assign from corpse"],
            desc = CLM.L["Enable loot auto-assign (Master Looter UI) from corpse when item is awarded"],
            type = "toggle",
            set = function(i, v) SetAutoAssign(self, v) end,
            get = function(i) return GetAutoAssign(self) end,
            width = "double",
            order = 32
        },
        auctioning_enable_auto_trade = {
            name = CLM.L["Auto-trade after award"],
            desc = CLM.L["Enables auto-trade awarded loot after auctioning from bag"],
            type = "toggle",
            set = function(i, v) SetAutoTrade(self, v) end,
            get = function(i) return GetAutoTrade(self) end,
            -- width = "double",
            order = 33
        },
        auctioning_list_header = {
            type = "header",
            name = CLM.L["Auctioning - List Filling"],
            order = 33.5
        },
        auction_fill_from_corpse = {
            name = CLM.L["Fill auction list from corpse"],
            desc = CLM.L["Fill auction list with items from corpse. Will happen only if you open the corpse loot window."],
            type = "toggle",
            set = function(i, v) SetFillAuctionListFromCorpse(self, v) end,
            get = function(i) return GetFillAuctionListFromCorpse(self) end,
            width = "double",
            order = 34,
        },
        auction_fill_from_corpse_ml_only = {
            name = CLM.L["Master Loot Only"],
            desc = CLM.L["Fill from corpse only if you are the Loot Master."],
            type = "toggle",
            set = function(i, v) SetFillAuctionListFromCorpseMLOnly(self, v) end,
            get = function(i) return GetFillAuctionListFromCorpseMLOnly(self) end,
            -- width = "double",
            order = 35,
        },
        auction_fill_from_loot = {
            name = CLM.L["Fill auction list with looted items"],
            desc = CLM.L["Fill auction list with looted items. This will automatically add all items you have received."],
            type = "toggle",
            set = function(i, v) SetFillAuctionListFromLoot(self, v) end,
            get = function(i) return GetFillAuctionListFromLoot(self) end,
            width = "double",
            order = 36,
        },
        auction_fill_from_loot_gl_only = {
            name = CLM.L["Group Loot Only"],
            desc = CLM.L["Fill from loot only if you are using Group Loot."],
            type = "toggle",
            set = function(i, v) SetFillAuctionListFromLootGLOnly(self, v) end,
            get = function(i) return GetFillAuctionListFromLootGLOnly(self) end,
            -- width = "double",
            order = 37,
        },
        auction_fill_threshold = {
            name = CLM.L["Loot rarity"],
            desc = CLM.L["Select loot rarity threshold to used to fill the auction list."],
            type = "select",
            values = CONSTANTS.ITEM_QUALITY,
            set = function(i, v) SetFilledLootRarity(self, v) end,
            get = function(i) return GetFilledLootRarity(self) end,
            order = 38
        },
        global_auction_spacer = {
            name = "",
            desc = "",
            type = "description",
            width = 1,
            order =  38.5
        },
        global_auction_combination = {
            name = CLM.L["Modifier combination"],
            desc = CLM.L["Select modifier combination for filling auction from bags and corpse."],
            type = "select",
            values = CONSTANTS.MODIFIER_COMBINATIONS_GUI,
            sorting = CONSTANTS.MODIFIER_COMBINATIONS_SORTED,
            set = function(i, v) CLM.GlobalConfigs:SetModifierCombination(v) end,
            get = function(i) return CLM.GlobalConfigs:GetModifierCombination() end,
            order = 39.5
        },
        auctioning_chat_commands_header = {
            type = "header",
            name = CLM.L["Auctioning - Chat Commands"],
            order = 40
        },
        auctioning_chat_commands = {
            name = CLM.L["Enable chat commands"],
            desc = CLM.L["Enable !dkp and !bid through whisper / raid. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetAllowChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetAllowChatCommands() end,
            width = "double",
            order = 41
        },
        auctioning_suppress_incoming = {
            name = CLM.L["Suppress incoming whispers"],
            desc = CLM.L["Hides incoming !dkp and !bid whispers. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetSuppressIncomingChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetSuppressIncomingChatCommands() end,
            width = "double",
            order = 42
        },
        auctioning_suppress_outgoing = {
            name = CLM.L["Suppress outgoing whispers"],
            desc = CLM.L["Hides outgoing !dkp and !bid responses. Change requires /reload."],
            type = "toggle",
            set = function(i, v) CLM.GlobalConfigs:SetSuppressOutgoingChatCommands(v) end,
            get = function(i) return CLM.GlobalConfigs:GetSuppressOutgoingChatCommands() end,
            width = "double",
            order = 43
        },
    }
    return options
end

-- Private

local function UpdateAuctionInfo(self, raid)
    for _, auction in ipairs({"currentAuction", "pendingAuction"}) do
        self[auction]:UpdateRaid(raid)
    end
end

local function SetRaidConnection(self)
    if CLM.MODULES.RaidManager:IsInRaid() then
        print("SetRaidConnection")
        UpdateAuctionInfo(self, CLM.MODULES.RaidManager:GetRaid())
    end
end

function AuctionManager:Initialize()
    LOG:Trace("AuctionManager:Initialize()")

    InitializeDB(self)

    CLM.MODULES.Comms:Register(AUCTION_COMM_PREFIX,
    (function(rawMessage, distribution, sender)
        local message = CLM.MODELS.AuctionCommStructure:New(rawMessage)
        if CONSTANTS.AUCTION_COMM.TYPES[message:Type()] == nil then return end
        -- Auction Manager is owner of the channel
        -- pass handling to BidManager
        CLM.MODULES.BiddingManager:HandleIncomingMessage(message, distribution, sender)
    end),
    (function(name)
        return self:IsAuctioneer(name, true) -- relaxed for cross-guild bidding
    end),
    true)

    if not CLM.MODULES.ACL:IsTrusted() then return end

    self.handlers = {
        [CONSTANTS.BIDDING_COMM.TYPE.SUBMIT_BID]        = "HandleSubmitBid",
        [CONSTANTS.BIDDING_COMM.TYPE.CANCEL_BID]        = "HandleCancelBid",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_PASS]       = "HandleNotifyPass",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_HIDE]       = "HandleNotifyHide",
        [CONSTANTS.BIDDING_COMM.TYPE.NOTIFY_CANTUSE]    = "HandleNotifyCantUse",
    }

    CLM.MODULES.ConfigManager:Register(CLM.CONSTANTS.CONFIGS.GROUP.GLOBAL, CreateConfigurationOptions(self))

    self.currentAuction = AuctionInfo:New()
    self.pendingAuction = AuctionInfo:New()

    HookBagSlots()
    CLM.MODULES.EventManager:RegisterWoWEvent({"LOOT_OPENED"}, HandleLootOpenedEvent)
    -- CLM.MODULES.EventManager:RegisterWoWEvent({"LOOT_CLOSED"}, HandleLootClosedEvent)

    CLM.MODULES.LedgerManager:RegisterOnUpdate(function(lag, uncommitted)
        if lag ~= 0 or uncommitted ~= 0 then return end
        SetRaidConnection(self)
        self:RefreshGUI()
    end)
end

-- LOCAL AUCTION MANAGEMENT

local function DefaultCallback(_)
    AuctionManager:RefreshGUI()
end

-- If using custom callback, function, then it is responsible for doing refresh
local function AddItemToAuctionList(self, item, callbackFn)
    callbackFn = callbackFn or DefaultCallback

    local auctionInfo = self.currentAuction
    if auctionInfo:IsInProgress() then
        auctionInfo = self.pendingAuction
    end

    local auctionItem = auctionInfo:AddItem(item)
    if auctionItem then
        auctionItem:SetNote(self.db.notes[item:GetItemID()])
    end
    callbackFn(auctionItem)
end

local function AddItemProxy(self, item, callbackFn)
    if not item:IsItemEmpty() then
        if item:IsItemDataCached() then
        AddItemToAuctionList(self, item, callbackFn)
        else
            item:ContinueOnItemLoad(function() AddItemToAuctionList(self, item, callbackFn) end)
        end
    end
end

function AuctionManager:AddItemById(itemId, callbackFn)
    if not CLM.MODULES.RaidManager:IsInRaid() then
        LOG:Message(CLM.L["Auctioning requires active raid or roster mode."])
        return
    end
    AddItemProxy(self, Item:CreateFromItemID(itemId), callbackFn)
end

function AuctionManager:AddItemByLink(itemLink, callbackFn)
    if not CLM.MODULES.RaidManager:IsInRaid() then
        LOG:Message(CLM.L["Auctioning requires active raid or roster mode."])
        return
    end
    AddItemProxy(self, Item:CreateFromItemLink(itemLink), callbackFn)
end

function AuctionManager:ClearItemList()
    self.currentAuction = self.pendingAuction
    self.pendingAuction = AuctionInfo:New() -- TODO config
    CLM.GUI.AuctionManager:SetVisibleAuctionItem(nil)
    self:RefreshGUI()
end

function AuctionManager:StartAuction()
    LOG:Trace("AuctionManager:StartAuction()")
    local auction = self.currentAuction
    if auction:IsInProgress() then
        LOG:Warning("AuctionManager:StartAuction(): Auction in progress")
        return
    end
    if not self:IsAuctioneer() then
        LOG:Message(CLM.L["You are not allowed to auction items"])
        return
    end
    -- Auction parameters sanity checks
    if not typeof(auction.raid, CLM.MODELS.Raid) then
        LOG:Warning("AuctionManager:StartAuction(): Invalid raid object")
        return false
    end
    if auction:IsEmpty() then
        LOG:Warning("AuctionManager:StartAuction(): Empty auction item list")
        return false
    end
    -- Auction Settings sanity checks
    if auction:GetTime() <= 0 then
        LOG:Warning("AuctionManager:StartAuction(): 0s auction time")
        return false
    end
    if auction:GetTime() < 10 then
        LOG:Warning("AuctionManager:StartAuction(): Very short (below 10s) auction time")
    end
    local commData = CLM.MODELS.AuctionCommStartAuction:NewFromAuctionInfo(auction)
    if CLM.GlobalConfigs:GetAuctionWarning() then
        local numItems = auction:GetItemCount()
        local _, item = next(auction:GetItems())
        local auctionMessage
        if numItems > 1 then
            auctionMessage = sformat(CLM.L["Auction of %s items."], numItems)
        else
            auctionMessage = sformat(CLM.L["Auction of %s"], item:GetItemLink())
        end
        SendChatMessage(auctionMessage , "RAID_WARNING")
        auctionMessage = ""
        auctionMessage = auctionMessage .. sformat(CLM.L["Auction time: %s."] .. " ", auction:GetTime())
        if self.antiSnipe > 0 then
            auctionMessage = auctionMessage .. sformat(CLM.L["Anti-snipe time: %s."], auction:GetAntiSnipe())
        end
        SendChatMessage(auctionMessage , "RAID_WARNING")
        if CLM.GlobalConfigs:GetCommandsWarning() and CLM.GlobalConfigs:GetAllowChatCommands() then
            SendChatMessage("Whisper me '!bid <amount>' to bid. Whisper '!dkp' to check your dkp.", "RAID_WARNING")
        end
    end
    ---- TODO TODO TODO ----
    ---- TODO TODO TODO ----
    ---- TODO TODO TODO ----
    -- -- if values are different than current (or default if no override) item value we will need to update the config
    -- CLM.MODULES.RosterManager:SetRosterItemValues(self.raid:Roster(), itemId, values)
    ---- TODO TODO TODO ----
    ---- TODO TODO TODO ----

    -- self:ClearBids()
    -- -- calculate server end time
    -- self.auctionEndTime = GetServerTime() + self.auctionTime
    -- self.auctionTimeLeft = self.auctionEndTime

    -- -- workaround for open bid to allow 0 bid
    -- if CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] then
    --     self.highestBid = self.values[CONSTANTS.SLOT_VALUE_TIER.BASE] - self.minimalIncrement
    -- end

    -- -- Send auction information
    -- self:SendAuctionStart(self.raid:Roster():UID())
    -- -- Start Auction Ticker
    -- self.lastCountdownValue = 5
    -- self.ticker = C_TimerNewTicker(0.1, (function()
    --     self.auctionTimeLeft = self.auctionEndTime - GetServerTime()
    --     if CLM.GlobalConfigs:GetCountdownWarning() and self.lastCountdownValue > 0 and self.auctionTimeLeft <= self.lastCountdownValue and self.auctionTimeLeft <= 5 then
    --         SendChatMessage(tostring(mceil(self.auctionTimeLeft)), "RAID_WARNING")
    --         self.lastCountdownValue = self.lastCountdownValue - 1
    --     end
    --     if self.auctionTimeLeft < 0.1 then
    --         self:StopAuctionTimed()
    --         return
    --     end
    -- end))
    -- -- Anonymous mapping
    -- self.anonymousMap = {}
    -- self.nextAnonymousId = 1
    -- -- Set auction in progress
    -- self.auctionInProgress = true
    -- -- UI
    -- CLM.GUI.AuctionManager:UpdateBids()
    -- -- Event
    -- CLM.MODULES.EventManager:DispatchEvent(EVENT_START_AUCTION, { itemId = self.itemId })
    -- return true
end

local function AuctionEnd(self, postToChat)
    self:SendAuctionEnd()
    local bidTypeNames = {}

    for bidder, type in pairs(self.userResponses.bidTypes) do
        local bidTypeString = CLM.L["MS"]
        if type == CONSTANTS.BID_TYPE.OFF_SPEC then
            bidTypeString = CLM.L["OS"]
        else
            if self.raid:Roster():GetConfiguration("namedButtons") then
                local name = self.raid:Roster():GetFieldName(type)
                if name ~= "" then
                    bidTypeString = name
                end
            end
        end
        bidTypeNames[bidder] = bidTypeString
    end

    self.lastAuctionEndTime = GetServerTime()
    CLM.MODULES.EventManager:DispatchEvent(EVENT_END_AUCTION, {
        link = self.itemLink,
        id = self.itemId,
        bids = self.userResponses.bids,
        bidNames = bidTypeNames,
        items = self.userResponses.upgradedItems,
        time = self.lastAuctionEndTime,
        isEPGP = (self.raid:Roster():GetPointType() == CONSTANTS.POINT_TYPE.EPGP),
        postToChat = postToChat
     })
end

function AuctionManager:StopAuctionTimed()
    LOG:Trace("AuctionManager:StopAuctionTimed()")
    self.auctionInProgress = false
    self.ticker:Cancel()
    if CLM.GlobalConfigs:GetAuctionWarning() then
        SendChatMessage(CLM.L["Auction complete"], "RAID_WARNING")
    end
    AuctionEnd(self, true)
    CLM.GUI.AuctionManager:UpdateBids()
end

function AuctionManager:StopAuctionManual()
    LOG:Trace("AuctionManager:StopAuctionManual()")
    self.auctionInProgress = false
    self.ticker:Cancel()
    if CLM.GlobalConfigs:GetAuctionWarning() then
        SendChatMessage(CLM.L["Auction stopped by Master Looter"], "RAID_WARNING")
    end
    AuctionEnd(self, false)
    CLM.GUI.AuctionManager:UpdateBids()
end

function AuctionManager:AntiSnipe()
    LOG:Trace("AuctionManager:AntiSnipe()")
    if self.antiSnipeLimit > 0 then
        if self.auctionTimeLeft < self.antiSnipe then
            self.auctionEndTime = self.auctionEndTime + self.antiSnipe
            self.antiSnipeLimit = self.antiSnipeLimit - 1
            self:SendAntiSnipe()
            -- Cheeky update the warning countdown, but only if above 3/5s
            if self.antiSnipe >= 5 then
                self.lastCountdownValue = 5
            elseif self.antiSnipe >= 3 then
                self.lastCountdownValue = 3
            end
        end
    end
end

-- COMMS

function AuctionManager:SendAuctionStart(rosterUid)
    local message = CLM.MODELS.AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.START_AUCTION,
        CLM.MODELS.AuctionCommStartAuction:New(
            self.auctionType,
            self.itemValueMode,
            self.values,
            self.itemLink,
            self.auctionTime,
            self.auctionEndTime,
            self.antiSnipe,
            self.note,
            self.minimalIncrement,
            not self.useOS, -- for backwards compatibility
            rosterUid
        )
    )
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendAuctionEnd()
    local message = CLM.MODELS.AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.STOP_AUCTION, {})
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendAntiSnipe()
    local message = CLM.MODELS.AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.ANTISNIPE, {})
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID)
end

function AuctionManager:SendBidAccepted(name)
    local message = CLM.MODELS.AuctionCommStructure:New(CONSTANTS.AUCTION_COMM.TYPE.ACCEPT_BID, {})
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.WHISPER, name, CONSTANTS.COMMS.PRIORITY.ALERT)
end

function AuctionManager:SendBidDenied(name, reason)
    local message = CLM.MODELS.AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.DENY_BID,
        CLM.MODELS.AuctionCommDenyBid:New(reason)
    )
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.WHISPER, name, CONSTANTS.COMMS.PRIORITY.ALERT)
end

function AuctionManager:SendBidInfo(name, bid)
    local message = CLM.MODELS.AuctionCommStructure:New(
        CONSTANTS.AUCTION_COMM.TYPE.DISTRIBUTE_BID,
        CLM.MODELS.AuctionCommDistributeBid:New(name, bid)
    )
    CLM.MODULES.Comms:Send(AUCTION_COMM_PREFIX, message, CONSTANTS.COMMS.DISTRIBUTION.RAID, nil, CONSTANTS.COMMS.PRIORITY.ALERT)
    -- TODO this must be batched cause of RAID throttling
    -- print(">>>SB[", name, bid:Value(), bid:Type(), "]")
end

local nickMap = {
    "Milhouse ",
    "Jenkins ",
    "Hemet ",
    "Mrgl-Mrgl "
}

function AuctionManager:AnnounceBid(newHighBid, name, bid)
    if not CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] then return end

    local message
    local nameModdified
    if self.auctionType == CONSTANTS.AUCTION_TYPE.ANONYMOUS_OPEN then
        nameModdified = ""
        if not self.anonymousMap[name] then
            self.anonymousMap[name] = nickMap[math.random(1,#nickMap)] .. tostring(self.nextAnonymousId)
            self.nextAnonymousId = self.nextAnonymousId + 1
        end
        local modifiedBid = UTILS.DeepCopy(bid)
        modifiedBid.i = {} -- Clear Upgraded items info
        self:SendBidInfo(self.anonymousMap[name], modifiedBid)
    else
        nameModdified = "(" .. name .. ")"
        self:SendBidInfo(name, bid)
    end

    -- Raid warning highest bidder
    if not newHighBid then return end
    if not CLM.GlobalConfigs:GetBidsWarning() then return end
    if self.itemValueMode ~= CONSTANTS.ITEM_VALUE_MODE.ASCENDING then return end
    if bid:Type() ~= CONSTANTS.BID_TYPE.MAIN_SPEC then return end
    message = sformat(CLM.L["New highest bid: %d DKP %s"], bid:Value(), nameModdified)
    SendChatMessage(message, "RAID_WARNING")
end

function AuctionManager:HandleIncomingMessage(message, distribution, sender)
    LOG:Trace("AuctionManager:HandleIncomingMessage()")
    local mtype = message:Type() or 0
    -- UTILS.DumpTable(message)
    if self.handlers[mtype] then
        self[self.handlers[mtype]](self, message:Data(), sender)
    end
end

function AuctionManager:HandleSubmitBid(data, sender)
    LOG:Trace("AuctionManager:HandleSubmitBid()")
    if not self:IsAuctionInProgress() then
        LOG:Debug("Received submit bid from %s while no auctions are in progress", sender)
        return
    end
    self:UpdateBid(sender, data)
end

function AuctionManager:HandleCancelBid(data, sender)
    LOG:Trace("AuctionManager:HandleCancelBid()")
    if not self:IsAuctionInProgress() then
        LOG:Debug("Received cancel bid from %s while no auctions are in progress", sender)
        return
    end

    self:UpdateBid(sender, CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.BID_TYPE.CANCEL, {}))
end

function AuctionManager:HandleNotifyPass(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyPass()")
    if not self:IsAuctionInProgress() then
        LOG:Debug("Received pass from %s while no auctions are in progress", sender)
        return
    end
    -- Pass (unlike other notifciations) needs to go through update bid since it overwrites bid value
    self:UpdateBid(sender, CLM.MODELS.BiddingCommSubmitBid:New(0, CONSTANTS.BID_TYPE.PASS, {}))
end

function AuctionManager:HandleNotifyHide(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyHide()")
    if not self:IsAuctionInProgress() then
        LOG:Debug("Received hide from %s while no auctions are in progress", sender)
        return
    end
    self.userResponses.hidden[sender] = true
end

function AuctionManager:HandleNotifyCantUse(data, sender)
    LOG:Trace("AuctionManager:HandleNotifyCantUse()")
    if not self:IsAuctionInProgress() then
        LOG:Debug("Received can't use from %s while no auctions are in progress", sender)
        return
    end
    self.userResponses.cantUse[sender] = true
end

-- BIDS

function AuctionManager:ValidateBid(name, bid)
    -- bid cancelling
    if bid:Type() == CONSTANTS.BID_TYPE.CANCEL then
        if CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] then
            return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.CANCELLING_NOT_ALLOWED
        else
            return true
        end
    end
    -- bid passing
    if bid:Type() == CONSTANTS.BID_TYPE.PASS then
        -- only allow passing if no bids have been placed in open auctions
        if (self.itemValueMode == CONSTANTS.ITEM_VALUE_MODE.ASCENDING) and CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] and self.userResponses.bids[name] then
            return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.PASSING_NOT_ALLOWED
        else
            return true
        end
    end
    if (not self.useOS) and (bid:Type() == CONSTANTS.BID_TYPE.OFF_SPEC) then
        return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.OFF_SPEC_NOT_ALLOWED
    end
    local value = bid:Value()
    -- sanity check
    local profile = CLM.MODULES.ProfileManager:GetProfileByName(name)
    if not profile then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NOT_IN_ROSTER end
    local GUID = profile:GUID()
    if not self.raid:Roster():IsProfileInRoster(GUID) then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NOT_IN_ROSTER end
    -- allow negative bidders
    local current = self.raid:Roster():Standings(GUID)
    if current < self.minimumPoints then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BELOW_MIN_BIDDER end
    -- allow negative standings after bid
    local new = current - value
    if (new < self.minimumPoints) and not self.allowBelowMinStandings and (self.raid:Roster():GetPointType() == CONSTANTS.POINT_TYPE.DKP) then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NEGATIVE_STANDING_AFTER end
    -- bid value
    if self.itemValueMode == CONSTANTS.ITEM_VALUE_MODE.ASCENDING then
        -- ascending
        -- min
        if self.values[CONSTANTS.SLOT_VALUE_TIER.BASE] > 0 and value < self.values[CONSTANTS.SLOT_VALUE_TIER.BASE] then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_VALUE_TOO_LOW end
        -- max
        if self.values[CONSTANTS.SLOT_VALUE_TIER.MAX] > 0 and value > self.values[CONSTANTS.SLOT_VALUE_TIER.MAX] then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_VALUE_TOO_HIGH end
        -- open bid ascending
        if CONSTANTS.AUCTION_TYPES_OPEN[self.auctionType] then
            -- always allow bidding min in ascending mode if haven't bid yet
            if value == self.values[CONSTANTS.SLOT_VALUE_TIER.BASE] and self.userResponses.bids[name] == nil then
                return true
            end
            if value <= self.highestBid then
                return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_VALUE_TOO_LOW
            end
            if (value - self.highestBid) < self.minimalIncrement then
                return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_INCREMENT_TOO_LOW
            end
        end
    elseif self.itemValueMode == CONSTANTS.ITEM_VALUE_MODE.TIERED then
        if not self.acceptedTierValues[value] then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_VALUE_INVALID end
    else
        -- single-priced
        if self.values[CONSTANTS.SLOT_VALUE_TIER.BASE] ~= value then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.BID_VALUE_INVALID end
    end
    -- accept otherwise
    return true
end

function AuctionManager:UpdateBid(name, bid)
    LOG:Trace("AuctionManager:UpdateBid()")
    if not self:IsAuctionInProgress() then return false, CONSTANTS.AUCTION_COMM.DENY_BID_REASON.NO_AUCTION_IN_PROGRESS end
    local accept, reason = self:ValidateBid(name, bid)
    if accept then
        local newHighBid = self:UpdateBidsInternal(name, bid)
        self:SendBidAccepted(name)
        self:AnnounceBid(newHighBid, name, bid)
    else
        self:SendBidDenied(name, reason)
    end

    CLM.GUI.AuctionManager:UpdateBids()

    return accept, reason
end

function AuctionManager:UpdateBidsInternal(name, bid)
    if bid:Type() == CONSTANTS.BID_TYPE.CANCEL then
        self.userResponses.bids[name] = nil
        self.userResponses.bidTypes[name] = nil
        self.userResponses.upgradedItems[name] = nil
        self.userResponses.passes[name] = nil
        return false
    end
    if bid:Type() == CONSTANTS.BID_TYPE.PASS then
        -- We remove from the bids list but add to pass list
        self.userResponses.bids[name] = nil
        self.userResponses.passes[name] = true
        return false
    end
    -- actual bid
    local value = bid:Value()
    local items = bid:Items()
    self.userResponses.bids[name] = value
    self.userResponses.bidTypes[name] = bid:Type()
    self.userResponses.upgradedItems[name] = items
    self.userResponses.passes[name] = nil

    -- Force item caching
    if items[1] then GetItemInfo(items[1]) end
    if items[2] then GetItemInfo(items[2]) end

    local newHighBid = false

    if bid:Type() == CONSTANTS.BID_TYPE.MAIN_SPEC then
        if value > self.highestBid then
            self.highestBid = value
            newHighBid = true
        end
        self:AntiSnipe()
    end
    return newHighBid
end

function AuctionManager:Bids()
    return self.userResponses.bids
end

function AuctionManager:BidTypes()
    return self.userResponses.bidTypes
end

function AuctionManager:Passes()
    return self.userResponses.passes
end

function AuctionManager:CantUse()
    return self.userResponses.cantUse
end

function AuctionManager:Hidden()
    return self.userResponses.hidden
end

function AuctionManager:UpgradedItems()
    return self.userResponses.upgradedItems
end

function AuctionManager:ClearBids()
    self.userResponses = {
        bids    = {},
        bidTypes = {},
        upgradedItems = {},
        passes  = {},
        cantUse = {},
        hidden  = {}
    }
    self.highestBid = 0
end

function AuctionManager:Award(itemLink, itemId, price, name)
    LOG:Trace("AuctionManager:Award()")
    local success, uuid = CLM.MODULES.LootManager:AwardItem(self.raid, name, itemLink, itemId, price)
    if success then
        CLM.MODULES.AuctionHistoryManager:CorrelateWithLoot(self.lastAuctionEndTime, uuid)
    end
    return success
end

function AuctionManager:IsAuctioneer(name, relaxed)
    LOG:Trace("AuctionManager:IsAuctioneer()")
    name = name or whoami
    return CLM.MODULES.RaidManager:IsAllowedToAuction(name, relaxed)
end

-- NEW

function AuctionManager:IsAuctionInProgress()
    return self.currentAuction:IsInProgress()
end

function AuctionManager:GetCurrentAuctionInfo()
    return self.currentAuction
end

function AuctionManager:SetAuctionTime(time)
    time = tonumber(time) or 0
    if time <= 0 then
        LOG:Warning("Trying to set 0s auction time.")
        return
    end
    self.currentAuction:SetTime(time)
end

function AuctionManager:GetAuctionTime()
    return self.currentAuction:GetTime()
end

function AuctionManager:SetAntiSnipe(time)
    time = tonumber(time) or 0
    if time < 0 then
        LOG:Warning("Trying to set negative anti-snipe time.")
        return
    end
    self.currentAuction:SetAntiSnipe(time)
end

function AuctionManager:GetAntiSnipe()
    return self.currentAuction:GetAntiSnipe()
end

function AuctionManager:SetItemNote(auctionItem, note)
    local itemId = auctionItem.item:GetItemID()
    if note and note:len() > 0 then
        self.db.notes[itemId] = note
    else
        self.db.notes[itemId] = nil
    end
    auctionItem:SetNote(note)
end

function AuctionManager:RefreshGUI()
    CLM.GUI.AuctionManager:Refresh(true)
end

CONSTANTS.AUCTION_COMM = {
    BID_PASS  = CLM.L["PASS"],
    TYPE = {
        START_AUCTION = 1,
        STOP_AUCTION = 2,
        ANTISNIPE = 3,
        ACCEPT_BID = 4,
        DENY_BID = 5,
        DISTRIBUTE_BID = 6
    },
    TYPES = UTILS.Set({
        1, -- START AUCTION
        2, -- STOP ACUTION
        3, -- ANTISNIPE
        4, -- ACCEPT BID
        5, -- DENY BID
        6, -- DISTRIBUTE BID
    }),
    DENY_BID_REASON = {
        NOT_IN_ROSTER = 1,
        BELOW_MIN_BIDDER = 2,
        NEGATIVE_STANDING_AFTER = 3,
        BID_VALUE_TOO_LOW = 4,
        BID_VALUE_TOO_HIGH = 5,
        BID_VALUE_INVALID = 6,
        BID_INCREMENT_TOO_LOW = 7,
        NO_AUCTION_IN_PROGRESS = 8,
        CANCELLING_NOT_ALLOWED = 9,
        PASSING_NOT_ALLOWED = 10,
        OFF_SPEC_NOT_ALLOWED = 11
    },
    DENY_BID_REASONS = UTILS.Set({
        1, -- NOT_IN_ROSTER
        2, -- BELOW_MIN_BIDDER
        3, -- NEGATIVE_STANDING_AFTER
        4, -- BID_VALUE_TOO_LOW
        5, -- BID_VALUE_TOO_HIGH
        6, -- BID_VALUE_INVALID
        7, -- BID_INCREMENT_TOO_LOW
        8, -- NO_AUCTION_IN_PROGRESS
        9, -- CANCELLING_NOT_ALLOWED
        10,-- PASSING_NOT_ALLOWED
        11,-- OFF_SPEC_NOT_ALLOWED
    }),
    DENY_BID_REASONS_STRING = {
        [1] = CLM.L["Not in a roster"],
        [2] = CLM.L["Bidding while below minimum standings not allowed"],
        [3] = CLM.L["Bidding over current standings not allowed"],
        [4] = CLM.L["Bid too low"],
        [5] = CLM.L["Bid too high"],
        [6] = CLM.L["Invalid bid value"],
        [7] = CLM.L["Bid increment too low"],
        [8] = CLM.L["No auction in progress"],
        [9] = CLM.L["Bid cancelling not allowed"],
        [10] = CLM.L["Passing after bidding not allowed"],
        [11] = CLM.L["Off-spec bidding not allowed"]
    }
}

CLM.MODULES.AuctionManager = AuctionManager
--@do-not-package@
function AuctionManager:FakeBids()
    if CLM.MODULES.RaidManager:IsInRaid() and self:IsAuctionInProgress() then
        local roster = CLM.MODULES.RaidManager:GetRaid():Roster()
        local profiles = roster:Profiles()
        local numBids = math.random(1, math.min(#profiles, 25))
        for _=1,numBids do
            local bidder = CLM.MODULES.ProfileManager:GetProfileByGUID(profiles[math.random(1, #profiles)]):Name()
            local bidType = math.random(1,6)
            if     bidType == 1 then -- none
            elseif bidType == 2 then -- value
                local namedButtons = roster:GetConfiguration("namedButtons")
                if namedButtons then
                    local b = {"b","s", "m", "l", "x"}
                    local bt = b[math.random(1,5)]
                    self:HandleSubmitBid(CLM.MODELS.BiddingCommSubmitBid:New(self.values[bt], bt), bidder)
                else
                    local min, max = self.values[CONSTANTS.SLOT_VALUE_TIER.BASE], 10000
                    if self.values[CONSTANTS.SLOT_VALUE_TIER.MAX] > 0 then
                        max = self.values[CONSTANTS.SLOT_VALUE_TIER.MAX]
                    end
                    self:HandleSubmitBid(CLM.MODELS.BiddingCommSubmitBid:New(math.random(min, max), math.random(1,2)), bidder)
                end
            elseif bidType == 3 then -- pass
                self:HandleNotifyPass(nil, bidder)
            elseif bidType == 4 then -- cancel
                self:HandleCancelBid(nil, bidder)
            elseif bidType == 5 then -- hide
                self:HandleNotifyHide(nil, bidder)
            elseif bidType == 6 then -- cant use
                self:HandleNotifyCantUse(nil, bidder)
            end
        end
    end
end
--@end-do-not-package@