if not lib then return end

if cache.resource ~= 'slrn_qbmultijob' then
    lib.print.error('The resource needs to be named ^5slrn_qbmultijob^7.')
    return
end

local Config = lib.require('config')
local saveJobsCreated = false

local function GetJobCount(cid)
    local result = MySQL.query.await('SELECT COUNT(*) as jobCount FROM save_jobs WHERE cid = ?', { cid })
    local jobCount = result[1].jobCount
    return jobCount
end

local function isWhiteListedJob(job)
    if Config.WhiteListJobs[job] then return true end

    for _, whiteListedJob in pairs(Config.WhiteListJobs) do
        if whiteListedJob:lower() == job then return true end
    end

    return false
end

local function canSetJob(cid, jobName)
    local jobs = MySQL.query.await('SELECT job, grade FROM save_jobs WHERE cid = ? ', { cid })
    if not jobs then return false end
    for i = 1, #jobs do
        if jobs[i].job == jobName then
            return true, jobs[i].grade
        end
    end
    return false
end

local function validateSavedJobs()
    local savedJobs = MySQL.query.await('SELECT cid, job, grade FROM save_jobs')
    local invalidCount = 0

    for i = 1, #savedJobs do
        local savedJob = savedJobs[i]
        local jobInfo = QBCore.Shared.Jobs[savedJob.job]
        local invalidReason

        if not jobInfo then
            invalidReason = 'job does not exist in QBCore.Shared.Jobs'
        elseif not jobInfo.grades or not jobInfo.grades[tostring(savedJob.grade)] then
            invalidReason = 'grade does not exist for this job'
        end

        if invalidReason then
            invalidCount = invalidCount + 1
            local message = ('Invalid save_jobs entry: cid=%s job=%s grade=%s (%s)')
                :format(savedJob.cid, savedJob.job, savedJob.grade, invalidReason)

            if Config.RemoveInvalidJobsOnStart then
                MySQL.query.await('DELETE FROM save_jobs WHERE cid = ? AND job = ?',
                    { savedJob.cid, savedJob.job })
                lib.print.warn(message .. ' - removed')
            else
                lib.print.warn(message)
            end
        end
    end

    if invalidCount > 0 then
        local action = Config.RemoveInvalidJobsOnStart and 'removed' or 'reported'
        lib.print.warn(('save_jobs validation complete: %d invalid entr%s %s.')
            :format(invalidCount, invalidCount == 1 and 'y' or 'ies', action))
    end
end

local function populateSavedJobs()
    local players = MySQL.query.await('SELECT citizenid, job FROM players')

    for i = 1, #players do
        local playerJob = json.decode(players[i].job)
        if playerJob and playerJob.name ~= 'unemployed' and playerJob.grade and playerJob.grade.level ~= nil then
            MySQL.query.await('INSERT IGNORE INTO save_jobs (cid, job, grade) VALUES (?, ?, ?)', {
                players[i].citizenid,
                playerJob.name,
                playerJob.grade.level
            })
        end
    end
end

lib.callback.register('slrn_multijob:server:myJobs', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local storeJobs = {}
    local result = MySQL.query.await('SELECT * FROM save_jobs WHERE cid = ?', { Player.PlayerData.citizenid })
    for _, v in pairs(result) do
        local job = QBCore.Shared.Jobs[v.job]

        if not job then
            lib.print.error(('MISSING JOB FROM jobs.lua: "%s" | CITIZEN ID: %s'):format(v.job, Player.PlayerData.citizenid))
            return storeJobs
        end

        local grade = job.grades[tostring(v.grade)]

        if not grade then
            lib.print.error(('MISSING JOB GRADE for "%s". GRADE MISSING: %s | CITIZEN ID: %s'):format(v.job, v.grade,
                Player.PlayerData.citizenid))
            return storeJobs
        end

        storeJobs[#storeJobs + 1] = {
            job = v.job,
            salary = grade.payment,
            jobLabel = job.label,
            gradeLabel = grade.name,
            grade = v.grade,
        }
    end
    return storeJobs
end)

lib.callback.register('slrn_multijob:server:changeJob', function(source, job)
    local player = QBCore.Functions.GetPlayer(source)

    if player.PlayerData.job.name == job then
        QBCore.Functions.Notify(source, 'Your current job is already set to this.', 'error')
        return
    end

    local jobInfo = QBCore.Shared.Jobs[job]
    if not jobInfo then
        QBCore.Functions.Notify(source, 'Invalid job.', 'error')
        return
    end

    local cid = player.PlayerData.citizenid
    local canSet, grade = canSetJob(cid, job)

    if not canSet then return end

    local changed = player.Functions.SetJob(job, grade)
    if not changed then
        QBCore.Functions.Notify(source, 'Unable to change your job.', 'error')
        return false
    end

    player.Functions.SetJobDuty(false)
    TriggerClientEvent('QBCore:Client:SetDuty', source, false)
    QBCore.Functions.Notify(source, ('Your job is now: %s'):format(jobInfo.label))
    return true
end)

lib.callback.register('slrn_multijob:server:deleteJob', function(source, job)
    local Player = QBCore.Functions.GetPlayer(source)
    MySQL.query.await('DELETE FROM save_jobs WHERE cid = ? and job = ?', { Player.PlayerData.citizenid, job })
    QBCore.Functions.Notify(source, 'You deleted ' .. QBCore.Shared.Jobs[job].label .. ' job from your menu.')
    if Player.PlayerData.job.name == job then
        Player.Functions.SetJob('unemployed', 0)
    end
    return true
end)

