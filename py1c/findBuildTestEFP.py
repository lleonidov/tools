import argparse
import subprocess
import sys
from pathlib import Path


DEFAULT_SOURCE = Path("src/tests")
DEFAULT_BUILD = Path("build/test")
DEFAULT_OUTPUT = Path("build/out/tests")
BUILDER = Path(__file__).resolve().with_name("buildTestEPF.py")


def main():
    parser = argparse.ArgumentParser(
        description="Найти BSL-файлы в каталогах epf и собрать тестовые обработки."
    )
    parser.add_argument(
        "source", nargs="?", type=Path, default=DEFAULT_SOURCE,
        help="Каталог поиска тестов (по умолчанию src/tests)",
    )
    parser.add_argument(
        "--build-dir", type=Path, default=DEFAULT_BUILD,
        help="Каталог подготовленных файлов (по умолчанию build/test)",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help="Каталог готовых EPF (по умолчанию build/out/tests)",
    )
    args = parser.parse_args()

    if not args.source.is_dir():
        parser.error(f"Каталог поиска не найден: {args.source}")

    files = find_test_files(args.source)
    if not files:
        print(f"BSL-файлы в каталогах epf не найдены: {args.source}")
        return 0

    failures = []
    for bsl_path in files:
        relative_dir = bsl_path.parent.relative_to(args.source)
        build_dir = args.build_dir / relative_dir
        output_dir = args.output / relative_dir
        print(f"Подготовка: {bsl_path}", flush=True)
        result = subprocess.run([
            sys.executable, str(BUILDER), str(bsl_path), str(build_dir), "--prepare-only"
        ])
        if result.returncode != 0:
            failures.append(bsl_path)
            continue

        src_dir = build_dir / bsl_path.stem / "src"
        epf_path = output_dir / f"{bsl_path.stem}.epf"
        if not build_epf(src_dir, epf_path):
            failures.append(bsl_path)

    if failures:
        print(f"Ошибок сборки: {len(failures)} из {len(files)}", file=sys.stderr)
        for path in failures:
            print(f"  {path}", file=sys.stderr)
        return 1

    print(f"Собрано обработок: {len(files)}")
    return 0


def find_test_files(source):
    """Найти BSL-файлы, непосредственно расположенные в каталогах epf."""
    return sorted(
        path for path in source.rglob("*")
        if path.is_file() and path.suffix.lower() == ".bsl" and path.parent.name == "epf"
    )


def build_epf(src_dir, epf_path):
    """Собрать EPF из подготовленных файлов и сохранить результат."""
    temporary_path = epf_path.with_name(f".{epf_path.stem}.building.epf")
    try:
        epf_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path.unlink(missing_ok=True)
        print(f"Сборка: {epf_path}", flush=True)
        result = subprocess.run([
            sys.executable, "-m", "v8unpack", "-B", str(src_dir), str(temporary_path)
        ])
        if result.returncode != 0:
            return False
        if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
            print(f"Ошибка: v8unpack не создал EPF: {epf_path}", file=sys.stderr)
            return False
        temporary_path.replace(epf_path)
        return True
    except OSError as error:
        print(f"Ошибка сборки {epf_path}: {error}", file=sys.stderr)
        return False
    finally:
        try:
            temporary_path.unlink(missing_ok=True)
        except OSError as error:
            print(f"Не удалось удалить временный файл {temporary_path}: {error}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
