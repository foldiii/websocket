var socket;
function createSocket(host) {

      if (window.WebSocket)
         return new WebSocket(host);
      else if (window.MozWebSocket)
         return new MozWebSocket(host);

}
function hw_init()
{
//   var host = "ws://192.168.124.200:8085/hweb/konyvel";
//    var host = "ws://localhost:8085/hweb/konyvel";
   var host="ws://"+(document.location.hostname==""?"localhost":document.location.hostname)+ 
         ":"+(document.location.port== ""? "8080":document.location.port)+
         document.location.pathname;
//          "/hweb/konyvel";
      console.log('WebSocket cím: ' + host);
   try {
      socket = createSocket(host);
//       console.log('WebSocket - status ' + socket.readyState);
      socket.onopen = function(msg) {
//          console.log("Welcome - status " + this.readyState);
      };
//       socket.onmessage = hw_kiirat;
      
      socket.onmessage = function(msg) {
//          console.log("onmessage",msg);
//          alert("uzenet jott");
         hw_kiirat(msg);
      }
      
      socket.onclose = function(msg) {
//          console.log("Disconnected - status " + this.readyState);
      };
   }
   catch (ex) {
//       console.log(ex);
   }
   //$("msg").focus(); // az msg ID-jű mezőre állítja a fókuszt 
   var i,par
   var x = document.querySelectorAll("input[type='button']");
   for (i = 0; i < x.length; i++) {
      x[i].addEventListener("click", function(obj){
         var par
         var valasz
         valasz=new Object();
//          valasz={};
         valasz["command"]={};
         valasz["command"]["comm"]=obj.currentTarget.getAttribute("data-command");
         if ( obj.currentTarget.getAttribute("data-par") != null ) valasz["command"]["par"]=obj.currentTarget.getAttribute("data-par");
         if ( obj.currentTarget.getAttribute("data-submit") != null ) hw_jssubmit(valasz);
         hw_ir(valasz);
      } );
   }
}
function hw_ir(par)
{
   var msg;
//    msg="mezok:"+par; 
   msg=JSON.stringify(par,null, " ");
   console.log("hw_ir",msg);
   try {
      socket.send(msg);
//       console.log('Sent (' + msg.length + " bytes): " + msg);
   } catch (ex) {
//       console.log("Hiba a kuldesnel:",ex);
   }
}

function hw_kiirat(msg)
{
   var rc;
   var rc2;
   var elem;
   console.log(msg.data);
  try{
   var response = JSON.parse(msg.data);		
   if (typeof response.command !== "undefined") {
      if (typeof response.command.comm !== "undefined") {
         if (response.command.comm == "reset"){
            parent.location.reload(true);
            return;
         }
      }
   }
   if (typeof response.newpage !== "undefined") {
      //body.innerHtml:=response.newpage;
   }
   if (typeof response.ertek !== "undefined") {
      for(var i in response.ertek){
         rc2=hw_fugvenyek(i,response.ertek[i],response.ertek);
         if (rc2== true && document.getElementById(i)){
            elem=document.getElementById(i);
            var nodeName = elem.nodeName.toLowerCase ();
            var type = elem.type ? elem.type.toLowerCase () : "";
            nodeName=elem.nodeName.toLowerCase ()
            //    if (nodeName === "input" && (type === "checkbox" || type === "radio"))
            if (nodeName === "input" && type === "text" ) {
                  //alert(i+" "+nodename+" "+type);
                  elem.value=response.ertek[i];
            }else{
                  document.getElementById(i ).innerHTML = response.ertek[i];
            }
         }
      }
   }
      }
     catch(Exception){
      //   document.getElementById('toltes').innerHTML = "Hibás adatok.";
//                          console.log("Hibas adatok.");
   //                       console.log(request.responseText);
                      }
   //                 console.log("Státusz\n",rc);
}
function hw_fugvenyek(nev,ertek,adatok)
{
   var rc = true;
   var k;
   if ( typeof(ttomb) == "object" ){   
//      if ( typeof(ttomb[nev]) == "function" ){
//           rc=ttomb[nev](nev,ertek,adatok);
//      }
     for (k=0;k<ttomb.length;k++){
       if (typeof(ttomb[k][0])=="string"){
          if (ttomb[k][0]==nev){
            rc=ttomb[k][1](nev,ertek,adatok);
          } 
       }else{
          if (nev.match(ttomb[k][0])!=null){
            rc=ttomb[k][1](nev,ertek,adatok);
          } 
       }
     }
   }
   return(rc);
}
function hw_jssubmit(obj)
{
   var elemek = document.getElementsByClassName('mezo');
   var rc;
   hw_GetMessageBody(elemek,obj);
   return(obj);
}
function hw_GetMessageBody (elements,objpar) {
      var data = "";
      var obj;
      obj={};
      for (var i = 0; i < elements.length; i++) {
         var elem = elements[i];
         if (elem.name) {
            var nodeName = elem.nodeName.toLowerCase ();
            var type = elem.type ? elem.type.toLowerCase () : "";

                  // if an input:checked or input:radio is not checked, skip it
            if (nodeName === "input" && (type === "checkbox" || type === "radio")) {
                  if (!elem.checked) {
                     continue;
                  }
            }

                  // select element is special, if no value is specified the text must be sent
            if (nodeName === "select") {
                  for (var j = 0; j < elem.options.length; j++) {
                     var option = elem.options[j];
                     if (option.selected) {
                        var valueAttr = option.getAttributeNode ("value");
                        var value = (valueAttr && valueAttr.specified) ? option.value : option.text;
                        obj[elem.name]=value;
                     }
                  }
            }
            else {
                  obj[elem.name]=elem.value;
            }

         }
      }
      objpar["mezok"]=obj;
      return data;
}
window.addEventListener('load', hw_init, false);
