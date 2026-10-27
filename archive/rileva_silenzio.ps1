# rileva_silenzio.ps1
# Analizza gli MP3 e rileva silenzio in testa e in coda
# NON MODIFICA I FILE - solo analisi
#
# Uso base (output a video):
# .\rileva_silenzio.ps1 -InputPath "C:\Musica"
#
# Con output CSV:
# .\rileva_silenzio.ps1 -InputPath "C:\Musica" -CsvOutput "C:\report.csv"
#
# Con spostamento file problematici:
# .\rileva_silenzio.ps1 -InputPath "C:\Musica" -MoveToFolder "C:\Musica\Da_pulire"

param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,

    [string]$CsvOutput,
    [string]$MoveToFolder,

    [double]$NoiseThreshold = -50.0,
    [double]$MinSilenceDuration = 0.5,

    [double]$MinHeadSilence = 0.3,
    [double]$MinTailSilence = 0.3
)

# Forza encoding UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ============================================
# FUNZIONI DI UTILITÀ
# ============================================

function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor $Color
    Write-Host "  $Message" -ForegroundColor $Color
    Write-Host "=" * 60 -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message) Write-Host "  [X] $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "  [i] $Message" -ForegroundColor Yellow }
function Write-Warning { param([string]$Message) Write-Host "  [!] $Message" -ForegroundColor Magenta }

# ============================================
# DURATA FILE
# ============================================

function Get-MP3Duration {
    param([string]$FilePath)
    try {
        $result = ffprobe -v quiet -print_format json -show_format "$FilePath" 2>&1 | ConvertFrom-Json
        return [double]$result.format.duration
    } catch {
        return 0
    }
}

# ============================================
# ANALISI SILENZIO CON silencedetect
# ============================================

function Get-SilenceInfo {
    param(
        [string]$FilePath,
        [double]$NoiseThreshold,
        [double]$MinSilenceDuration
    )

    $tempLog = [System.IO.Path]::Combine($env:TEMP, "silence_$(Get-Random).log")

    # silencedetect scrive i risultati su stderr, quindi catturiamo tutto
    $cmdLine = "ffmpeg -i `"$FilePath`" -af `"silencedetect=noise=$($NoiseThreshold)dB:d=$($MinSilenceDuration)`" -f null NUL > `"$tempLog`" 2>&1"
    $null = & cmd.exe /c $cmdLine

    $output = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
    Remove-Item $tempLog -Force -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    # Estrai tutte le righe silence_start e silence_end
    $starts = [regex]::Matches($output, 'silence_start:\s*([\d\.]+)') | ForEach-Object { [double]$_.Groups[1].Value }
    $ends   = [regex]::Matches($output, 'silence_end:\s*([\d\.]+)')   | ForEach-Object { [double]$_.Groups[1].Value }
    $durations = [regex]::Matches($output, 'silence_duration:\s*([\d\.]+)') | ForEach-Object { [double]$_.Groups[1].Value }

    return @{
        Starts = $starts
        Ends   = $ends
        Durations = $durations
    }
}

# ============================================
# ANALISI PRINCIPALE
# ============================================

# Verifica FFmpeg
try {
    $null = & ffmpeg -version 2>&1 | Select-Object -First 1
} catch {
    Write-ErrorMsg "FFmpeg non trovato!"
    exit 1
}

if (-not (Test-Path $InputPath)) {
    Write-ErrorMsg "Cartella non trovata: $InputPath"
    exit 1
}

$mp3Files = @(Get-ChildItem -LiteralPath $InputPath -Filter "*.mp3" -File)
$total = $mp3Files.Count

if ($total -eq 0) {
    Write-ErrorMsg "Nessun MP3 trovato in: $InputPath"
    exit 1
}

Write-Step "ANALISI SILENZIO" "Cyan"
Write-Info "Cartella:     $InputPath"
Write-Info "File trovati: $total"
Write-Info "Soglia rumore: $NoiseThreshold dB"
Write-Info "Durata minima silenzio: $MinSilenceDuration s"
Write-Host ""

# Prepara spostamento se richiesto
$moveEnabled = -not [string]::IsNullOrWhiteSpace($MoveToFolder)
if ($moveEnabled -and -not (Test-Path $MoveToFolder)) {
    New-Item -ItemType Directory -Path $MoveToFolder -Force | Out-Null
    Write-Info "Creata cartella per file problematici: $MoveToFolder"
}

$results = @()
$current = 0
$withHeadSilence = 0
$withTailSilence = 0
$withBoth = 0

