#!/usr/bin/env pwsh
#======================================================================
# project_scanner.ps1  –  версия для PowerShell 7
#
# ОПИСАНИЕ
# -------
# Этот скрипт предназначен для автоматического анализа исходного кода
# проекта. Он рекурсивно проходит по указанной директории, формирует
# отчёт в виде markdown‑похожего текста и сохраняет его в файл
# (по‑умолчанию — project_analysis.txt). В отчёте присутствуют:
#
#   • Шапка с метаданными (имя проекта, дата сканирования, путь).
#   • (Опционально) статистика: количество файлов, количество строк,
#     распределение по типам файлов.
#   • Дерево проекта – список всех файлов, прошедших фильтры.
#   • Содержимое файлов, отфильтрованных по расширениям. Если файл
#     превышает заданный размер, выводятся только первые 50 строк.
#
# Основные возможности:
#   – Исключение каталогов (ExcludeDirs) и отдельных файлов
#     (ExcludeFiles, поддерживаются шаблоны * и ?).
#   – Включение только нужных расширений (IncludeExtensions).
#   – Ограничение вывода большого файла (MaxFileSize, по умолчанию 50 KB).
#   – Параметры управления выводом:
#         -TreeOnly   – вывод только дерева проекта;
#         -NoContent  – не выводить содержимое файлов;
#         -ShowStats  – добавить блок со статистикой;
#         -Help       – вывести справку.
#   – При наличии внешней утилиты `tree` на Windows используется она
#     с параметром /I для ускоренного построения дерева.
#   – Кроссплатформенный: работает в PowerShell 7 как под Windows,
#     так и под Linux/macOS.
#
# ПАРАМЕТРЫ (см. справку, вызывая скрипт с -Help):
#   -ProjectDir <path>          Путь к сканируемому проекту (по умолчанию '.')
#   -OutputFile <file>          Файл, в который будет записан результат
#   -MaxFileSize <KB>           Максимальный размер файла, который полностью выводится
#   -ExcludeDirs <list>         Список каталогов‑исключений
#   -IncludeExtensions <list>   Список расширений, которые включать в отчёт
#   -ExcludeFiles <list>        Список файлов (или шаблонов) для исключения
#   -AdditionalExclude <list>   Доп. каталоги‑исключения (удобно задавать в командной строке)
#   -AdditionalInclude <list>   Доп. расширения‑включения
#   -TreeOnly                   Выводить только дерево проекта
#   -NoContent                  Не выводить содержимое файлов
#   -ShowStats                  Показать статистику проекта
#   -Help                       Показать эту справку
#
#======================================================================

[CmdletBinding()]
param(
    # ── Основные параметры
    [Parameter(Position = 0)][ValidateNotNullOrEmpty()][string] $ProjectDir = '.',
    [Parameter(Position = 1)][ValidateNotNullOrEmpty()][string] $OutputFile = 'project_analysis.txt',
    [int] $MaxFileSize = 50000,

    # ── Каталоги, которые нужно игнорировать
    [string[]] $ExcludeDirs = @(
        '.git', '.svn', 'node_modules', '.next', 'dist', 'build',
        'coverage', '.pytest_cache', '__pycache__', '.venv', 'venv',
        'env', '.env', 'target', '.idea', '.vscode', 'cypress'
    ),

    # ── Расширения файлов, которые **включаются** в отчёт
    [string[]] $IncludeExtensions = @(
        'py','js','ts','jsx','tsx','php','java','c','cpp','h','cs',
        'go','rs','rb','swift','kt','scala','sh','bash','zsh','fish',
        'ps1','html','css','scss','sass','less','vue','svelte','md',
        'txt','yml','yaml','json','xml','toml','cfg','ini','conf','config'
    ),

    # ── **Новый** параметр – список файлов‑исключений (можно использовать wildcards)
    [string[]] $ExcludeFiles = @('project_scanner.ps1', 'project_analysis.txt', 'package-lock.json'),

    # ── Дополнительные списки (удобно для передачи из консоли)
    [string[]] $AdditionalExclude = @(),
    [string[]] $AdditionalInclude = @(),

    # ── Флаги вывода
    [switch] $TreeOnly,
    [switch] $NoContent,
    [switch] $ShowStats,
    [switch] $Help
)

