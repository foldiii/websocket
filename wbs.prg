#include "hbclass.ch"
#include "hbsocket.ch"

#define CR_LF                   ( Chr( 13 ) + Chr( 10 ) )

MEMVAR server, httpd

FUNCTION TraceLog( bTrace )

   STATIC s_trace

   IF HB_ISEVALITEM( bTrace )
      s_trace := bTrace
   ENDIF

   RETURN s_trace

FUNCTION PageParse( cName, hPar )
   RETURN UParse( hb_defaultValue( hPar, { => } ), cName, TraceLog() )

CREATE CLASS WebSocketError

   VAR ErrorCode   INIT 0
   VAR Description INIT ""

   METHOD New( ErrorCode, Description )

ENDCLASS

METHOD New( ErrorCode, Description ) CLASS WebSocketError

   ::ErrorCode := ErrorCode
   ::Description := Description

   RETURN self

CREATE CLASS WebSocket MODULE FRIENDLY

   PROTECTED:

   VAR cRequest
   VAR cWebsocketKey
   VAR cKeyResponse
   VAR nStatus  INIT 0 // 0 - nem WebSocket kapcsolat
   // 1 - érvényes Websocket kapcsolat
   VAR nErrorCode INIT 0
   VAR nErrorMode INIT 0  // 0 - normál hibakezelés hibakóddal tér vissza
   // 1 - "begin sequence" hibakezelés meghívja a break-t
   VAR cErrorString
   VAR cFileName
   VAR CFileBody
   VAR hSocket
   VAR hSSL
   VAR bTrace
   VAR oConnect
   VAR nBlockType   // Az utoljára beolvasott blokk típusa

   METHOD KeyGen()
   METHOD CreateHead( nType, nLength, lLast, lMask )

   EXPORTED:

   METHOD New( oConnect, cRequest, bTrace )
   METHOD WriteRaw( cBuffer )
   METHOD WriteTextBlock( cBuffer )
   METHOD WriteBinBlock( cBuffer )
   METHOD Status()
   METHOD ErrorMode( nMod )
   METHOD ErrorCode()
   METHOD ReadRaw( nLength, /* @ */ cBuffer, nTimeout )
   METHOD ReadBlock( /* @ */ cBlock, nTimeout )
   METHOD Socket() INLINE ( ::hSocket )

ENDCLASS

METHOD New( oConnect, cRequest, bTrace ) CLASS WebSocket

   LOCAL cResponse

   ::cRequest := cRequest
   ::cErrorString := ""
   ::hSocket := oConnect:hSocket
   ::hSSL := oConnect:hSSL
   ::bTrace := bTrace
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
      IF ::WriteRaw( cResponse ) > 0
         ::nStatus := 1
      ENDIF
   ENDIF

   RETURN Self

