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
> feladata a kapcsolat felvétele a böngészővel, és az átvitt adatok fejlécének kezelése.
     
* New( oConnect, cRequest, bTrace )

- Létrehoz egy objektumot és befejezi a kapcsolatfelvételt.

* Status()

> Visszaadja a kapcsolat típusát
>-  0 - nem websocek kérés volt
>-  1 - érvényes websocket kapcsolat kiépült

Socket()
      Visszaadja a TCP socket-t 

    ErrorCode()
       Az utoljára elvégzett művelet hibakódját adja vissza

    ErrorMode( nMod )
       Beállítja a hibakezelés módját
         0 - Az ErrorCode fügvénnyel lehet lekérdezni a hibakódot
         1 - Hiba esetén "break" hívása WebSocketError objektummal

    WriteRaw( cBuffer )
       A cBuffer blokk kiírása a websocket kapcsolatra

    WriteTextBlock( cBuffer )
       A cBuffer text módu fejlécének elkézítése és kiírása a WriteRaw fügvénnyel

    WriteBinBlock( cBuffer )
       A cBuffer bináris módu fejlécének elkézítése és kiírása a WriteRaw fügvénnyel
       Még nem láttam böngészőt ami támogatta volna!!!

    ReadRaw( nLength,/* @ */ cBuffer, nTimeout )
       Adott számú byte beolvasása a CBuffer-be

    ReadBlock(/* @ */ cBlock, nTimeout )
       Beolvas egy websocket blokkot.


