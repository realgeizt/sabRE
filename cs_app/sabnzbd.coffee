# dependencies
path = require 'path'
fs = require 'fs'
http = require 'http'
_ = require 'underscore'
async = require 'async'

# project dependencies
settings = require './settings'
logger = require './logger'
functions = require './functions'

if settings.useCurl
  exec = require('child_process').exec

class SABnzbd
  @addUserNZB = (username, nzbname) ->
    userNZBs = functions.getUserNZBs()
    userNZBs.push {user: username, nzb: nzbname, time: new Date().getTime()}
    functions.writeUserNZBs(userNZBs)
  @getNZBName = (name) ->
    nzbname = path.basename name
    nzbname = nzbname.replace(/[\/:*?"<>| ]/g, '_');
    if nzbname.length > 70
      nzbname = nzbname.substring 0, 70
    if _.endsWith nzbname.toLowerCase(), '.nzb'
      nzbname = nzbname.substring(0, nzbname.length - 4)
    if _.endsWith nzbname.toLowerCase(), '.par2'
      nzbname = nzbname.substring(0, nzbname.length - 5)
    return nzbname
  @getSabData = (type, cb) ->
    if type == 'queue'
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
      if r[0]? and r[1]? and r[0] != '' and r[1] != ''
        s = 'SABnzbd is running'
        s2 = 0
        if r[0].status == 'Paused'
          s = 'SABnzbd is paused'
          s2 = 1
      else
        s = 'SABnzbd is not running'
        s2 = 1
      run = r[0] != ''

      # modify sabnzbd data
      if r[0]?
        # adjust speed display
        if r[0].kbpersec > 1024
          r[0].speed = (r[0].kbpersec / 1024).toFixed(2) + ' MB/s'
        else
          r[0].speed = r[0].kbpersec + ' KB/s'

        if r[0].slots?
          # hide specific slots by name
          r[0].slots = _.filter r[0].slots, (s) -> !(_.find settings.sabHideQueue, (q) -> s.filename.substring(0, q.length) == q)
          # append responsible username to slot if needed
          if settings.hideOtherUsersData
            _.each r[0].slots, (s) ->
              s.user = _.find(userNZBs, (u) -> u.nzb is s.filename).user if _.find(userNZBs, (u) -> u.nzb is s.filename)?

      if r[1]? and r[1].slots?
        # only allow one item per name
        r[1].slots = _.uniq r[1].slots, (item) ->
          return item.name
        # append responsible username to slot if needed
        if settings.hideOtherUsersData
          _.each r[1].slots, (s) ->
            s.user = _.find(userNZBs, (u) -> u.nzb is s.name).user if _.find(userNZBs, (u) -> u.nzb is s.name)?

        # iterate every slot and adjust it's data so it is useful to the client
        r[1].slots = _.filter r[1].slots, (s) -> s.status != 'Completed' || (s.status == 'Completed' && fs.existsSync(settings.downloadDir + s.name + '.tar'))
        _.each r[1].slots, (s) ->
          s.actionpercent = -1
          try
            if s.status == 'Verifying'
              try
                done = parseInt s.action_line.split(' ')[1].split('/')[0]
                max = parseInt s.action_line.split(' ')[1].split('/')[1]
                s.actionpercent = parseInt (parseFloat(done) / max) * 100
              catch e
                s.actionpercent = -1
            if s.status == 'Repairing'
              try
                s.actionpercent = parseInt s.action_line.split(' ')[1].split('%')[0]
              catch e
                s.actionpercent = 0
            if s.status == 'Extracting'
              done = parseInt s.action_line.split(' ')[1].split('/')[0]
              max = parseInt s.action_line.split(' ')[1].split('/')[1]
              try
                s.actionpercent = parseInt (parseFloat(done) / max) * 100
              catch e
                s.actionpercent = 0
            if s.status == 'Running'
              data = fs.readFileSync(settings.postProcessProgressFile).toString().split('|')
              if data[0].toLowerCase() == 'rar'
                s.status = 'Extracting'
              else
                s.status = 'Building'
              s.actionpercent = parseInt data[1]
          if _.isNaN(s.actionpercent)
            s.actionpercent = -1

          s.filelist = []
          if fs.existsSync(settings.downloadDir + s.name + '.tar') and s.status == 'Completed'
            tc = functions.getTarContents()
            tc = _.filter tc, (asdf) -> asdf.filename == s.name + '.tar'
            if tc.length == 1
              s.filelist = tc[0].files

          s.filelist_short = _.first s.filelist, 5
          if s.filelist.length > s.filelist_short.length
            s.filelist_short.push '...'
          s.filelist_str = s.filelist.join ', '
          s.filelist_short_str = s.filelist_short.join ', '
          if s.filelist_str != ''
            s.filelist_str = s.filelist.length + ' File(s): ' + s.filelist_str
            s.filelist_short_str = s.filelist.length + ' File(s): ' + s.filelist_short_str

          if (s.status == 'Repairing' or s.status == 'Extracting' or s.status == 'Building' or s.status == 'Running') and s.actionpercent == -1
            s.status = 'Working'

          if fs.existsSync(settings.downloadDir + s.name + '.tar') and s.status != 'Failed'
            s.size = functions.filesize(fs.statSync(settings.downloadDir + s.name + '.tar')["size"]).toUpperCase()
          else if s.status == 'Failed'
            s.size = null

      cb {running: run, queue: r[0], history: r[1], status: s, statusint: s2}
  @queueNZBFile = (filename, cb) ->
    nzbname = @getNZBName filename

    sabReq = http.request {host: settings.sabHost, port: settings.sabPort, path: encodeURI('/api?mode=addlocalfile&name=' + filename + '&nzbname=' + nzbname + '&pp=3&script=postprocess.py&apikey=' + settings.sabApiKey)}, (response) ->
      str = ''
      response.on 'data', (data) ->
        str += data
      response.on 'end', () ->
        if str.trim() == 'ok'
          cb nzbname, true
        else
          cb nzbname, false
    sabReq.on 'error', (err) ->
      cb '', false
    sabReq.end()
  @queueNZBUrl = (url, cb) ->
    realQueueNZBLink = (url, cb) ->
      nzbname = SABnzbd.getNZBName url

      if nzbname.length > 5
        p = '/api?mode=addurl&name=' + url + '&nzbname=' + nzbname + '&pp=3&script=postprocess.py&apikey=' + settings.sabApiKey
      else
        p = '/api?mode=addurl&name=' + url + '&pp=1&script=postprocess.py&apikey=' + settings.sabApiKey

      sabReq = http.request {host: settings.sabHost, port: settings.sabPort, path: p}, (response) ->
        str = ''
        response.on 'data', (data) ->
          str += data
        response.on 'end', () ->
          if str.trim() == 'ok'
            cb nzbname, true
          else
            cb '', false
      sabReq.on 'error', (err) ->
        cb '', false
      sabReq.end()

    if settings.useCurl
      exec 'curl -k ' + url, {maxBuffer: 1024 * 1024 * 30}, (err, stdout, stderr) ->
        if err || stdout.trim() == ''
          return cb '', false
        realQueueNZBLink url, cb
    else
      realQueueNZBLink url, cb

module.exports = SABnzbd