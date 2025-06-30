-- Автор: XDevster
-- Версия: 1.1.1
-- Дата: 2025-06-16

local component = require("component")
local gpu = component.gpu
local computer = require("computer")
local event = require("event")

local buffer = {}
local width, height = gpu.getResolution()
local maxDepth = gpu.maxDepth()

-- Состояние системы
local backBuffer, frontBuffer
local bufferInitialized = false
local useHardwareBuffering = false
local lastError = nil

-- Проверка работоспособности GPU
local function checkGPU()
    if not gpu or not gpu.getResolution then
        lastError = "GPU component not available"
        return false
    end
    return true
end

-- Безопасная проверка поддержки аппаратных буферов
local function checkHardwareSupport()
    local ok, result = pcall(function()
        return gpu.allocateBuffer and gpu.copyBuffer and gpu.freeBuffer
    end)
    return ok and result
end

-- Инициализация буферов с защитой от сбоев
local function initBuffers()
    if not checkGPU() then return false end
    
    width, height = gpu.getResolution()
    useHardwareBuffering = checkHardwareSupport()
    
    -- Очистка предыдущих буферов
    if useHardwareBuffering then
        pcall(function()
            if backBuffer then gpu.freeBuffer(backBuffer) end
            if frontBuffer then gpu.freeBuffer(frontBuffer) end
        end)
    end
    
    -- Создание новых буферов
    local success, err = pcall(function()
        if useHardwareBuffering then
            -- Аппаратные буферы
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
            -- Программные буферы
            backBuffer = {}
            frontBuffer = {}
            
            for y = 1, height do
                backBuffer[y] = {}
                frontBuffer[y] = {}
                for x = 1, width do
                    backBuffer[y][x] = {char = " ", fg = 0xFFFFFF, bg = 0x000000}
                    frontBuffer[y][x] = {char = nil, fg = nil, bg = nil}
                end
            end
        end
        
        bufferInitialized = true
        lastError = nil
        return true
    end)
    
    if not success then
        lastError = err or "Unknown buffer initialization error"
        bufferInitialized = false
        useHardwareBuffering = false
        
        -- Попытка восстановления с программными буферами
        backBuffer = {}
        frontBuffer = {}
        for y = 1, height do
            backBuffer[y] = {}
            frontBuffer[y] = {}
            for x = 1, width do
                backBuffer[y][x] = {char = " ", fg = 0xFFFFFF, bg = 0x000000}
                frontBuffer[y][x] = {char = nil, fg = nil, bg = nil}
            end
        end
        bufferInitialized = true
    end
    
    return bufferInitialized
end

-- Безопасное копирование буферов
local function safeBufferCopy()
    if not bufferInitialized then return false end
    
    if useHardwareBuffering then
        local success, err = pcall(function()
            -- Первая попытка
            gpu.copyBuffer(backBuffer, 0, 1, 1, width, height, 1, 1)
            gpu.copyBuffer(0, frontBuffer, 1, 1, width, height, 1, 1)
            return true
        end)
        
        if not success then
            -- Вторая попытка с восстановлением
            computer.pullSignal(0.1) -- Даем системе передышку
            local ok = pcall(function()
                gpu.copyBuffer(backBuffer, 0, 1, 1, width, height, 1, 1)
                gpu.copyBuffer(0, frontBuffer, 1, 1, width, height, 1, 1)
                return true
            end)
            
            if not ok then
                -- Переключаемся на программный режим
                useHardwareBuffering = false
                lastError = "Hardware buffer copy failed, switched to software mode"
                return false
            end
        end
        return true
    else
        -- Программная реализация копирования
        local currentFg, currentBg = nil, nil
        local anyChanges = false
        
        for y = 1, height do
            for x = 1, width do
                local back = backBuffer[y][x]
                local front = frontBuffer[y][x]
                
                if back.char ~= front.char or back.fg ~= front.fg or back.bg ~= front.bg then
                    if back.fg ~= currentFg then
                        gpu.setForeground(back.fg)
                        currentFg = back.fg
                    end
                    if back.bg ~= currentBg then
                        gpu.setBackground(back.bg)
                        currentBg = back.bg
                    end
                    
                    gpu.set(x, y, back.char)
                    frontBuffer[y][x] = {
                        char = back.char,
                        fg = back.fg,
                        bg = back.bg
                    }
                    anyChanges = true
                end
            end
        end
        
        return anyChanges
    end
end

-- Основной API

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
        local success = pcall(function()
            gpu.setActiveBuffer(backBuffer)
            gpu.setBackground(bg)
            gpu.setForeground(fg)
            gpu.fill(1, 1, width, height, " ")
            gpu.setActiveBuffer(0)
        end)
        if not success then
            lastError = "Hardware buffer clear failed"
            return false
        end
    else
        for y = 1, height do
            for x = 1, width do
                backBuffer[y][x] = {
                    char = " ",
                    fg = fg,
                    bg = bg
                }
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
        local success = pcall(function()
            gpu.setActiveBuffer(backBuffer)
            gpu.setForeground(fg)
            gpu.setBackground(bg)
            gpu.set(x, y, char)
            gpu.setActiveBuffer(0)
        end)
        if not success then
            lastError = "Hardware buffer set failed"
            return false
        end
    else
        backBuffer[y][x] = {
            char = char,
            fg = fg,
            bg = bg
        }
    end
    return true
end

function buffer.draw(force)
    if not bufferInitialized then return false end
    return safeBufferCopy()
end

-- Инициализация при загрузке
buffer.start()

return buffer
