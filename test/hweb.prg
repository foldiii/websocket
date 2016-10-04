/*
 * $Id: h2.prg,v 1.5 2013-10-16 15:12:32 foldii Exp $
 */

/*
openssl genrsa -out privatekey.pem 2048
openssl req -new -subj "/C=LT/CN=mycompany.org/O=My Company" -key privatekey.pem -out certrequest.csr
openssl x509 -req -days 730 -in certrequest.csr -signkey privatekey.pem -out certificate.pem
openssl x509 -in certificate.pem -text -noout
*/
#include "fileio.ch"
#include "hbcom.ch"
#include "hbthread.ch"
#include "hbclass.ch"

#require "hbssl"
#require "hbhttpd"

// #define TRACE
#define TRUE .t.
#define FALSE .f.
#define CRLF (chr(13)+chr(10))
#define FILE_STOP ".hweb.stop"

// #define wbs Server["HTTP_EXTRAPROTOCOL"]


REQUEST __HBEXTERN__HBSSL__
REQUEST DBFCDX
REQUEST HB_GT_CGI_DEFAULT

MEMVAR server, get, post, cookie, session, wbs
PROCEDURE Main()
   LOCAL oServer
#ifdef TRACE
   LOCAL oLogAccess
#endif
   LOCAL oLogError
   LOCAL bLogAccess
   LOCAL bLogError
   LOCAL bTrace

   LOCAL nPort

   IF hb_argCheck( "help" )
      ? "Usage: app [options]"
      ? "Options:"
      ? "  //help               Print help"
      ? "  //stop               Stop running server"
      RETURN
   ENDIF

   IF hb_argCheck( "stop" )
      hb_MemoWrit( FILE_STOP, "" )
      RETURN
   ELSE
      FErase( FILE_STOP )
   ENDIF
*   IF hb_argCheck( "test" )
*      test:=.y.
*   ENDIF

   Set( _SET_DATEFORMAT, "yyyy-mm-dd" )

   rddSetDefault( "DBFCDX" )

#ifdef TRACE
   bTrace:= {| ... | QOut( ... ) }
   oLogAccess := UHttpdLog():New( "log/hweb_access.log" )
   IF ! oLogAccess:Add( "" )
      oLogAccess:Close()
      ? "Access log file open error " + hb_ntos( FError() )
      RETURN
   ENDIF
   bLogAccess:= {| m | oLogAccess:Add( m + hb_eol() ) }
#else
   bLogAccess:= {|| NIL }
   bTrace:= {|| NIL }
#endif

   oLogError := UHttpdLog():New( "log/hweb_error.log" )
   IF ! oLogError:Add( "" )
      oLogError:Close()
#ifdef TRACE
      oLogAccess:Close()
#endif
      ? "Error log file open error " + hb_ntos( FError() )
      RETURN
   ENDIF
   bLogError:= {| m | oLogError:Add( m + hb_eol() ) }
   nPort := 8085
   ? "Listening on port:", nPort

   oServer := UHttpdNew()
//         "Idle"                => {| o | sessiontorol(o), iif( hb_FileExists( FILE_STOP ), ( FErase( FILE_STOP ), o:Stop() ), NIL ) }, ;
   TraceLog( bTrace )
   IF ! oServer:Run( { ;
         "FirewallFilter"      => "", ;
         "LogAccess"           => bLogAccess,;
         "LogError"            => bLogError, ;
         "Port"                => nPort, ;
         "Trace"               => bTrace, ;
         "Idle"                => {| o | iif( hb_FileExists( FILE_STOP ), ( FErase( FILE_STOP ), o:Stop() ), NIL ) }, ;
         "PrivateKeyFilename"  => "private.key", ;
         "CertificateFilename" => "certificate.crt", ;
         "SSL"                 => .F., ;
         "RequestFilter"       => {|oConnect, cRequest| websocketcall(oConnect,cRequest, bTrace) }, ;
         "SocketReuse"         => .T.,;
         "Mount"          => { ;
         "/hello"            => {|| UWrite( "Hello!" ) }, ;
         "/info"             => {|| UProcInfo() }, ;
         "/files/*"          => {| x | UProcFiles( hb_DirBase() + "files/" + X, .F. ) }, ;
         "/echo"             => @wbsocket_echo(), ;
         "/filefeltolt"      => @proc_filefel(), ;
         "/hwebx"             => @proc_hweb(), ;
         "/hweb"             => @konyvel(), ;
         "/hweb/*"           => @proc_hwebnincs(), ;
         "/hweb/konyvel"     => @konyvel(), ;
         "/"                 => {|| URedirect( "/hweb" ) } } } )

      *
      *  core.prg 711. sor
      *    eredeit:
      *            UWrite( UParse( xRet) )
      *    új:
      *            UWrite( UParse( xRet,,oServer:hConfig ) )
      *  core.prg 144. sor
      *     hb_socketsetreuseaddr(Self:hListen,TRUE)
      *
      *  uhttpd objectben  a hSession vátozót átteni az exported
      *     változók közé
      oLogError:Close()