# ------------------------------------------------------------------
# 1️⃣ Объединяем дополнительные списки
# ------------------------------------------------------------------
$ExcludeDirs      += $AdditionalExclude
$IncludeExtensions+= $AdditionalInclude

# ------------------------------------------------------------------
# 2️⃣ Справка
# ------------------------------------------------------------------
function Show-Help {
    @"
Использование: .\project_scanner.ps1 [ПАРАМЕТРЫ]

Параметры:
  -ProjectDir <path>          Путь к сканируемому проекту (по умолчанию '.')
  -OutputFile <file>          Файл, в который будет записан результат
  -MaxFileSize <KB>           Максимальный размер файла, который полностью выводится
  -ExcludeDirs <list>         Список каталогов, которые следует игнорировать
  -IncludeExtensions <list>   Список расширений, которые включать в отчёт
  -ExcludeFiles <list>        **Новый** – список файлов (или шаблонов) для исключения
  -AdditionalExclude <list>   Доп. каталоги‑исключения (удобно задавать в командной строке)
  -AdditionalInclude <list>   Доп. расширения‑включения
  -TreeOnly                   Выводить только дерево проекта
  -NoContent                  Не выводить содержимое файлов
  -ShowStats                  Показать статистику проекта
  -Help                       Показать эту справку
"@ | Write-Host -ForegroundColor Green
}
if ($Help) { Show-Help; exit 0 }

# ------------------------------------------------------------------
# 3️⃣ Проверяем директорию проекта
# ------------------------------------------------------------------
if (-not (Test-Path -Path $ProjectDir -PathType Container)) {
    Write-Error "❌ Ошибка: директория '$ProjectDir' не существует."
    exit 1
}
$ProjectDir = (Resolve-Path $ProjectDir).Path

# ------------------------------------------------------------------
# 4️⃣ Вспомогательные функции
# ------------------------------------------------------------------

#region 4.1  Фильтрация путей – надёжно (каталоги)
function Test-PathExclusion {
    param(
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string[]] $ExcludeList
    )
    foreach ($ex in $ExcludeList) {
        $clean   = $ex.TrimEnd('\','/')
        $escaped = [regex]::Escape($clean)
        if ($RelativePath -match "^(?:$escaped)(?:[\\/]|$)") { return $true }
    }
    return $false
}
#endregion

#region 4.1b  Фильтрация отдельных файлов
function Test-FileExclusion {
    param(
        [Parameter(Mandatory)][string] $RelativePath,   # путь от корня проекта
        [Parameter(Mandatory)][string[]] $ExcludeList   # шаблоны/имена
    )
    foreach ($pattern in $ExcludeList) {
        # Преобразуем wildcard‑шаблон в regex
        $escaped = [regex]::Escape($pattern).Replace('\*','.*').Replace('\?','.')
        if ($RelativePath -match "^$escaped$") { return $true }
    }
    return $false
}
#endregion

#region 4.2  Карта расширений → язык
function Get-LanguageByExtension {
    param([string] $Extension)
    $map = @{
        'py'='python';'js'='javascript';'jsx'='javascript';'ts'='typescript';'tsx'='typescript';
        'php'='php';'java'='java';'c'='c';'h'='c';'cpp'='cpp';'cc'='cpp';'cxx'='cpp';
        'cs'='csharp';'go'='go';'rs'='rust';'rb'='ruby';'swift'='swift';'kt'='kotlin';
        'scala'='scala';'sh'='bash';'bash'='bash';'ps1'='powershell';'html'='html';
        'css'='css';'scss'='scss';'sass'='scss';'less'='less';'vue'='vue';
        'json'='json';'xml'='xml';'yml'='yaml';'yaml'='yaml';'md'='markdown';
        'sql'='sql'
    }
    $ext = $Extension.TrimStart('.').ToLower()
    if ($map.ContainsKey($ext)) { return $map[$ext] }
    if ($ext -eq '' -and $FileName -eq 'Dockerfile') { return 'dockerfile' }
    return ''
}
#endregion

