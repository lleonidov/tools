import argparse
import json
import shutil
import sys
from pathlib import Path

from prepareMetadataTestEPF import prepare_metadata

# Эталон: пустая внешняя обработка, распакованная v8unpack 1.2.15
TEMPLATE_JSON = r'''{
  "root": true,
  "file_uuid": "26bb15d8-9467-356b-bc17-03e57bc02841",
  "uuid": "893bded9-0323-3365-82d8-9de465940094",
  "name": "ТестБазовоеСложение",
  "name2": {},
  "comment": "",
  "header": [
    [
      "1",
      ["26bb15d8-9467-356b-bc17-03e57bc02841"],
      "1",
      [
        "c3831ec8-d8d5-4f93-8a22-f9bfae07327f",
        [
          "1",
          [
            "4",
            "84b1b801-6875-3085-b358-c9e54cf2174f",
            "3a6dadb0-58e6-3051-932c-14bde4518d10",
            [
              "0",
              [
                "3",
                ["1", "0", "893bded9-0323-3365-82d8-9de465940094"],
                "\"ТестБазовоеСложение\"",
                ["0"],
                "\"\"",
                "0",
                "0",
                "00000000-0000-0000-0000-000000000000",
                "0"
              ]
            ],
            "00000000-0000-0000-0000-000000000000",
            "\"\"",
            "00000000-0000-0000-0000-000000000000"
          ],
          "4",
          ["2bcef0d1-0981-11d6-b9b8-0050bae0a95d", "0"],
          ["3daea016-69b7-4ed4-9453-127911372fe6", "0"],
          ["d5b0e5ed-256d-401c-9c36-f630cafd8a62", "0"],
          ["ec6bb5e5-b7a8-4d75-bec9-658107a699cf", "0"]
        ]
      ]
    ]
  ],
  "v8unpack": "1.2.15",
  "version": [[ ["216", "0", ["80501", "0"]] ]],
  "copyinfo": [["4", ["0"], ["0"], ["0"], ["0", "0"], ["0"]]],
  "form1": null,
  "code_info_obj": [["3", "1", "0", "\"\"", "0"]],
  "code_encoding_obj": "utf-8-sig",
  "obj_version": "805"
}'''

# Параметры
parser = argparse.ArgumentParser(description="Подготовить и собрать тестовую обработку.")
parser.add_argument("bsl", type=Path, help="Исходный файл BSL")
parser.add_argument("output", type=Path, help="Каталог сборки или путь к файлу EPF")
parser.add_argument("--prepare-only", action="store_true", help="Только подготовить файлы обработки")
args = parser.parse_args()
bsl_path = args.bsl

try:
    fields = prepare_metadata(bsl_path)
except (ValueError, OSError, UnicodeError) as error:
    sys.exit(str(error))

name = fields["Имя"]
synonym = fields["Синоним"]
comment = fields["Комментарий"]
ids = fields

# Определение путей
output_arg = args.output

epf_path = (
    output_arg
    if output_arg.suffix.lower() == ".epf"
    else output_arg / f"{name}.epf"
)

src_dir = epf_path.parent / name / "src"

# Заполнение JSON
metadata = json.loads(TEMPLATE_JSON)

metadata["file_uuid"] = ids["ObjectId"]
metadata["uuid"] = ids["UUID"]
metadata["name"] = name
metadata["name2"] = {"ru": synonym}
metadata["comment"] = comment

# Внутренние идентификаторы и свойства
header = metadata["header"][0]
header[1][0] = ids["ObjectId"]

internal = header[3][1][1]
internal[1] = ids["TypeId"]
internal[2] = ids["ValueId"]

properties = internal[3][1]
properties[1][2] = ids["UUID"]
properties[2] = json.dumps(name, ensure_ascii=False)
properties[3] = ["1", '"ru"', json.dumps(synonym, ensure_ascii=False)]
properties[4] = json.dumps(comment, ensure_ascii=False)

# Создание структуры каталогов и исходников
src_dir.mkdir(parents=True, exist_ok=True)

shutil.copyfile(
    bsl_path,
    src_dir / "ExternalDataProcessor.obj.bsl"
)

(src_dir / "ExternalDataProcessor.json").write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

if args.prepare_only:
    print(f"Подготовлено: {src_dir}")
    sys.exit(0)

# Сборка EPF
import v8unpack

# Удаляем предыдущую сборку, чтобы при ошибке не осталось старого результата
epf_path.unlink(missing_ok=True)

tmp_epf = epf_path.with_name(f".{epf_path.stem}.building.epf")
tmp_epf.unlink(missing_ok=True)

try:
    v8unpack.build(str(src_dir), str(tmp_epf))

    if not tmp_epf.is_file() or tmp_epf.stat().st_size == 0:
        raise RuntimeError("v8unpack не создал EPF")

    tmp_epf.replace(epf_path)

except Exception as error:
    tmp_epf.unlink(missing_ok=True)
    sys.exit(f"Ошибка сборки: {error}")

print(f"Собрано: {epf_path}")
