import argparse
import sys
import re
import uuid
from pathlib import Path
from datetime import datetime

# Шаблон для создания нового теста в формате EPF (1С:Предприятие)
TEMPLATE_CONTENT = """\
// Синоним: {name}
// Комментарий: {comment}
// Теги: {tags}
// ВерсияОбработки: 1.0.0.1
// ДатаИзменения: {date}
// UUID: {ids[UUID]}
// ObjectId: {ids[ObjectId]}
// TypeId: {ids[TypeId]}
// ValueId: {ids[ValueId]}


Перем Ожидаем;

Процедура Инициализация(КонтекстADD) Экспорт
    Ожидаем = КонтекстADD.Плагин("УтвержденияBDD");
КонецПроцедуры

Процедура ЗаполнитьНаборТеса у втов(НаборТестов, КонтекстADD) Экспорт
    // НаборТестов.НачатьГруппу("Проверка запуска");
    НаборТестов.Добавить("Тест{name}");
КонецПроцедуры

Процедура Тест{name}() Экспорт
    // Ожидаем.Что(2 + 2).Равно(4);
КонецПроцедуры
"""

def main():
    if len(sys.argv) < 2:
        sys.exit("Использование: addTestEPF.py <Имя> [unit|integration] [Теги] [Комментарий]")

    name = sys.argv[1]
    test_type = sys.argv[2].lower() if len(sys.argv) > 2 else "integration"
    tags = sys.argv[3] if len(sys.argv) > 3 else ""
    comment = sys.argv[4] if len(sys.argv) > 4 else ""
    create_test(name, test_type, tags, comment)

def create_test(name, test_type, tags="", comment=""):
    # Допускаем оба варианта написания
    if test_type == "integretion":
        test_type = "integration"

    if test_type not in ("unit", "integration"):
        sys.exit(f"Неизвестный тип теста: {test_type}")

    # Проверка имени по правилам идентификаторов 1С
    if not re.fullmatch(r"[А-Яа-яЁёA-Za-z_][А-Яа-яЁёA-Za-z_0-9]*", name):
        sys.exit(f"Недопустимое имя теста: {name}")

    # Путь относительно корня проекта
    file_path = Path("src") / "tests" / test_type / "epf" / f"{name}.bsl"

    if file_path.exists():
        sys.exit(f"Файл уже существует: {file_path}")

    # Генерация UUID
    ids = {
        "UUID": str(uuid.uuid4()),
        "ClassId": "c3831ec8-d8d5-4f93-8a22-f9bfae07327f",
        "ObjectId": str(uuid.uuid4()),
        "TypeId": str(uuid.uuid4()),
        "ValueId": str(uuid.uuid4()),
    }

    date = datetime.now().strftime("%d.%m.%Y %H:%M:%S")

    # Шаблон BSL
    content = TEMPLATE_CONTENT.format_map(locals())

    # Создание файла
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with file_path.open("x", encoding="utf-8", newline="\n") as file:
        file.write(content)

    print(f"Создан тест: {file_path}")


def run_for_type(test_type):
    parser = argparse.ArgumentParser(
        description=f"Создать шаблон {test_type}-теста для Vanessa ADD."
    )
    parser.add_argument("name", help="Имя теста")
    parser.add_argument("--tags", default="", help="Теги теста")
    parser.add_argument("--comment", default="", help="Комментарий к тесту")
    args = parser.parse_args()
    create_test(args.name, test_type, args.tags, args.comment)

if __name__ == "__main__":
    main()