#ifdef TRACE
      oLogAccess:Close()
#endif
      ? "Server error:", oServer:cError
      ErrorLevel( 1 )
      RETURN
   ENDIF

   oLogError:Close()
#ifdef TRACE
   oLogAccess:Close()
#endif
   ?
RETURN
function websocketcall(oConnect, cRequest, bTrace)
Local rc:=NIL
   public wbs
   wbs:=WebProtocol():New(oConnect, cRequest, bTrace) 
   if wbs:Status()#0
      rc:=""
   endif
return(rc)
function kiirat(nev,adat,szint)
local soreleje:="",k,sor
  if szint==NIL
     szint:=0
  else
     soreleje:=space(3*szint)
  endif
  sor:=""
  switch(valtype(adat))
  case "C"
     sor+=soreleje+" "+nev+" "+adat+hb_eol()
     exit
  case "N"
     sor+=soreleje+" "+nev+" "+str(adat)+hb_eol()
     exit
  case "L"
     sor+=soreleje+" "+nev+" "+if(adat,'I','N')+hb_eol()
     exit
  case "D"
     sor+=soreleje+" "+nev+" "+dtoc(adat)+hb_eol()
     exit
  case "A"
     sor+=soreleje+" "+nev+" tomb"+hb_eol()
     for k:=1 to len(adat)
        sor+=kiirat(str(k,3),adat[k],szint+1)
     next
     exit
  case "H"
     sor+=soreleje+" "+nev+" hash"+hb_eol()
     for each k in adat:keys
        sor+=kiirat(k,adat[k],szint+1)
     next
     exit
  otherwise
     sor+=soreleje+" "+nev+" ismeretlen tipus:"+valtype(adat)+hb_eol() 
  end
RETURN sor
//#command NAGYHIBA <szam> [<mezok,...>]=> hibat_ir(112,<szam>,,{<"mezok">},{<mezok>}) ; quit
// #command <obj> WEBSAY <mezo> TO <nev> => <obj>:PutFields({<"nev"> => <mezo>}) 
#command <obj> WEBSAY <mezo> TO <nev> => <obj>:PutFields({<(nev)> => <mezo>}) 
#command <obj> WEBREAD <par> TIMEOUT <ido> => <par>:=<obj>:GetFields(<ido>) 
static function konyvel(path)
local par,ciklus:=0,k,muvelet,mpar,mnev,poz,kiirat
local sor,Hcommand
   HB_SYMBOL_UNUSED(path)
   ?"szal elindult:"
   // dbUseArea( [<lNewArea>], [<cDriver>], <cName>, [<xcAlias>],
   //            [<lShared>], [<lReadonly>]) --> NIL
   *altd()
   if __mvScope( "wbs" )#1
      RETURN  PageParse("konyvel")
   else      
       if wbs:Status()==0
         RETURN  PageParse("konyvel")
      endif
   endif
   dbUseArea( .T., , "ugyfel", "ugyfel", .T., .F. )
   ordSetFocus( "rnev" )
   dbgotop()
/*   
   if wbs:PageWrite("hwebl")==nil
      RETURN NIL
   endif
   */
   kiirat:=.y.
   while .y.
      if kiirat
         wbs WEBSAY str(ciklus) TO ciklus
         for k:=1 to fcount()
            wbs WEBSAY alltrim(fieldget(k)) TO (lower(fieldname(k)))
//             ?lower(fieldname(k))+"=",alltrim(fieldget(k))
         next
         wbs WEBSAY "Rekord:"+str(ciklus) TO time
      endif
//          par:=wbs:WebRead(2)
      par:=wbs:WebRead()
      if wbs:Error()
        ?"Error miatt kilép"
         exit
      endif
      ciklus++
      if wbs:Timeout()
         wbs WEBSAY Dtoc(date()) TO date
         wbs WEBSAY time()+" Ciklus:"+str(ciklus) TO time
         kiirat:=.n.
      else
