# configuration
settings = require '../settings/settings'

# dependencies
express = require 'express'
path = require 'path'
fs = require 'fs'
http = require 'http'
_ = require 'underscore'
async = require 'async'
mime = require 'mime'

# project dependencies
logger = require './logger'
auth = require './auth'
sabnzbd = require './sabnzbd'
functions = require './functions'

# initialize express
app = express()

# working data for status updates to clients
sabData = {queue: null, history: null}

# express config
app.set 'port', process.env.PORT or 3000
app.set 'view engine', 'jade'
app.use require('body-parser')({limit: 1024 * 1024 * 100})
app.use require('cookie-parser')()
app.use require('method-override')()
app.use express.static(path.join(__dirname, '../public'))

# locals
app.locals =
  title: 'sabRE'

# index route
app.get '/', (req, res) ->
  res.render 'index'

# authentication route
app.post '/login', auth.authUser, (req, res) ->
  res.json auth: true

# route to add a nzb by user-uploaded file to sabnzbd
app.post '/nzb', auth.authUser, (req, res) ->
  logger.info 'user "' + req.user + '" queued "' + req.body.nzbname + '"'

  filename = path.join(settings.nzbUploadDir + path.basename(req.body.nzbname))
  fs.writeFileSync filename, req.body.nzbdata

  sabnzbd.queueNZBFile filename, (queueRes) ->
    fs.unlink filename
    if queueRes
      res.json nzb: true
    else
      res.send 500

# route to add a nzb by url to sabnzbd
app.post '/nzburl', auth.authUser, (req, res) ->
  logger.info 'user "' + req.user + '" queued URL "' + req.body.nzburl + '"'

  sabnzbd.queueNZBUrl req.body.nzburl, (queueRes) ->
    if queueRes
      res.json nzb: true
    else
      res.send 500

# route to add a password for .rar files to extract
app.post '/nzbpass', auth.authUser, (req, res) ->
  logger.info 'user "' + req.user + '" added password "' + req.body.nzbpass + '"'

  if req.body.nzbpass? and req.body.nzbpass.length > 0
    req.body.nzbpass = req.body.nzbpass.trim()
    passes = functions.getPasses()
    if not _.find(passes, (p) -> return p.pass is req.body.nzbpass)
      passes.push {pass: req.body.nzbpass, time: new Date().getTime()}
      functions.writePasses(passes)
      res.json {}
    else
      res.send 500
  else
    res.send 500

# route to get current sabnzbd data
app.post '/sabdata', auth.authUser, (req, res) ->
  res.json sabData

# route to download a file
app.get '/downloads/:filename', auth.authUser, (req, res) ->
  logger.info 'user "' + req.user + '" downloads "' + req.params.filename + '"'
  
  if fs.existsSync(settings.downloadDir + req.params.filename)
    ct = mime.lookup(settings.downloadDir + req.params.filename)
    # we only allow .tar because that is what the postprocessing gives us
    if ct != 'application/x-tar'
      return res.send 404
    res.writeHead(200, {'X-Sendfile': settings.downloadDir + req.params.filename});
    res.end()
  else
    res.send 404

# load current data from sabnzb every second
loadDataInterval = () ->
  setTimeout () ->
    sabnzbd.updateSabData (data) ->
      sabData = data
      loadDataInterval()
  , 1000
loadDataInterval()

# cleanup passes and tarcontents
setInterval () ->
  functions.writePasses _.filter(functions.getPasses(), (p) -> p.time > new Date().getTime() - 604800000)
  functions.writeTarContents _.filter(functions.getTarContents(), (c) -> fs.existsSync(settings.downloadDir + c.filename))
, 86400

# start the server
app.listen app.get('port')
logger.info 'server listening on port ' + app.get('port')
