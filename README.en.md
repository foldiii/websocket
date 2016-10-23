# Harbour WebSocket support

A WebSocket connection establishes a direct communication channel between the
a page open in a web browser and an application thread running on the web
server.

WebSocket support is build upon the `hbhttpd` web server library.

Such connection enables direct data exchange between the application thread and
JavaScript code running inside the browser. The webpage will act as the display
and keyboard of the application, just as if it was a terminal. User interface
is only limited by the capabilities of HTML, supporting f.e. images or videos.
It is possible to change the page design, color scheme, logos and language
without touching the application code itself.

WebSocket will run on any hardware on any operating system as long as there
exist a web browser for it with WebSocket support.

To enable support in an application, add source file `wbs.prg` to your project.

## Objects in file `wbs.prg`:

### WebSocket

   Its job is to connect to the browser and handle the headers
   of the transferred data.

   * `New( oConnect, cRequest, bTrace )`

     Create an object and establish a connection.

   * `Status()`

     Return the status of the connection

     - 0 - Not a WebSocket request
     - 1 - WebSocket connection successfully established

   * `Socket()`

     Return TCP socket handle

   * `ErrorCode()`

     Return the error code of the last operation

   * `ErrorMode( nMod )`

     Set error handling mode

     - 0 - Error code can be queried with `ErrorCode()` function
     - 1 - On error execute `BREAK` with an `WebSocketError` object

   * `WriteRaw( cBuffer )`

     Send `cBuffer` to the WebSocket connection

   * `WriteTextBlock( cBuffer )`

     Assemble text mode header and send it using `WriteRaw()` function

   *  `WriteBinBlock( cBuffer )`

     Assemble binary mode header and send it using `WriteRaw()` function

     I've yet to see a browser that supports this one.

   * `ReadRaw( nLength, /* @ */ cBuffer, nTimeout )`

     Read number of bytes into `cBuffer`.

   * `ReadBlock( /* @ */ cBlock, nTimeout )`

     Read a WebSocket block.

### WebProtocol

   The protocol communicating with the `ws.js` JavaScript app.
   Child of the WebSocket object.

   * `New( oConnect, cRequest, bTrace )`

     Create an object and establish a connection.

   * `Write( xMessage )`

     Convert `xMessage` to a JSON object and send it to the JavaScript app.
     If `xMessage` is a string, send it as-is, without conversion.

   * `PageWrite( cName, hPar )`

     Pick template file named `cName` from the `tpl` directory, populate
     it with values passed in `hPar` and send it via `Write()` function.

   * `PageParse( cName, hPar )`

     Pick template file named `cName` from the `tpl` directory, populate
     it with values passed in `hPar` and return it as a string.

   * `PutFields( hPar )`

     Set values on the webpage with the `ID` - `value` pairs passed in
     hash `hPar`. Sets the `value` property for input and text HTML
     elements, and `innerHTML` for any other kind.

     ```xbase
        wbs:PutFields( { "id1" => 23, "id2" => "hello" } )
     ```

   * `InsertHTML( cId, cHTML )`

     Set `innerHTML` property of element `cId`.

   * `SetFocus( cId )`

     Give focus to element `cId`.

   * `SetSelection( cId, nStart, nEnd )`

     Select part of element `cId` from `nStart` to `nEnd`.

   * `Set( cSearch, cName, cValue )`

     Set property `cName` to `cValue` for elements with CSS selector
     value `cSearch`.

   * `SetStyle( cSearch, cName, cValue )`

     Set style element `cName` to `cValue` for elements with CSS selector
     value `cSearch`.

   * `GetFields( nTimeout )`

     Read a WebSocket block and return the result as a hash.
     In case of timeout, return an empty array.

   * `WebRead( nTimeout, bTimeout )`

     Wait for user input. Similar to Harbour's `READ` command.
     If `bTiemout` is not specified, return an empty hash after
     `nTimeout`. If `nTimeout` is 0 or not specified, wait
     indefinitely. If `bTimeout` contains a codeblock, call it
     each time `nTimeout` has passed. If the codeblock returned
     a hash value, forward it as-is.

   * `isTimeout()`

     Return .T. if the last I/O operation timed out.

   * `isError()`

     Return .T. if an I/O error occurred in the last operation.

   * `isCommand()`

     Return .T. if a keystroke is present in the data received.

   * `Command()`

     Return command associated with the button.

     ```html
     <button data-command="OK">OK</button>
     ```

     If the `type=submit` parameter is specified, return all input fields
     of the form. If there is no form, return all of the input fields
     instead.

     ```html
     <form>
       <input text id=content />
       <button type="submit" data-command="OK">OK</button>
     </form>
     ```

   * `Parameter()`

   Return parameter associated with the button.
   ```html
   <button data-command="skip" data-par="-1">Previous</button>
   ```

   * `isFiles()`

   Return .T. if there is a file uploaded.

   * `Files()`

     Return an array of hashes for each uploaded file, with the
     following elements:

     - name = file name
     - size = file size
     - data = file content with base64 encoding
     - id   = field ID

   * `isFields()`

     Return .T. if an input field exists.

   * `isField( cName )`

     Return .T., if a field exists with ID `cName`.

   * `Fields()`

     Return a hash containing `ID` - `value` pairs.

   * `FieldGet( cName, /* @ */ xVar, xDefault )`

     Return value of field `cName` in `xVar`. If there is no such
     field, return `xDefault`.

   * `Redirect( cLink )`

     Redirect current page to URL specified in `cLink`.

   * `InkeyOn( cId )`

     Enable sending keystrokes for element ID `cId`, if specified,
     or the whole page, if it's omitted.

   * `InkeyOff( cId )`

     Disable sending keystrokes.