//          altd()
         ?"valtype:",valtype(par)
         sor:="============================"+hb_eol()
         sor+=kiirat( "par",par )
         ?sor
         kiirat:=.y.
         if (hCommand:=hb_HGetDef(par,"command",NIL))#NIL
            muvelet:=hb_HGetDef(hCommand,"comm","*")
            mpar:=hb_HGetDef(hCommand,"par","")
            ?"muvelet:"+muvelet+"<="
            do case
            case muvelet=="skip"
               mpar:=val(mpar)
               dbskip(mpar)
            case muvelet=="gotop"
               dbgotop()
            case muvelet=="gobottom"
               dbgobottom()
            case muvelet=="append"
               if hb_HHasKey(par,"mezok")
                  dbappend()
                  for each mnev in par["mezok"]:keys
                     poz=fieldpos(mnev)
                     if poz>0
                        fieldput(poz,par["mezok"][mnev])
                     endif
                  next
                  dbunlock()
               endif
            case muvelet=="clear"
               for k:=1 to fcount()
                  wbs WEBSAY "" TO (lower(fieldname(k)))
               next
               kiirat:=.n.
            case muvelet=="replace"
               ?"replace"
               if hb_HHasKey(par,"mezok")
                  while !dbrlock()
                  enddo
                  for each mnev in par["mezok"]:keys
                     poz=fieldpos(mnev)
                     ?mnev,poz
                     if poz>0
                        fieldput(poz,par["mezok"][mnev])
                     endif
                  next
                  dbunlock()
               endif
            case muvelet=="kilepes"
               exit
            otherwise
               kiirat:=.n. 
            endcase
         endif
      endif
   enddo
   dbcloseall()
   ?"szal lealt:",path
RETURN NIL
STATIC FUNCTION proc_hweb()
/*
   *local sor:=""

   sor+="============================"+hb_eol()
   sor+=kiirat( "server",server )
   sor+="============================"+hb_eol()
   sor+=kiirat( "get",get )
   sor+="============================"+hb_eol()
   sor+=kiirat( "post",post )
   sor+="============================"+hb_eol()
   sor+=kiirat( "cookie",cookie)
   sor+="============================"+hb_eol()
   sor+=kiirat( "session",session)
   ?sor
*/
RETURN { => }
STATIC FUNCTION proc_hwebnincs(path)
/*
   *local sor:=""

   sor+="============================"+hb_eol()
   sor+=kiirat( "server",server )
   sor+="============================"+hb_eol()
   sor+=kiirat( "get",get )
   sor+="============================"+hb_eol()
   sor+=kiirat( "post",post )
   sor+="============================"+hb_eol()
   sor+=kiirat( "cookie",cookie)
   sor+="============================"+hb_eol()
   sor+=kiirat( "session",session)
   ?sor
*/
?"webnincs"
RETURN PageParse("hwebnincs",{"time" => time(),"path" => path})
STATIC FUNCTION wbsocket_echo(path)
local buff
local sor,db,rc,fut:=.y.
   HB_SYMBOL_UNUSED(path)
   db:=1
   if wbs#NIL
      buff:=space(1)
      while fut
         rc:=wbs:ReadBlock(@buff) 
         if rc<=0
            exit
         endif
         sor:="sorszam:"+alltrim(str(db++))+" "+buff
         wbs:WriteTextBlock(sor) 
//          wbs:WriteBinBlock(sor) 
      enddo
   endif
return("")
STATIC FUNCTION proc_filefel(path)
local buff,fh
local rc,fut:=.y.
   HB_SYMBOL_UNUSED(path)
   if wbs#NIL
      buff:=space(1)
      while fut
         rc:=wbs:ReadBlock(@buff) 
         if rc<=0
            exit
         endif
         ?"rc:",rc
         fh:=fcreate("feltoltve")
         fwrite(fh,hb_base64Decode(buff))
         fclose(fh)
//          sor:="sorszam:"+alltrim(str(db++))+" "+buff
//          wbs:WriteTextBlock(sor) 
//          wbs:WriteBinBlock(sor) 
      enddo
   endif
return("")
function HB_ISEVALINFO()
return(.y.)
procedure prockiir()
local n
   n:=1
   do while ! empty(procname(n))
      ?"===============",procname(n),procline(n++)
   enddo
return
