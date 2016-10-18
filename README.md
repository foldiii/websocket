# Harbour websocket támogatás

A websocket kapcsolat egy közvetlen csatornát épít ki a böngésző egy lapján megjelenő weboldal és egy programszál között.

Ez a kapcsolat lehetővé teszi a közvetlen adatcserét a programszál és az oldal JavaScript programja között.
A weboldal a program képernyőjeként és billentyűzeteként viselkedik, mint egy terminál.
A felhasználói felület mindent kihasználhat amit a HTML lehetővé tesz.
Például képek, videók megjelenítése. A program módosítása nélkül lehetőség van a megjelenés teljes áttervezésére.
Különböző színvilág, logók és más nyelv alkalmazására

Bármilyen operáciosrendszeren és bármilyen hardveren lehet a felhasználói felület ha van websoket-t támogató böngésző az eszközre.

A websocket támogatás a hbhttpd webszerverre épül.

## Objektumok a wbs.prg fájlban:

### WebSocket
   Feladata a kapcsolat felvétele a böngészővel, és az átvitt adatok fejlécének kezelése.
     
   * New( oConnect, cRequest, bTrace )
   Létrehoz egy objektumot és befejezi a kapcsolatfelvételt.

   * Status()
   Visszaadja a kapcsolat típusát
      - 0 - nem websocek kérés volt
      - 1 - érvényes websocket kapcsolat kiépült

   *   Socket()
   Visszaadja a TCP socket-t 

   *    ErrorCode()
   Az utoljára elvégzett művelet hibakódját adja vissza

   *    ErrorMode( nMod )
   Beállítja a hibakezelés módját
      -  0 - Az ErrorCode fügvénnyel lehet lekérdezni a hibakódot
      -  1 - Hiba esetén "break" hívása WebSocketError objektummal

   *   WriteRaw( cBuffer )
   A cBuffer blokk kiírása a websocket kapcsolatra

   *    WriteTextBlock( cBuffer )
   A cBuffer text módu fejlécének elkézítése és kiírása a WriteRaw fügvénnyel

   *    WriteBinBlock( cBuffer )
   A cBuffer bináris módu fejlécének elkézítése és kiírása a WriteRaw fügvénnyel.
       
   Még nem láttam böngészőt ami támogatta volna!!!

   *    ReadRaw( nLength,/* @ */ cBuffer, nTimeout )
   Adott számú byte beolvasása a CBuffer-be

   *    ReadBlock(/* @ */ cBlock, nTimeout )
   Beolvas egy websocket blokkot.

### WebProtocol
   A ws.js-ben lév javascript programmal kommunikáló protokol.
   A WebSocket objektum a szúlője.
    
   * New( oConnect, cRequest, bTrace )
   Létrehoz egy objektumot és befejezi a kapcsolatfelvételt.

   * Write( xMessage )
   Az xMessage tömböt hb_jsonEncode parancsal átalakítja és elküldi a javascript prógramnak.
   Ha az xMessage karakteres változó akkor változtatás nélkűl elküldi.
 
   * PageWrite( cName, hPar )
   A tpl könyvtárban lévő cName nevű template file-t feldolgozza és behelyettesíti a hPar nevű hash tömbben
   lévő értékeket. Majd elküldi a Write fügvénnyel.
 
   * PageParse( cName, hPar )
   A tpl könyvtárban lévő cName nevű template file-t feldolgozza és behelyettesíti a hPar nevű hash tömbben
   lévő értékeket. Majd elküldi visszaadja az eredményt egy karakteres stringben.
 
   * PutFields( hPar )
   A hPar hash tömbben megadott Id érték párok alapján átirja a weboldal adatait.
   Ha input vagy text típusú html ellem akkor a value értékét cseréli le, ha egyéb akkor az elem innerHTML tulajdonságát változtatja meg.
   ````xbase
      wbs:PutFields({"id1"=>23, "id2"=>"vétel"})
   ````

   * InsertHTML( cId, cHtml )
   A cId-ben megadott elem innerHTML tulajdonságát változtatja meg.

   * SetFocus( cId )
   A cId-ben megadott elemre teszi a fokuszt.

   * SetSelection( cId, nStart, nEnd )
   A cId-ben megadott input elem nStart-tól nEnd-ig tartó résszének kijelölése.

   * Set( cSearch, cName, cValue )
   A cSearch-ban megadott CSS selector által kiválasztott elemek cName nevű tulajdonságának a cValue értékeket adja.

   * SetStyle( cSearch, cName, cValue )
   A cSearch-ban megadott CSS selector által kiválasztott elemek style eleme cName nevű tulajdonságának a cValue értékeket adja.

   * GetFields( nTimeout )
   Beolvas egy websocket blokkot és a megkapott értékeket egy hash tömbben adja vissza.
   Ha timeoutra futott akkor üres tömböt ad vissza.

   * WebRead( nTimeout, bTimeout )
   * isTimeout()
   Igazat ad vissza ha az utolsó I/O müvelet időtullépéssel tért vissza.

   * isError()
   Igazat ad vissza ha az utolsó I/O müvelet során hiba történt.

   * isCommand()
   Igaz az értéke ha van lenyomott gomb azonosító a visszakapott értékek között.

   * Command()
   A gombhoz rendelt parancsot adja vissza.
   ````HTML
   <button data-command="OK">OK</button>
   ````
   Ha a type=submit paraméter is meg van adva akkor az összes input mezőt is elküldi ami az aktuális formban van. 
   Ha nincs form akkor az oldalon lávő összes input mezőt elküldi.
   ````HTML
   <form>
   <input text id=szoveg />
   <button type="submit" data-command="OK">OK</button>
   </form>
   ````

   * Parameter()
   A gombhoz rendelt paramétert adja vissza.
   ````HTML
   <button data-command="skip" data-par="-1">Előző</button>
   ````

   * isFiles()
   Igaz az értéke ha van feltöltött file.

   * Files()
   Egy tömböt ad vissza ami minden feltöltött filehoz egy has tömöt tartalmaz amiben a következö adatok vannak:
   >- name = a file neve
   >- size = a file mérete
   >- data = a file tartalma base64 kódolással
   >- id   = a mező ID-je

   * isFields()
   Igazat ad vissza a van input mező.

   * isField( cName )
   Igazat ad vissza ha van cName azonosítóju input mező.

   * Fields()
   Egy hash tömböt ad vissza egy mező iD érték párokat ad vissza.

   * FieldGet( cName,/* @ */ xVar, xDefault )
   A cName nevü mező értékét visszaadja az xVar változóban ha nincs ilyen változó akkor az xDefault értéket  adja vissza.

   * Redirect( cLink )
   A aktuális weboldalt kicseréli a cLink című oldalra.

   * Inkeyon( cId )
   Minden gombnyomást átküld, ha a cId nincs megadva akkor az egész oldalon. Ha cId meg van adva akkor az adott elemen.

   * Inkeyoff( cId )
   Kikapcsolja a gombok átküldését.

