# 🎵 Audio Silence Tools

Una coppia di tool per analizzare e rimuovere i silenzi in testa e coda dai file MP3.

## ✨ I due script

### 1. Silence-Detector.ps1 (Analisi)
- ✅ **Analizza** una cartella di MP3 (anche ricorsivamente) e trova silenzi in testa e coda
- ✅ **Copia** i file problematici in una cartella `Da_Pulire` (senza toccare gli originali)
- ✅ **Esporta CSV** con i dettagli (opzionale)
- ✅ **Log su file** per tenere traccia dell'analisi

### 2. Silence-Trimmer.ps1 (Riparazione)
- ✅ **Rimuove** i silenzi dai file in `Da_Pulire`
- ✅ **Salva** i file puliti in `Puliti` (mantenendo la struttura delle cartelle)
- ✅ **Preserva** i metadati ID3 (titolo, artista, copertina)
- ✅ **Log su file**

## 📋 Requisiti

- **Windows 10 / 11**
- **PowerShell 7+** (scarica da https://aka.ms/powershell)
- **FFmpeg** (scaricato automaticamente al primo avvio)

## 🚀 Quick start

### Fase 1: Analisi
```powershell
git clone https://github.com/fabrytoolbox/Audio-Silence-Tools.git
cd Audio-Silence-Tools
Unblock-File .\Silence-Detector.ps1
.\Silence-Detector.ps1 -InputPath "D:\Musica"

### Fase 2: Riparazione

.\Silence-Trimmer.ps1
Oppure doppio click su avvia-detector.bat o avvia-trimmer.bat.

🎯 Il flusso di lavoro
Detector: analizza la tua libreria. Copia i file problematici in Da_Pulire (mantenendo le sottocartelle).

Trimmer: prende i file da Da_Pulire, li pulisce e li salva in Puliti.

I file originali non vengono mai toccati. Zero rischi.

🎯 Casi d'uso
Pulire file live o registrazioni con silenzi iniziali/finali

Rimuovere i "buchi" di silenzio da file scaricati da fonti dubbie

Preparare una playlist per l'auto (Android Auto) senza attese infinite tra i brani

Analizzare una libreria prima di normalizzarla (con MP3_Normalizza)

⚙️ Come funziona
Il Detector usa silencedetect di FFmpeg per trovare i silenzi.

Il Trimmer usa silenceremove (con un trucco: inverti l'audio per tagliare la coda).

I metadati vengono copiati dall'originale al file riparato.

I file originali sono sempre al sicuro.

🐛 Problemi comuni
"FFmpeg non trovato"
Il tool chiede se scaricarlo. Se il download fallisce, scaricalo manualmente da https://www.gyan.dev/ffmpeg/builds/ e mettilo nella cartella dello script.

"L'audio è tagliato troppo"
Riduci la soglia di rumore (-NoiseThreshold) o aumenta la durata minima (-MinSilenceDuration).

"Voglio solo analizzare, non modificare"
Rispondi "N" alla domanda "Vuoi copiare i file in Da_Pulire?".

📜 Licenza
MIT (vedi LICENSE).

🙏 Crediti
FFmpeg per silencedetect e silenceremove

Fabry Toolbox

