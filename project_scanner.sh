#!/bin/bash

# project_scanner.sh - Скрипт для подготовки проекта к анализу LLM

set -euo pipefail

# Конфигурация по умолчанию
OUTPUT_FILE="project_analysis.md"
MAX_FILE_SIZE=50000  # Максимальный размер файла в байтах
INCLUDE_EXTENSIONS="py js ts jsx tsx php java c cpp h cs go rs rb swift kt scala sh bash zsh fish ps1 html css scss sass less vue svelte md txt yml yaml json xml toml cfg ini conf config Dockerfile docker-compose dot"

# ------------------------- ИСКЛЮЧАЕМЫЕ ДИРЕКТОРИИ --------------------------------------------------
EXCLUDE_DIRS=".git .svn node_modules .next dist build coverage .pytest_cache __pycache__ .venv venv env .env target .idea .vscode .angular diagrams"

# ------------------------- ИСКЛЮЧАЕМЫЕ ФАЙЛЫ --------------------------------------------------
EXCLUDE_FILES=".gitignore .gitkeep .DS_Store thumbs.db snapshot.jsonl collect_files.sh package-lock.json prompt.ts project_scanner.ps1 project_scanner.sh project_analysis.md README.md migration.md"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Массив для отслеживания реально исключённых файлов
declare -a ACTUALLY_EXCLUDED_FILES=()

# Функция помощи
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ] [ДИРЕКТОРИЯ]

Сканирует проект и создает файл, оптимизированный для анализа LLM.

ОПЦИИ:
    -o, --output FILE       Выходной файл (по умолчанию: $OUTPUT_FILE)
    -s, --max-size SIZE     Максимальный размер файла в байтах (по умолчанию: $MAX_FILE_SIZE)
    -e, --exclude DIRS      Дополнительные исключаемые директории
    -i, --include EXTS      Дополнительные расширения файлов
    -f, --exclude-files     Исключаемые файлы (по имени или пути)
    --exclude-file-list     Файл со списком исключаемых файлов (по одному на строку)
    -h, --help              Показать эту справку
    --tree-only             Создать только дерево проекта
    --no-content            Не включать содержимое файлов
    --stats                 Показать статистику проекта

ПРИМЕРЫ:
    $0                                    # Сканировать текущую директорию
    $0 /path/to/project                   # Сканировать указанную директорию
    $0 -o analysis.md                     # Сохранить в указанный файл
    $0 -f "prompt.md .env config.local"   # Исключить конкретные файлы
    $0 --exclude-file-list exclude.txt    # Исключить файлы из списка
    $0 --tree-only                        # Создать только структуру проекта

ИСКЛЮЧЕНИЕ ФАЙЛОВ:
    Файлы можно исключать по точному имени (например, ".gitignore") или по
    относительному пути от корня проекта (например, "src/config.local.js").

    Поддерживаются простые паттерны:
    - "*.log" исключит все .log файлы
    - "temp/*" исключит все файлы в директории temp
    - "**/node_modules" исключит node_modules в любой поддиректории

EOF
}

# Парсинг аргументов
TREE_ONLY=false
NO_CONTENT=false
SHOW_STATS=false
PROJECT_DIR="."
EXCLUDE_FILE_LIST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -s|--max-size)
            MAX_FILE_SIZE="$2"
            shift 2
            ;;
        -e|--exclude)
            EXCLUDE_DIRS="$EXCLUDE_DIRS $2"
            shift 2
            ;;
        -i|--include)
            INCLUDE_EXTENSIONS="$INCLUDE_EXTENSIONS $2"
            shift 2
            ;;
        -f|--exclude-files)
            EXCLUDE_FILES="$EXCLUDE_FILES $2"
            shift 2
            ;;
        --exclude-file-list)
            EXCLUDE_FILE_LIST="$2"
            shift 2
            ;;
        --tree-only)
            TREE_ONLY=true
            shift
            ;;
        --no-content)
            NO_CONTENT=true
            shift
            ;;
        --stats)
            SHOW_STATS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}Неизвестная опция: $1${NC}" >&2
            exit 1
            ;;
        *)
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

# Загрузка списка исключаемых файлов из файла
if [[ -n "$EXCLUDE_FILE_LIST" && -f "$EXCLUDE_FILE_LIST" ]]; then
    echo -e "${BLUE}Загружается список исключаемых файлов из: $EXCLUDE_FILE_LIST${NC}" >&2
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        EXCLUDE_FILES="$EXCLUDE_FILES $line"
    done < "$EXCLUDE_FILE_LIST"
