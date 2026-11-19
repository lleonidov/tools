#!/usr/bin/env bash
set -euo pipefail

# Установка OneScript и входящего в его состав OPM для текущего пользователя.
# Источник: https://oscript.io/downloads/
version=2.2.1
version_url=${version//./_}
install_dir="${HOME}/.local/opt/onescript-${version}"
bin_dir="${HOME}/.local/bin"
download_url="https://oscript.io/downloads/${version_url}/scd-lin/x64"
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runner_script="$project_dir/oscript_modules/vanessa-runner/src/main.os"

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    printf 'Этот скрипт предназначен для Linux x86-64.\n' >&2
    exit 1
fi

if [[ -e "$install_dir" ]]; then
    if [[ ! -x "$install_dir/bin/oscript" || ! -x "$install_dir/bin/opm" ]]; then
        printf 'Неполная установка в %s. Проверьте каталог перед повторным запуском.\n' "$install_dir" >&2
        exit 1
    fi
    printf 'OneScript уже установлен в %s\n' "$install_dir"
else
    for command in curl unzip; do
        if ! command -v "$command" >/dev/null 2>&1; then
            printf 'Не найдена команда %s. Установите её и повторите запуск.\n' "$command" >&2
            exit 1
        fi
    done

    for command in oscript opm; do
        if [[ -e "$bin_dir/$command" || -L "$bin_dir/$command" ]]; then
            printf 'Файл уже существует: %s. Установка прервана.\n' "$bin_dir/$command" >&2
            exit 1
        fi
    done

    mkdir -p "${HOME}/.local/opt" "$bin_dir"
    temp_dir=$(mktemp -d "${HOME}/.local/opt/.onescript-install.XXXXXXXX")
    trap 'rm -rf -- "$temp_dir"' EXIT

    printf 'Скачивание OneScript %s...\n' "$version"
    curl --fail --location --show-error --output "$temp_dir/onescript.zip" "$download_url"
    mkdir "$temp_dir/unpacked"
    unzip -q "$temp_dir/onescript.zip" -d "$temp_dir/unpacked"

    if [[ ! -f "$temp_dir/unpacked/bin/oscript" || ! -f "$temp_dir/unpacked/bin/opm" ]]; then
        printf 'Неожиданное содержимое архива: bin/oscript или bin/opm не найдены.\n' >&2
        exit 1
    fi

    chmod +x "$temp_dir/unpacked/bin/oscript" "$temp_dir/unpacked/bin/opm"
    "$temp_dir/unpacked/bin/oscript" -version
    mv "$temp_dir/unpacked" "$install_dir"
fi

mkdir -p "$bin_dir"
for command in oscript opm; do
    if [[ ! -e "$bin_dir/$command" && ! -L "$bin_dir/$command" ]]; then
        printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$install_dir/bin/$command" > "$bin_dir/$command"
        chmod +x "$bin_dir/$command"
    fi
done

original_path=$PATH
export PATH="$bin_dir:$PATH"
printf 'Проверка OneScript и OPM...\n'
oscript -version
opm --version

if [[ ! -f "$runner_script" ]]; then
    printf 'Установка Vanessa Runner в каталог проекта...\n'
    (cd "$project_dir" && opm install --local vanessa-runner)
fi

if [[ ! -f "$runner_script" ]]; then
    printf 'Не найден файл Vanessa Runner: %s\n' "$runner_script" >&2
    exit 1
fi

if [[ -e "$bin_dir/vrunner" || -L "$bin_dir/vrunner" ]]; then
    printf 'Команда %s уже существует, оставляем её без изменений.\n' "$bin_dir/vrunner"
else
    opm app -n vrunner "$runner_script" "$bin_dir"
fi
vrunner --help >/dev/null

printf '\nOneScript и OPM установлены в %s\n' "$install_dir"
printf 'Vanessa Runner проверен, команды запуска находятся в %s\n' "$bin_dir"
case ":$original_path:" in
    *":$bin_dir:"*) ;;
    *) printf 'Для текущего терминала добавьте их в PATH:\n  export PATH="$HOME/.local/bin:$PATH"\n' ;;
esac
printf 'Проверка: oscript -version и opm --help\n'
