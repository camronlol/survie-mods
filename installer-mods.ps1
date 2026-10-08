<#
.SYNOPSIS
    Installe ou met à jour les mods du modpack à partir de mods.json.

.DESCRIPTION
    - Télécharge chaque mod listé dans mods.json (Modrinth ou release GitHub).
    - Vérifie le SHA-256 quand il est indiqué, et que le fichier est bien un .jar.
    - Ignore les mods déjà présents et intacts (relancer le script ne retélécharge rien).
    - Signale les .jar en trop dans le dossier ; avec -Nettoyer, les déplace dans
      un sous-dossier "_anciens" (rien n'est supprimé).

.PARAMETER Dossier
    Dossier "mods" de l'instance. Sans ce paramètre, le script propose les
    instances Prism Launcher trouvées sur le PC.

.PARAMETER Manifeste
    Chemin ou URL du mods.json. Par défaut : le mods.json à côté du script.

.PARAMETER Nettoyer
    Déplace les .jar qui ne sont pas dans la liste vers mods\_anciens\<date>.

.EXAMPLE
    .\installer-mods.ps1
.EXAMPLE
    .\installer-mods.ps1 -Dossier "C:\...\instances\MonPack\minecraft\mods" -Nettoyer
#>
[CmdletBinding()]
param(
    [string]$Dossier,
    [string]$Manifeste = (Join-Path $PSScriptRoot 'mods.json'),
    [switch]$Nettoyer
)

$ErrorActionPreference = 'Stop'
try { Start-Transcript -Path (Join-Path $PSScriptRoot 'installation.log') -Force | Out-Null } catch {}
$ProgressPreference = 'SilentlyContinue'   # la barre de progression ralentit énormément Invoke-WebRequest sous PowerShell 5
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Ecrire([string]$texte, [string]$couleur = 'Gray') { Write-Host $texte -ForegroundColor $couleur }

function Get-Sha256([string]$chemin) {
    (Get-FileHash -Path $chemin -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Un .jar est une archive zip : il commence par "PK". Évite de garder une page d'erreur HTML.
function Test-Jar([string]$chemin) {
    $flux = [IO.File]::OpenRead($chemin)
    try {
        $octets = New-Object byte[] 2
        $lus = $flux.Read($octets, 0, 2)
        return ($lus -eq 2 -and $octets[0] -eq 0x50 -and $octets[1] -eq 0x4B)
    } finally { $flux.Dispose() }
}

# Télécharge avec curl.exe (fourni avec Windows 10/11) : rapide, suit les redirections de
# GitHub et n'a pas de limite de durée, donc les gros mods passent même sur une connexion lente.
$curlExe = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
function Telecharger([string]$url, [string]$destination) {
    if ($curlExe) {
        & $curlExe.Source -fL --retry 2 --connect-timeout 30 --progress-bar -o $destination $url
        if ($LASTEXITCODE -ne 0) { throw "téléchargement impossible (curl, code $LASTEXITCODE)" }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
    }
}

# ---------------------------------------------------------------- Manifeste
try {
    if ($Manifeste -match '^https?://') {
        Ecrire "Lecture de la liste en ligne : $Manifeste"
        $json = (Invoke-WebRequest -Uri $Manifeste -UseBasicParsing).Content
    } else {
        $json = Get-Content -LiteralPath $Manifeste -Raw -Encoding UTF8
    }
    $mods = @(($json | ConvertFrom-Json).mods)
} catch {
    Ecrire "Impossible de lire la liste des mods ($Manifeste) : $($_.Exception.Message)" Red
    exit 1
}
if ($mods.Count -eq 0) { Ecrire "La liste des mods est vide." Red; exit 1 }

# ---------------------------------------------------------------- Dossier cible
if (-not $Dossier) {
    $racinePrism = Join-Path $env:APPDATA 'PrismLauncher\instances'
    $instances = @()
    if (Test-Path -LiteralPath $racinePrism) {
        $instances = @(Get-ChildItem -LiteralPath $racinePrism -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'minecraft') })
    }
    if ($instances.Count -gt 0) {
        Ecrire "Instances Prism Launcher trouvées :" Cyan
        for ($i = 0; $i -lt $instances.Count; $i++) { Ecrire ("  [{0}] {1}" -f ($i + 1), $instances[$i].Name) }
        Ecrire "  [0] Autre dossier (saisie manuelle)"
        $choix = Read-Host "Numéro de l'instance"
        $n = 0
        if ([int]::TryParse($choix, [ref]$n) -and $n -ge 1 -and $n -le $instances.Count) {
            $Dossier = Join-Path $instances[$n - 1].FullName 'minecraft\mods'
        }
    }
    if (-not $Dossier) {
        $Dossier = (Read-Host "Chemin complet du dossier mods").Trim('"', ' ')
    }
}
if (-not $Dossier) { Ecrire "Aucun dossier indiqué." Red; exit 1 }
if (-not (Test-Path -LiteralPath $Dossier)) { New-Item -ItemType Directory -Path $Dossier | Out-Null }
$Dossier = (Resolve-Path -LiteralPath $Dossier).Path
Ecrire "`nDossier des mods : $Dossier`n" Cyan

# ---------------------------------------------------------------- Installation
$stats = [ordered]@{ 'Déjà à jour' = 0; 'Téléchargés' = 0; 'En échec' = 0 }
$echecs = New-Object System.Collections.Generic.List[string]
$total = $mods.Count
$num = 0

foreach ($mod in $mods) {
    $num++
    $nom = [string]$mod.fichier
    $cible = Join-Path $Dossier $nom
    $prefixe = "[{0,3}/{1}] " -f $num, $total
    $attendu = ([string]$mod.sha256).ToLowerInvariant()

    if (Test-Path -LiteralPath $cible) {
        $intact = if ($attendu) { (Get-Sha256 $cible) -eq $attendu } else { Test-Jar $cible }
        if ($intact) {
            $stats['Déjà à jour']++
            Ecrire "$prefixe$nom (déjà à jour)" DarkGray
            continue
        }
    }

    Ecrire "$prefixe$nom : téléchargement..." White
    $temp = "$cible.part"
    $ok = $false
    $erreur = ''
    for ($essai = 1; $essai -le 3 -and -not $ok; $essai++) {
        try {
            Telecharger $mod.url $temp
            if (-not (Test-Jar $temp)) { throw "le fichier reçu n'est pas un .jar (lien cassé ?)" }
            if ($attendu -and (Get-Sha256 $temp) -ne $attendu) { throw "empreinte SHA-256 incorrecte" }
            Move-Item -LiteralPath $temp -Destination $cible -Force
            $ok = $true
        } catch {
            $erreur = $_.Exception.Message
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
            if ($essai -lt 3) { Start-Sleep -Seconds (2 * $essai) }
        }
    }

    if ($ok) {
        $stats['Téléchargés']++
        Ecrire "$prefixe$nom" Green
    } else {
        $stats['En échec']++
        $echecs.Add("$nom : $erreur")
        Ecrire "$prefixe$nom -> ÉCHEC ($erreur)" Red
    }
}

# ---------------------------------------------------------------- Fichiers en trop
$attendus = @{}
foreach ($m in $mods) { $attendus[[string]$m.fichier] = $true }
$enTrop = @(Get-ChildItem -LiteralPath $Dossier -File -Filter '*.jar' | Where-Object { -not $attendus.ContainsKey($_.Name) })

if ($enTrop.Count -gt 0) {
    if ($Nettoyer) {
        $archive = Join-Path $Dossier ("_anciens\" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        New-Item -ItemType Directory -Path $archive -Force | Out-Null
        Ecrire "`nMods qui ne sont plus dans la liste, déplacés vers $archive :" Yellow
        foreach ($f in $enTrop) { Move-Item -LiteralPath $f.FullName -Destination $archive; Ecrire "  - $($f.Name)" Yellow }
    } else {
        Ecrire "`nMods présents mais absents de la liste (relance avec -Nettoyer pour les mettre de côté) :" Yellow
        foreach ($f in $enTrop) { Ecrire "  - $($f.Name)" Yellow }
    }
}

# ---------------------------------------------------------------- Résumé
Ecrire "`n===== Résumé =====" Cyan
foreach ($k in $stats.Keys) { Ecrire ("  {0,-14} {1}" -f $k, $stats[$k]) }

if ($echecs.Count -gt 0) {
    Ecrire "`nÉchecs :" Red
    foreach ($e in $echecs) { Ecrire "  - $e" Red }
    Ecrire "Vérifie ta connexion puis relance le script : seuls les mods manquants seront retéléchargés." Red
    Ecrire "Le détail est dans installation.log, à côté du script." Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 2
}
Ecrire "`nTout est prêt, bon jeu !" Green
try { Stop-Transcript | Out-Null } catch {}
exit 0