fi

# Проверка существования директории
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo -e "${RED}Ошибка: Директория '$PROJECT_DIR' не существует${NC}" >&2
    exit 1
fi

# ========================================================================
# Построение массивов аргументов для find (вместо eval + строк)
# ========================================================================
build_find_args() {
    FIND_CMD_ARGS=()

    # Исключаемые директории: ( -name dir1 -o -name dir2 ... ) -prune -o
    local exclude_dirs_arr=()
    for dir in $EXCLUDE_DIRS; do
        dir=$(echo "$dir" | xargs)  # trim пробелов
        [[ -z "$dir" ]] && continue
        exclude_dirs_arr+=("$dir")
    done

    if [[ ${#exclude_dirs_arr[@]} -gt 0 ]]; then
        FIND_CMD_ARGS+=("(")
        local first=true
        for dir in "${exclude_dirs_arr[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                FIND_CMD_ARGS+=("-o")
            fi
            FIND_CMD_ARGS+=("-name" "$dir")
        done
        FIND_CMD_ARGS+=(")" "-prune" "-o")
    fi

    # Включаемые расширения: -type f ( -name '*.ext1' -o -name '*.ext2' ... ) -print0
    local include_exts_arr=()
    for ext in $INCLUDE_EXTENSIONS; do
        ext=$(echo "$ext" | xargs)
        [[ -z "$ext" ]] && continue
        include_exts_arr+=("$ext")
    done

    FIND_CMD_ARGS+=("-type" "f")

    if [[ ${#include_exts_arr[@]} -gt 0 ]]; then
        FIND_CMD_ARGS+=("(")
        local first=true
        for ext in "${include_exts_arr[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                FIND_CMD_ARGS+=("-o")
            fi
            FIND_CMD_ARGS+=("-name" "*.$ext")
        done
        FIND_CMD_ARGS+=(")")
    fi

    FIND_CMD_ARGS+=("-print0")
}

# Построить аргументы один раз
FIND_CMD_ARGS=()
build_find_args

# Обёртка для запуска find с правильными аргументами
run_find() {
    find "$PROJECT_DIR" "${FIND_CMD_ARGS[@]}"
}

# Вариант с -print вместо -print0 (для дерева)
run_find_print() {
    local args=()
    for arg in "${FIND_CMD_ARGS[@]}"; do
        if [[ "$arg" == "-print0" ]]; then
            args+=("-print")
        else
            args+=("$arg")
        fi
    done
    find "$PROJECT_DIR" "${args[@]}"
}

# Функция для проверки, должен ли файл быть исключен
should_exclude_file() {
    local file="$1"
    local relative_path="${file#$PROJECT_DIR/}"
    local basename_file
    basename_file=$(basename "$file")

    for pattern in $EXCLUDE_FILES; do
        pattern=$(echo "$pattern" | sed 's/^["'\'']*//;s/["'\'']*$//')

        # Проверка по точному имени файла
        if [[ "$basename_file" == "$pattern" ]]; then
            return 0
        fi

        # Проверка по относительному пути
        if [[ "$relative_path" == "$pattern" ]]; then
            return 0
        fi

        # Проверка по паттерну с wildcards
        if [[ "$basename_file" == $pattern ]]; then
            return 0
        fi

        if [[ "$relative_path" == $pattern ]]; then
            return 0
        fi

        # Проверка паттернов типа "dir/*"
        if [[ "$pattern" == *"/*" ]]; then
            local dir_pattern="${pattern%/*}"
            if [[ "$relative_path" == $dir_pattern/* ]]; then
                return 0
            fi
        fi

        # Проверка паттернов типа "**/pattern"
        if [[ "$pattern" == "**/"* ]]; then
            local file_pattern="${pattern#**/}"
            if [[ "$relative_path" == *"/$file_pattern" || "$basename_file" == "$file_pattern" ]]; then
                return 0
            fi
        fi
    done

    return 1
}

# Функция для создания дерева проекта
create_project_tree() {
    echo "## Структура проекта"
    echo

    if command -v tree >/dev/null 2>&1; then
        local tree_ignore=""
        local first=true
        for dir in $EXCLUDE_DIRS; do
            dir=$(echo "$dir" | xargs)
            [[ -z "$dir" ]] && continue
            if [[ "$first" == true ]]; then
                tree_ignore="$dir"
                first=false
            else
                tree_ignore="$tree_ignore|$dir"
            fi
        done

        echo '```'
        if [[ -n "$tree_ignore" ]]; then
            tree "$PROJECT_DIR" -I "$tree_ignore" -a --charset=ascii 2>/dev/null || {
                echo "tree завершился с ошибкой, используется упрощённый вывод:"
                run_find_print | head -50 | sed 's|^|  |'
            }
        else
            tree "$PROJECT_DIR" -a --charset=ascii 2>/dev/null || {
                run_find_print | head -50 | sed 's|^|  |'
            }
        fi
        echo '```'
    else
        echo '```'
        run_find_print | \
        while IFS= read -r file; do
            if ! should_exclude_file "$file"; then
                echo "$file"
            fi
        done | \
        head -50 | \
        sed "s|^$PROJECT_DIR/||" | \
        sort | \
        sed 's|^|  |'
        echo '```'
    fi

    echo
    echo "---"
    echo
}

# Функция для получения статистики
get_project_stats() {
    local total_files=0
    local total_lines=0
    local excluded_files=0

    echo "## Статистика проекта"
    echo

    declare -A ext_count
    declare -A ext_lines

    while IFS= read -r -d '' file; do
        if [[ -f "$file" && $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0) -le $MAX_FILE_SIZE ]]; then

            if should_exclude_file "$file"; then
                excluded_files=$((excluded_files + 1))
                continue
            fi

            ext="${file##*.}"
            [[ "$file" == *.* ]] || ext="no-extension"

            ext_count["$ext"]=$((${ext_count["$ext"]:-0} + 1))

            if [[ -r "$file" ]]; then
                lines=$(wc -l < "$file" 2>/dev/null || echo 0)
                ext_lines["$ext"]=$((${ext_lines["$ext"]:-0} + lines))
                total_lines=$((total_lines + lines))
            fi

            total_files=$((total_files + 1))
        fi
    done < <(run_find)

    echo "| Метрика | Значение |"
    echo "|---------|----------|"
    echo "| Общее количество файлов | $total_files |"
    echo "| Исключено файлов | $excluded_files |"
    echo "| Общее количество строк | $total_lines |"
    echo

    echo "### Распределение по типам файлов"
    echo
    echo "| Расширение | Файлов | Строк |"
    echo "|------------|--------|-------|"

    for ext in $(printf '%s\n' "${!ext_count[@]}" | sort); do
        printf "| %-14s | %5d | %8d |\n" "$ext" "${ext_count[$ext]}" "${ext_lines[$ext]}"
    done

    echo
    echo "---"
    echo
}

# Функция для обработки файла
process_file() {
    local file="$1"
    local relative_path="${file#$PROJECT_DIR/}"

    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

    if [[ $file_size -gt $MAX_FILE_SIZE ]]; then
        echo "### \`$relative_path\`"
        echo
        echo "> **Внимание:** Файл слишком большой ($file_size байт), показаны только первые 50 строк."
        echo
        echo '```'
        head -50 "$file" 2>/dev/null || echo "[Не удается прочитать файл]"
        # Если файл не заканчивается символом новой строки, добавляем его
        if [[ -s "$file" && -n "$(tail -c 1 "$file" 2>/dev/null)" ]]; then
            echo
        fi
        echo '```'
        echo
        echo "---"
        echo
        return
    fi

    local lang=""
    case "${file##*.}" in
        py) lang="python" ;;
        js|jsx) lang="javascript" ;;
        ts|tsx) lang="typescript" ;;
        php) lang="php" ;;
        java) lang="java" ;;
        c|h) lang="c" ;;
        cpp|cc|cxx) lang="cpp" ;;
        cs) lang="csharp" ;;
        go) lang="go" ;;
        rs) lang="rust" ;;
        rb) lang="ruby" ;;
        swift) lang="swift" ;;
        kt) lang="kotlin" ;;
        scala) lang="scala" ;;
        sh|bash) lang="bash" ;;
        html) lang="html" ;;
        css) lang="css" ;;
        scss|sass) lang="scss" ;;
        vue) lang="vue" ;;
        json) lang="json" ;;
        xml) lang="xml" ;;
        yml|yaml) lang="yaml" ;;
        md) lang="markdown" ;;
        sql) lang="sql" ;;
        Dockerfile) lang="dockerfile" ;;
        *) lang="" ;;
    esac

    echo "### \`$relative_path\`"
    echo

    if [[ -r "$file" ]]; then
        echo "\`\`\`$lang"
        cat "$file" 2>/dev/null || echo "[Не удается прочитать файл]"
        # Если файл не заканчивается символом новой строки, добавляем его,
        # чтобы закрывающие ``` оказались на отдельной строке
        if [[ -s "$file" && -n "$(tail -c 1 "$file" 2>/dev/null)" ]]; then
            echo
        fi
        echo "\`\`\`"
    else
        echo "> *Файл недоступен для чтения*"
    fi

    echo
    echo "---"
    echo
}

