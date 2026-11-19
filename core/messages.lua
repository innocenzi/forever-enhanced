local _, ns = ...

-- Chat message, shown like the game's system messages: no prefix, in the
-- system color, in every chat tab that shows system messages (the main one
-- when none does, so it is never lost).
function ns:Print(message)
    local info = ChatTypeInfo["SYSTEM"]
    local shown = false
    ChatFrameUtil.ForEachChatFrame(function(chatFrame)
        if chatFrame:ContainsMessageGroup("SYSTEM") then
            chatFrame:AddMessage(message, info.r, info.g, info.b, info.id)
            shown = true
        end
    end)
    if not shown then
        DEFAULT_CHAT_FRAME:AddMessage(message, info.r, info.g, info.b, info.id)
    end
end

-- Red error text in the middle of the screen, like a blocked game action.
function ns:Error(message)
    UIErrorsFrame:AddExternalErrorMessage(message)
end

-- Yellow text in the middle of the screen, like the game's own notices.
function ns:Warning(message)
    UIErrorsFrame:AddExternalWarningMessage(message)
end

-- Muting the game's errors: while any owner mutes them, UIErrorsFrame stops
-- showing UI_ERROR_MESSAGE (red text and voice: not enough mana, out of range,
-- ...). Errors we show ourselves (ns:Error) still show. The event is only
-- registered back if we unregistered it, so another addon's choice stays.
local ERROR_EVENT = "UI_ERROR_MESSAGE"
local errorMuters = {}
local errorsUnregistered = false

local function SyncGameErrors()
    if next(errorMuters) then
        if not errorsUnregistered and UIErrorsFrame:IsEventRegistered(ERROR_EVENT) then
            UIErrorsFrame:UnregisterEvent(ERROR_EVENT)
            errorsUnregistered = true
        end
    elseif errorsUnregistered then
        errorsUnregistered = false
        UIErrorsFrame:RegisterEvent(ERROR_EVENT)
    end
end

function ns:MuteGameErrors(owner)
    errorMuters[owner] = true
    SyncGameErrors()
end

function ns:UnmuteGameErrors(owner)
    errorMuters[owner] = nil
    SyncGameErrors()
end

-- Mutes the game's errors until the next frame: those of a cast just made (or
-- about to be), which the client reports later in the same frame.
local frameMuter = {}
local frameMuted = false

local function UnmuteFrame()
    frameMuted = false
    ns:UnmuteGameErrors(frameMuter)
end

function ns:MuteGameErrorsThisFrame()
    if not frameMuted then
        frameMuted = true
        self:MuteGameErrors(frameMuter)
        C_Timer.After(0, UnmuteFrame)
    end
end
