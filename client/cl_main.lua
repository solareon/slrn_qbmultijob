if GetCurrentResourceName() ~= 'slrn_qbmultijob' then
    lib.print.error('This resource needs to be named ^5slrn_qbmultijob^7.')
    return
end

local function AddApp()
    local added, errorMessage = exports['lb-phone']:AddCustomApp({
        identifier = 'slrn_multijob',
        name = 'Employment',
        description = 'Employment application',
        defaultApp = true,
        developer = 'solareon.',
        ui = 'slrn_qbmultijob/ui/index.html',
        icon = 'https://cfx-nui-slrn_qbmultijob/ui/assets/icon.png',
    })

    if not added then
        print('Could not add app:', errorMessage)
    end
end
CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do
        Wait(500)
    end

    AddApp()
end)


RegisterNUICallback('getJobs', function(_, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local jobMenu = {}
    local playerJobs = lib.callback.await('slrn_multijob:server:myJobs', false)
    for _, job in pairs(playerJobs) do
        local primaryJob = PlayerData.job.name == job.job
        jobMenu[#jobMenu + 1] = {
            title = job.jobLabel,
            description = ('Grade: %s [%s] <br /> Salary: $%s'):format(job.gradeLabel, job.grade, job.salary),
            disabled = primaryJob,
            jobName = job.job,
            duty = primaryJob and PlayerData.job.onduty or false,
        }
    end
    cb(jobMenu)
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    TriggerServerEvent('QBCore:ToggleDuty')
    cb(true)
    Wait(500)
    exports["lb-phone"]:SendCustomAppMessage('slrn_multijob', { action = 'update-jobs' })
end)

RegisterNUICallback('removeJob', function(job, cb)
    lib.callback('slrn_multijob:server:deleteJob', false, function()
        cb(true)
        exports["lb-phone"]:SendCustomAppMessage('slrn_multijob', { action = 'update-jobs' })
    end, job)
end)

RegisterNUICallback('changeJob', function(job, cb)
    lib.callback('slrn_multijob:server:changeJob', false, function()
        cb(true)
        exports["lb-phone"]:SendCustomAppMessage('slrn_multijob', { action = 'update-jobs' })
    end, job)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    exports["lb-phone"]:SendCustomAppMessage('slrn_multijob', { action = 'update-jobs' })
    TriggerServerEvent('slrn_multijob:server:newJob', JobInfo)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'lb-phone' then
        AddApp()
    end
end)
