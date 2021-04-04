import os
import parseopt
import times
import strformat
import asynchttpserver
import asyncdispatch
import strutils
import mimetypes

proc main {.async.} =
  var dir: string

  # defaults
  var port = 8080

  # parse cli args
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key == "port":
        port = strutils.parseInt(p.val)
    of cmdArgument:
      echo "Target: ", p.key
      dir = p.key

  doAssert dir.len > 0
    
  # make sure we have a folder to work with - from cli args, or mk tmp one
  var absDir = absolutePath(dir)
  var created = false
  if absDir.len > 0:
    if dirExists(absDir):
      echo absDir & " is a pre-existing folder, lookinf for index.html file..."
    else:
      echo absDir & " folder does not exist, creating..."
      createDir(absDir)
      created = true
  else:
    absDir = absolutePath(getTempDir() & "/dev-reload-" & $getTime().toUnix())
    echo "No dir specified; creating a temp one: ", absDir
    createDir(absDir)
    created = true

  # ensure required files exist - index.html
  # TODO index.js, style.css
  if not created: # pre-existing folder
    for kind, path in walkDir(absDir):
      echo(path)
  else:
    echo "creating index.html..."

    # TODO: this is not great - the html file template should be a separate file, but:
    # - this is too unstable to make a package yet
    # - even when it is a package, how do you get the current script's folder ?
    let html = fmt"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>dev-reload ({absDir})</title>
</head>
<body>
</body>
</html>
    """
    writeFile(absDir & "/index.html", html)

  # TODO inject links to js & css files

  # TODO watch folder for changes - html, js, css
  # TODO watch folder for changes - svg

  # TODO js runtime listening to server events (SSE, websockets ?)

  # http server for static files
  var server = newAsyncHttpServer()
  var mimeTypes = newMimetypes()
  proc requestCallback(req: Request) {.async.} =
    let absFilePath = absolutePath("./" & req.url.path)
    if fileExists(absFilePath):
      
      # TODO sim slowness
      # TODO sim errors

      # headers
      # TODO more headers - etag, last-modified
      let (_, _, ext) = splitFile(absFilePath)
      let mimeType = mimeTypes.getMimetype(ext)
      var headers = newHttpHeaders()
      if mimeType.startsWith("text/"):
        headers["Content-type"] = fmt"{mimeType}; charset=utf-8"
      else:
        headers["Content-type"] = mimeType
      
      # server log
      echo 200, " ", req.reqMethod, " ", req.url.path, fmt" ({absFilePath})"

      # 200 response
      await req.respond(Http200, readFile(absFilePath), headers)
    else:
      echo 404, " ", req.reqMethod, " ", req.url.path
      await req.respond(Http404, "Not found!")
  
  # start server & listen for requests
  server.listen Port(port)
  echo "listening on ", port, "..."
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(requestCallback)
    else:
      await sleepAsync(500)

when isMainModule:
  asyncCheck main()
  runForever()
