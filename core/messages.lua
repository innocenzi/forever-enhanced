local _, ns = ...

local CHAT_PREFIX = "|cff4fc3f7" .. ns.title .. "|r: "

-- Informational chat message.
function ns:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. message)
end

-- Red error text in the middle of the screen, like a blocked game action.
function ns:Error(message)
    UIErrorsFrame:AddExternalErrorMessage(message)
end
