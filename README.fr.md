# stylo-neo-notes

*[English version](README.md)*

Vos notes manuscrites du **Neo smartpen M1**, transformées en **notes Obsidian**, sans l'application NeoLAB.

- `pen/` : **stylo-neo**, petit outil Windows en ligne de commande (.NET 8, SDK officiel NeoLAB) qui télécharge en
  Bluetooth LE les pages gardées dans le stylo et les range par carnet et par page : traits bruts (JSON), dessin
  vectoriel (SVG) et image (PNG). Il n'efface jamais le stylo sans qu'on le lui demande.
- `.claude/skills/pen-notes/` : un **skill Claude Code** qui lit chaque page et écrit les notes Obsidian :
  transcription fidèle (mots incertains marqués `mot[?]`), tâches, schémas redessinés en Mermaid en gardant leur
  disposition, croquis gardés en SVG, une note par réunion ou par sujet plus une note du jour, comptes rendus
  rattachés à votre agenda (facultatif), tags. En cas de doute, il l'écrit **dans la note** ; vous corrigez dans
  Obsidian, et il apprend de vos corrections (glossaire, tags) sans jamais réécrire votre texte.
- `scripts/` : un raccourci sur le bureau : *1 = charger les notes du stylo*, *2 = intégrer mes corrections*.

> Aujourd'hui la conversion passe par [Claude Code](https://claude.com/claude-code). Le choix d'un autre LLM
> (API Anthropic, API compatibles OpenAI, modèles locaux par Ollama) est prévu.

## Prérequis
- Windows 10/11 avec Bluetooth LE, un **Neo smartpen M1** (les autres stylos Neo du même SDK devraient marcher,
  non essayés) et du **papier Ncode** (cahiers NeoLAB, Moleskine Smart…) : le papier ordinaire n'est pas capté.
- Pour construire l'outil du stylo : le SDK .NET 8 (installable dans le profil, sans droits admin, voir plus bas)
  et Git.
- Pour la conversion : Python 3.11+ avec Pillow (`pip install pillow`), PowerShell 7 (`pwsh`) pour le raccourci,
  Claude Code et Obsidian.

## Installer
```powershell
git clone https://github.com/<vous>/stylo-neo-notes
cd stylo-neo-notes
powershell -ExecutionPolicy Bypass -File pen/setup.ps1     # récupère le SDK NeoLAB à une version figée
powershell -ExecutionPolicy Bypass -File pen/publish.ps1   # construit pen/dist/stylo-neo.exe (autonome)
copy config.example.toml config.toml                       # puis régler vault.path et pen.data_dir
pwsh -File scripts/install-shortcut.ps1 -Name "Notes du stylo"   # facultatif : raccourci sur le bureau
```
Sans droits admin : installer le SDK .NET 8 dans le profil avec le script officiel de Microsoft,
`dotnet-install.ps1 -Channel 8.0 -InstallDir "$env:LOCALAPPDATA\Microsoft\dotnet"`.
L'exe autonome (~90 Mo) peut aussi être construit sur un autre poste et copié.

## Régler
Tout est dans `config.toml` (voir [`config.example.toml`](config.example.toml)) : chemin du coffre et noms de ses
dossiers, langue des notes (`language = "fr"` pour des notes en français, avec les dossiers `Carnets`,
`Réunions`, `_stylo`…), fuseau horaire, dossier des données du stylo, dossier des copies de référence, agenda.
Le fichier est cherché dans `STYLO_NEO_CONFIG`, puis `config.toml` à la racine du dépôt, puis
`%APPDATA%\stylo-neo-notes\config.toml` ; `STYLO_NEO_VAULT`, `STYLO_NEO_DATA`, `STYLO_NEO_REFERENCES` priment.
`python .claude/skills/pen-notes/pen_tool.py config` affiche les valeurs retenues.

**Agenda (facultatif)** : avec `agenda.source = "mcp"`, la conversion rattache l'heure des traits à vos réunions
par des outils MCP en lecture seule que vous fournissez (`agenda.mcp_config`, `agenda.tools`), et le raccourci
peut vérifier et renouveler la session de l'agenda (`agenda.session_check`, `agenda.login`). Sans agenda, les
notes sont écrites quand même, sans rattachement aux réunions.

## Utiliser
1. Stylo allumé (voyant bleu), Bluetooth du téléphone coupé (l'appli Neo garderait le stylo connecté ou le viderait).
2. Double-clic sur le raccourci, Entrée : synchro du stylo (la première fois, il demande son mot de passe, à taper
   dans cette fenêtre seulement ; il peut être gardé dans le Gestionnaire d'identification Windows), puis
   conversion des nouvelles pages par Claude Code.
3. Relire dans Obsidian. Les doutes sont dans un encadré **« À trancher »** en tête de chaque note : corriger le
   texte, ou répondre dans la ligne du doute (« → oui », « → c'est DLQ »).
4. Double-clic, **2** : vos corrections sont intégrées (doutes levés, glossaire et tags mis à jour).

En session, ouvrir le dépôt dans Claude Code et dire « convertis mes notes du stylo » (`/pen-notes`).

Signes reconnus sur le papier : `M:` ou `R: titre` en haut de page = réunion ; `SL: titre` au-dessus d'une grille
= maquette de slide ; `!` en marge = important ; `?` = question ouverte ; texte encadré = décision ; mot entouré
= tag ; ☐ ou `→ Nom` = tâche.

## L'outil du stylo seul
Commandes : `sync [--mac] [--notebook 3-27-738] [--erase]`, `pending [--json]`, `mark-done <clé>`,
`listen [--seconds 45]`, `forget-password`, `render`, `log`, `migrate` (détail dans le [README anglais](README.md)).
Options communes : `--data-dir <chemin>` (sinon `STYLO_NEO_DATA`, sinon `Documents\StyloNeo`), `--lang en|fr` (sinon `STYLO_NEO_LANG`, sinon `en`).

## Garde-fous
- **Effacement** : le SDK efface par défaut après téléchargement ; l'outil ne le fait jamais sans `--erase`, et
  alors seulement pour les carnets dont le stylo a confirmé la fin du transfert.
- **Mot de passe** : trop d'essais ratés réinitialisent le stylo ; l'outil s'arrête quand il reste 3 essais. Le mot
  de passe n'est jamais écrit sur disque ni dans un journal.
- **Votre texte** : la conversion garde une copie de ce qu'elle a écrit (hors du coffre) et travaille sur la
  différence avec votre version ; elle ne réécrit jamais ce que vous avez corrigé.
- **Mode automatique** : le raccourci lance `claude -p` verrouillé (outils de fichiers limités au coffre, aux
  données du stylo et au skill ; dépôt refusé ; seule commande permise : `pen_tool.py`).

## Licence
[GPL-3.0](LICENSE). L'outil du stylo est lié au [SDK Windows 2.0 de NeoLAB](https://github.com/NeoSmartpen/Windows-SDK2.0),
lui-même sous GPL-3.0. Projet sans lien avec NeoLAB, Obsidian ou Anthropic.