#region 4.3  Дерево проекта (кроссплатформенный)
function New-ProjectTree {
    Write-Output "# СТРУКТУРА ПРОЕКТА"
    Write-Output ''

    # --------------------------------------------------------------
    # 1️⃣ Если есть утилита tree (Windows) – используем её с параметром /I
    # --------------------------------------------------------------
    if ($IsWindows -and (Get-Command -Name tree -ErrorAction SilentlyContinue)) {
        $ignoreList = $ExcludeDirs -join ' '
        $treeCmd = "tree `"$ProjectDir`" /A /F /I `"$ignoreList`""
        try {
            $tree = & $treeCmd 2>$null
            if ($LASTEXITCODE -eq 0 -and $tree) {
                Write-Output $tree
                Write-Output "`n---`n"
                return
            }
        } catch { }
    }

    # --------------------------------------------------------------
    # 2️⃣ Встроенный генератор дерева (работает везде)
    # --------------------------------------------------------------

    # Максимальное количество элементов в дереве – защита от слишком
    # больших проектов (можно увеличить/убрать при необходимости)
    $maxTreeItems = 2000
    $counter      = 0

    # Рекурсивный вывод
    function Write-Tree {
        param(
            [Parameter(Mandatory)][string] $CurrentPath,
            [string] $Prefix = ''
        )

        # Получаем дочерние элементы и сразу фильтруем их
        $children = Get-ChildItem -LiteralPath $CurrentPath -Force |
            Where-Object {
                $rel = $_.FullName.Substring($ProjectDir.Length).TrimStart('\','/')
                -not (Test-PathExclusion -RelativePath $rel -ExcludeList $ExcludeDirs) `
                -and -not (Test-FileExclusion -RelativePath $rel -ExcludeList $ExcludeFiles)
            } |
            Sort-Object @{Expression = {$_.PSIsContainer}; Descending = $true}, Name

        $total = $children.Count
        $i = 0

        foreach ($child in $children) {
            if ($counter -ge $maxTreeItems) { break }
            $i++
            $isLast   = $i -eq $total
            $connector = if ($isLast) {'└── '} else {'├── '}
            $line = "$Prefix$connector$($child.Name)"
            Write-Output $line
            $counter++

            if ($child.PSIsContainer) {
                $newPrefix = if ($isLast) {"$Prefix    "} else {"$Prefix│   "}
                Write-Tree -CurrentPath $child.FullName -Prefix $newPrefix
            }
        }
    }

    # Запускаем от корня проекта
    Write-Tree -CurrentPath $ProjectDir -Prefix ''

    if ($counter -ge $maxTreeItems) {
        Write-Output "`n... (вывод ограничен первыми $maxTreeItems элементами) ..."
    }

    Write-Output "`n---`n"
}
#endregion

#region 4.4  Статистика проекта
function Get-ProjectStats {
    Write-Output "# СТАТИСТИКА ПРОЕКТА"
    Write-Output ''

    $stats = @{}
    $totalFiles = 0
    $totalLines = 0

    $whereScript = {
        $rel = $_.FullName.Substring($ProjectDir.Length).TrimStart('\','/')
        -not (Test-PathExclusion -RelativePath $rel -ExcludeList $ExcludeDirs) `
        -and -not (Test-FileExclusion -RelativePath $rel -ExcludeList $ExcludeFiles)
    }

    $files = Get-ChildItem -Path $ProjectDir -Recurse -File |
        Where-Object $whereScript |
        Where-Object {
            $ext = $_.Extension.TrimStart('.')
            ($IncludeExtensions -contains $ext -or $_.Name -in @(
                'Dockerfile','docker-compose.yml','docker-compose.yaml'
            )) -and $_.Length -le $MaxFileSize
        }

    foreach ($f in $files) {
        $ext = $f.Extension.TrimStart('.')
        if (-not $stats.ContainsKey($ext)) { $stats[$ext] = [pscustomobject]@{Files=0;Lines=0} }

        $stats[$ext].Files++
        $totalFiles++

        try {
            $lineCount = (Get-Content -Path $f.FullName -ErrorAction SilentlyContinue).Count
            $stats[$ext].Lines += $lineCount
            $totalLines          += $lineCount
        } catch { }
    }

    Write-Output "Общее количество файлов: $totalFiles"
    Write-Output "Общее количество строк:  $totalLines"
    Write-Output ''
    Write-Output 'Распределение по типам файлов:'
    foreach ($kv in $stats.GetEnumerator() | Sort-Object Name) {
        $ext  = $kv.Key
        $info = $kv.Value
        Write-Output ("  {0,-15} : {1,5} файлов, {2,8} строк" -f $ext, $info.Files, $info.Lines)
    }
    Write-Output "`n---`n"
}
#endregion

#region 4.5  Обработка отдельного файла
function Process-File {
    param([System.IO.FileInfo] $File)

    $rel = $File.FullName.Substring($ProjectDir.Length).TrimStart('\','/')

    Write-Output "## $rel"
    Write-Output ''

    if ($File.Length -gt $MaxFileSize) {
        Write-Output "*Файл слишком большой ($($File.Length) байт). Выводятся первые 50 строк:*"
        Write-Output ''
        Write-Output '```'
        try {
            Get-Content -Path $File.FullName -TotalCount 50 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Output $_ }
        } catch {
            Write-Output '[Не удалось прочитать файл]'
        }
        Write-Output '```'
        Write-Output "`n---`n"
        return
    }

    $lang = Get-LanguageByExtension -Extension $File.Extension
    if ($File.Name -eq 'Dockerfile') { $lang = 'dockerfile' }

    try {
        $content = Get-Content -Path $File.FullName -Raw -ErrorAction Stop
        Write-Output "```$lang"
        Write-Output $content
        Write-Output '```'
    } catch {
        Write-Output '*Файл недоступен для чтения*'
    }
    Write-Output "`n---`n"
}
#endregion

# ------------------------------------------------------------------
# 5️⃣ Основная логика
# ------------------------------------------------------------------
function Main {
    $host.UI.WriteLine()
    Write-Host "🔎 Сканирование проекта: $ProjectDir" -ForegroundColor Cyan
    Write-Host "📁 Выходной файл: $OutputFile`n" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Общий фильтр, который будет применяться в нескольких местах
    # ------------------------------------------------------------------
    $whereScript = {
        $rel = $_.FullName.Substring($ProjectDir.Length).TrimStart('\','/')
        -not (Test-PathExclusion -RelativePath $rel -ExcludeList $ExcludeDirs) `
        -and -not (Test-FileExclusion -RelativePath $rel -ExcludeList $ExcludeFiles)
    }

    $output = @()

    # ── Шапка
    $output += '# АНАЛИЗ ПРОЕКТА'
    $output += ''
    $output += "**Проект:** $(Split-Path $ProjectDir -Leaf)"
    $output += "**Дата сканирования:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $output += "**Сканируемая директория:** $ProjectDir"
    $output += ''
    $output += '---'
    $output += ''

    # ── Статистика (по запросу)
    if ($ShowStats) { $output += Get-ProjectStats }

    # ── Дерево проекта
    $output += New-ProjectTree

    # ── Содержимое файлов
    if (-not $TreeOnly -and -not $NoContent) {
        $output += '# СОДЕРЖИМОЕ ФАЙЛОВ'
        $output += ''

        $files = Get-ChildItem -Path $ProjectDir -Recurse -File |
            Where-Object $whereScript |
            Where-Object {
                $ext = $_.Extension.TrimStart('.')
                $IncludeExtensions -contains $ext -or $_.Name -in @(
                    'Dockerfile','docker-compose.yml','docker-compose.yaml'
                )
            } |
            Sort-Object FullName

        $processed = 0
        foreach ($f in $files) {
            Write-Host "📄 Обрабатывается: $($f.Name)" -ForegroundColor Yellow
            $output += Process-File -File $f
            $processed++
        }
        Write-Host "`n✅ Обработано файлов: $processed" -ForegroundColor Green
    }

    # ── Запись результата
    $output | Out-File -FilePath $OutputFile -Encoding UTF8 -Force

    Write-Host "`n✅ Анализ завершён!" -ForegroundColor Green
    Write-Host "📄 Результат сохранён в: $OutputFile" -ForegroundColor Green

    # Размер итогового файла
    $size = (Get-Item $OutputFile).Length
    $sizeStr = if ($size -ge 1MB) {
        "{0:N2} MB" -f ($size / 1MB)
    } elseif ($size -ge 1KB) {
        "{0:N2} KB" -f ($size / 1KB)
    } else {
        "$size байт"
    }
    Write-Host "📏 Размер файла: $sizeStr" -ForegroundColor Cyan
}

# ------------------------------------------------------------------
# Запуск
# ------------------------------------------------------------------
Main
