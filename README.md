# ARUHAWORKS OBD-II Terminal

ESX, QBCore, QBox (qbx_core) ir standalone su ox_inventory. Target: ox_target arba qb-target. LT / EN.

## Diegimas

1. Importuok `sql/install.sql` (ESX items lentelė įtraukta). QBCore / QBox / ox_inventory - daiktai faile `items_snippet.lua`.
2. Aplanką `aw-obdsystem` įkelk į `resources`, `server.cfg` pridėk `ensure oxmysql`, `ensure ox_target` (arba `qb-target`) ir `ensure aw-obdsystem`.
3. Framework, target, policijos darbai, veiksmų kainos ir atsargumo šansai - `config.lua`.
4. Standalone režime policijos teisės suteikiamos per ACE: `add_ace group.police aw_obd.police allow`.

## Naudojimas

- Prie bet kurio automobilio target meniu atsiranda "OBD-II terminalas" (rodomas tik turint `obd_scanner` arba `obd_ghost`).
- `obd_scanner` taip pat veikia kaip naudojamas daiktas; `/obd` galima įjungti per `Config.Command`.
- `obd_ghost` - naudojamas iš inventoriaus: atidaro terminalą tiesiai neleistinu režimu (arba 5x spustelėk logotipą atidarytame terminale).
- `obd_chip` - sunaudojamas kai kuriems neleistiniems veiksmams.

## Žaidimo logika

Kiekvienas neleistinas veiksmas palieka pėdsakų ECU. Policija per "Ekspertizė" skiltį mato pėdsakų skaičių, paskutinį veiksmą ir gali pažymėti automobilį kaip vogtą. Su 3+ pėdsakais net įprastas skenavimas parodo kodą U3000. Numerių klastojimas sukuria naują švarią istoriją naujiems numeriams.
