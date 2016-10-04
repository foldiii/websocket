#include "hbclass.ch"
#include "hbsocket.ch"

#define CR_LF                   ( Chr( 13 ) + Chr( 10 ) )

memvar server, httpd

FUNCTION TraceLog(bTrace)
   static trace := NIL
   if bTrace#NIL
      trace:=bTrace
   endif
RETURN(trace)
FUNCTION PageParse(cName, hPar)
   LOCAL rc
   hb_default(@hPar,hb_hash())
   rc:=UParse(hPar,cName,Tracelog())
RETURN(rc)

CREATE CLASS WebSocketError
   VAR ErrorCode INIT 0
   VAR Description INIT ""
   METHOD New(ErrorCode,Description)
ENDCLASS
METHOD New(ErrorCode,Description) CLASS WebSocketError
   ::ErrorCode:=ErrorCode
   ::Description:=Description
return(self)
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
      METHOD CreateHead(nType,nLength,lLast,lMask)
   EXPORTED:
      METHOD New(oConnect, cRequest)
      METHOD WriteRaw(cBuffer)
      METHOD WriteTextBlock(cBuffer)
      METHOD WriteBinBlock(cBuffer)
      METHOD Status()
      METHOD Response()
      METHOD ErrorMode(nMod)
      METHOD ErrorCode()
      METHOD ReadRaw(nLength,cBuffer,nTimeout)
      METHOD ReadBlock(cBlock,nTimeout)
      METHOD FileName() INLINE (::cFileName)
      METHOD FileBody() INLINE (::cFileBody)
      METHOD Socket() INLINE (server[ "HSOCKET" ])
ENDCLASS
METHOD New(oConnect, cRequest) CLASS WebSocket
   LOCAL cResponse
   LOCAL poz,tipus,oPost,oPart,mezonev,hibakod
   
   ::cRequest:=cRequest
   ::cErrorString:=""
   ::hSocket:=oConnect:hSocket
   ::hSSL:=oConnect:hSSL
   ::oConnect := oConnect
   ::cWebsocketKey:=hb_hgetdef(server,"HTTP_SEC_WEBSOCKET_KEY","")
   if at("upgrade",lower(hb_hgetdef( server,"HTTP_CONNECTION","") ) )>0 ;
      .and.  lower(hb_hgetdef( server,"HTTP_UPGRADE","")) == "websocket" .and. ;
      ::Keygen()
      cResponse:="HTTP/1.1 101 WebSocket Protocol Handshake"+CR_LF
      cResponse+="Upgrade: WebSocket"+CR_LF
      cResponse+="Connection: Upgrade"+CR_LF
      cResponse+="Sec-WebSocket-Accept: "+::cKeyResponse+CR_LF
      cResponse+=CR_LF
      if ::WriteRaw(cResponse) > 0
         ::nStatus:=1
      endif
   else
      tipus:=hb_hgetdef(server,"CONTENT_TYPE","nincs")
      poz:=at(";",tipus)
      if poz!=0
         tipus:=left(tipus,poz-1)
      endif
      if tipus=="multipart/form-data"
         ::nStatus:=2
         oPost:=tipmail():new()
         hibakod:=oPost:fromstring("CONTENT-TYPE: "+server["CONTENT_TYPE"]+e"\r\n\r\n"+::cRequest)
         if hibakod==0
            ::nErrorCode:=4 && adatformátum hiba
         else
            ::nErrorCode:=2 && nincs feltöltött file
            while oPost:GetAttachment() != NIL
               oPart:=oPost:nextAttachment()
               mezonev:=oPart:GetFieldOption("Content-Disposition","name")
               if mezonev=='"file"' .or. mezonev=='file'
                  ::cFileName:=oPart:GetFieldOption("Content-Disposition","filename")
                  if left(::cFileName,1)=='"' .and. right(::cFileName,1)=='"'
                     ::cFileName=substr(::cFileName,2,len(::cFileName)-2)
                  endif
                  if len(::cFileName)>0
                     ::cFileBody:=oPart:GetRawBody()
                     ::cFileBody:=substr(::cFileBody,1,len(::cFileBody)-2)
                     ::nErrorCode:=0
                     exit
                  else
                     ::nErrorCode:=3 && nem volt kijelölve file a feltöltéshez
                  endif
               endif
            enddo
         endif
      endif
   endif
