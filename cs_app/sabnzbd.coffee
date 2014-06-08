# configuration
settings = require '../settings/settings'

# dependencies
path = require 'path'
fs = require 'fs'
http = require 'http'
_ = require 'underscore'
async = require 'async'
if settings.useCurl
  exec = require('child_process').exec

# project dependencies
logger = require './logger'
functions = require './functions'

class SABnzbd
  @getNZBName = (name) ->
    nzbname = path.basename name
    if nzbname.length > 70
      nzbname = nzbname.substring 0, 70
    if nzbname.toLowerCase().endsWith('.nzb')
      nzbname = nzbname.substring(0, nzbname.length - 4)
    if nzbname.toLowerCase().endsWith('.par2')
      nzbname = nzbname.substring(0, nzbname.length - 5)
    return nzbname
  @getSabData = (type, cb) ->
    if type == 'queue'
      p = '/api?mode=queue&start=0&limit=0&output=json&apikey=' + settings.sabData.apiKey
    else
      p = '/api?mode=history&start=0&limit=0&output=json&apikey=' + settings.sabData.apiKey
    req = http.request {host: settings.sabData.host, port: settings.sabData.port, path: p}, (response) ->
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
          if d != ''
            cb null, JSON.parse(d).queue
          else
            cb 'err', '',
      (cb) ->
        SABnzbd.getSabData 'history', (d) ->
          if d != ''
            cb null, JSON.parse(d).history
          else
            cb 'err', ''
    ]
    async.parallel funcs, (e, r) ->
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

        # hide specific slots by name
        if r[0].slots?
          r[0].slots = _.filter r[0].slots, (s) -> !(_.find settings.sabHideQueue, (q) -> s.filename.substring(0, q.length) == q)

      if r[1]? and r[1].slots?
        # only allow one item per name
        r[1].slots = _.uniq r[1].slots, (item) ->
          return item.name

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

        # don't send everything to the client, only needed stuff
        if r[0]?
          r[0] = _.omit r[0], _.keys(_.omit r[0], 'slots', 'speed', 'diskspace1')
          if r[0].slots?
            r[0].slots = _.map r[0].slots, (ss) ->
              return _.omit ss, _.keys(_.omit ss, 'status', 'filename', 'percentage', 'timeleft', 'size', 'sizeleft')
        if r[1]?
          r[1] = _.omit r[1], _.keys(_.omit r[1], 'slots')
          if r[1].slots?
            r[1].slots = _.map r[1].slots, (ss) ->
              return _.omit ss, _.keys(_.omit ss, 'status', 'size', 'filelist_str', 'filelist_short_str', 'fail_message', 'name', 'actionpercent', 'extendedstatus')

      cb {running: run, queue: r[0], history: r[1], status: s, statusint: s2}
  @queueNZBFile = (filename, cb) ->
    nzbname = @getNZBName filename

    sabReq = http.request {host: settings.sabData.host, port: settings.sabData.port, path: '/api?mode=addlocalfile&name=' + filename + '&nzbname=' + nzbname + '&pp=3&script=postprocess.py&apikey=' + settings.sabData.apiKey}, (response) ->
      str = ''
      response.on 'data', (data) ->
        str += data
      response.on 'end', () ->
        if str.trim() == 'ok'
          cb true
        else
          cb false
    sabReq.on 'error', (err) ->
      cb false
    sabReq.end()
  @queueNZBUrl = (url, cb) ->
    realQueueNZBLink = (url, cb) ->
      nzbname = SABnzbd.getNZBName url

      if nzbname.length > 5
        p = '/api?mode=addurl&name=' + url + '&nzbname=' + nzbname + '&pp=3&script=postprocess.py&apikey=' + settings.sabData.apiKey
      else
        p = '/api?mode=addurl&name=' + url + '&pp=1&script=postprocess.py&apikey=' + settings.sabData.apiKey

      sabReq = http.request {host: settings.sabData.host, port: settings.sabData.port, path: p}, (response) ->
        str = ''
        response.on 'data', (data) ->
          str += data
        response.on 'end', () ->
          if str.trim() == 'ok'
            cb true
          else
            cb false
      sabReq.on 'error', (err) ->
        cb false
      sabReq.end()

    if settings.useCurl
      exec 'curl -k ' + url, {maxBuffer: 1024 * 1024 * 30}, (err, stdout, stderr) ->
        if err || stdout.trim() == ''
          return cb false
        realQueueNZBLink url, cb
    else
      realQueueNZBLink url, cb

module.exports = SABnzbd