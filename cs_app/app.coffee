try
# dependencies
  express = require 'express'
  path = require 'path'
  fs = require 'fs'
  http = require 'http'
  _ = require 'underscore'
  async = require 'async'
  mime = require 'mime'

  _.s = require 'underscore.string'
  _.mixin(_.s.exports())

  # project dependencies
  settings = require './settings'
  logger = require './logger'
  auth = require './auth'
  sabnzbd = require './sabnzbd'
  functions = require './functions'
catch e
  console.log 'an error occured starting the application (did you forget "npm install"?):\n' + e
  process.exit(1)

# initialize express
app = express()

# working data for status updates to clients
sabData = {queue: null, history: null}
speeds = []

# express config
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
  res.render 'index', {authRequired: settings.authRequired}

# authentication route
app.post '/login', auth.authUser, (req, res) ->
  res.json auth: true

# route to add a nzb by user-uploaded file to sabnzbd
app.post '/nzb', auth.authUser, (req, res) ->
  if req.body.flac2mp3? and (not _.isBoolean req.body.flac2mp3 or not settings.noFLAC2MP3)
    return res.send 500

  logger.info 'user "' + req.user + '" queued "' + req.body.nzbname + '"'

  filename = sabnzbd.getTempNZBName()
  nzbname = sabnzbd.getNZBName req.body.nzbname

  fs.writeFileSync filename, req.body.nzbdata

  sabnzbd.queueNZBFile filename, nzbname, req.user, (queueRes) ->
    fs.unlink filename
    if queueRes
      sabnzbd.addUserNZB req.user, nzbname, req.body.flac2mp3
      res.json nzb: true
    else
      res.send 500

# route to add a nzb by url to sabnzbd
app.post '/nzburl', auth.authUser, (req, res) ->
  if req.body.flac2mp3? and (not _.isBoolean req.body.flac2mp3 or not settings.noFLAC2MP3)
    return res.send 500

  logger.info 'user "' + req.user + '" queued URL "' + req.body.nzburl + '"'

  nzbname = sabnzbd.getNZBName req.body.nzburl

  sabnzbd.queueNZBUrl req.body.nzburl, nzbname, req.user, (queueRes) ->
    if queueRes
      sabnzbd.addUserNZB req.user, nzbname, req.body.flac2mp3
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
  data = functions.clone sabData
  data.noPostProcess = settings.noPostProcess
  data.noFLAC2MP3 = settings.noFLAC2MP3
  data.sabreDownloadsEnabled = settings.sabreDownloadsEnabled

  if data? and data.queue? and data.history?
    # if a user should only see data he enqueued, remove other data here
    if settings.hideOtherUsersData
      if data.queue.slots
        data.queue.slots = _.filter data.queue.slots, (s) -> s.user is req.user or s.user is '__:ALL:__'
      if data.history.slots
        data.history.slots = _.filter data.history.slots, (s) -> s.user is req.user

    # don't send everything to the client, only needed stuff
    data.queue = _.omit data.queue, _.keys(_.omit data.queue, 'slots', 'speed', 'diskspace1')
    if data.queue.slots?
      data.queue.slots = _.map data.queue.slots, (ss) ->
        return _.omit ss, _.keys(_.omit ss, 'status', 'filename', 'percentage', 'timeleft', 'size', 'sizeleft', 'user')
    data.history = _.omit data.history, _.keys(_.omit data.history, 'slots')
    if data.history.slots?
      data.history.slots = _.map data.history.slots, (ss) ->
        return _.omit ss, _.keys(_.omit ss, 'status', 'size', 'filelist', 'fail_message', 'name', 'actionpercent', 'extendedstatus', 'user', 'downloadable', 'downloads')

  res.json data

# route to download a file
if settings.authRequired and settings.downloadAuthRequired
  app.get '/downloads/:filename', auth.authUser, (req, res) ->
    return downloadFile req, res
else
  app.get '/downloads/:filename', (req, res) ->
    if req.body.user?
      req.user = req.body.user
    else
      req.user = 'anonymous'
    return downloadFile req, res

