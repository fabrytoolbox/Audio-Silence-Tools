# Silence-Detector.ps1 - v3.0
# Rileva silenzio in testa e coda degli MP3 e copia i problematici in "Da_Pulire"
# Supporto ricorsivo, auto-FFmpeg, log su file

param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,

    [string]$CsvOutput,
    [switch]$Recurse,

    [double]$NoiseThreshold = -50.0,
    [double]$MinSilenceDuration = 0.5,

    [double]$MinHeadSilence = 0.3,
    [double]$MinTailSilence = 0.3
)

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ============================================
# AUTO-FFMPEG
# ============================================
$script:workDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:ffmpegPath = Join-Path $script:workDir "ffmpeg.exe"
$script:ffprobePath = Join-Path $script:workDir "ffprobe.exe"

function Initialize-FFmpeg {
    if ((Test-Path $script:ffmpegPath) -and (Test-Path $script:ffprobePath)) { return $true }
    try {
        $sysFfmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
        if ($sysFfmpeg) {
            $script:ffmpegPath = $sysFfmpeg
            $sysFfprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source
            if ($sysFfprobe) { $script:ffprobePath = $sysFfprobe }
            return $true
        }
    } catch {}
    Write-Host "[i] FFmpeg non trovato. Download in corso..." -ForegroundColor Yellow
    $zipPath = Join-Path $env:TEMP "ffmpeg_dl.zip"
    $extractPath = Join-Path $env:TEMP "ffmpeg_temp"
    $url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Get-ChildItem -Path $extractPath -Include "ffmpeg.exe", "ffprobe.exe" -Recurse | ForEach-Object {
            Move-Item $_.FullName $script:workDir -Force
        }
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] FFmpeg installato." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[X] Errore download: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

if (-not (Initialize-FFmpeg)) { exit 1 }

# ============================================
# LOGGING
# ============================================
$script:logFile = $null
function Start-Log {
    param([string]$Folder)
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFile = Join-Path $Folder "silence_detector_$ts.log"
    @("============================================================", " SILENCE DETECTOR - LOG", "============================================================", "Data: $(Get-Date)", "") | Set-Content -Path $script:logFile -Encoding UTF8
}
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if ($script:logFile) {
        Add-Content -Path $script:logFile -Value "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -Encoding UTF8
    }
}