RegisterNetEvent('qb-bossmenu:server:FireEmployee', function(target) -- Removes job when fired from qb-bossmenu.
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local Employee = QBCore.Functions.GetPlayerByCitizenId(target)
    if Employee then
        local oldJob = Employee.PlayerData.job.name
        MySQL.query.await('DELETE FROM save_jobs WHERE cid = ? AND job = ?', { Employee.PlayerData.citizenid, oldJob })
    else
        local player = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? LIMIT 1', { target })
        if player[1] then
            Employee = player[1]
            Employee.job = json.decode(Employee.job)
            if Employee.job.grade.level > Player.PlayerData.job.grade.level then return end
            MySQL.query.await('DELETE FROM save_jobs WHERE cid = ? AND job = ?', { target, Employee.job.name })
        end
    end
end)

local function adminRemoveJob(src, id, job)
    local Player = QBCore.Functions.GetPlayer(id)
    local cid = Player.PlayerData.citizenid
    local result = MySQL.query.await('SELECT * FROM save_jobs WHERE cid = ? AND job = ?', { cid, job })
    if result[1] then
        MySQL.query.await('DELETE FROM save_jobs WHERE cid = ? AND job = ?', { cid, job })
        QBCore.Functions.Notify(src, ('Job: %s was removed from ID: %s'):format(job, id), 'success')
        if Player.PlayerData.job.name == job then
            Player.Functions.SetJob('unemployed', 0)
        end
    else
        QBCore.Functions.Notify(src, 'Player doesn\'t have this job?', 'error')
    end
end

QBCore.Commands.Add('removejob', "Remove a job from the player's multijob.",
    { { name = 'id', help = 'ID of the player' }, { name = 'job', help = 'Name of Job' } }, true, function(source, args)
    local src = source
    if not args[1] then
        QBCore.Functions.Notify(src, 'Must provide a player id.', 'error')
        return
    end
    if not args[2] then
        QBCore.Functions.Notify(src, 'Must provide the name of the job to remove from the player.', 'error')
        return
    end
    local id = tonumber(args[1])
    local Player = QBCore.Functions.GetPlayer(id)
    if not Player then
        QBCore.Functions.Notify(src, 'Player not online.', 'error')
        return
    end

    adminRemoveJob(src, id, args[2])
end, 'admin')

local function newSetJob(source, job, grade)
    local player = QBCore.Functions.GetPlayer(source)
    job = job:lower()
    grade = grade or '0'
    if not QBCore.Shared.Jobs[job] then return false end

    local gradeKey = tostring(grade)
    local jobGradeInfo = QBCore.Shared.Jobs[job].grades[gradeKey]
    if not jobGradeInfo then
        QBCore.Functions.Notify(source, 'Invalid job grade.', 'error')
        return false
    end

    local hasJob = false
    local whiteListJob = isWhiteListedJob(job)
    local whiteListLimit = false
    local cid = player.PlayerData.citizenid
    if job ~= 'unemployed' then
        local result = MySQL.query.await('SELECT * FROM save_jobs WHERE cid = ?', { cid })
        if result then
            for _, v in pairs(result) do
                if isWhiteListedJob(v.job) and whiteListJob and v.job ~= job then whiteListLimit = true end
                if v.job == job then
                    MySQL.query.await('UPDATE save_jobs SET grade = ? WHERE job = ? and cid = ?',
                        { grade, job, cid })
                    hasJob = true
                end
            end
        end

        if not hasJob and not whiteListLimit and GetJobCount(cid) < Config.MaxJobs then
            MySQL.insert.await('INSERT INTO save_jobs (cid, job, grade) VALUE (?, ?, ?)',
                { cid, job, grade })
        else
            local message = whiteListLimit and 'You have the maximum amount of allowlist jobs' or 'You have the max amount of jobs.'
            QBCore.Functions.Notify(source, message, 'error')
            return false
        end
    end

    local gradeData = {
        name = 'No Grades',
        level = 0,
        payment = 30,
        isboss = false
    }
    if jobGradeInfo then
        gradeData.name = jobGradeInfo.name
        gradeData.level = tonumber(gradeKey)
        gradeData.payment = jobGradeInfo.payment
        gradeData.isboss = jobGradeInfo.isboss or false
    end

    player.Functions.SetPlayerData('job', {
        name = job,
        label = QBCore.Shared.Jobs[job].label,
        onduty = QBCore.Shared.Jobs[job].defaultDuty,
        type = QBCore.Shared.Jobs[job].type or 'none',
        grade = gradeData,
        isboss = jobGradeInfo.isboss or false
    })

    if not player.Offline then
        TriggerEvent('QBCore:Server:OnJobUpdate', source, player.PlayerData.job)
        TriggerClientEvent('QBCore:Client:OnJobUpdate', source, player.PlayerData.job)
    end

    return true
end

local function fixJobMethod(Player)
    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, 'SetJob', function(job, grade)
        return newSetJob(Player.PlayerData.source, job, grade)
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    fixJobMethod(Player)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then return end
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do fixJobMethod(Player) end

    local existingTable = MySQL.query.await([[
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'save_jobs'
        LIMIT 1
    ]])

    saveJobsCreated = #existingTable == 0
    if saveJobsCreated then
        MySQL.query.await([=[
            CREATE TABLE `save_jobs` (
                `cid` VARCHAR(100) NOT NULL,
                `job` VARCHAR(100) NOT NULL,
                `grade` INT(11) NOT NULL,
                UNIQUE KEY `cid_job` (`cid`,`job`)
            );
        ]=])
        populateSavedJobs()
    end

    validateSavedJobs()
end)

CreateThread(function()
    if GetResourceState('qbx_core') == 'started' then
        while true do
            lib.print.error('QBX Core detected! You downloaded the wrong one. Visit https://github.com/solareon/slrn_multijob and download the correct resource')
            Wait(100)
        end
    end
end)
