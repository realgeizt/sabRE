# dependencies
path = require 'path'
fs = require 'fs'
http = require 'http'
_ = require 'underscore'
async = require 'async'
crypto = require 'crypto'
libxmljs = require 'libxmljs'
child_process = require 'child_process'
XRegExp = require('xregexp').XRegExp

# project dependencies
settings = require './settings'
logger = require './logger'
functions = require './functions'

class SABnzbd
  @getTempNZBName = () ->
    return settings.nzbUploadDir + 'nzb' + crypto.randomBytes(4).readUInt32LE(0) + '.nzb'
  @addUserNZB = (username, nzbname, flac2mp3) ->
    userNZBs = functions.getUserNZBs()
    userNZBs.push {user: username, nzb: nzbname, time: new Date().getTime(), flac2mp3: flac2mp3, downloads: 0}
    functions.writeUserNZBs(userNZBs)
  @getNZBName = (name) ->
    nzbname = path.basename name

    if _.endsWith nzbname.toLowerCase(), '.nzb'
      nzbname = nzbname.substring(0, nzbname.length - 4)
    if _.endsWith nzbname.toLowerCase(), '.par2'
      nzbname = nzbname.substring(0, nzbname.length - 5)

    nzbname = nzbname.replace(/[\/:*?"<>| ]/g, '_').trim()
    # "-" is included because otherwise postprocessing does not work as it should.
    # subprocess.popen won't quote the filename and when it starts with "-" tar
    # interprets it as arguments and fails...
    nzbname = nzbname.replace(/^[.\-_ ]+|[.\-_ ]+$/g, '')

    if nzbname.length > 70
      nzbname = nzbname.substring 0, 70

    if nzbname.length == 0
      nzbname = 'Download'

    append = ''
    userNZBs = functions.getUserNZBs()
    while _.find(userNZBs, (n) -> n.nzb is nzbname + append or n.nzb is nzbname + '.' + append)
      if append is ''
        append = 1
      else
        append += 1

    if append is ''
      return nzbname
    else
      return nzbname + '.' + append
  @getSabData = (type, cb) ->
    if type is 'queue'
      p = '/api?mode=queue&start=0&limit=0&output=json&apikey=' + settings.sabApiKey
    else
      p = '/api?mode=history&start=0&limit=0&output=json&apikey=' + settings.sabApiKey
    req = http.request {host: settings.sabHost, port: settings.sabPort, path: p}, (response) ->
      str = ''
      response.on 'data', (chunk) ->
        str += chunk
      response.on 'end', () ->
        cb str
    req.on 'error', (err) ->
      cb ''
    req.end()
  @updateSabData = (cb) ->
    funcs = [
      (cb) ->
        SABnzbd.getSabData 'queue', (d) ->
          try
            cb null, JSON.parse(d).queue
          catch e
            cb 'err', ''
      (cb) ->
        SABnzbd.getSabData 'history', (d) ->
          try
            cb null, JSON.parse(d).history
          catch e
            cb 'err', ''
    ]
    async.parallel funcs, (e, r) ->
      userNZBs = functions.getUserNZBs()
      # set general data
      if r[0]? and r[1]? and r[0] isnt '' and r[1] isnt ''
        s = 'SABnzbd is running'
        s2 = 0
        if r[0].status is 'Paused'
          s = 'SABnzbd is paused'
          s2 = 1
      else
        s = 'SABnzbd is not running'
        s2 = 1
      run = r[0] isnt ''

      # modify sabnzbd data
      if r[0]?
        # adjust speed display
        if r[0].kbpersec > 1024
          r[0].speed = (r[0].kbpersec / 1024).toFixed(2) + ' MB/s'
        else
          r[0].speed = r[0].kbpersec + ' KB/s'

        if r[0].slots?
          # hide specific slots by name
          r[0].slots = _.filter r[0].slots, (s) -> !(_.find settings.sabHideQueue, (q) -> s.filename.substring(0, q.length) is q)

          # change title of nzb's sabnzb tries to fetch
          r[0].slots = _.map r[0].slots, (s) ->
            regex = XRegExp(settings.sabNZBDownload, 'i')
            match = XRegExp.exec(s['filename'], regex)
            if not match?
              regex = XRegExp(settings.sabNZBDownloadWait, 'i')
              match = XRegExp.exec(s['filename'], regex)
            if match? and match.url? and match.sec?
              match.url = path.basename match.url if path.basename(match.url).length > 0
              s['filename'] = _.sprintf 'Trying to fetch (waiting %s seconds) "%s"', match.sec, path.basename match.url
              s.status = 'Fetching'
            else if match? and match.url?
              match.url = path.basename match.url if path.basename(match.url).length > 0
              s['filename'] = _.sprintf 'Trying to fetch "%s"', path.basename match.url
              s.status = 'Fetching'
            return s

          # append responsible username to slot if needed
          if settings.hideOtherUsersData
            _.each r[0].slots, (s) ->
              s.user = _.find(userNZBs, (u) -> u.nzb is s.filename).user if _.find(userNZBs, (u) -> u.nzb is s.filename)?
              if not s.user?
                s.user = '__:ALL:__'

      if r[1]? and r[1].slots?
        # only allow one item per name
        r[1].slots = _.uniq r[1].slots, (item) ->
          return item.name
        # append responsible username to slot if needed
        if settings.hideOtherUsersData
          _.each r[1].slots, (s) ->
            s.user = _.find(userNZBs, (u) -> u.nzb is s.name).user if _.find(userNZBs, (u) -> u.nzb is s.name)?

        # iterate every slot and adjust it's data so it is useful to the client
        r[1].slots = _.filter r[1].slots, (s) -> (s.status isnt 'Completed' || (s.status is 'Completed' && (settings.noPostProcess or fs.existsSync(settings.downloadDir + s.name + '.tar')))) and (settings.downloadExpireDays is 0 or (s.completed > (new Date().getTime() / 1000) - 86400 * settings.downloadExpireDays))
        _.each r[1].slots, (s) ->
          s.actionpercent = -1
          try
            if s.status is 'Verifying'
              try
                done = parseInt s.action_line.split(' ')[1].split('/')[0]
                max = parseInt s.action_line.split(' ')[1].split('/')[1]
                s.actionpercent = parseInt (parseFloat(done) / max) * 100
              catch e
                s.actionpercent = -1
            if s.status is 'Repairing'
              try
                s.actionpercent = parseInt s.action_line.split(' ')[1].split('%')[0]
              catch e
                s.actionpercent = 0
            if s.status is 'Extracting'
              done = parseInt s.action_line.split(' ')[1].split('/')[0]
              max = parseInt s.action_line.split(' ')[1].split('/')[1]
              try
                s.actionpercent = parseInt (parseFloat(done) / max) * 100
              catch e
                s.actionpercent = 0
            if s.status is 'Running'
              data = fs.readFileSync(settings.postProcessProgressFile).toString().split('|')
              if data[0].toLowerCase() is 'rar'
                s.status = 'Extracting'
              else
                s.status = 'Building'
              s.actionpercent = parseInt data[1]

          if _.isNaN(s.actionpercent)
            s.actionpercent = -1

          s.filelist = []
          s.nfolist = []
          if fs.existsSync(settings.downloadDir + s.name + '.tar') and s.status is 'Completed'
            tc = functions.getTarContents()
            tc = _.filter tc, (asdf) -> asdf.filename is s.name + '.tar'
            if tc.length is 1
              s.filelist = tc[0].files
              s.nfolist = tc[0].nfos
            s.downloadable = settings.sabreDownloadsEnabled
          else
            s.downloadable = false

          if (s.status is 'Repairing' or s.status is 'Extracting' or s.status is 'Building' or s.status is 'Running') and s.actionpercent is -1
            s.status = 'Working'

          nzb = _.find(userNZBs, (n) -> n.nzb is s.name)
          if nzb
            if nzb.downloads
              s.downloads = nzb.downloads
            else
              s.downloads = 0
          else
            s.downloads = 0

          if fs.existsSync(settings.downloadDir + s.name + '.tar') and s.status isnt 'Failed'
            s.size = functions.filesize(fs.statSync(settings.downloadDir + s.name + '.tar')["size"]).toUpperCase()
          else if s.status is 'Failed'
            s.size = null

        # remove failed items at the end of history
        while r[1].slots.length > 0 and r[1].slots[r[1].slots.length - 1].status is 'Failed'
          r[1].slots = _.without r[1].slots, r[1].slots[r[1].slots.length - 1]

      cb {running: run, queue: r[0], history: r[1], status: s, statusint: s2}
  @queueNZBFile = (filename, nzbname, username, cb) ->
    data = fs.readFileSync(filename)
    try
      libxmljs.parseXmlString data
    catch
      return cb false

    if settings.noPostProcess
      p = '/api?mode=addlocalfile&name=' + filename + '&nzbname=' + nzbname + '&cat=' + username + '&pp=3&apikey=' + settings.sabApiKey
    else
      p = '/api?mode=addlocalfile&name=' + filename + '&nzbname=' + nzbname + '&pp=1&script=sabre_postprocess.py&apikey=' + settings.sabApiKey

    sabReq = http.request {host: settings.sabHost, port: settings.sabPort, path: encodeURI(p)}, (response) ->
      str = ''
      response.on 'data', (data) ->
        str += data
      response.on 'end', () ->
        if str.trim() is 'ok'
          cb true
        else
          cb false
    sabReq.on 'error', (err) ->
      cb false
    sabReq.end()
  @queueNZBUrl = (url, nzbname, username, cb) ->
    realQueueNZBLink = (url, cb) ->
      if settings.noPostProcess
        p = '/api?mode=addurl&name=' + url + '&nzbname=' + nzbname + '&cat=' + username + '&pp=3&apikey=' + settings.sabApiKey
      else
        p = '/api?mode=addurl&name=' + url + '&nzbname=' + nzbname + '&pp=1&script=sabre_postprocess.py&apikey=' + settings.sabApiKey

      sabReq = http.request {host: settings.sabHost, port: settings.sabPort, path: encodeURI(p)}, (response) ->
        str = ''
        response.on 'data', (data) ->
          str += data
        response.on 'end', () ->
          if str.trim() is 'ok'
            cb true
          else
            cb false
      sabReq.on 'error', (err) ->
        cb false
      sabReq.end()

    if settings.useCurl
      filename = @getTempNZBName()
      child_process.execFile 'curl', ['-k', '-o', filename, url], {maxBuffer: 1024 * 1024 * 30}, (err, stdout, stderr) =>
        if err || not fs.existsSync filename || fs.statSync(filename)['size'] is 0
          return cb false

        @queueNZBFile filename, nzbname, username, (queueRes) ->
          fs.unlink filename
          return cb queueRes
    else
      realQueueNZBLink url, cb

module.exports = SABnzbd
