# Silence-Trimmer.ps1 - v3.0
# Rimuove i silenzi in testa e coda dagli MP3 nella cartella "Da_Pulire"
# Salva i file puliti in "Puliti" mantenendo la struttura delle cartelle

param(
    [string]$InputPath
)

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

Add-Type -AssemblyName System.Windows.Forms
if (-not (Initialize-FFmpeg)) { exit 1 }

# ============================================
# LOGGING
# ============================================
$script:logFile = $null
function Start-Log {
    param([string]$Folder)
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFile = Join-Path $Folder "silence_trimmer_$ts.log"
    @("============================================================", " SILENCE TRIMMER - LOG", "============================================================", "Data: $(Get-Date)", "") | Set-Content -Path $script:logFile -Encoding UTF8
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

# ============================================
# TRIM SINGOLO FILE
# ============================================
function Trim-SingleFile {
    param([string]$InputFile, [string]$OutputFile, [double]$NoiseThreshold = -50.0, [double]$MinSilenceDuration = 0.3)

    $filter = "silenceremove=start_periods=1:start_threshold=${NoiseThreshold}dB:start_silence=$($MinSilenceDuration):detection=peak,areverse,silenceremove=start_periods=1:start_threshold=${NoiseThreshold}dB:start_silence=$($MinSilenceDuration):detection=peak,areverse"

    $ffmpegArgs = @(
        "-y",
        "-i", $InputFile,
        "-af", $filter,
        "-map_metadata", "0",
        "-c:a", "libmp3lame",
        "-b:a", "320k",
        $OutputFile
    )

    try {
        $null = & $script:ffmpegPath @ffmpegArgs 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

# ============================================
# MODALITÀ INTERATTIVA
# ============================================
function Start-Interactive {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "      SILENCE TRIMMER - FABRY TOOLBOX v3.0                  " -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta

    Write-Step "STEP 1: Cartella Sorgente" "Cyan"
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Seleziona la cartella radice (deve contenere 'Da_Pulire')"
    if ($dlg.ShowDialog() -ne "OK") { return }
    $script:InputPath = $dlg.SelectedPath
    Write-Success "Cartella: $($script:InputPath)"

    $daPulireRoot = Join-Path $script:InputPath "Da_Pulire"
    $pulitiRoot = Join-Path $script:InputPath "Puliti"

    if (-not (Test-Path $daPulireRoot)) {
        Write-ErrorMsg "Cartella 'Da_Pulire' non trovata in $($script:InputPath)."
        return
    }

    Write-Step "STEP 2: Ricerca file" "Cyan"
    Write-Info "Cerco file in: $daPulireRoot"
    $mp3Files = @(Get-ChildItem -Path $daPulireRoot -Filter "*.mp3" -File -Recurse)

    if ($mp3Files.Count -eq 0) {
        Write-ErrorMsg "Nessun file da elaborare in 'Da_Pulire'."
        return
    }
    Write-Success "Trovati $($mp3Files.Count) file da elaborare"

    Write-Step "STEP 3: Output" "Cyan"
    Write-Info "I file puliti verranno salvati in: $pulitiRoot (mantenendo la struttura)"

    $conf = Read-Host "Confermi l'avvio? (S/N)"
    if ($conf -ne 'S' -and $conf -ne 's') { return }

    Write-Step "STEP 4: Avvio" "Green"
    Start-Log -Folder $script:InputPath

    $success = 0; $failed = 0; $current = 0
    foreach ($file in $mp3Files) {
        $current++
        $percent = [math]::Round(($current / $mp3Files.Count) * 100, 1)
        Write-Progress -Activity "Rimozione silenzi..." -Status "[$current/$($mp3Files.Count)] $percent% - $($file.Name)" -PercentComplete $percent

        # Calcola percorso di output mantenendo la struttura
        $relativePath = $file.FullName.Substring($daPulireRoot.Length).TrimStart('\')
        $outputFile = Join-Path $pulitiRoot $relativePath
        $outputDir = Split-Path $outputFile -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        Write-Host "[$current/$($mp3Files.Count)] $($file.Name)" -ForegroundColor Gray -NoNewline

        if (Trim-SingleFile -InputFile $file.FullName -OutputFile $outputFile) {
            Write-Host " [OK]" -ForegroundColor Green
            Write-Log "OK: $($file.Name) -> $outputFile" "OK"
            $success++
        } else {
            Write-Host " [X] FALLITO" -ForegroundColor Red
            Write-Log "FALLITO: $($file.Name)" "ERROR"
            $failed++
        }
    }
    Write-Progress -Activity "Rimozione silenzi..." -Completed

    Write-Host ""
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "|        OPERAZIONE COMPLETATA             |" -ForegroundColor Green
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host "| File:      $($mp3Files.Count)" -ForegroundColor White
    Write-Host "| Successi:  $success" -ForegroundColor Green
    if ($failed -gt 0) { Write-Host "| Falliti:   $failed" -ForegroundColor Red }
    Write-Host "+==========================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "I file puliti sono in: $pulitiRoot" -ForegroundColor Cyan
    Write-Host "Log: $($script:logFile)" -ForegroundColor Magenta

    $apri = Read-Host "`nVuoi aprire la cartella 'Puliti'? (S/N)"
    if ($apri -eq 'S' -or $apri -eq 's') {
        Invoke-Item $pulitiRoot
    }
}

# ============================================
# ESECUZIONE
# ============================================
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Start-Interactive
} else {
    # Modalità CLI
    $daPulireRoot = Join-Path $InputPath "Da_Pulire"
    $pulitiRoot = Join-Path $InputPath "Puliti"
    Start-Log -Folder $InputPath
    
    if (-not (Test-Path $daPulireRoot)) {
        Write-Host "[X] Cartella 'Da_Pulire' non trovata in $InputPath" -ForegroundColor Red
        exit 1
    }
    
    $mp3Files = @(Get-ChildItem -Path $daPulireRoot -Filter "*.mp3" -File -Recurse)
    $current = 0; $success = 0; $failed = 0
    foreach ($file in $mp3Files) {
        $current++
        $relativePath = $file.FullName.Substring($daPulireRoot.Length).TrimStart('\')
        $outputFile = Join-Path $pulitiRoot $relativePath
        $outputDir = Split-Path $outputFile -Parent
        if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
        
        Write-Host "[$current/$($mp3Files.Count)] $($file.Name)" -ForegroundColor Gray -NoNewline
        if (Trim-SingleFile -InputFile $file.FullName -OutputFile $outputFile) {
            Write-Host " [OK]" -ForegroundColor Green; $success++
            Write-Log "OK: $($file.Name)" "OK"
        } else {
            Write-Host " [X]" -ForegroundColor Red; $failed++
            Write-Log "FALLITO: $($file.Name)" "ERROR"
        }
    }
    Write-Host "`nCompletato: $success OK, $failed falliti." -ForegroundColor Green
    Write-Host "File puliti in: $pulitiRoot" -ForegroundColor Cyan
    Write-Host "Log: $script:logFile" -ForegroundColor Magenta
}