# Функция для формирования секции исключённых файлов в markdown
generate_excluded_section() {
    if [[ ${#ACTUALLY_EXCLUDED_FILES[@]} -gt 0 ]]; then
        echo "## Исключённые файлы"
        echo
        echo "Следующие файлы были найдены в проекте, но исключены из анализа:"
        echo
        for ef in "${ACTUALLY_EXCLUDED_FILES[@]}"; do
            echo "- \`$ef\`"
        done
        echo
        echo "---"
        echo
    fi
}

# Основная функция
main() {
    echo -e "${BLUE}Сканирование проекта: $PROJECT_DIR${NC}" >&2
    echo -e "${BLUE}Выходной файл: $OUTPUT_FILE${NC}" >&2

    if [[ -n "$EXCLUDE_FILES" ]]; then
        echo -e "${YELLOW}Паттерны исключения файлов: $EXCLUDE_FILES${NC}" >&2
    fi
    echo >&2

    # Отладка: показать команду find
    echo -e "${BLUE}Аргументы find: find \"$PROJECT_DIR\" ${FIND_CMD_ARGS[*]}${NC}" >&2
    echo >&2

    # Первый проход: собираем список реально исключённых файлов
    ACTUALLY_EXCLUDED_FILES=()
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if should_exclude_file "$file"; then
                local relative_path="${file#$PROJECT_DIR/}"
                ACTUALLY_EXCLUDED_FILES+=("$relative_path")
            fi
        fi
    done < <(run_find)

    # Создание выходного файла
    {
        echo "# Анализ проекта"
        echo
        echo "| Параметр | Значение |"
        echo "|----------|----------|"
        echo "| **Проект** | \`$(basename "$(realpath "$PROJECT_DIR")")\` |"
        echo "| **Дата сканирования** | $(date) |"
        echo "| **Сканированная директория** | \`$(realpath "$PROJECT_DIR")\` |"
        echo
        echo "---"
        echo

        # Секция реально исключённых файлов
        generate_excluded_section

        # Статистика (если запрошена)
        if [[ "$SHOW_STATS" == true ]]; then
            get_project_stats
        fi

        # Дерево проекта
        create_project_tree

        # Содержимое файлов (если не отключено)
        if [[ "$TREE_ONLY" == false && "$NO_CONTENT" == false ]]; then
            echo "## Содержимое файлов"
            echo

            local file_count=0
            local excluded_count=0

            while IFS= read -r -d '' file; do
                if [[ -f "$file" ]]; then
                    if should_exclude_file "$file"; then
                        excluded_count=$((excluded_count + 1))
                        echo -e "${RED}Исключен: ${file#$PROJECT_DIR/}${NC}" >&2
                        continue
                    fi

                    echo -e "${YELLOW}Обработка: ${file#$PROJECT_DIR/}${NC}" >&2
                    process_file "$file"
                    file_count=$((file_count + 1))
                fi
            done < <(run_find | sort -z)

            echo -e "${GREEN}Обработано файлов: $file_count${NC}" >&2
            if [[ $excluded_count -gt 0 ]]; then
                echo -e "${YELLOW}Исключено файлов: $excluded_count${NC}" >&2
            fi
        fi

    } > "$OUTPUT_FILE"

    echo -e "${GREEN}✓ Анализ завершен!${NC}" >&2
    echo -e "${GREEN}✓ Результат сохранен в: $OUTPUT_FILE${NC}" >&2

    local output_size
    output_size=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
    echo -e "${BLUE}Размер файла: $(numfmt --to=iec "$output_size" 2>/dev/null || echo "$output_size байт")${NC}" >&2

    # Сообщение о реально исключённых файлах в консоль
    if [[ ${#ACTUALLY_EXCLUDED_FILES[@]} -gt 0 ]]; then
        echo >&2
        echo -e "${YELLOW}Реально исключённые файлы (${#ACTUALLY_EXCLUDED_FILES[@]} шт.):${NC}" >&2
        for ef in "${ACTUALLY_EXCLUDED_FILES[@]}"; do
            echo -e "  ${RED}✗ $ef${NC}" >&2
        done
    fi
}

# Запуск основной функции
main
