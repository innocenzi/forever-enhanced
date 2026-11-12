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
