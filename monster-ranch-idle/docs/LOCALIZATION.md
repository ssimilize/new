# Localization

Since update 3.2 the game is in English, Spanish (Latin America) and Portuguese (Brazil).

## How it works

- **English stays the source language in code.** Screens, toasts and server messages are
  written in English as before.
- **`src/shared/Locale/es.luau` and `pt.luau`** map every English string the game shows to its
  translation. This works like the Source column of a Roblox LocalizationTable.
- **The client's `Localize` controller** watches every text in the PlayerGui and the Workspace
  and shows the translation. Screens and systems never call it.
- **Language:** a player picks it in Settings (Auto, English, Español, Português).
  - Auto follows their Roblox language (`Player.LocaleId`).
  - The choice is saved as `profile.Settings.language`.
- **Roblox's own automatic translation** is switched off on every GUI the controller sees. Leave
  automatic text capture and translation off in the Creator Dashboard, too.

### Catalogue entries

```lua
["Egg Shop"] = "Tienda de huevos",                                   -- exact
["Unlocks at Ranch Level {1}"] = "Se desbloquea en el Nivel de Rancho {1}",  -- template
["{1} sold for {2}!"] = "¡{1} se vendió por {2}!",
```

**Templates**
- `{1}`, `{2}` … stand for the parts that change. Keep every one of them; the order can change.
- The text a placeholder matches is translated too:
  - as a whole (`Needs {1}` with `Grove Egg`);
  - or split on `, `, ` · ` and new lines.
- Two placeholders may never touch (`{1}{2}`).

**What passes through untranslated**
- Numbers in the game's formats: `1.2K`, `3h 12m`, `4.5 kg`, `45%`, `+30 XP`.
- Monster species and form names (like Pokémon names, they are the same in every language).
- Names players choose (monsters, clubs, designs), which can also be marked
  `SetAttribute("Localize", false)`.
- Anything without an entry, which stays English.

**Fit.** A translation longer than its English is drawn smaller, down to 75% of the size, so it
takes no more room than the English did. Aim for translations no more than about a third
longer than the English. Buttons and tabs should be about as long as the English.

## Adding or changing English text

1. **Build every sentence as one literal or one `string.format`.** Never glue fragments
   together: `"Unlocks at Ranch Level " .. n` can't be matched reliably as a template.
   Use `string.format("Unlocks at Ranch Level %d", n)`.
2. **Add the English to both catalogues** with its Spanish and Portuguese. Use `{n}` where the
   format has `%d` / `%s`.
3. **Run the checks:**
   ```sh
   LOCALE_REPORT=missing.txt lune run tests Locale
   ```
   `missing.txt` then lists every string still missing, and where it was found:
   - `Locale.spec` checks every name and description in `Config` and every `ctx:Fail`,
     `ctx:Notify` and `Broadcast` message in `src/server`.
   - `LocaleClient.spec` plays every screen as a new and a veteran player and checks every
     text shown.
   - Both catalogues must have the same keys, with the same placeholders.

## Style

- **Voice:** friendly and simple; many players are 9–15.
  - Spanish: neutral Latin American, `tú`, with opening `¡` and `¿`.
  - Portuguese: Brazilian, `você`.
- **Buttons and tabs:** short verbs and nouns (`Comprar`, `Recoger`, `Coletar`).
- **Capitals:** English Title Case in names becomes sentence case, except proper names
  (`Tienda de huevos`, not `Tienda De Huevos`). Keep ALL-CAPS text in caps.
- **Punctuation:** keep `·`, `×`, `★`, `✓`, `✗`, `🔒`, emoji and line breaks where the English
  has them.
- **Numbers:** keep the game's number formats unchanged (`1.2K`, `12,345`).

## Glossary

