-- Автор: XDevster
-- Версия: 1.0
-- Дата: 2025-06-16

local component = require("component")
local gpu = component.gpu
local computer = require("computer")
local event = require("event")

local buffer = {}
local backBuffer = {}
local frontBuffer = {}
local width, height = gpu.getResolution()
local changed = true

-- Инициализация буферов
local function initBuffers()
    width, height = gpu.getResolution()
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

-- Начало работы с двойной буферизацией
function buffer.start()
    initBuffers()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, width, height, " ")
end

-- Очистка буфера
function buffer.clear(fg, bg, forceRedraw)
    for y = 1, height do
        for x = 1, width do
            backBuffer[y][x] = {
                char = " ",
                fg = fg or 0xFFFFFF,
                bg = bg or 0x000000
            }
        end
    end
    if forceRedraw then
        changed = true
    end
end

-- Установка символа в буфер
function buffer.set(x, y, char, fg, bg, ignoreBounds)
    if not ignoreBounds and (x < 1 or y < 1 or x > width or y > height) then
        return false
    end
    
    if type(char) == "string" and #char > 1 then
        for i = 1, #char do
            buffer.set(x + i - 1, y, char:sub(i, i), fg, bg, ignoreBounds)
        end
        return true
    end
    
    backBuffer[y][x] = {
        char = char or " ",
        fg = fg or 0xFFFFFF,
        bg = bg or 0x000000
    }
    
    return true
end

-- Заполнение области
function buffer.fill(x, y, w, h, char, fg, bg)
    for dy = 0, h - 1 do
        for dx = 0, w - 1 do
            buffer.set(x + dx, y + dy, char, fg, bg, true)
        end
    end
end

-- Рисование прямоугольника
function buffer.rect(x, y, w, h, char, fg, bg)
    -- Верхняя и нижняя границы
    buffer.fill(x, y, w, 1, char, fg, bg)
    buffer.fill(x, y + h - 1, w, 1, char, fg, bg)
    
    -- Боковые границы
    buffer.fill(x, y + 1, 1, h - 2, char, fg, bg)
    buffer.fill(x + w - 1, y + 1, 1, h - 2, char, fg, bg)
end

-- Отрисовка изменений
function buffer.draw(force)
    if not changed and not force then
        return false
    end
    
    local anyChanged = false
    
    for y = 1, height do
        for x = 1, width do
            local back = backBuffer[y][x]
            local front = frontBuffer[y][x]
            
            if force or 
               back.char ~= front.char or 
               back.fg ~= front.fg or 
               back.bg ~= front.bg then
                
                gpu.setForeground(back.fg)
                gpu.setBackground(back.bg)
                gpu.set(x, y, back.char)
                
                frontBuffer[y][x] = {
                    char = back.char,
                    fg = back.fg,
                    bg = back.bg
                }
                
                anyChanged = true
            end
        end
    end
    
    changed = false
    return anyChanged
end

-- Получение разрешения
function buffer.getResolution()
    return width, height
end

-- Обновление разрешения
function buffer.updateResolution()
    local newWidth, newHeight = gpu.getResolution()
    if newWidth ~= width or newHeight ~= height then
        initBuffers()
        return true
    end
    return false
end

-- Частичная отрисовка (оптимизация)
function buffer.drawChanges()
    local anyChanged = false
    
    for y = 1, height do
        for x = 1, width do
            local back = backBuffer[y][x]
            local front = frontBuffer[y][x]
            
            if back.char ~= front.char or 
               back.fg ~= front.fg or 
               back.bg ~= front.bg then
                
                gpu.setForeground(back.fg)
                gpu.setBackground(back.bg)
                gpu.set(x, y, back.char)
                
                frontBuffer[y][x] = {
                    char = back.char,
                    fg = back.fg,
                    bg = back.bg
                }
                
                anyChanged = true
            end
        end
    end
    
    return anyChanged
end

-- Градиентная заливка
function buffer.gradient(x, y, w, h, colors, vertical)
    local steps = vertical and h or w
    for i = 0, steps - 1 do
        local ratio = i / (steps - 1)
        local r = math.floor(colors[1][1] + (colors[2][1] - colors[1][1]) * ratio)
        local g = math.floor(colors[1][2] + (colors[2][2] - colors[1][2]) * ratio)
        local b = math.floor(colors[1][3] + (colors[2][3] - colors[1][3]) * ratio)
        local color = r * 0x10000 + g * 0x100 + b
        
        if vertical then
            buffer.fill(x, y + i, w, 1, " ", nil, color)
        else
            buffer.fill(x + i, y, 1, h, " ", nil, color)
        end
    end
end

-- Получение информации о символе
function buffer.get(x, y)
    if x < 1 or y < 1 or x > width or y > height then
        return nil
    end
    return backBuffer[y][x].char, backBuffer[y][x].fg, backBuffer[y][x].bg
end

-- Очистка экрана (аппаратная)
function buffer.flush()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, width, height, " ")
    initBuffers()
end

return buffer
