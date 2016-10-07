#include "hbclass.ch"
#include "hbsocket.ch"

#define CR_LF                   ( Chr( 13 ) + Chr( 10 ) )

MEMVAR server, httpd

FUNCTION TraceLog( bTrace )

   STATIC trace := NIL

   IF bTrace # NIL
      trace := bTrace
   ENDIF

   RETURN( trace )
FUNCTION PageParse( cName, hPar )

   LOCAL rc

   hb_default( @hPar, hb_Hash() )
   rc := UParse( hPar, cName, Tracelog() )

   RETURN( rc )

CREATE CLASS WebSocketError

   VAR ErrorCode INIT 0
   VAR Description INIT ""
   METHOD New( ErrorCode, Description )

ENDCLASS
METHOD New( ErrorCode, Description ) CLASS WebSocketError

   ::ErrorCode := ErrorCode
   ::Description := Description

   return( self )
CREATE CLASS WebSocket MODULE FRIENDLY

   PROTECTED:
   VAR cRequest
   VAR cWebsocketKey
   VAR cKeyResponse
   VAR nStatus  INIT 0 // 0 - nem WebSocket kapcsolat
   // 1 - érvényes Websocket kapcsolat
   // 2 - multipart feltöltés
   VAR nErrorCode INIT 0
   VAR nErrorMode INIT 0  // 0 - normál hibakezelés hibakóddal tér vissza
   // 1 - "begin sequence" hibakezelés meghívja a break-t
   VAR cErrorString
   VAR cFileName
   VAR CFileBody
   VAR hSocket
   VAR hSSL
   VAR oConnect
   VAR nBlockType   // Az utoljára beolvasott blokk tipusa
   METHOD KeyGen()
   METHOD CreateHead( nType, nLength, lLast, lMask )
   EXPORTED:
   METHOD New( oConnect, cRequest )
   METHOD WriteRaw( cBuffer )
   METHOD WriteTextBlock( cBuffer )
   METHOD WriteBinBlock( cBuffer )
   METHOD Status()
   METHOD Response()
   METHOD ErrorMode( nMod )
   METHOD ErrorCode()
   METHOD ReadRaw( nLength, cBuffer, nTimeout )
   METHOD ReadBlock( cBlock, nTimeout )
   METHOD FileName() INLINE ( ::cFileName )
   METHOD FileBody() INLINE ( ::cFileBody )
   METHOD Socket() INLINE ( server[ "HSOCKET" ] )

ENDCLASS
METHOD New( oConnect, cRequest ) CLASS WebSocket

   LOCAL cResponse
   LOCAL poz, tipus, oPost, oPart, mezonev, hibakod

   ::cRequest := cRequest
   ::cErrorString := ""
   ::hSocket := oConnect:hSocket
   ::hSSL := oConnect:hSSL
   ::oConnect := oConnect
   ::cWebsocketKey := hb_HGetDef( server, "HTTP_SEC_WEBSOCKET_KEY", "" )
   IF At( "upgrade", Lower( hb_HGetDef( server, "HTTP_CONNECTION", "" ) ) ) > 0 ;
         .AND.  Lower( hb_HGetDef( server, "HTTP_UPGRADE", "" ) ) == "websocket" .AND. ;
         ::Keygen()
      cResponse := "HTTP/1.1 101 WebSocket Protocol Handshake" + CR_LF
      cResponse += "Upgrade: WebSocket" + CR_LF
      cResponse += "Connection: Upgrade" + CR_LF
      cResponse += "Sec-WebSocket-Accept: " + ::cKeyResponse + CR_LF
      cResponse += CR_LF
      if ::WriteRaw( cResponse ) > 0
         ::nStatus := 1
      ENDIF
   ELSE
      tipus := hb_HGetDef( server, "CONTENT_TYPE", "nincs" )
      poz := At( ";", tipus )
      IF poz != 0
         tipus := Left( tipus, poz - 1 )
      ENDIF
      IF tipus == "multipart/form-data"
         ::nStatus := 2
         oPost := tipmail():new()
         hibakod := oPost:fromstring( "CONTENT-TYPE: " + server[ "CONTENT_TYPE" ] + e"\r\n\r\n" + ::cRequest )
         IF hibakod == 0
            ::nErrorCode := 4 // adatformátum hiba
         ELSE
            ::nErrorCode := 2 // nincs feltöltött file
            WHILE oPost:GetAttachment() != NIL
               oPart := oPost:nextAttachment()
               mezonev := oPart:GetFieldOption( "Content-Disposition", "name" )
               IF mezonev == '"file"' .OR. mezonev == 'file'
                  ::cFileName := oPart:GetFieldOption( "Content-Disposition", "filename" )
                  IF Left( ::cFileName, 1 ) == '"' .AND. Right( ::cFileName, 1 ) == '"'
                     ::cFileName = SubStr( ::cFileName, 2, Len( ::cFileName ) -2 )
                  ENDIF
                  IF Len( ::cFileName ) > 0
                     ::cFileBody := oPart:GetRawBody()
                     ::cFileBody := SubStr( ::cFileBody, 1, Len( ::cFileBody ) -2 )
                     ::nErrorCode := 0
                     EXIT
                  ELSE
                     ::nErrorCode := 3 // nem volt kijelölve file a feltöltéshez
                  ENDIF
               ENDIF
            ENDDO
         ENDIF
      ENDIF
   ENDIF

   return( Self )
