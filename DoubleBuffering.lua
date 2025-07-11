-- Автор: XDevster
-- Версия: 1.1.2
-- Дата: 2025-07-11

local component = require("component")
local gpu = component.gpu
local computer = require("computer")
local event = require("event")

local buffer = {}
local width, height = gpu.getResolution()
local maxDepth = gpu.maxDepth()

local backBuffer, frontBuffer
local bufferInitialized = false
local useHardwareBuffering = false
local lastError = nil

-- Проверка доступности GPU
local function checkGPU()
    if not gpu or not gpu.getResolution then
        lastError = "GPU component not available"
        return false
    end
    return true
end

-- Проверка поддержки аппаратных буферов
local function checkHardwareSupport()
    local ok, res = pcall(function()
        return gpu.allocateBuffer and gpu.freeBuffer and gpu.bitblt
    end)
    return ok and res
end

-- Инициализация буферов
local function initBuffers()
    if not checkGPU() then return false end

    width, height = gpu.getResolution()
    useHardwareBuffering = checkHardwareSupport()

    if useHardwareBuffering then
        pcall(function()
            if backBuffer then gpu.freeBuffer(backBuffer) end
            if frontBuffer then gpu.freeBuffer(frontBuffer) end
        end)
    end

    local success, err = pcall(function()
        if useHardwareBuffering then
            backBuffer = gpu.allocateBuffer(width, height)
            frontBuffer = gpu.allocateBuffer(width, height)

            gpu.setActiveBuffer(backBuffer)
            gpu.setBackground(0x000000)
            gpu.setForeground(0xFFFFFF)
            gpu.fill(1, 1, width, height, " ")

            gpu.setActiveBuffer(frontBuffer)
            gpu.setBackground(0x000000)
            gpu.setForeground(0xFFFFFF)
            gpu.fill(1, 1, width, height, " ")

            gpu.setActiveBuffer(0)
        else
            backBuffer = {}
            frontBuffer = {}
            for y = 1, height do
                backBuffer[y], frontBuffer[y] = {}, {}
                for x = 1, width do
                    backBuffer[y][x] = {char = " ", fg = 0xFFFFFF, bg = 0x000000}
                    frontBuffer[y][x] = {char = nil, fg = nil, bg = nil}
                end
            end
        end
    end)

    if not success then
        lastError = err or "Buffer init failed"
        useHardwareBuffering = false
        backBuffer, frontBuffer = {}, {}
        for y = 1, height do
            backBuffer[y], frontBuffer[y] = {}, {}
            for x = 1, width do
                backBuffer[y][x] = {char = " ", fg = 0xFFFFFF, bg = 0x000000}
                frontBuffer[y][x] = {char = nil, fg = nil, bg = nil}
            end
        end
    end

    bufferInitialized = true
    return bufferInitialized
end

-- Копирование буфера
local function safeBufferCopy()
    if not bufferInitialized then return false end

    if useHardwareBuffering then
        local ok, err = pcall(function()
            gpu.setActiveBuffer(backBuffer)
            gpu.bitblt(0, 1, 1, width, height, 1, 1)
            gpu.setActiveBuffer(0)
        end)

        if not ok then
            computer.pullSignal(0.1)
            if not pcall(function()
                gpu.setActiveBuffer(backBuffer)
                gpu.bitblt(0, 1, 1, width, height, 1, 1)
                gpu.setActiveBuffer(0)
            end) then
                useHardwareBuffering = false
                lastError = "Hardware buffer copy failed; switched to software mode"
                return false
            end
        end
        return true
    else
        local currentFg, currentBg = nil, nil
        local changed = false
        for y = 1, height do
            for x = 1, width do
                local b = backBuffer[y][x]
                local f = frontBuffer[y][x]
                if b.char ~= f.char or b.fg ~= f.fg or b.bg ~= f.bg then
                    if b.fg ~= currentFg then
                        gpu.setForeground(b.fg)
                        currentFg = b.fg
                    end
                    if b.bg ~= currentBg then
                        gpu.setBackground(b.bg)
                        currentBg = b.bg
                    end
                    gpu.set(x, y, b.char)
                    frontBuffer[y][x] = {char = b.char, fg = b.fg, bg = b.bg}
                    changed = true
                end
            end
        end
        return changed
    end
end

-- API

function buffer.start()
    return initBuffers()
end

function buffer.isHealthy()
    return bufferInitialized and (lastError == nil)
end

function buffer.getLastError()
    return lastError
end

function buffer.clear(fg, bg)
    if not bufferInitialized then return false end

    fg = fg or 0xFFFFFF
    bg = bg or 0x000000

    if useHardwareBuffering then
        local ok = pcall(function()
            gpu.setActiveBuffer(backBuffer)
            gpu.setBackground(bg)
            gpu.setForeground(fg)
            gpu.fill(1, 1, width, height, " ")
            gpu.setActiveBuffer(0)
        end)
        if not ok then
            lastError = "Hardware clear failed"
            return false
        end
    else
        for y = 1, height do
            for x = 1, width do
                backBuffer[y][x] = {char = " ", fg = fg, bg = bg}
            end
        end
    end
    return true
end

function buffer.set(x, y, char, fg, bg)
    if not bufferInitialized or x < 1 or y < 1 or x > width or y > height then
        return false
    end

    char = char or " "
    fg = fg or 0xFFFFFF
    bg = bg or 0x000000

    if type(char) == "string" and #char > 1 then
        return buffer.setString(x, y, char, fg, bg)
    end

    if useHardwareBuffering then
        local ok = pcall(function()
            gpu.setActiveBuffer(backBuffer)
            gpu.setForeground(fg)
            gpu.setBackground(bg)
            gpu.set(x, y, char)
            gpu.setActiveBuffer(0)
        end)
        if not ok then
            lastError = "Hardware set failed"
            return false
        end
    else
        backBuffer[y][x] = {char = char, fg = fg, bg = bg}
    end

    return true
end

function buffer.setString(x, y, str, fg, bg)
    if not bufferInitialized then return false end
    fg = fg or 0xFFFFFF
    bg = bg or 0x000000
    for i = 1, #str do
        buffer.set(x + i - 1, y, str:sub(i,i), fg, bg)
    end
    return true
end

function buffer.draw(force)
    if not bufferInitialized then return false end
    return safeBufferCopy()
end

-- Авто-инициализация при загрузке
buffer.start()

return buffer
