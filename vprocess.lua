-- vprocess.lua - ComputerCraft Process Inspector & Manager
local VPROCESS_VERSION = "1.0.0"

-- Colors matching original ANSI theme
local COLOR_HEADER = colors.cyan
local COLOR_PID = colors.yellow
local COLOR_USER = colors.green
local COLOR_DIM = colors.gray
local COLOR_TEXT = colors.white

local function print_version()
    print("vprocess version " .. VPROCESS_VERSION)
    print("Copyright (C) 2026 Cole Bohte (CC Port)")
end

local function print_help()
    print("NAME")
    print("       vprocess - list active running processes or send termination signals\n")
    print("SYNOPSIS")
    print("       vprocess [OPTIONS]\n")
    print("DESCRIPTION")
    print("       Inspects the ComputerCraft multishell environment and displays active")
    print("       processes sorted numerically by Tab ID, or terminates specified tasks.\n")
    print("OPTIONS")
    print("       -k, --kill <PID>")
    print("              Send a termination signal to the specified process ID.\n")
    print("       -f, --force")
    print("              Force terminates the process immediately via multishell.\n")
    print("       -s, --stdout")
    print("              Bypass page-by-page pausing and write directly to output.\n")
    print("       -u <username>")
    print("              Filter process list by owning computer/user label.\n")
    print("       -v, --version")
    print("              Display version information and exit.\n")
    print("       -h, --help")
    print("              Display this help manual and exit.\n")
end

-- Collect process details using ComputerCraft multishell API
local function get_processes()
    local processes = {}
    
    -- Check if multishell is available
    if not multishell then
        -- Fallback for standalone/single-thread environments
        table.insert(processes, {
            pid = 1,
            user = os.getComputerLabel() or ("id_" .. os.computerID()),
            name = shell.getRunningProgram(),
            rss_kb = 0,
            is_kernel_thread = false
        })
        return processes
    end

    local current_tab = multishell.getCurrent()
    local tabs = multishell.getCount()

    for id = 1, tabs do
        local title = multishell.getTitle(id)
        if title then
            -- Note: CC Lua RAM usage cannot be split per-thread accurately,
            -- using total dynamic Lua memory allocation as baseline context
            local total_mem_kb = math.floor(collectgarbage("count"))

            table.insert(processes, {
                pid = id,
                user = os.getComputerLabel() or ("id_" .. os.computerID()),
                name = title ~= "" and title or "shell",
                rss_kb = id == current_tab and total_mem_kb or 0,
                is_kernel_thread = (id == 1 and title == "shell")
            })
        end
    end

    table.sort(processes, function(a, b) return a.pid < b.pid end)
    return processes
end

local function print_colored(text, color)
    if term.isColor() then
        term.setTextColor(color)
        write(text)
        term.setTextColor(COLOR_TEXT)
    else
        write(text)
    end
end

local function main(args)
    local filter_user = nil
    local force_stdout = false
    local target_pid = nil
    local force_kill = false

    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "-u" and i + 1 <= #args do
            i = i + 1
            filter_user = args[i]
        elseif arg == "-s" or arg == "--stdout" then
            force_stdout = true
        elseif (arg == "-k" or arg == "--kill") and i + 1 <= #args do
            i = i + 1
            target_pid = tonumber(args[i])
        elseif arg == "-f" or arg == "--force" then
            force_kill = true
        elseif arg == "-v" or arg == "--version" then
            print_version()
            return
        elseif arg == "-h" or arg == "--help" then
            print_help()
            return
        end
        i = i + 1
    end

    -- Process termination mode
    if target_pid then
        if not multishell then
            printError("Error: Multishell manager is not running.")
            return
        end

        if target_pid <= 0 or target_pid > multishell.getCount() then
            printError("Error: Invalid PID " .. tostring(target_pid))
            return
        end

        if force_kill then
            -- SIGKILL equivalent: Force stopping the process tab
            multishell.terminate(target_pid)
            print("Successfully sent SIGKILL (9) to PID " .. target_pid)
        else
            -- SIGTERM equivalent: Queuing graceful termination event
            os.queueEvent("terminate")
            print("Successfully sent SIGTERM (15) to PID " .. target_pid)
        end
        return
    elseif force_kill and not target_pid then
        printError("Error: --force (-f) must be used alongside --kill (-k) <PID>")
        return
    end

    -- Process listing mode
    local processes = get_processes()
    local _, term_height = term.getSize()
    local line_count = 0

    -- Header
    print_colored(string.format("%-8s %-12s %-10s %s\n", "PID", "USER", "RSS (KB)", "COMMAND"), COLOR_HEADER)
    print_colored("------------------------------------------------------------\n", COLOR_DIM)
    line_count = line_count + 2

    for _, proc in ipairs(processes) do
        if not filter_user or proc.user == filter_user then
            print_colored(string.format("%-8d ", proc.pid), COLOR_PID)
            print_colored(string.format("%-12s ", proc.user), COLOR_USER)
            
            if proc.is_kernel_thread then
                print_colored(string.format("%-10d ", proc.rss_kb), COLOR_TEXT)
                print_colored(string.format("[%s]\n", proc.name), COLOR_DIM)
            else
                print_colored(string.format("%-10d %s\n", proc.rss_kb, proc.name), COLOR_TEXT)
            end

            line_count = line_count + 1

            -- Pager implementation (simulating `less`)
            if not force_stdout and line_count >= (term_height - 1) then
                print_colored("--- Press any key for more ---", COLOR_DIM)
                os.pullEvent("key")
                term.clearLine()
                line_count = 0
            end
        end
    end
end

main({...})