# ============================================
# UTILITÀ
# ============================================
function Write-Step { param([string]$Message, [string]$Color = "Cyan") Write-Host ""; Write-Host ("=" * 60) -ForegroundColor $Color; Write-Host "  $Message" -ForegroundColor $Color; Write-Host ("=" * 60) -ForegroundColor $Color }
function Write-Success { param([string]$Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message) Write-Host "  [X] $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "  [i] $Message" -ForegroundColor Yellow }

function Get-MP3Duration {
    param([string]$FilePath)
    try {
        $result = & $script:ffprobePath -v quiet -print_format json -show_format "$FilePath" 2>&1 | ConvertFrom-Json
        return [double]$result.format.duration
    } catch { return 0 }
}

function Get-SilenceInfo {
    param([string]$FilePath, [double]$NoiseThreshold, [double]$MinSilenceDuration)
    $tempLog = [System.IO.Path]::Combine($env:TEMP, "silence_$(Get-Random).log")
    $cmdLine = "`"$script:ffmpegPath`" -i `"$FilePath`" -af `"silencedetect=noise=$($NoiseThreshold)dB:d=$($MinSilenceDuration)`" -f null NUL > `"$tempLog`" 2>&1"
    $null = & cmd.exe /c $cmdLine
    $output = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
    Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($output)) { return $null }
    $starts = [regex]::Matches($output, 'silence_start:\s*([\d\.]+)') | ForEach-Object { [double]$_.Groups[1].Value }
    $ends   = [regex]::Matches($output, 'silence_end:\s*([\d\.]+)')   | ForEach-Object { [double]$_.Groups[1].Value }
    return @{ Starts = $starts; Ends = $ends }
}

# ============================================
# AVVIO E OPZIONI
# ============================================
if (-not (Test-Path $InputPath)) {
    Write-ErrorMsg "Cartella non trovata: $InputPath"
    exit 1
}

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "      SILENCE DETECTOR - FABRY TOOLBOX v3.0                 " -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Scelta ricorsiva
if (-not $PSBoundParameters.ContainsKey('Recurse')) {
    Write-Host ""
    $rec = Read-Host "Vuoi analizzare anche le SOTTOCARTELLE? (S/N, default N)"
    $useRecurse = ($rec -eq 'S' -or $rec -eq 's')
} else {
    $useRecurse = $Recurse
}

# Scelta copia file
Write-Host ""
$copia = Read-Host "Vuoi COPIARE i file problematici in una cartella 'Da_Pulire'? (S/N, default N)"
$copiaEnabled = ($copia -eq 'S' -or $copia -eq 's')

$DaPulireRoot = Join-Path $InputPath "Da_Pulire"
if ($copiaEnabled -and -not (Test-Path $DaPulireRoot)) {
    New-Item -ItemType Directory -Path $DaPulireRoot -Force | Out-Null
    Write-Info "Creata cartella: $DaPulireRoot"
}

$searchParams = @{ LiteralPath = $InputPath; Filter = "*.mp3"; File = $true }
if ($useRecurse) { $searchParams.Recurse = $true }

$mp3Files = @(Get-ChildItem @searchParams)
$total = $mp3Files.Count

if ($total -eq 0) {
    Write-ErrorMsg "Nessun MP3 trovato in: $InputPath"
    exit 1
}

Start-Log -Folder $InputPath

Write-Step "ANALISI SILENZIO" "Cyan"
Write-Info "Cartella:     $InputPath"
Write-Info "Ricorsivo:    $useRecurse"
Write-Info "Copia file:   $copiaEnabled"
Write-Info "File trovati: $total"
Write-Info "Soglia rumore: $NoiseThreshold dB"
Write-Host ""

# ============================================
# CICLO DI ANALISI
# ============================================
$results = @()
$current = 0
$withHeadSilence = 0
$withTailSilence = 0
$withBoth = 0
$copiedCount = 0

foreach ($file in $mp3Files) {
    $current++
    $percent = [math]::Round(($current / $total) * 100, 1)

    Write-Progress -Activity "Analisi silenzio..." -Status "[$current/$total] $percent% - $($file.Name)" -PercentComplete $percent
    Write-Host "[$current/$total] " -ForegroundColor Gray -NoNewline
    Write-Host $file.Name -ForegroundColor Gray -NoNewline

    $duration = Get-MP3Duration -FilePath $file.FullName
    $silence = Get-SilenceInfo -FilePath $file.FullName -NoiseThreshold $NoiseThreshold -MinSilenceDuration $MinSilenceDuration

    $headSilence = 0.0
    $tailSilence = 0.0

    if ($silence -and $silence.Starts.Count -gt 0) {
        if ($silence.Starts[0] -lt 0.1 -and $silence.Ends.Count -gt 0) {
            $headSilence = [math]::Round($silence.Ends[0], 2)
        }
        $lastEndIndex = $silence.Ends.Count - 1
        if ($lastEndIndex -ge 0 -and $duration -gt 0) {
            $lastEnd = $silence.Ends[$lastEndIndex]
            if ([math]::Abs($duration - $lastEnd) -lt 0.5) {
                $matchingStart = $silence.Starts | Where-Object { $_ -lt $lastEnd } | Select-Object -Last 1
                if ($matchingStart) { $tailSilence = [math]::Round($lastEnd - $matchingStart, 2) }
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
        Write-Log "PROBLEMATICO: $($file.Name) (Head: ${headSilence}s, Tail: ${tailSilence}s)" "WARN"
    } else {
        Write-Host " - OK" -ForegroundColor DarkGray
        Write-Log "OK: $($file.Name)" "INFO"
    }

    $results += [PSCustomObject]@{
        File          = $file.Name
        Cartella      = $file.DirectoryName
        Durata        = [math]::Round($duration, 2)
        SilenzioTesta = $headSilence
        SilenzioCoda  = $tailSilence
        Problematico  = ($hasHead -or $hasTail)
        Percorso      = $file.FullName
    }

    # Copia file problematici mantenendo la struttura
    if ($copiaEnabled -and ($hasHead -or $hasTail)) {
        $relativePath = $file.FullName.Substring($InputPath.Length).TrimStart('\')
        $destFile = Join-Path $DaPulireRoot $relativePath
        $destFolder = Split-Path $destFile -Parent
        
        if (-not (Test-Path $destFolder)) {
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
        }
        
        try {
            Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force
            Write-Log "COPIATO: $($file.Name) -> $destFile" "OK"
            $copiedCount++
        } catch {
            Write-Log "ERRORE COPIA: $($file.Name) - $($_.Exception.Message)" "ERROR"
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
if ($copiaEnabled) { Write-Host "| File copiati:          $copiedCount" -ForegroundColor Cyan }
Write-Host "+==========================================+" -ForegroundColor Green

if (-not [string]::IsNullOrWhiteSpace($CsvOutput)) {
    $results | Export-Csv -Path $CsvOutput -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Success "Report CSV salvato in: $CsvOutput"
}

$problematici = $results | Where-Object { $_.Problematico }
if ($problematici.Count -gt 0) {
    Write-Host ""
    Write-Host "FILE CHE NECESSITANO INTERVENTO:" -ForegroundColor Magenta
    foreach ($p in $problematici | Sort-Object SilenzioTesta -Descending | Select-Object -First 20) {
        $head = if ($p.SilenzioTesta -gt 0) { "testa: $($p.SilenzioTesta)s" } else { "" }
        $tail = if ($p.SilenzioCoda -gt 0) { "coda: $($p.SilenzioCoda)s" } else { "" }
        $dettagli = @($head, $tail) | Where-Object { $_ -ne "" } | Join-String -Separator " | "
        Write-Host "  - $($p.File)  [$dettagli]" -ForegroundColor Yellow
    }
    if ($problematici.Count -gt 20) { Write-Host "  ... e altri $($problematici.Count - 20) file" -ForegroundColor Gray }
}

Write-Host ""
Write-Host "Log: $script:logFile" -ForegroundColor Magenta
