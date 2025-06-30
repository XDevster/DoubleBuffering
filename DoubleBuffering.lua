-- Автор: XDevster
-- Версия: 1.0
-- Дата: 2025-06-16

local component = require("component")
local gpu = component.gpu
local computer = require("computer")
local event = require("event")

local buffer = {}
local width, height = gpu.getResolution()
local maxDepth = gpu.maxDepth()

-- Проверка поддержки аппаратных буферов
local hasVideoRAM = pcall(function() return gpu.allocateBuffer ~= nil end)

-- Инициализация буферов
local backBuffer, frontBuffer

local function initBuffers()
    width, height = gpu.getResolution()
    
    if hasVideoRAM then
        -- Освобождаем старые буферы
        if backBuffer then gpu.freeBuffer(backBuffer) end
        if frontBuffer then gpu.freeBuffer(frontBuffer) end
        
        -- Создаем новые буферы в видеопамяти
        backBuffer = gpu.allocateBuffer(width, height)
        frontBuffer = gpu.allocateBuffer(width, height)
        
        -- Инициализация буферов
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
        -- Программная реализация буферов
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
end

-- Основные функции API

function buffer.start()
    initBuffers()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, width, height, " ")
end

function buffer.clear(fg, bg)
    if hasVideoRAM then
        gpu.setActiveBuffer(backBuffer)
        gpu.setBackground(bg or 0x000000)
        gpu.setForeground(fg or 0xFFFFFF)
        gpu.fill(1, 1, width, height, " ")
        gpu.setActiveBuffer(0)
    else
        for y = 1, height do
            for x = 1, width do
                backBuffer[y][x] = {
                    char = " ",
                    fg = fg or 0xFFFFFF,
                    bg = bg or 0x000000
                }
            end
        end
    end
end

function buffer.set(x, y, char, fg, bg)
    if x < 1 or y < 1 or x > width or y > height then return false end
    
    if type(char) == "string" and #char > 1 then
        return buffer.setString(x, y, char, fg, bg)
    end
    
    if hasVideoRAM then
        gpu.setActiveBuffer(backBuffer)
        gpu.setForeground(fg or 0xFFFFFF)
        gpu.setBackground(bg or 0x000000)
        gpu.set(x, y, char or " ")
        gpu.setActiveBuffer(0)
    else
        backBuffer[y][x] = {
            char = char or " ",
            fg = fg or 0xFFFFFF,
            bg = bg or 0x000000
        }
    end
    
    return true
end

function buffer.setString(x, y, text, fg, bg)
    if y < 1 or y > height then return false end
    
    local len = #text
    local startX = math.max(1, x)
    local endX = math.min(width, x + len - 1)
    local substr = text:sub(startX - x + 1, endX - x + 1)
    
    if hasVideoRAM then
        gpu.setActiveBuffer(backBuffer)
        gpu.setForeground(fg or 0xFFFFFF)
        gpu.setBackground(bg or 0x000000)
        gpu.set(startX, y, substr)
        gpu.setActiveBuffer(0)
    else
        for i = startX, endX do
            backBuffer[y][i] = {
                char = substr:sub(i - startX + 1, i - startX + 1),
                fg = fg or 0xFFFFFF,
                bg = bg or 0x000000
            }
        end
    end
    
    return true
end

function buffer.fill(x, y, w, h, char, fg, bg)
    if hasVideoRAM then
        gpu.setActiveBuffer(backBuffer)
        gpu.setForeground(fg or 0xFFFFFF)
        gpu.setBackground(bg or 0x000000)
        gpu.fill(x, y, w, h, char or " ")
        gpu.setActiveBuffer(0)
    else
        char = char or " "
        for dy = 0, h - 1 do
            for dx = 0, w - 1 do
                local px, py = x + dx, y + dy
                if px >= 1 and px <= width and py >= 1 and py <= height then
                    backBuffer[py][px] = {
                        char = char,
                        fg = fg or 0xFFFFFF,
                        bg = bg or 0x000000
                    }
                end
            end
        end
    end
end

function buffer.draw(force)
    if hasVideoRAM then
        gpu.copyBuffer(backBuffer, 0, 1, 1, width, height, 1, 1)
        gpu.copyBuffer(0, frontBuffer, 1, 1, width, height, 1, 1)
    else
        local currentFg, currentBg = nil, nil
        
        for y = 1, height do
            for x = 1, width do
                local back = backBuffer[y][x]
                local front = frontBuffer[y][x]
                
                if force or back.char ~= front.char or back.fg ~= front.fg or back.bg ~= front.bg then
                    if back.fg ~= currentFg then
                        gpu.setForeground(back.fg)
                        currentFg = back.fg
                    end
                    if back.bg ~= currentBg then
                        gpu.setBackground(back.bg)
                        currentBg = back.bg
                    end
                    
                    gpu.set(x, y, back.char)
                    frontBuffer[y][x] = {char = back.char, fg = back.fg, bg = back.bg}
                end
            end
        end
    end
    return true
end

function buffer.getResolution()
    return width, height
end

function buffer.updateResolution()
    local newWidth, newHeight = gpu.getResolution()
    if newWidth ~= width or newHeight ~= height then
        initBuffers()
        return true
    end
    return false
end

function buffer.flush()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, width, height, " ")
    initBuffers()
end

return buffer