downloadFile = (req, res) ->
  if not settings.sabreDownloadsEnabled
    return res.send 404

  logger.info 'user "' + req.user + '" downloads "' + req.params.filename + '"'

  filename = path.resolve __dirname, settings.downloadDir + req.params.filename
  if not _.startsWith filename, settings.downloadDir
    return res.send 404

  if fs.existsSync filename
    ct = mime.lookup filename
    # we only allow .tar because that is what the postprocessing gives us
    if ct isnt 'application/x-tar'
      return res.send 404

    # for apache using mod-xsendfile
    #res.writeHead(200, {'X-Sendfile': settings.downloadDir + req.params.filename});
    #return res.end()

    # sending file without apache
    filesize = fs.statSync(filename)["size"]
    start = 0
    end = filesize - 1
    partial = false
    if req.headers? and req.headers.range?
      try
        range = req.headers.range.toLowerCase()
        if range.split('bytes=').length is 2
          partial = true
          range = _.map(_.filter(range.split('bytes=')[1].split('-'), (r) -> parseInt(r) and not _.isNaN(r)), (r) -> parseInt r)
          start = parseInt range[0] if range.length > 0
          end = parseInt range[1] if range.length > 1
      catch e
        return res.send 500

    speedObj = {res: res, startTime: new Date().getTime(), lastTime: new Date().getTime(), transferred: 0, speed: 0}
    speeds.push speedObj

    res.on 'close', () ->
      speeds = _.without speeds, speedObj

    res.on 'finish', () ->
      speeds = _.without speeds, speedObj
      logger.info 'user "' + req.user + '" finished download of "' + req.params.filename + '"'
      userNZBs = functions.getUserNZBs()
      nzb = _.find(userNZBs, (n) -> n.nzb + '.tar' is req.params.filename)
      if nzb
        if nzb.downloads?
          nzb.downloads += 1
        else
          nzb.downloads = 1
        functions.writeUserNZBs(userNZBs)

    if partial
      res.writeHead 206, { 'Content-Length': end - start + 1, 'Content-Range': 'bytes ' + start + '-' + end + '/' + filesize }
    else
      res.writeHead 200, { 'Content-Length': end - start + 1, 'Content-Range': 'bytes ' + start + '-' + end + '/' + filesize }

    stream = fs.createReadStream filename, { bufferSize: 64 * 1024, start: start, end: end }

    stream.on('data', (data) ->
      speedObj.lastTime = new Date().getTime()
      speedObj.transferred += data.length
      if speedObj.lastTime > speedObj.startTime + 1000
        speedObj.speed = speedObj.transferred / 1024
        speedObj.transferred = 0
        speedObj.startTime = speedObj.lastTime
    ).pipe res
  else
    res.send 404

if settings.loaded
  # start the server
  app.listen settings.port, '::', () =>
    logger.info 'server listening on port ' + settings.port
  .on 'error', (e) ->
    logger.error _.sprintf('could not listen on port %d, is it already in use?', settings.port)
    process.exit 1

  # load current data from sabnzb every second
  loadDataInterval = () ->
    setTimeout () ->
      sabnzbd.updateSabData (data) ->
        data.outSpeed = _.reduce speeds, (memo, s) ->
          memo += s.speed
        , 0
        if data.outSpeed >= 1024
          data.outSpeed = _.numberFormat((data.outSpeed / 1024), 2) + ' MB/s'
        else
          data.outSpeed = _.numberFormat(data.outSpeed, 2) + ' KB/s'

        sabData = data

        loadDataInterval()
    , 1000
  loadDataInterval()

  # cleanup passes, tarcontents and usernzbs
  setInterval () ->
    functions.writePasses _.filter(functions.getPasses(), (p) -> p.time > new Date().getTime() - 604800000)
    functions.writeTarContents _.filter(functions.getTarContents(), (c) -> fs.existsSync(settings.downloadDir + c.filename))
    if settings.downloadExpireDays > 0
      functions.writeUserNZBs _.filter(functions.getUserNZBs(), (n) -> n.time > new Date().getTime() - (settings.downloadExpireDays * 86400000))
  , 86400
else
  settings.setup()
