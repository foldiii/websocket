# Harbour WebSocket támogatás

A WebSocket kapcsolat egy közvetlen csatornát épít ki a böngésző egy lapján
megjelenő weboldal és egy web szerveren futó programszál között.

A WebSocket támogatás a `hbhttpd` webszerverre épül.

Ez a kapcsolat lehetővé teszi a közvetlen adatcserét a programszál és az oldal
JavaScript programja között. A weboldal a program képernyőjeként és
billentyűzeteként viselkedik, mint egy terminál. A felhasználói felület mindent
kihasználhat, amit a HTML lehetővé tesz, például képek, videók megjelenítése.
A program módosítása nélkül lehetőség van a megjelenés teljes áttervezésére,
különböző színvilág, logók és más nyelv alkalmazására.

Bármilyen operációs rendszeren és bármilyen hardveren lehet a felhasználói
felület, ha van WebSocket-et támogató böngésző az eszközre.

A támogatás használatához a felhasználói programhoz kell szerkeszteni a
`wbs.prg` modult.

## Objektumok a `wbs.prg` fájlban:

### WebSocket

   Feladata a kapcsolat felvétele a böngészővel, és az átvitt adatok fejlécének
   kezelése.

   * `New( oConnect, cRequest, bTrace )`
   Létrehoz egy objektumot és befejezi a kapcsolatfelvételt.

   * `Status()`
   Visszaadja a kapcsolat típusát
      - 0 - nem WebSocket kérés volt
      - 1 - érvényes WebSocket kapcsolat kiépült

   * `Socket()`
   Visszaadja a TCP socket-t

   * `ErrorCode()`
   Az utoljára elvégzett művelet hibakódját adja vissza.

   * `ErrorMode( nMod )`
   Beállítja a hibakezelés módját
      - 0 - Az `ErrorCode()` függvénnyel lehet lekérdezni a hibakódot
      - 1 - Hiba esetén `BREAK` hívása `WebSocketError` objektummal

   * `WriteRaw( cBuffer )`
   A `cBuffer` blokk kiírása a WebSocket kapcsolatra.

   * `WriteTextBlock( cBuffer )`
   A `cBuffer` text módú fejlécének elkészítése és kiírása a `WriteRaw()`
   függvénnyel.

   *  `WriteBinBlock( cBuffer )`
   A `cBuffer` bináris módú fejlécének elkészítése és kiírása a `WriteRaw()`
   függvénnyel.

   Még nem láttam böngészőt, ami támogatta volna!

   * `ReadRaw( nLength, /* @ */ cBuffer, nTimeout )`
   Adott számú byte beolvasása a `cBuffer`-be.

   * `ReadBlock( /* @ */ cBlock, nTimeout )`
   Beolvas egy WebSocket blokkot.