METHOD KeyGen() CLASS WebSocket

   IF hb_BLen( ::cWebsocketKey ) > 0
      ::cKeyResponse := hb_base64Encode( hb_SHA1( ::cWebSocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", .T. ) )
      RETURN .T.
   ENDIF

   RETURN .F.

METHOD WriteRaw( cBuffer ) CLASS WebSocket

   LOCAL rc := ::oConnect:Write( cBuffer )

   ::nErrorCode := rc
   IF ::nErrorMode == 1 .AND. ::nErrorCode < 0
      Break( WebSocketError():New( ::nErrorCode, "WebSocket írási hib!" ) )
   ENDIF

   RETURN rc

METHOD WriteTextBlock( cBuffer ) CLASS WebSocket
   RETURN ::WriteRaw( ::CreateHead( 1, hb_BLen( cBuffer ) ) + cBuffer )

METHOD WriteBinBlock( cBuffer ) CLASS WebSocket
   RETURN ::WriteRaw( ::CreateHead( 2, hb_BLen( cBuffer ) ) + cBuffer )

METHOD ReadRaw( nLength, /* @ */ cBuffer, nTimeout ) CLASS WebSocket

   LOCAL rc := ::oConnect:Read( @cBuffer, nLength, nTimeout )

   ::nErrorCode := rc
   IF ::nErrorMode == 1 .AND. ::nErrorCode < 0
      Break( WebSocketError():New( ::nErrorCode, "WebSocket olvasási hiba!" ) )
   ENDIF

   RETURN rc

METHOD ReadBlock( /* @ */ cBlock, nTimeout ) CLASS WebSocket

   LOCAL rc
   LOCAL lLast := .F.
   LOCAL lMask
   LOCAL nLength
   LOCAL cBuffer := ""
   LOCAL cMask
   LOCAL k, l

   cBlock := ""
   WHILE ! lLast
      cBuffer := Space( 2 )
      rc := ::ReadRaw( 2, @cBuffer, nTimeout )
      IF rc != 2
         RETURN rc
      ENDIF
      // The opcode (4 bits) indicates type of transferred frame:
      // text (1) or binary (2) for transferring application data or a control frame
      // such as connection close (8), ping (9), and pong (10) for connection liveness checks.
      lLast := hb_bitAnd( hb_BPeek( cBuffer, 1 ), 0x80 ) > 0
      ::nBlockType := hb_bitAnd( hb_BPeek( cBuffer, 1 ), 0x0f )
      lMask := hb_bitAnd( hb_BPeek( cBuffer, 2 ), 0x80 ) > 0
      nLength := hb_bitAnd( hb_BPeek( cBuffer, 2 ), 0x7f )
      IF ::nBlockType == 8
         ::nErrorCode := -2
         IF ::nErrorMode == 1 .AND. ::nErrorCode < 0
            Break( WebSocketError():New( ::nErrorCode, "WebSocket lezárás kérése!" ) )
         ENDIF
         RETURN ::nErrorCode
      ELSE
         SWITCH nLength
         CASE 126
            // 16 bites hossz
            cBuffer := Space( 2 )
            IF ( rc := ::ReadRaw( 2, @cBuffer ) ) != 2
               RETURN rc
            ENDIF
            nLength := hb_BPeek( cBuffer, 1 ) * 256 + hb_BPeek( cBuffer, 2 )
            EXIT
         CASE 127
            // 64 bites hossz
            cBuffer := Space( 2 )
            IF ( rc := ::ReadRaw( 8, @cBuffer ) ) != 8
               RETURN rc
            ENDIF
            nLength := ( ( hb_BPeek( cBuffer, 1 ) * 256 + hb_BPeek( cBuffer, 2 ) ) * 256 + hb_BPeek( cBuffer, 3 ) ) * 256 + hb_BPeek( cBuffer, 4 ) * 256 * 256 * 256 * 256
            nLength += ( ( hb_BPeek( cBuffer, 5 ) * 256 + hb_BPeek( cBuffer, 6 ) ) * 256 + hb_BPeek( cBuffer, 7 ) ) * 256 + hb_BPeek( cBuffer, 8 )
            EXIT
         ENDSWITCH
         IF lMask
            cBuffer := Space( 4 )
            rc := ::ReadRaw( 4, @cMask )
            IF rc != 4
               RETURN rc
            ENDIF
         ENDIF
         cBuffer := Space( nLength )
         rc := ::ReadRaw( nLength, @cBuffer )
         IF rc != nLength
            RETURN rc
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

   RETURN rc

METHOD Status() CLASS WebSocket
   /*
        > 0 WebSocket kapcsolat felépült
        0 Nem Websocket kérés
       -1 Hiba kilépés
   */
   RETURN ::nStatus

METHOD ErrorMode( nMod ) CLASS WebSocket

   IF nMod != NIL
      ::nErrorMode := nMod
   ENDIF

   RETURN ::nErrorMode

METHOD ErrorCode() CLASS WebSocket
   /*
        > 0 Érvényes művelet
        0 Timeout
       -1 Hiba kilépés
   */
   RETURN ::nErrorCode

/*
   nType: 1 szöveg
          2 bináris
          8 close
          9 ping
         10 pong
   lLast: logikai érték ha igaz ez az utolsó
   lMask: logikai érték ha igaz van Mask
*/
METHOD CreateHead( nType, nLength, lLast, lMask ) CLASS WebSocket

   // text (1) or binary (2) for transferring application data or a control frame
   // such as connection close (8), ping (9), and pong (10) for connection liveness checks.
   LOCAL cHead := ""
   LOCAL nByte := 0, tbyte, k

   hb_default( @lLast, .T. )
   hb_default( @lMask, .F. )

   IF lLast
      nByte += 0x80
   ENDIF

   SWITCH nType
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
   ENDSWITCH

   cHead += hb_BChar( nByte )
   nByte := 0
   IF lMask
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

   RETURN cHead

CLASS WebProtocol FROM WebSocket

   VAR   base64 INIT .T.

   PROTECTED:

   VAR   Respond
   VAR   jsonformat INIT .T.  // .T. human format .F. compact

   EXPORTED:

   METHOD Write( oMessage )
   METHOD New( oConnect, cRequest, bTrace )
   METHOD PageWrite( cName, hPar )
   METHOD PageParse( cName, hPar )
   METHOD PutFields( hPar )
   METHOD SetFocus( cId )
   METHOD SetSelection( cId, nStart, nEnd )
   METHOD InsertHTML( cId, cHtml )
   METHOD Set( cSearch, cName, cValue )
   METHOD SetStyle( cSearch, cName, cValue )
   METHOD GetFields( nTimeout )
   METHOD WebRead( nTimeout, bTimeout )
   METHOD isTimeout()
   METHOD isError()
   METHOD isCommand()
   METHOD Command()
   METHOD Parameter()
   METHOD isFiles()
   METHOD Files()
   METHOD isFields()
   METHOD isField( cName )
   METHOD Fields()
   METHOD FieldGet( cName, /* @ */ xVar, xDefault )
   METHOD Redirect( cLink )
   METHOD Inkeyon( cId )
   METHOD Inkeyoff( cId )

ENDCLASS

METHOD New( oConnect, cRequest, bTrace ) CLASS WebProtocol

   ::Super:New( oConnect, cRequest, bTrace )

   RETURN Self

METHOD Webread( nTimeout, bTimeout ) CLASS WebProtocol

   WHILE .T.
      ::Respond = ::GetFields( nTimeout )
      IF nTimeout != NIL .AND. HB_ISEVALITEM( bTimeout ) .AND. ::isTimeout()
         ::Respond := Eval( bTimeout )
         IF HB_ISHASH( ::Respond )
            EXIT
         ENDIF
      ELSE
         EXIT
      ENDIF
   ENDDO

   RETURN hb_defaultValue( ::Respond, { => } )

METHOD Write( oMessage ) CLASS WebProtocol

   LOCAL rc := ""
   LOCAL cMessage

   IF Len( oMessage ) > 0
      cMessage := hb_jsonEncode( oMessage, ::jsonformat )
      IF ::base64
         cMessage := hb_jsonEncode( { "base64" => hb_base64Encode( cMessage ) }, ::jsonformat )
#if 0
         ? "1:", cMessage
         cMessage := hb_Translate( cMessage, "UTF16LE", "UTF8" )
         ? "2:", cMessage
         cMessage := hb_Translate( cMessage, "UTF8", "UTF16LE" )
         ? "3:", cMessage
#endif
      ENDIF
      IF ::WriteTextBlock( cMessage ) <= 0
         rc := NIL
      ENDIF
   ENDIF

   RETURN rc

METHOD isTimeout() CLASS WebProtocol
   RETURN ::Super:ErrorCode() == 0

METHOD isError() CLASS WebProtocol
   RETURN ::Super:ErrorCode() < 0

METHOD PageWrite( cName, hPar ) CLASS WebProtocol

   LOCAL rc

   IF ( rc := ::PageParse( cName, hPar ) ) != NIL
      RETURN ::Write( { "newpage" => rc } )
   ENDIF

   RETURN rc

METHOD PageParse( cName, hPar ) CLASS WebProtocol
   RETURN UParse( hb_defaultValue( hPar, { => } ), cName, ::bTrace )

METHOD PutFields( hPar ) CLASS WebProtocol
   RETURN ::Write( { "ertek" => hb_defaultValue( hPar, { => } ) } )

METHOD SetFocus( cId ) CLASS WebProtocol
   RETURN ::Write( { "focus" => { "id" => cId } } )

METHOD SetSelection( cId, nStart, nEnd ) CLASS WebProtocol
   RETURN ::Write( { "select" => { "id" => cId, "start" => nStart, "end" => nEnd } } )

METHOD InsertHTML( cId, cHtml ) CLASS WebProtocol
   RETURN ::Write( { "insert" => { "id" => cId, "html" => cHtml } } )

METHOD Set( cSearch, cName, cValue ) CLASS WebProtocol
   RETURN ::Write( { "set" => { "search" => cSearch, "nev" => cName, "ertek" => cValue } } )

METHOD SetStyle( cSearch, cName, cValue ) CLASS WebProtocol
   RETURN ::Write( { "setstyle" => { "search" => cSearch, "nev" => cName, "ertek" => cValue } } )

METHOD Inkeyon( cId ) CLASS WebProtocol

   LOCAL rc

   IF cId == NIL
      rc := { "inkey" => { "mode" => "windowadd" } }
   ELSE
      rc := { "inkey" => { "mode" => "idadd", "id" => cId } }
   ENDIF

   RETURN ::Write( rc )

METHOD Inkeyoff( cId ) CLASS WebProtocol

   LOCAL rc

   IF cId == NIL
      rc := { "inkey" => { "mode" => "windowremove" } }
   ELSE
      rc := { "inkey" => { "mode" => "idremove", "id" => cId } }
   ENDIF

   RETURN ::Write( rc )

METHOD Redirect( cLink ) CLASS WebProtocol
   RETURN ::Write( { "href" => cLink } )

METHOD GetFields( nTimeout ) CLASS WebProtocol

   LOCAL cValasz := ""
   LOCAL nReadstatus := ::ReadBlock( @cValasz, hb_defaultValue( nTimeout, 0 ) )

   DO CASE
   CASE nReadstatus > 0
      RETURN hb_defaultValue( hb_jsonDecode( cValasz ), { => } )
   CASE nReadstatus == 0
      RETURN { => }  // Timeout
   ENDCASE

   RETURN NIL  // Error

METHOD isCommand() CLASS WebProtocol
   RETURN "command" $ ::Respond

METHOD Command() CLASS WebProtocol

   IF ::isCommand()
      RETURN hb_HGetDef( ::Respond[ "command" ], "comm", "" )
   ENDIF

   RETURN ""

METHOD Parameter() CLASS WebProtocol

   IF ::isCommand()
      RETURN hb_HGetDef( ::Respond[ "command" ], "par", "" )
   ENDIF

   RETURN ""

METHOD isFiles() CLASS WebProtocol
   RETURN "fileok" $ ::Respond

METHOD Files() CLASS WebProtocol
   RETURN iif( ::isFiles(), ::Respond[ "fileok" ], {} )

METHOD isFields() CLASS WebProtocol
   RETURN ;
      "mezok" $ ::Respond .AND. ;
      Len( ::Respond[ "mezok" ] ) > 0

METHOD Fields() CLASS WebProtocol
   RETURN iif( ::isFields(), ::Respond[ "mezok" ], { => } )

METHOD isField( cName ) CLASS WebProtocol
   RETURN ::isFields() .AND. cName $ ::Respond[ "mezok" ]

METHOD FieldGet( cName, /* @ */ xVar, xDefault ) CLASS WebProtocol

   LOCAL xWork

   IF ::isField( cName )
      xWork := ::Respond[ "mezok" ][ cName ]
      SWITCH ValType( xVar )
      CASE "N"
         xVar := Val( xWork )
         EXIT
      CASE "C"
      CASE "M"
      OTHERWISE
         xVar := xWork
         EXIT
      ENDSWITCH
   ELSEIF xDefault != NIL
      xVar := xDefault
   ENDIF

   RETURN .F.
