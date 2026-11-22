import re
import uuid
from datetime import datetime
from pathlib import Path


CLASS_ID = "c3831ec8-d8d5-4f93-8a22-f9bfae07327f"
ID_FIELDS = ("UUID", "ObjectId", "TypeId", "ValueId")
DEFAULT_VERSION = "1.0.0.1"


def prepare_metadata(bsl_path):
    """Проверить и дополнить заголовок BSL, вернуть параметры обработки."""
    name, raw, error = _read_bsl(bsl_path)
    if error: raise ValueError(error)

    # Получение всех параметров по шаблону // ИмяПараметра : Значение заканчиваются любым кодом не в комментарии
    known_fields = ("Синоним", "Комментарий", "Теги", "ВерсияОбработки", "ДатаИзменения", *ID_FIELDS)
    fields, error = _parse_fields(known_fields, raw)
    if error: raise ValueError(error)
    fields["ДатаИзменения"] = datetime.now().strftime("%d.%m.%Y %H:%M:%S")

    _fill_missing_fields(fields, known_fields)
    if not fields["Синоним"]: fields["Синоним"] = name
    if not fields["ВерсияОбработки"]: fields["ВерсияОбработки"] = DEFAULT_VERSION
    _ensure_ids(fields, ID_FIELDS)

    # Переносим параметры в начало файла в заданном порядке
    remaining = _remove_header_fields(raw, known_fields)
    updated = _insert_header_fields(raw, remaining, known_fields, fields)
    error = _write_bsl(bsl_path, raw, updated)
    if error: raise ValueError(error)

    fields["ClassId"] = CLASS_ID
    fields["Имя"] = name
    return fields


def _fill_missing_fields(fields, known_fields):
    """Добавить отсутствующие поля с пустыми значениями."""
    for key in known_fields:
        fields.setdefault(key, "")


def _ensure_ids(fields, id_fields):
    """Сохранить корректные уникальные UUID, остальные создать заново."""
    existing_ids = set()
    invalid_fields = []
    for key in id_fields:
        try:
            value = str(uuid.UUID(fields[key]))
        except (ValueError, AttributeError, TypeError):
            invalid_fields.append(key)
            continue
        if value in existing_ids:
            invalid_fields.append(key)
            continue
        existing_ids.add(value)
        fields[key] = value

    for key in invalid_fields:
        value = str(uuid.uuid4())
        while value in existing_ids:
            value = str(uuid.uuid4())
        fields[key] = value
        existing_ids.add(value)


def _remove_header_fields(raw, known_fields):
    """Удалить известные поля из начальных комментариев, сохранив остальной текст."""
    source = raw.decode("utf-8-sig")
    lines = source.splitlines(keepends=True)
    remaining = []
    in_header = True
    for line in lines:
        if in_header and line.strip() and not line.lstrip().startswith("//"):
            in_header = False
        if in_header:
            match = re.match(r"\s*//\s*([^:]+):", line)
            if match and match.group(1).strip() in known_fields:
                continue
        remaining.append(line)
    return "".join(remaining)


def _insert_header_fields(raw, remaining, known_fields, fields):
    """Добавить параметры в начало текста, сохранив BOM и формат строк."""
    source = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in source else "\r" if "\r" in source else "\n"
    header = newline.join(f"// {key}: {fields[key]}" for key in known_fields)
    bom = b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    return bom + (header + newline + remaining).encode("utf-8")


def _write_bsl(bsl_path, raw, updated):
    """Записать измененное содержимое и вернуть сообщение об ошибке, если она возникла."""
    if updated == raw:
        return None
    try:
        with open(bsl_path, "wb") as file:
            file.write(updated)
    except OSError as error:
        return f"Ошибка записи BSL {bsl_path}: {error}"
    return None



def _parse_fields(known_fields, raw):
    """Прочитать и проверить поля заголовка, вернуть поля и ошибку."""
    try:
        source = raw.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        return None, str(error)

    fields = {}
    for line in source.splitlines():
        if not line.strip():
            continue
        if not line.lstrip().startswith("//"):
            break
        match = re.match(r"\s*//\s*([^:]+):\s*(.*)", line)
        if match:
            key, value = match.group(1).strip(), match.group(2).strip()
            if key not in known_fields:
                continue
            if key in fields:
                return None, f"Параметр заголовка указан несколько раз: {key}"
            fields[key] = value

    return fields, None



def _read_bsl(bsl_path):
    """Прочитать BSL и вернуть имя, содержимое и текст ошибки."""
    bsl_path = Path(bsl_path)
    if not bsl_path.is_file() or bsl_path.suffix.lower() != ".bsl":
        return None, None, f"Не найден BSL: {bsl_path}"

    name = bsl_path.stem
    if not re.fullmatch(r"[А-Яа-яЁёA-Za-z_][А-Яа-яЁёA-Za-z_0-9]*", name):
        return None, None, f"Недопустимое имя обработки: {name}"

    try:
        return name, bsl_path.read_bytes(), None
    except OSError as error:
        return None, None, str(error)
