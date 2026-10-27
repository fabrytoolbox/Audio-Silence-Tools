# Changelog

## [3.0.0] - 2025-01-27

### Added
- **Silence-Detector.ps1**: analizza gli MP3 e copia i file problematici in "Da_Pulire" (senza toccare gli originali)
  - Auto-download FFmpeg
  - Supporto ricorsivo
  - Log su file
  - Esportazione CSV opzionale
- **Silence-Trimmer.ps1**: rimuove i silenzi dai file in "Da_Pulire" e li salva in "Puliti"
  - Auto-download FFmpeg
  - Log su file
  - Preservazione dei metadati ID3
  - Struttura delle cartelle preservata

### Changed
- Flusso di lavoro "non distruttivo": i file originali non vengono mai modificati