| English | Español | Português (BR) |
|---|---|---|
| Ranch / Ranch Level | Rancho / Nivel de Rancho | Rancho / Nível do Rancho |
| Coins / Gems | Monedas / Gemas | Moedas / Gemas |
| Stardust / Star Shards | Polvo estelar / Fragmentos estelares | Poeira estelar / Fragmentos estelares |
| Treats / Friendship | Golosinas / Amistad | Petiscos / Amizade |
| Contest Ribbons (Ribbons) | Listones de concurso (Listones) | Fitas de concurso (Fitas) |
| Egg / Incubator / Hatch | Huevo / Incubadora / Eclosionar | Ovo / Incubadora / Chocar |
| Pen / Barn / Coin jar | Corral / Granero / Tarro de monedas | Cercado / Celeiro / Pote de moedas |
| Collect / Claim | Recoger / Reclamar | Coletar / Resgatar |
| Buy / Sell / Upgrade / Unlock | Comprar / Vender / Mejorar / Desbloquear | Comprar / Vender / Melhorar / Desbloquear |
| Baby / Teen / Adult | Bebé / Joven / Adulto | Bebê / Jovem / Adulto |
| Lv 12 (monster level) | Nv 12 | Nv 12 |
| Common / Uncommon / Rare | Común / Poco común / Raro | Comum / Incomum / Raro |
| Epic / Legendary / Mythic | Épico / Legendario / Mítico | Épico / Lendário / Mítico |
| Normal / Golden / Rainbow | Normal / Dorado / Arcoíris | Normal / Dourado / Arco-íris |
| Ember / Tide / Sprout | Brasa / Marea / Brote | Brasa / Maré / Broto |
| Spark / Gloom / Stone | Chispa / Penumbra / Piedra | Faísca / Penumbra / Pedra |
| Light / Void | Luz / Vacío | Luz / Vazio |
| Mood / Feed / Weight | Ánimo / Alimentar / Peso | Humor / Alimentar / Peso |
| Mutation / Trait / Hidden trait | Mutación / Rasgo / Rasgo oculto | Mutação / Traço / Traço oculto |
| Gene / Gene surge / Gen (generation) | Gen / Impulso genético / Gen. | Gene / Impulso genético / Ger. |
| Expedition / Squad / Stage / Region | Expedición / Equipo / Etapa / Región | Expedição / Equipe / Fase / Região |
| Caravan | Caravana | Caravana |
| Boss / Stampede | Jefe / Estampida | Chefe / Debandada |
| Raid / Raid Egg | Incursión / Huevo de incursión | Reide / Ovo de reide |
| Arena / Rating / Defense team | Arena / Puntuación / Equipo de defensa | Arena / Pontuação / Equipe de defesa |
| Breeding / Breeding Barn | Cría / Granero de cría | Criação / Celeiro de criação |
| Trade / Trading Hub / Trade Board | Intercambio / Centro de Intercambio / Tablón de intercambios | Troca / Centro de Trocas / Mural de trocas |
| Market / Listing / Mailbox | Mercado / Oferta / Buzón | Mercado / Anúncio / Caixa de correio |
| Club / Club Wars / League | Club / Guerra de Clubes / Liga | Clube / Guerra de Clubes / Liga |
| Codex / Hall of Fame | Códice / Salón de la Fama | Códex / Hall da Fama |
| Rebirth / Rebirth Star / Heirloom | Renacer / Estrella de renacimiento / Reliquia | Renascer / Estrela de renascimento / Relíquia |
| Ranch Pass / Premium | Pase del Rancho / Premium | Passe do Rancho / Premium |
| Daily quests / Achievements / Codes | Misiones diarias / Logros / Códigos | Missões diárias / Conquistas / Códigos |
| Weather / Night | Clima / Noche | Clima / Noite |
| Decor / Pen theme | Decoración / Tema del corral | Decoração / Tema do cercado |
| Wardrobe / Accessory | Vestidor / Accesorio | Guarda-roupa / Acessório |
| Workshop / Design / Gallery / Royalties | Taller / Diseño / Galería / Regalías | Oficina / Design / Galeria / Royalties |
| Monster Contests / Showtime | Concursos de monstruos / Hora del show | Concursos de monstros / Hora do show |
| Racing / Racetrack / Racing Cup | Carreras / Hipódromo / Copa de Carreras | Corrida / Pista / Copa de Corrida |
| Leaderboards | Clasificaciones | Rankings |
| Sky Islands / Wind crystal | Islas del Cielo / Cristal de viento | Ilhas do Céu / Cristal de vento |
| Riding / Mount / Get off | Montar / Montura / Bajar | Montar / Montaria / Descer |
| Settings / Language | Ajustes / Idioma | Ajustes / Idioma |
| Robux / VIP / XP | Robux / VIP / XP | Robux / VIP / XP |

Regions, events, eggs, decor, accessories, bosses and raids are translated like any other name
(`Coral Coast` → `Costa de Coral` / `Costa de Coral`). Monster species and form names are not,
even when a raid or boss shares one (`Frost Leviathan`).
