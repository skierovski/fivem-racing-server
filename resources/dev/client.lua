RegisterCommand('refresh', function(source, args)
    local name = args[1]
    if not name then
        print('^3[dev]^0 Usage: /refresh <resource>  |  /refresh all')
        return
    end
    TriggerServerEvent('dev:refreshResource', name)
end, false)

print('[dev] ^2/refresh command ready (F8)^0')