foreach ($file in $mp3Files) {
    $current++
    $percent = [math]::Round(($current / $total) * 100, 1)

    Write-Progress -Activity "Analisi silenzio..." `
                   -Status "[$current/$total] $percent% - $($file.Name)" `
                   -PercentComplete $percent

    Write-Host "[$current/$total] " -ForegroundColor Gray -NoNewline
    Write-Host $file.Name -ForegroundColor Gray -NoNewline

    $duration = Get-MP3Duration -FilePath $file.FullName
    $silence = Get-SilenceInfo -FilePath $file.FullName -NoiseThreshold $NoiseThreshold -MinSilenceDuration $MinSilenceDuration

    $headSilence = 0.0
    $tailSilence = 0.0

    if ($silence -and $silence.Starts.Count -gt 0) {
        # Silenzio in testa: primo silence_start vicino a 0
        if ($silence.Starts[0] -lt 0.1) {
            if ($silence.Ends.Count -gt 0) {
                $headSilence = [math]::Round($silence.Ends[0], 2)
            }
        }

        # Silenzio in coda: ultimo silence_end vicino alla durata totale
        $lastEndIndex = $silence.Ends.Count - 1
        if ($lastEndIndex -ge 0 -and $duration -gt 0) {
            $lastEnd = $silence.Ends[$lastEndIndex]
            if ([math]::Abs($duration - $lastEnd) -lt 0.5) {
                # Trova il silence_start corrispondente
                $matchingStart = $silence.Starts | Where-Object { $_ -lt $lastEnd } | Select-Object -Last 1
                if ($matchingStart) {
                    $tailSilence = [math]::Round($lastEnd - $matchingStart, 2)
                }
            }
        }
    }

    $hasHead = $headSilence -ge $MinHeadSilence
    $hasTail = $tailSilence -ge $MinTailSilence

    if ($hasHead) { $withHeadSilence++ }
    if ($hasTail) { $withTailSilence++ }
    if ($hasHead -and $hasTail) { $withBoth++ }

    $status = ""
    if ($hasHead -and $hasTail) { $status = " [TESTA+Coda]" }
    elseif ($hasHead) { $status = " [TESTA]" }
    elseif ($hasTail) { $status = " [CODA]" }

    if ($status) {
        Write-Host " - Head: ${headSilence}s | Tail: ${tailSilence}s$status" -ForegroundColor Yellow
    } else {
        Write-Host " - OK" -ForegroundColor DarkGray
    }

    $results += [PSCustomObject]@{
        File          = $file.Name
        Durata        = [math]::Round($duration, 2)
        SilenzioTesta = $headSilence
        SilenzioCoda  = $tailSilence
        Problematico  = ($hasHead -or $hasTail)
        Percorso      = $file.FullName
    }

    # Sposta file problematici se richiesto
    if ($moveEnabled -and ($hasHead -or $hasTail)) {
        $dest = Join-Path $MoveToFolder $file.Name
        if (-not (Test-Path $dest)) {
            Move-Item -LiteralPath $file.FullName -Destination $dest
        }
    }
}

Write-Progress -Activity "Analisi silenzio..." -Completed

# ============================================
# RIEPILOGO
# ============================================

Write-Host ""
Write-Host "+==========================================+" -ForegroundColor Green
Write-Host "|        ANALISI COMPLETATA                |" -ForegroundColor Green
Write-Host "+==========================================+" -ForegroundColor Green
Write-Host "| Totale file:           $total" -ForegroundColor White
Write-Host "| Con silenzio in testa: $withHeadSilence" -ForegroundColor Yellow
Write-Host "| Con silenzio in coda:  $withTailSilence" -ForegroundColor Yellow
Write-Host "| Con entrambi:          $withBoth" -ForegroundColor Yellow
Write-Host "+==========================================+" -ForegroundColor Green

# ============================================
# OUTPUT CSV
# ============================================

if (-not [string]::IsNullOrWhiteSpace($CsvOutput)) {
    $results | Export-Csv -Path $CsvOutput -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Success "Report CSV salvato in: $CsvOutput"
}

# ============================================
# DETTAGLIO FILE PROBLEMATICI
# ============================================

$problematici = $results | Where-Object { $_.Problematico }
if ($problematici.Count -gt 0) {
    Write-Host ""
    Write-Host "FILE CHE NECESSITANO INTERVENTO:" -ForegroundColor Magenta
    Write-Host ""
    foreach ($p in $problematici | Sort-Object SilenzioTesta -Descending) {
        $head = if ($p.SilenzioTesta -gt 0) { "testa: $($p.SilenzioTesta)s" } else { "" }
        $tail = if ($p.SilenzioCoda -gt 0) { "coda: $($p.SilenzioCoda)s" } else { "" }
        $dettagli = @($head, $tail) | Where-Object { $_ -ne "" } | Join-String -Separator " | "
        Write-Host "  - $($p.File)  [$dettagli]" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Analisi completata." -ForegroundColor Green