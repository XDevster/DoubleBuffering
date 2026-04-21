# Документация

## Работа с памятью

buffer.start() - Запуск библиотеки<br>
buffer.isHealthy() - Провееряет всё ли хорошо<br>
buffer.getLastError() - если был смерть то да можно получить так ошибку<br>
buffer.clear(fg, bg) - fg цвет текста а bg цвет заднего фона<br>
buffer.set(x, y, char, fg, bg) - ставит char (символ) в координаты указаные по X Y с указаными цветами<br>
buffer.setString(x, y, str, fg, bg) - Выводит строку текста str в координатах X Y<br>

## Граф. Вывод
buffer.draw() - просто команда которая берёт всё из оперативы
buffer.stop() - выключениие 
