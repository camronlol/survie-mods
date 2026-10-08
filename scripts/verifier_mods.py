"""Vérifie mods.json : structure, doublons, et (avec --telecharger) les liens et SHA-256.

Pour les mods sans "sha256" (ceux de la release GitHub), affiche l'empreinte à ajouter.
"""
import hashlib
import json
import re
import sys
import urllib.request

def main() -> int:
    telecharger = "--telecharger" in sys.argv
    with open("mods.json", encoding="utf-8") as f:
        mods = json.load(f)["mods"]

    erreurs = []
    vus = set()
    for m in mods:
        nom = m.get("fichier", "")
        if not nom.endswith(".jar"):
            erreurs.append(f"{nom!r} : nom de fichier invalide")
        if nom.lower() in vus:
            erreurs.append(f"{nom} : en double")
        vus.add(nom.lower())
        if not m.get("url", "").startswith("https://"):
            erreurs.append(f"{nom} : 'url' manquante ou non https")
        if "sha256" in m and not re.fullmatch(r"[0-9a-fA-F]{64}", m["sha256"]):
            erreurs.append(f"{nom} : 'sha256' invalide")

    a_ajouter = []
    if telecharger and not erreurs:
        for m in mods:
            try:
                req = urllib.request.Request(m["url"], headers={"User-Agent": "verif-modpack"})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
            except Exception as e:  # noqa: BLE001
                erreurs.append(f"{m['fichier']} : téléchargement impossible ({e})")
                continue
            if not data.startswith(b"PK"):
                erreurs.append(f"{m['fichier']} : le lien ne renvoie pas un .jar")
                continue
            h = hashlib.sha256(data).hexdigest()
            if "sha256" not in m:
                a_ajouter.append((m["fichier"], h))
                print(f"OK  {m['fichier']} (sans sha256)")
            elif h != m["sha256"].lower():
                erreurs.append(f"{m['fichier']} : SHA-256 différent ({h})")
            else:
                print(f"OK  {m['fichier']}")

    if a_ajouter:
        print("\nEmpreintes à ajouter dans mods.json (facultatif, mais plus sûr) :")
        for nom, h in a_ajouter:
            print(f'  {nom}\n    "sha256": "{h}"')

    for e in erreurs:
        print(f"ERREUR  {e}")
    print(f"\n{len(mods)} mods, {len(erreurs)} erreur(s)")
    return 1 if erreurs else 0

if __name__ == "__main__":
    sys.exit(main())
