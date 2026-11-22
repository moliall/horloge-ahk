# Horloge AHK

Petit panneau pour Windows 11 qui remplace le centre de notifications (Win + N) par une horloge sobre, un calendrier et une saisie multifonction.

## Installation

1. Installer [AutoHotkey v2](https://www.autohotkey.com/) (`winget install AutoHotkey.AutoHotkey`)
2. Double-cliquer sur `horloge.ahk`
3. Pour le lancer au démarrage : `Win + R` → `shell:startup` → y placer un raccourci vers le script

## Utilisation

**Win + N** ouvre/ferme le panneau (Échap ou clic ailleurs pour fermer). Il s'ouvre sur l'écran où se trouve la souris.

### Panneau
- Météo du jour sous la date (`METEO_VILLE` en haut du script)
- Statut des sites listés dans `SERVERS` : pastille verte/rouge + temps de réponse, clic pour ouvrir le site

### Calendrier
- Clic sur une date : écart avec aujourd'hui
- Clic sur une deuxième date : écart entre les deux
- Clic sur le résultat : efface la sélection
- Molette : change de mois (haut = mois suivant) — clic sur le nom du mois : revient à aujourd'hui

### Saisie multifonction
Entrée sur un calcul copie le résultat. Flèches haut/bas : historique (conservé entre les redémarrages dans `%AppData%\horloge-ahk\historique.txt`).

| Fonction | Exemples |
|---|---|
| Calculs | `50k*5` · `2^10` · `sqrt(16)` · `0xFF` · `0b1010` |
| Pourcentages | `150 + 20%` · `150 - 20%` · `20% de 150` |
| HT / TTC | `150 ht` · `180 ttc` · `100 ht 5,5%` |
| Durées | `10min+5000s` · `1h30 - 45min` · `5000s en min` |
| Quantités | `2km + 300m` · `3,5 Go en Mo` · `1500 g en kg` |
| Devises | `50€ en $` · `20 usd + 10 €` · `100 chf en eur` |
| Bases | `255 en hex` · `255 en bin` · `0xFF en dec` |
| Dates | `25/12` (affiche aussi la division) · `auj + 45j` · `demain + 2 sem` · `25/12 - 01/11` |
| Minuteur | `t 25` (minutes) · `t 1h30 pâtes` · `t stop` |
| Alarme | `@18h30` · `@7h réveil` |
| Météo | `météo` (ville par défaut) · `météo Rodez` |
| Serveurs | `statut` (tous) · `ping neoheberg.fr` |
| IP | `ip` (locale + publique, copiée) |
| Bourse | `cours cac` · `cours cw8.pa` · `cours btc` |
| Mot de passe | `mdp` (16) · `mdp 24` — copié |
| Couleurs | `#FF8800` · `#f80` · `rgb(255, 136, 0)` |
| Timestamps | `ts` · `ts 1732300000` · `ts 25/12/2026 18:00` |
| Autoclic | `auto F6 5ms` · `auto F7 50ms droit x100` · `auto F8 10ms maintien` · `auto stop` |

`m` = mètre, `M` = million : pour les minutes, écrire `min`.  
Les taux de change viennent de [open.er-api.com](https://open.er-api.com) (mis à jour toutes les 6 h).

## Personnalisation
Les couleurs, la largeur, la durée du fondu, la ville de la météo et la liste des serveurs se règlent en haut de `horloge.ahk`.
