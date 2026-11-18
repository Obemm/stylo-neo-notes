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
- `scripts/` : une fenêtre sur le bureau (`app.ps1`) : synchro + conversion, convertir sans synchro, intégrer mes
  corrections, ouvrir la note du jour ou le journal des conversions, progression en direct ; `run.ps1` fait la même
  chose en console, pour l'automatisation.

> Aujourd'hui la conversion passe par [Claude Code](https://claude.com/claude-code). Le choix d'un autre LLM
> (API Anthropic, API compatibles OpenAI, modèles locaux par Ollama) est prévu.

## Prérequis
- Windows 10/11 avec Bluetooth LE, un **Neo smartpen M1** (les autres stylos Neo du même SDK devraient marcher,
  non essayés) et du **papier Ncode** (cahiers NeoLAB, Moleskine Smart…, ou imprimé soi-même, voir
  [Papier et impression](#papier-et-impression)) : le papier ordinaire n'est pas capté.
- Pour construire l'outil du stylo : le SDK .NET 8 (installable dans le profil, sans droits admin, voir plus bas)
  et Git.
- Pour la conversion : Python 3.11+ avec Pillow (`pip install pillow`), PowerShell 7 (`pwsh`) pour le raccourci,
  Claude Code et Obsidian.

## Papier et impression
Le stylo ne lit que le papier qui porte la trame de points **Ncode**. Deux possibilités :

- **Des carnets du commerce** marqués Ncode (NeoLAB, Moleskine Smart, Lamy Ncode) : la trame est imprimée par le
  fabricant, c'est la reconnaissance la plus fiable.
- **L'imprimer soi-même** à partir des PDF gratuits de NeoLAB : **[Ncode PDF printables](https://neolab.net/en/customer/ncode-pdf)** — papiers de base
  (Plain, Lined, Grid, Dot, Landscape), modèles (Cornell, Check List, Meeting Minutes, Log Sheet, A5…), storyboards,
  50 pages par PDF.

Conseils d'impression de NeoLAB (sur cette page) : imprimer avec **Adobe PDF Reader** sur une **imprimante laser
couleur** (toners CMJN) avec un **pilote PCL ou PostScript** ; sur une laser en niveaux de gris, prendre le modèle
**Plain** ; **imprimer d'abord quelques pages d'essai** et vérifier que le stylo les lit avant de tout imprimer —
certaines imprimantes ne savent pas imprimer le Ncode.

Ce que nous avons constaté sur ces fichiers (vérifié en novembre 2026, pas indiqué par NeoLAB) :
- **Plain est au format US Letter, pas A4** : il est rangé sous « Basic Paper (A4) », mais ses pages font
  21,6 × 27,9 cm et la trame (une image à 600 dpi) est même un peu plus large que la page. Sur du papier A4,
  imprimer en **taille réelle (100 %)** : on perd environ 6 mm à droite. Éviter « ajuster à la page », qui réduit la
  trame d'environ 3 %.
- **Jamais en mode économie ou brouillon**, et garder la pleine résolution de l'imprimante (600 dpi ou plus) : les
  points doivent rester nets.
- **Imprimer deux fois le même PDF donne les mêmes pages** : la trame est identique (fichiers identiques à l'octet
  près), donc la page A3 du second tirage a la même adresse que la page A3 du premier, et le stylo mélange ce qui
  est écrit sur les deux feuilles. Imprimer chaque PDF une seule fois, ou noter les pages déjà utilisées.
- Même une impression correcte n'est pas parfaite : sur un carnet imprimé, environ 5 % des traits contenaient un
  point mal lu (saut de plus de 12 mm). La conversion marque alors les mots douteux `[?]` au lieu de deviner.

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
peut vérifier et renouveler la session de l'agenda (`agenda.session_check`, `agenda.login`).
`agenda.list_command` donne à la fenêtre les réunions d'une date (onglet Coller). Sans agenda, les notes sont
écrites quand même, sans rattachement aux réunions.

## Utiliser
1. Stylo allumé (voyant bleu), Bluetooth du téléphone coupé (l'appli Neo garderait le stylo connecté ou le viderait).
2. Double-clic sur le raccourci : une fenêtre s'ouvre. **Synchro + conversion** (tous les carnets ou un seul) :
   synchro du stylo, puis conversion des nouvelles pages par Claude Code ; progression en direct, **Arrêter**
   interrompt. Cocher **Effacer du stylo après la synchro** vide le stylo des carnets reçus en entier (seulement une
   fois enregistrés sur le PC) : les synchros suivantes sont plus rapides. Le mot de passe du stylo ne se tape jamais dans la fenêtre : s'il n'est pas encore enregistré, une
   console s'ouvre pour le saisir (il peut alors être gardé dans le Gestionnaire d'identification Windows), puis
   la conversion reprend dans la fenêtre.
3. Relire dans Obsidian. Les doutes sont dans un encadré **« À trancher »** en tête de chaque note : corriger le
   texte, ou répondre dans la ligne du doute (« → oui », « → c'est DLQ »).
4. **Intégrer mes corrections** : doutes levés, glossaire et tags mis à jour. **Convertir sans synchro** convertit
   ce qui est déjà téléchargé ; les deux derniers boutons ouvrent la note du jour et le journal des conversions.
5. Onglet **Coller des notes ou une transcription** : des notes tapées ailleurs (chat, mail, autre application) ou
   la transcription d'une réunion. Choisir la date et la réunion (liste lue par `agenda.list_command`, ou un titre et
   une heure de début), coller, puis **Ranger dans Obsidian**. Le texte est gardé dans le dossier des transcriptions
   du coffre, puis Claude Code le range : des notes collées complètent la note du stylo de la réunion (section
   « Notes tapées », jamais reformulée) ou deviennent une note de réunion ; une transcription enrichit la note du
   stylo (décisions et actions dites mais pas écrites) ou devient une note de réunion sans manuscrit.

En session, ouvrir le dépôt dans Claude Code et dire « convertis mes notes du stylo » (`/pen-notes`).

Signes reconnus sur le papier : `M:` ou `R: titre` en haut de page = réunion ; `SL: titre` au-dessus d'une grille
= maquette de slide ; `!` en marge = important ; `?` = question ouverte ; texte encadré = décision ; mot entouré
= tag ; ☐ ou `→ Nom` = tâche.

## L'outil du stylo seul
Commandes : `sync [--mac] [--notebook 3-27-738] [--erase | --erase-received] [--no-prompt]`, `pending [--json]`, `mark-done <clé>`,
`listen [--seconds 45]`, `forget-password`, `render`, `log`, `migrate` (détail dans le [README anglais](README.md)).
Options communes : `--data-dir <chemin>` (sinon `STYLO_NEO_DATA`, sinon `Documents\StyloNeo`), `--lang en|fr` (sinon `STYLO_NEO_LANG`, sinon `en`).

## Garde-fous
- **Effacement** : le SDK efface par défaut après téléchargement ; l'outil ne le fait jamais sans qu'on le demande
  (`--erase`, `--erase-received` ou la case de la fenêtre), et alors seulement une fois les traits enregistrés sur
  le disque, jamais pour un carnet incomplet.
- **Mot de passe** : trop d'essais ratés réinitialisent le stylo ; l'outil s'arrête quand il reste 3 essais. Le mot
  de passe n'est jamais écrit sur disque ni dans un journal.
- **Votre texte** : la conversion garde une copie de ce qu'elle a écrit (hors du coffre) et travaille sur la
  différence avec votre version ; elle ne réécrit jamais ce que vous avez corrigé.
- **Mode automatique** : le raccourci lance `claude -p` verrouillé (outils de fichiers limités au coffre, aux
  données du stylo et au skill ; dépôt refusé ; seule commande permise : `pen_tool.py`).

## Licence
[GPL-3.0](LICENSE). L'outil du stylo est lié au [SDK Windows 2.0 de NeoLAB](https://github.com/NeoSmartpen/Windows-SDK2.0),
lui-même sous GPL-3.0. Projet sans lien avec NeoLAB, Obsidian ou Anthropic.