return(Self)
METHOD KeyGen() CLASS WebSocket
   LOCAL rc
   if hb_blen(::cWebsocketKey)>0
      ::cKeyResponse:=hb_base64encode(hb_sha1(::cWebSocketKey+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11",.t.))
      rc:=.y.
   else
      rc:=.n.
   endif
return(rc)
METHOD WriteRaw(cBuffer) CLASS WebSocket
   LOCAL rc
   rc:=::oConnect:Write(cBuffer)
   ::nErrorCode:=rc
   if ::nErrorMode==1 .and. ::nErrorCode<0
      break(WebSocketError():New(::nErrorCode,"WebSocket írási hib!"))
   endif
return(rc)
METHOD WriteTextBlock(cBuffer) CLASS WebSocket
   LOCAL rc
   rc:=::WriteRaw(::CreateHead(1,hb_bLen(cBuffer))+cBuffer)
return(rc)
METHOD WriteBinBlock(cBuffer) CLASS WebSocket
   LOCAL rc
   rc:=::WriteRaw(::CreateHead(2,hb_bLen(cBuffer))+cBuffer)
return(rc)
METHOD ReadRaw(nLength,cBuffer,nTimeout) CLASS WebSocket
   LOCAL rc
   rc:=::oConnect:Read(@cBuffer,nLength,nTimeout)
   ::nErrorCode:=rc
   if ::nErrorMode==1 .and. ::nErrorCode<0
      break(WebSocketError():New(::nErrorCode,"WebSocket olvasási hib!"))
   endif
return(rc)
METHOD ReadBlock(cBlock,nTimeout) CLASS WebSocket
   LOCAL rc
   LOCAL lLast:=.n.
   LOCAL lMask
   LOCAL nLength
   LOCAL cBuffer:=""
   LOCAL cMask
   LOCAL k,l
   cBlock:=""
   while !lLast
      cBuffer:=space(2)
      rc:=::ReadRaw(2,@cBuffer,nTimeout)
      if rc#2
         return(rc)
      endif
      // The opcode (4 bits) indicates type of transferred frame: 
      //     text (1) or binary (2) for transferring application data or a control frame
      //     such as connection close (8), ping (9), and pong (10) for connection liveness checks. 
      lLast:=hb_bitAnd(hb_bpeek(cBuffer,1),0x80)>0
      ::nBlockType:=hb_bitAnd(hb_bpeek(cBuffer,1),0x0f)
      lMask:=hb_bitAnd(hb_bpeek(cBuffer,2),0x80)>0
      nLength:=hb_bitAnd(hb_bpeek(cBuffer,2),0x7f)
      if ::nBlockType==8
         ::nErrorCode:=-2
         if ::nErrorMode==1 .and. ::nErrorCode<0
            break(WebSocketError():New(::nErrorCode,"WebSocket lezárás kérése!"))
         endif
         return(::nErrorCode)
      else
         switch nLength
         case 126
            // 16 bites hossz
            cBuffer:=space(2)
            rc:=::ReadRaw(2,@cBuffer)
            if rc# 2
               return(rc)
            endif
            nLength:=hb_bpeek(cBuffer,1)*256+hb_bpeek(cBuffer,2)
            exit
         case 127
            // 64 bites hossz
            cBuffer:=space(2)
            rc:=::ReadRaw(8,@cBuffer)
            if rc# 8
               return(rc)
            endif
            nLength:=((hb_bpeek(cBuffer,1)*256+hb_bpeek(cBuffer,2))*256+hb_bpeek(cBuffer,3))*256+hb_bpeek(cBuffer,4)*256*256*256*256
            nLength+=((hb_bpeek(cBuffer,5)*256+hb_bpeek(cBuffer,6))*256+hb_bpeek(cBuffer,7))*256+hb_bpeek(cBuffer,8)
            exit
         otherwise
         endswitch
         if lMask
            cBuffer:=space(4)
            rc:=::ReadRaw(4,@cMask)
            if rc# 4
               return(rc)
            endif
         endif
         cBuffer:=space(nLength)
         rc:=::ReadRaw(nLength,@cBuffer)
         if rc#nLength
            return(rc)
         endif
         if lMask
            k:=1
            for l:=1 to nLength
               hb_bpoke(@cBuffer,l,hb_bitxor(hb_bpeek(cMask,k++),hb_bpeek(cBuffer,l)))
               if k>4
                  k:=1
               endif
            next
         endif
         cBlock+=cBuffer
      endif
      rc:=hb_bLen(cBlock)
   enddo
return(rc)
METHOD Status() CLASS WebSocket
   /*
        > 0 WebSocket kapcsolat felépült
        0 Nem Websocket kérés
       -1 Hiba kilépés
   */
return(::nStatus)
METHOD Response() CLASS WebSocket
return("")
METHOD ErrorMode(nMod) CLASS WebSocket
   if nMod#NIL
      ::nErrorMode:=nMod
   endif
return(::nErrorMode)
METHOD ErrorCode() CLASS WebSocket
   /*
        > 0 Érvényes művelet
        0 Timeout 
       -1 Hiba kilépés
   */
return(::nErrorCode)
METHOD CreateHead(nType,nLength,lLast,lMask) CLASS WebSocket
/*
   nType: 1 szöveg
          2 bináris
          8 close
          9 ping
         10 pong 
   lLast: logikai érték ha igaz ez az utolsó
   lMask: logikai érték ha igaz van Mask
*/
      //     text (1) or binary (2) for transferring application data or a control frame
      //     such as connection close (8), ping (9), and pong (10) for connection liveness checks. 
   LOCAL cHead:=""
   LOCAL nByte:=0,tbyte,k
   hb_default(@lLast, .y.)
   hb_default(@lMask, .n.)
   if  lLast
      nByte+=0x80 
   endif
   switch nType
   case 1
   case 2
   case 8
   case 9
   case 10
      nByte+=nType
      exit
   otherwise
      nByte+=8
      exit
   endswitch
   cHead+=hb_bchar(nByte)
   nByte:=0
   if  lMask
      nByte+=0x80
   endif
   if nLength>125
      if nLength>0xffff
         nByte+=127
         cHead+=hb_bchar(nByte)
         tbyte:={}
         for k:=1 to 8
            aadd(tbyte,hb_bchar(nLength%256))
            nLength:=int(nLength/256)
         next
         for k:=8 to 1 step -1
            cHead+=tbyte[k]
         next
      else
         nByte+=126
         cHead+=hb_bchar(nByte)
         cHead+=hb_bchar(int(nLength/256))
         cHead+=hb_bchar(nLength%256)
      endif
   else
      nByte+=nLength
      cHead+=hb_bchar(nByte)
   endif
return(cHead)
CLASS WebProtocol FROM WebSocket
      VAR   base64 INIT .y.
   PROTECTED:
      VAR   Respond
      VAR   jsonformat INIT .y.  // .y. human format .n. compact
   EXPORTED:
      METHOD Write(oMessage)
      METHOD New(oConnect, cRequest)
      METHOD PageWrite(cName,hPar)
      METHOD PageParse(cName,hPar)
      METHOD PutFields(hPar)
      METHOD SetFocus(cId)
      METHOD SetSelection(cId,nStart,nEnd)
      METHOD InsertHTML(cId,cHtml)
      METHOD OpenModal(cId)
      METHOD Set(cSearch,cName,CValue)
      METHOD SetStyle(cSearch,cName,CValue)
      METHOD CloseModal(cId)
      METHOD GetFields(nTimeout)
      METHOD WebRead(nTimeout,bTimeout)
      METHOD Timeout()
      METHOD Error()
      METHOD isCommand()
      METHOD Command()
      METHOD Parameter()
      METHOD isFiles()
      METHOD Files()
      METHOD isFields()
      METHOD isField(cName)
      METHOD Fields()
      METHOD FieldGet(cName,xVar,xDefault)
      METHOD Redirect(cLink)
      METHOD Inkeyon(cId)
      METHOD Inkeyoff(cId)
ENDCLASS
METHOD New(oConnect, cRequest) CLASS WebProtocol
   ::nError:=0
   ::Super:New(oConnect, cRequest)
return(Self)
METHOD Webread(nTimeout,bTimeout) CLASS WebProtocol
   while .y.
      ::Respond=::GetFields(nTimeout)
      if nTimeout#NIL .and. bTimeout#NIL .and. ::Timeout()
         ::Respond:=eval(bTimeout)
         if valtype(::Respond)=="H"
            exit
         endif
      else
         exit
      endif
   enddo
   if valtype(::Respond)#"H"
      ::Respond:=hb_hash()
   endif
RETURN(::Respond)
METHOD Write(oMessage) CLASS WebProtocol
   LOCAL rc:=""
   LOCAL cMessage
      if len(oMessage)>0
      cMessage:=hb_jsonEncode(oMessage,::jsonformat)
      if ::base64
         cMessage:=hb_jsonEncode({"base64" => hb_base64encode(cMessage) },::jsonformat)
// ?"1:",cMessage
//           cMessage:=hb_translate(cMessage,"UTF16LE","UTF8")
// ?"2:",cMessage
//           cMessage:=hb_translate(cMessage,"UTF8","UTF16LE")
// ?"3:",cMessage
      endif
      if ::WriteTextBlock(cMessage) <=0
         rc:=NIL
      endif
   endif
RETURN(rc)
METHOD Timeout() CLASS WebProtocol
RETURN ::Super:ErrorCode()==0
METHOD Error() CLASS WebProtocol
RETURN ::Super:ErrorCode()<0
METHOD PageWrite(cName, hPar) CLASS WebProtocol
   LOCAL rc
   rc:=::PageParse(cName,hPar)
   if rc#NIL
      return(::Write({"newpage" => rc}))
   endif
RETURN(rc)
METHOD PageParse(cName, hPar) CLASS WebProtocol
   LOCAL rc
   hb_default(@hPar,hb_hash())
   rc:=UParse(hPar,cName,httpd:hconfig)
RETURN(rc)
METHOD PutFields(hPar) CLASS WebProtocol
   hb_default(@hPar,hb_hash())
RETURN(::Write(hb_hash("ertek",hPar)))
METHOD SetFocus(cId) CLASS WebProtocol
RETURN(::Write({"focus" => {"id" => cId}}))
METHOD SetSelection(cId,nStart,nEnd) CLASS WebProtocol
RETURN(::Write({"select" => {"id" => cId, "start" => nStart, "end" => nEnd}}))
METHOD InsertHTML(cId,cHtml) CLASS WebProtocol
RETURN(::Write({"insert" => {"id" => cId, "html" => cHtml}}))
METHOD Set(cSearch,cName,CValue) CLASS WebProtocol
RETURN(::Write({"set" => { "search" => cSearch, "nev" => cName, "ertek" => cValue}}))
METHOD SetStyle(cSearch,cName,CValue) CLASS WebProtocol
RETURN(::Write({"setstyle" => { "search" => cSearch, "nev" => cName, "ertek" => cValue}}))
METHOD Inkeyon(cId) CLASS WebProtocol
local rc
   if ( cId==NIL )
      rc:={"inkey" => { "mode" => "windowadd"}}
   else
      rc:={"inkey" => { "mode" => "idadd", "id" => cId}}
   endif
RETURN(::Write(rc))
METHOD Inkeyoff(cId) CLASS WebProtocol
local rc
   if ( cId==NIL )
      rc:={"inkey" => { "mode" => "windowremove"}}
   else
      rc:={"inkey" => { "mode" => "idremove", "id" => cId}}
   endif
RETURN(::Write(rc))
METHOD OpenModal(cId) CLASS WebProtocol
   hb_default(@cId,"openModal")
RETURN(::Write({"href" => "#"+cId}))
METHOD CloseModal(cId) CLASS WebProtocol
   hb_default(@cId,"openModal")
RETURN(::Write({"href" => "#"}))
METHOD Redirect(cLink) CLASS WebProtocol
RETURN(::Write({"href" => cLink}))
METHOD GetFields(nTimeout) CLASS WebProtocol
   LOCAL rc
   LOCAL cValasz
   LOCAL nReadstatus
   cValasz:=""
   hb_default(@nTimeout,0)
   nReadstatus:=::ReadBlock(@cValasz,nTimeout)
   DO CASE
   CASE nReadstatus>0
      hb_JsonDecode(cValasz,@rc)
      if valtype(rc)#"H"
         rc:=hb_hash()         
      endif
   CASE nReadstatus==0
      // Timeout
      rc:=hb_hash()
   OTHERWISE
      // Hiba
   ENDCASE
RETURN(rc)   
METHOD isCommand() CLASS WebProtocol
RETURN(hb_HHasKey(::Respond,"command"))
METHOD Command() CLASS WebProtocol
   if ::isCommand()
      RETURN(hb_HGetDef(::Respond["command"],"comm",""))
   endif
RETURN("")
METHOD Parameter() CLASS WebProtocol
   if ::isCommand()
      RETURN(hb_HGetDef(::Respond["command"],"par",""))
   endif
RETURN("")
METHOD isFiles()  CLASS WebProtocol
hb_HHasKey(::Respond,"fileok")
RETURN(hb_HHasKey(::Respond,"fileok") )
METHOD Files()  CLASS WebProtocol
   if ::isFiles()
      RETURN(::Respond["fileok"])
   endif
RETURN({})
METHOD isFields()  CLASS WebProtocol
local rc:=.n.
   if hb_HHasKey(::Respond,"mezok")
      if len(::Respond["mezok"])>0
         rc:=.y.
      endif
   endif
RETURN(rc)
METHOD Fields()  CLASS WebProtocol
   if ::isFields()
      RETURN(::Respond["mezok"])
   endif
RETURN({=>})
METHOD isField(cName)  CLASS WebProtocol
local rc:=.n.
   if ::isFields()
      if hb_HHasKey(::Respond["mezok"],cName)
         rc:=.y.
      endif
   endif
RETURN(rc)
METHOD FieldGet(cName,xVar,xDefault)  CLASS WebProtocol
local rc:=.n.,xWork
   if ::isField(cName)
      xWork:=::Respond["mezok"][cName]
      switch valtype(xVar)
      case "N"
         xVar:=val(xWork)
         exit
      case "C"
      case "M"
      otherwise
         xVar:=xWork
         exit
      endswitch
   else
      if xDefault#NIL
         xVar:=xDefault
      endif
   endif
RETURN(rc)