METHOD KeyGen() CLASS WebSocket

   LOCAL rc

   IF hb_BLen( ::cWebsocketKey ) > 0
      ::cKeyResponse := hb_base64Encode( hb_SHA1( ::cWebSocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", .T. ) )
      rc := .y.
   ELSE
      rc := .n.
   ENDIF

   return( rc )
METHOD WriteRaw( cBuffer ) CLASS WebSocket

   LOCAL rc

   rc := ::oConnect:Write( cBuffer )
   ::nErrorCode := rc
   if ::nErrorMode == 1 .AND. ::nErrorCode < 0
      Break( WebSocketError():New( ::nErrorCode, "WebSocket írási hib!" ) )
   ENDIF

   return( rc )
METHOD WriteTextBlock( cBuffer ) CLASS WebSocket

   LOCAL rc

   rc := ::WriteRaw( ::CreateHead( 1, hb_BLen( cBuffer ) ) + cBuffer )

   return( rc )
METHOD WriteBinBlock( cBuffer ) CLASS WebSocket

   LOCAL rc

   rc := ::WriteRaw( ::CreateHead( 2, hb_BLen( cBuffer ) ) + cBuffer )

   return( rc )
METHOD ReadRaw( nLength, cBuffer, nTimeout ) CLASS WebSocket

   LOCAL rc

   rc := ::oConnect:Read( @cBuffer, nLength, nTimeout )
   ::nErrorCode := rc
   if ::nErrorMode == 1 .AND. ::nErrorCode < 0
      Break( WebSocketError():New( ::nErrorCode, "WebSocket olvasási hib!" ) )
   ENDIF

   return( rc )
METHOD ReadBlock( cBlock, nTimeout ) CLASS WebSocket

   LOCAL rc
   LOCAL lLast := .n.
   LOCAL lMask
   LOCAL nLength
   LOCAL cBuffer := ""
   LOCAL cMask
   LOCAL k, l

   cBlock := ""
   WHILE !lLast
      cBuffer := Space( 2 )
      rc := ::ReadRaw( 2, @cBuffer, nTimeout )
      IF rc # 2
         return( rc )
      ENDIF
      // The opcode (4 bits) indicates type of transferred frame:
      // text (1) or binary (2) for transferring application data or a control frame
      // such as connection close (8), ping (9), and pong (10) for connection liveness checks.
      lLast := hb_bitAnd( hb_BPeek( cBuffer, 1 ), 0x80 ) > 0
      ::nBlockType := hb_bitAnd( hb_BPeek( cBuffer, 1 ), 0x0f )
      lMask := hb_bitAnd( hb_BPeek( cBuffer, 2 ), 0x80 ) > 0
      nLength := hb_bitAnd( hb_BPeek( cBuffer, 2 ), 0x7f )
      if ::nBlockType == 8
         ::nErrorCode := -2
         if ::nErrorMode == 1 .AND. ::nErrorCode < 0
            Break( WebSocketError():New( ::nErrorCode, "WebSocket lezárás kérése!" ) )
         ENDIF
         return( ::nErrorCode )
      ELSE
         switch nLength
         CASE 126
            // 16 bites hossz
            cBuffer := Space( 2 )
            rc := ::ReadRaw( 2, @cBuffer )
            IF rc # 2
               return( rc )
            ENDIF
            nLength := hb_BPeek( cBuffer, 1 ) * 256 + hb_BPeek( cBuffer, 2 )
            EXIT
         CASE 127
            // 64 bites hossz
            cBuffer := Space( 2 )
            rc := ::ReadRaw( 8, @cBuffer )
            IF rc # 8
               return( rc )
            ENDIF
            nLength := ( ( hb_BPeek( cBuffer, 1 ) * 256 + hb_BPeek( cBuffer, 2 ) ) * 256 + hb_BPeek( cBuffer, 3 ) ) * 256 + hb_BPeek( cBuffer, 4 ) * 256 * 256 * 256 * 256
            nLength += ( ( hb_BPeek( cBuffer, 5 ) * 256 + hb_BPeek( cBuffer, 6 ) ) * 256 + hb_BPeek( cBuffer, 7 ) ) * 256 + hb_BPeek( cBuffer, 8 )
            EXIT
         OTHERWISE
         endswitch
         IF lMask
            cBuffer := Space( 4 )
            rc := ::ReadRaw( 4, @cMask )
            IF rc # 4
               return( rc )
            ENDIF
         ENDIF
         cBuffer := Space( nLength )
         rc := ::ReadRaw( nLength, @cBuffer )
         IF rc # nLength
            return( rc )
         ENDIF
         IF lMask
            k := 1
            FOR l := 1 TO nLength
               hb_BPoke( @cBuffer, l, hb_bitXor( hb_BPeek( cMask, k++ ), hb_BPeek( cBuffer, l ) ) )
               IF k > 4
                  k := 1
               ENDIF
            NEXT
         ENDIF
         cBlock += cBuffer
      ENDIF
      rc := hb_BLen( cBlock )
   ENDDO

   return( rc )
METHOD Status() CLASS WebSocket
   /*
        > 0 WebSocket kapcsolat felépült
        0 Nem Websocket kérés
       -1 Hiba kilépés
   */
   return( ::nStatus )
METHOD Response() CLASS WebSocket
   return( "" )
METHOD ErrorMode( nMod ) CLASS WebSocket

   IF nMod # NIL
      ::nErrorMode := nMod
   ENDIF

   return( ::nErrorMode )
METHOD ErrorCode() CLASS WebSocket
   /*
        > 0 Érvényes művelet
        0 Timeout
       -1 Hiba kilépés
   */
   return( ::nErrorCode )
METHOD CreateHead( nType, nLength, lLast, lMask ) CLASS WebSocket
/*
   nType: 1 szöveg
          2 bináris
          8 close
          9 ping
         10 pong
   lLast: logikai érték ha igaz ez az utolsó
   lMask: logikai érték ha igaz van Mask
*/

   // text (1) or binary (2) for transferring application data or a control frame
   // such as connection close (8), ping (9), and pong (10) for connection liveness checks.
   LOCAL cHead := ""
   LOCAL nByte := 0, tbyte, k
   hb_default( @lLast, .y. )
   hb_default( @lMask, .n. )
   IF  lLast
      nByte += 0x80
   ENDIF
   switch nType
   CASE 1
   CASE 2
   CASE 8
   CASE 9
   CASE 10
      nByte += nType
      EXIT
   OTHERWISE
      nByte += 8
      EXIT
   endswitch
   cHead += hb_BChar( nByte )
   nByte := 0
   IF  lMask
      nByte += 0x80
   ENDIF
   IF nLength > 125
      IF nLength > 0xffff
         nByte += 127
         cHead += hb_BChar( nByte )
         tbyte := {}
         FOR k := 1 TO 8
            AAdd( tbyte, hb_BChar( nLength % 256 ) )
            nLength := Int( nLength / 256 )
         NEXT
         FOR k := 8 TO 1 STEP -1
            cHead += tbyte[ k ]
         NEXT
      ELSE
         nByte += 126
         cHead += hb_BChar( nByte )
         cHead += hb_BChar( Int( nLength / 256 ) )
         cHead += hb_BChar( nLength % 256 )
      ENDIF
   ELSE
      nByte += nLength
      cHead += hb_BChar( nByte )
   ENDIF

   return( cHead )
CLASS WebProtocol FROM WebSocket

   VAR   base64 INIT .y.
   PROTECTED:
   VAR   Respond
   VAR   jsonformat INIT .y.  // .y. human format .n. compact
   EXPORTED:
   METHOD Write( oMessage )
   METHOD New( oConnect, cRequest )
   METHOD PageWrite( cName, hPar )
   METHOD PageParse( cName, hPar )
   METHOD PutFields( hPar )
   METHOD SetFocus( cId )
   METHOD SetSelection( cId, nStart, nEnd )
   METHOD InsertHTML( cId, cHtml )
   METHOD OpenModal( cId )
   METHOD Set( cSearch, cName, CValue )
   METHOD SetStyle( cSearch, cName, CValue )
   METHOD CloseModal( cId )
   METHOD GetFields( nTimeout )
   METHOD WebRead( nTimeout, bTimeout )
   METHOD Timeout()
   METHOD Error()
   METHOD isCommand()
   METHOD Command()
   METHOD Parameter()
   METHOD isFiles()
   METHOD Files()
   METHOD isFields()
   METHOD isField( cName )
   METHOD Fields()
   METHOD FieldGet( cName, xVar, xDefault )
   METHOD Redirect( cLink )
   METHOD Inkeyon( cId )
   METHOD Inkeyoff( cId )

ENDCLASS
METHOD New( oConnect, cRequest ) CLASS WebProtocol

   ::nError := 0
   ::Super:New( oConnect, cRequest )

   return( Self )
METHOD Webread( nTimeout, bTimeout ) CLASS WebProtocol

   WHILE .y.
      ::Respond = ::GetFields( nTimeout )
      IF nTimeout # NIL .AND. bTimeout # NIL .AND. ::Timeout()
         ::Respond := Eval( bTimeout )
         IF ValType( ::Respond ) == "H"
            EXIT
         ENDIF
      ELSE
         EXIT
      ENDIF
   ENDDO
   IF ValType( ::Respond ) # "H"
      ::Respond := hb_Hash()
   ENDIF

   RETURN( ::Respond )
METHOD Write( oMessage ) CLASS WebProtocol

   LOCAL rc := ""
   LOCAL cMessage

   IF Len( oMessage ) > 0
      cMessage := hb_jsonEncode( oMessage, ::jsonformat )
      if ::base64
         cMessage := hb_jsonEncode( { "base64" => hb_base64Encode( cMessage ) }, ::jsonformat )
         // ?"1:",cMessage
         // cMessage:=hb_translate(cMessage,"UTF16LE","UTF8")
         // ?"2:",cMessage
         // cMessage:=hb_translate(cMessage,"UTF8","UTF16LE")
         // ?"3:",cMessage
      ENDIF
      if ::WriteTextBlock( cMessage ) <= 0
         rc := NIL
      ENDIF
   ENDIF

   RETURN( rc )
METHOD Timeout() CLASS WebProtocol
   RETURN ::Super:ErrorCode() == 0
METHOD Error() CLASS WebProtocol
   RETURN ::Super:ErrorCode() < 0
METHOD PageWrite( cName, hPar ) CLASS WebProtocol

   LOCAL rc

   rc := ::PageParse( cName, hPar )
   IF rc # NIL
      return( ::Write( { "newpage" => rc } ) )
   ENDIF

   RETURN( rc )
METHOD PageParse( cName, hPar ) CLASS WebProtocol

   LOCAL rc

   hb_default( @hPar, hb_Hash() )
   rc := UParse( hPar, cName, httpd:hconfig )

   RETURN( rc )
METHOD PutFields( hPar ) CLASS WebProtocol

   hb_default( @hPar, hb_Hash() )

   RETURN( ::Write( hb_Hash( "ertek", hPar ) ) )
METHOD SetFocus( cId ) CLASS WebProtocol
   RETURN( ::Write( { "focus" => { "id" => cId } } ) )
METHOD SetSelection( cId, nStart, nEnd ) CLASS WebProtocol
   RETURN( ::Write( { "select" => { "id" => cId, "start" => nStart, "end" => nEnd } } ) )
METHOD InsertHTML( cId, cHtml ) CLASS WebProtocol
   RETURN( ::Write( { "insert" => { "id" => cId, "html" => cHtml } } ) )
METHOD Set( cSearch, cName, CValue ) CLASS WebProtocol
   RETURN( ::Write( { "set" => { "search" => cSearch, "nev" => cName, "ertek" => cValue } } ) )
METHOD SetStyle( cSearch, cName, CValue ) CLASS WebProtocol
   RETURN( ::Write( { "setstyle" => { "search" => cSearch, "nev" => cName, "ertek" => cValue } } ) )
METHOD Inkeyon( cId ) CLASS WebProtocol

   LOCAL rc

   IF ( cId == NIL )
      rc := { "inkey" => { "mode" => "windowadd" } }
   ELSE
      rc := { "inkey" => { "mode" => "idadd", "id" => cId } }
   ENDIF

   RETURN( ::Write( rc ) )
METHOD Inkeyoff( cId ) CLASS WebProtocol

   LOCAL rc

   IF ( cId == NIL )
      rc := { "inkey" => { "mode" => "windowremove" } }
   ELSE
      rc := { "inkey" => { "mode" => "idremove", "id" => cId } }
   ENDIF

   RETURN( ::Write( rc ) )
METHOD OpenModal( cId ) CLASS WebProtocol

   hb_default( @cId, "openModal" )

   RETURN( ::Write( { "href" => "#" + cId } ) )
METHOD CloseModal( cId ) CLASS WebProtocol

   hb_default( @cId, "openModal" )

   RETURN( ::Write( { "href" => "#" } ) )
METHOD Redirect( cLink ) CLASS WebProtocol
   RETURN( ::Write( { "href" => cLink } ) )
METHOD GetFields( nTimeout ) CLASS WebProtocol

   LOCAL rc
   LOCAL cValasz
   LOCAL nReadstatus

   cValasz := ""
   hb_default( @nTimeout, 0 )
   nReadstatus := ::ReadBlock( @cValasz, nTimeout )
   DO CASE
   CASE nReadstatus > 0
      hb_jsonDecode( cValasz, @rc )
      IF ValType( rc ) # "H"
         rc := hb_Hash()
      ENDIF
   CASE nReadstatus == 0
      // Timeout
      rc := hb_Hash()
   OTHERWISE
      // Hiba
   ENDCASE

   RETURN( rc )
METHOD isCommand() CLASS WebProtocol
   RETURN( hb_HHasKey( ::Respond, "command" ) )
METHOD Command() CLASS WebProtocol

   if ::isCommand()
      RETURN( hb_HGetDef( ::Respond[ "command" ], "comm", "" ) )
   ENDIF

   RETURN( "" )
METHOD Parameter() CLASS WebProtocol

   if ::isCommand()
      RETURN( hb_HGetDef( ::Respond[ "command" ], "par", "" ) )
   ENDIF

   RETURN( "" )
METHOD isFiles()  CLASS WebProtocol

   hb_HHasKey( ::Respond, "fileok" )

   RETURN( hb_HHasKey( ::Respond, "fileok" ) )
METHOD Files()  CLASS WebProtocol

   if ::isFiles()
      RETURN( ::Respond[ "fileok" ] )
   ENDIF

   RETURN( {} )
METHOD isFields()  CLASS WebProtocol

   LOCAL rc := .n.

   IF hb_HHasKey( ::Respond, "mezok" )
      IF Len( ::Respond[ "mezok" ] ) > 0
         rc := .y.
      ENDIF
   ENDIF

   RETURN( rc )
METHOD Fields()  CLASS WebProtocol

   if ::isFields()
      RETURN( ::Respond[ "mezok" ] )
   ENDIF

   RETURN( { => } )
METHOD isField( cName )  CLASS WebProtocol

   LOCAL rc := .n.

   if ::isFields()
      IF hb_HHasKey( ::Respond[ "mezok" ], cName )
         rc := .y.
      ENDIF
   ENDIF

   RETURN( rc )
METHOD FieldGet( cName, xVar, xDefault )  CLASS WebProtocol

   LOCAL rc := .n., xWork

   if ::isField( cName )
      xWork := ::Respond[ "mezok" ][ cName ]
      switch ValType( xVar )
      CASE "N"
         xVar := Val( xWork )
         EXIT
      CASE "C"
      CASE "M"
      OTHERWISE
         xVar := xWork
         EXIT
      endswitch
   ELSE
      IF xDefault # NIL
         xVar := xDefault
      ENDIF
   ENDIF

   RETURN( rc )
