# Modpack MineColonies — Forge 1.20.1

Installe ou met à jour tous les mods du modpack en une fois, avec vérification de chaque fichier.

## Prérequis

- **Prism Launcher** avec une instance **Minecraft 1.20.1 + Forge 47.4.10**
- Windows (le script utilise PowerShell, déjà présent sur Windows 10/11)
- Mémoire conseillée dans Prism (*Modifier l'instance → Paramètres → Java*) : min **2048 Mo**, max **6144 à 8000 Mo**

## Installation

1. Sur cette page GitHub : **Code → Download ZIP**, puis extrais le dossier où tu veux.
2. Double-clique sur **`installer.bat`**.
3. Choisis ton instance Prism dans la liste (ou colle le chemin de ton dossier `mods`).
4. Attends la fin, puis lance le jeu depuis Prism.

Pour mettre à jour plus tard : retélécharge le ZIP et relance `installer.bat`. Seuls les mods nouveaux ou modifiés sont téléchargés.

> Windows peut afficher « Windows a protégé votre ordinateur » : clique sur **Informations complémentaires → Exécuter quand même**.

## Options avancées

Depuis PowerShell, dans le dossier du script :

```powershell
# Dossier précis
.\installer-mods.ps1 -Dossier "C:\Users\moi\AppData\Roaming\PrismLauncher\instances\MonPack\minecraft\mods"

# Mettre de côté les .jar qui ne sont plus dans la liste (déplacés dans mods\_anciens, rien n'est supprimé)
.\installer-mods.ps1 -Nettoyer

# Utiliser la liste en ligne plutôt que le fichier local
.\installer-mods.ps1 -Manifeste "https://raw.githubusercontent.com/camronlol/survie-mods/main/mods.json"
```

## Pour le mainteneur : modifier la liste

Chaque mod est une entrée de `mods.json` :

```json
{ "fichier": "nom-exact.jar", "url": "https://cdn.modrinth.com/...", "sha256": "..." }
```

Les mods absents de Modrinth sont hébergés dans la release **`mods`** de ce dépôt :

1. *Releases → mods → Edit*, glisse le `.jar` dans la zone des fichiers, puis *Update release*.
2. Ajoute l'entrée avec l'URL `https://github.com/camronlol/survie-mods/releases/download/mods/<nom-exact>.jar`. Vérifie que le nom du fichier dans la release correspond (GitHub remplace parfois certains caractères, comme les espaces).
3. Le `sha256` est facultatif. Sans lui, le script vérifie seulement que c'est bien un `.jar`.

Obtenir le SHA-256 d'un fichier sous Windows :

```powershell
(Get-FileHash .\le-mod.jar -Algorithm SHA256).Hash.ToLower()
```

À chaque modification de `mods.json`, une action GitHub (`.github/workflows/verifier-mods.yml`) télécharge tous les mods, vérifie les liens et les empreintes, et affiche le SHA-256 des mods qui n'en ont pas encore. Résultat dans l'onglet **Actions**.

## Problèmes connus

- **Deux versions de TerraBlender** : seule la 3.0.1.11 est dans la liste. `-Nettoyer` met l'ancienne de côté.
- **« Mémoire RAM insuffisante » dans Prism** : baisse la mémoire minimale (voir Prérequis) et ferme les autres applications.