### WebProtocol

   A `ws.js`-ben lévő JavaScript programmal kommunikáló protokoll.
   A WebSocket objektum a szülője.

   * `New( oConnect, cRequest, bTrace )`
   Létrehoz egy objektumot és befejezi a kapcsolatfelvételt.

   * `Write( xMessage )`
   Az `xMessage` tömböt `hb_jsonEncode()` paranccsal átalakítja és elküldi
   a JavaScript programnak. Ha az `xMessage` karakteres változó, akkor
   változtatás nélkül küldi el.

   * `PageWrite( cName, hPar )`
   A `tpl` könyvtárban lévő `cName` nevű template file-t feldolgozza és
   behelyettesíti a `hPar` nevű hash tömbben lévő értékeket, majd elküldi
   a `Write()` függvénnyel.

   * `PageParse( cName, hPar )`
   A `tpl` könyvtárban lévő `cName` nevű template file-t feldolgozza
   és behelyettesíti a `hPar` nevű hash tömbben lévő értékeket, majd
   visszaadja az eredményt egy karakteres stringben.

   * `PutFields( hPar )`
   A `hPar` hash tömbben megadott `ID` - `érték` párok alapján átírja a
   weboldal adatait. Ha input vagy text típusú a HTML elem, akkor a value
   értékét cseréli le, ha egyéb, akkor az elem `innerHTML` tulajdonságát
   változtatja meg.
   ```xbase
      wbs:PutFields( { "id1" => 23, "id2" => "hello" } )
   ```

   * `InsertHTML( cId, cHTML )`
   A `cId`-ben megadott elem `innerHTML` tulajdonságát változtatja meg.

   * `SetFocus( cId )`
   A `cId`-ben megadott elemre teszi a fókuszt.

   * `SetSelection( cId, nStart, nEnd )`
   A `cId`-ben megadott input elem `nStart`-tól `nEnd`-ig tartó részének
   kijelölése.

   * `Set( cSearch, cName, cValue )`
   A `cSearch`-ban megadott CSS selector által kiválasztott elemek `cName`
   nevű tulajdonságának a `cValue` értékeket adja.

   * `SetStyle( cSearch, cName, cValue )`
   A `cSearch`-ban megadott CSS selector által kiválasztott elemek `style`
   eleme `cName` nevű tulajdonságának a `cValue` értékeket adja.

   * `GetFields( nTimeout )`
   Beolvas egy WebSocket blokkot és a megkapott értékeket egy hash tömbben adja
   vissza. Ha timeout-ra futott, akkor üres tömböt ad vissza.

   * `WebRead( nTimeout, bTimeout )`
   Felhasználói válaszra vár. A Harbour `READ` parancsának felel meg.
   Ha nincs `bTiemout` megadva, akkor az `nTimeout`-ban megadott idő letelte
   után visszatér egy üres hash többel akkor is ha nincs válasz.
   Ha `nTimeout` 0 vagy nincs megadva akkor korlátlan ideig vár.
   Ha `bTimeout` egy kódblokkot tartalmaz, akkor `nTimeout` időnként meghívja
   ezt a kódblokkot.
   Ha a kódblokk egy hash tömbbel tér vissza akkor visszadja ezt a kódblokkot.

   * `isTimeout()`
   Igazat ad vissza, ha az utolsó I/O művelet időtúllépéssel tért vissza.

   * `isError()`
   Igazat ad vissza, ha az utolsó I/O művelet során hiba történt.

   * `isCommand()`
   Igaz az értéke, ha van lenyomott gomb azonosító a visszakapott értékek
   között.

   * `Command()`
   A gombhoz rendelt parancsot adja vissza.
   ```html
   <button data-command="OK">OK</button>
   ```
   Ha a `type=submit` paraméter is meg van adva, akkor az összes input mezőt
   is elküldi, ami az aktuális formban van.
   Ha nincs form, akkor az oldalon lévő összes input mezőt elküldi.
   ```html
   <form>
     <input text id=szöveg />
     <button type="submit" data-command="OK">OK</button>
   </form>
   ```

   * `Parameter()`
   A gombhoz rendelt paramétert adja vissza.
   ```html
   <button data-command="skip" data-par="-1">Előző</button>
   ```

   * `isFiles()`
   Igaz az értéke, ha van feltöltött file.

   * `Files()`
   Egy tömböt ad vissza, ami minden feltöltött filehoz egy hash tömböt
   tartalmaz, amiben a következö adatok vannak:
   >- name = a file neve
   >- size = a file mérete
   >- data = a file tartalma base64 kódolással
   >- id   = a mező ID-je

   * `isFields()`
   Igazat ad vissza, ha van input mező.

   * `isField( cName )`
   Igazat ad vissza, ha van `cName` azonosítójú input mező.

   * `Fields()`
   Egy hash tömböt ad vissza, amely mező `ID` - `érték` párokat tartalmaz.

   * `FieldGet( cName, /* @ */ xVar, xDefault )`
   A `cName` nevű mező értékét visszaadja az `xVar` változóban, ha nincs
   ilyen változó, akkor az `xDefault` értéket adja vissza.

   * `Redirect( cLink )`
   A aktuális weboldalt kicseréli a `cLink` című oldalra.

   * `InkeyOn( cId )`
   Minden gombnyomást átküld, ha a `cId` nincs megadva, akkor az egész
   oldalon, ha `cId` meg van adva, akkor csak az adott elemen.

   * `InkeyOff( cId )`
   Kikapcsolja a gombok átküldését.
