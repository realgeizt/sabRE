# dependencies
fs = require 'fs'
path = require 'path'
http = require 'http'
readline = require 'readline'
ini = require 'node-ini'
async = require 'async'
_ = require 'underscore'

class Settings
  # some variables...
  @loaded = false
  @error = false
  @loadedKeys = []
  @filename = path.resolve(__dirname, '../data/settings.json')
  @sabConfigFile = (process.env.HOME or process.env.HOMEPATH or process.env.USERPROFILE) + '/.sabnzbd/sabnzbd.ini'
  @sabConfigData = null

  # the template for the config file
  @configSchema = [
    # stuff needed to access SABnzbd's api for stage 2
    { stage: 1, name: 'sabHost', desc: 'host/ip where SABnzbd is running on.', default: '127.0.0.1', type: 'string' }
    { stage: 1, name: 'sabPort', desc: 'port where SABnzbd is listening on.', default: 8080, type: 'int', inisec: 'misc', ininame: 'port' }
    { stage: 1, name: 'sabApiKey', desc: 'the api key of SABnzbd.', default: '', type: 'string', inisec: 'misc', ininame: 'api_key' }

    # configuration of sabRE
    { stage: 2, name: 'port', desc: 'the port sabRE listens on.', default: 3000, type: 'int' }
    { stage: 2, name: 'useCurl', desc: 'check urls with curl before enqueueing to SABnzbd?', default: false, type: 'bool' }
    { stage: 2, name: 'hideOtherUsersData', desc: 'when enabled, users can only see stuff they enqueued. files from other users are hidden.', default: false, type: 'bool' }
    { stage: 2, name: 'noPostProcess', desc: 'when this is enabled no postprocessing (creation of tar archive) will take place. instead sabRE tries to set the category of the download to the currently logged in user\'s name so you can set up shares on the server to let users download the files directly. when enabling this, don\'t forget to configure categories in SABnzbd, one for each user. otherwise files will be downloaded to the regular download dir without placing them in separate directories for each user. enabled postprocessing requires sabRE to run on the same machine as SABnzbd.', default: false, type: 'bool' }
    { stage: 2, name: 'logFile', desc: 'file where sabRE logs into.', default: '../data/log.json', type: 'file', mustExist: false, wizardEnabled: false }
    { stage: 2, name: 'userFile', desc: 'sabRE\'s user/password "database".', default: '../data/users.json', type: 'file', wizardEnabled: false }
    { stage: 2, name: 'nzbUploadDir', desc: 'directory where uploaded .nzb files will be stored. files will be deleted after they have been enqueued.', default: '/tmp/', type: 'dir' }
    { stage: 2, name: 'postProcessProgressFile', desc: 'temporary file used for communication between postprocessing script and sabRE. must point to the same file as PROGRESS_FILE in settings.py from the postprocessor.', default: '/tmp/sabre_postprocessprogress', type: 'file', mustExist: false, wizardEnabled: false }
    { stage: 2, name: 'postProcessPasswordsFile', desc: 'sabRE\'s password database (NOT SABnzb\'s) to extract passworded rar files. must point to the same file as PASSWORDS_FILE in settings.py from the postprocessor.', default: '../data/passes.json', type: 'file', mustExist: false, wizardEnabled: false }
    { stage: 2, name: 'tarContentsFile', desc: 'file that stores contents of .tar files created by postprocessing so the contents of files can be displayed in sabRE. must point to the same file as TAR_CONTENTS_FILE in settings.py from the postprocessor.', default: '../data/tarcontents.json', type: 'file', mustExist: false, wizardEnabled: false }
    { stage: 2, name: 'userNZBsFile', desc: 'file that associates user accounts with downloaded nzbs. this file is important when every user should only see his own enqueued files (hideOtherUsersData == true).', default: '../data/usernzbs.json', type: 'file', mustExist: false, wizardEnabled: false }
    { stage: 2, name: 'sabHideQueue', default: ['Trying to fetch', ], type: 'list', wizardEnabled: false }
    { stage: 2, name: 'remoteAuthEnabled', 'desc': 'make use of user authentication using a remote url?', default: false, type: 'bool' }
    { stage: 2, name: 'remoteAuthHost', desc: 'host where remote authentication is running.', default: '127.0.0.1', type: 'string' }
    { stage: 2, name: 'remoteAuthPort', desc: 'port where remote authentication is listening on.', default: 80, type: 'int' }
    { stage: 2, name: 'remoteAuthPath', desc: 'path for the url to the remote authentication.', default: '/remoteauth/', type: 'string' }

    # SABnzbd's configuration
    { stage: 2, name: 'downloadDir', desc: 'must have same value as "Completed Download Folder" in SABnzbd\'s configuration.', type: 'dir' }
    { stage: 2, name: 'scriptDir', desc: 'must have same value as "Post-Processing Scripts Folder" in SABnzbd\'s configuration.', type: 'dir', maybeNull: true }
  ]

  # appends a slash to a path if it doesn't exist
  @appendTrailingSlash = (str) ->
    if not _.endsWith str, '/'
      return str += '/'
    return str
  # undefine previously loaded settings
  @resetSettings = ->
    for k in @loadedKeys
      @[k] = undefined
    for s in @configSchema
      s.loadedFromSABnzbd = undefined
    @loadedKeys = []
  # try to load settings from configuration file
  @loadSettings = ->
    @loaded = false
    @error = false

    if not fs.existsSync @filename
      return

    try
      @resetSettings()

      data = JSON.parse fs.readFileSync(@filename, 'utf8')

      for s in @configSchema
        val = data[s.name]
        # if it's a path modify it
        if s.type is 'file' or s.type is 'dir'
          val = path.resolve __dirname, val
        if s.type is 'dir'
          val = @appendTrailingSlash val
        if @validateField val, s
          @[s.name] = val
          @loadedKeys.push s.name
        else
          throw _.sprintf 'setting "%s" with value "%s" is invalid', s.name, val
      if not @validateSettings()
        throw 'could not validate settings'
      @loaded = true
    catch e
      @resetSettings()
      @error = true
      @errorMsg = e
  # save settings to configuration file
  @saveSettings = ->
    try
      obj = {}
      for c in @configSchema
        obj[c.name] = @[c.name]
      fs.writeFileSync @filename, JSON.stringify(obj, undefined, 2)
      return true
    return false
  # convert a value from string to type defined by field
  @convertField = (value, field) ->
    return null if not value? or value.toString().length is 0

    switch field.type
      when 'file', 'dir', 'string'
        return value
      when 'int'
        return parseInt value
      when 'bool'
        if value.toLowerCase() is 'true' or value.toLowerCase() is '1' then return true
        if value.toLowerCase() is 'false' or value.toLowerCase() is '0' then return true
      when 'list'
        throw 'not implemented'
    return null
  # validate the value of a field
  @validateField = (value, field) ->
    if (not value?) and field.maybeNull? and field.maybeNull
      return true
    return false if not value?

    switch field.type
      when 'file', 'dir'
        if not _.isString(value) or value.length is 0
          return false
        if not field.mustExist? or (field.mustExist? and field.mustExist)
          return fs.existsSync path.resolve(__dirname, value)
        else
          return _.isString(value) and value.length > 0
      when 'string'
        return _.isString(value) and value.length > 0
      when 'int'
        return _.isNumber(value) and not _.isNaN(value) and value % 1 is 0
      when 'bool'
        return _.isBoolean(value)
      when 'list'
        return true
    return false
  # validates all possible fields
  @validateSettings = (stage) ->
    for s in _.filter(@configSchema, (s) -> s.stage is stage)
      if not @validateField @[s.name], s
        console.log @[s.name]
        console.log s.name
        process.exit 1
        return false
    return true
  # imports some settings from sabnzbd.ini
  @assignSABConfigFile = ->
    return if not @sabConfigData?

    console.log @adjustText('reading configuration from sabnzbd.ini...')

    for field in @configSchema
      if field.inisec? and field.ininame? and @sabConfigData[field.inisec]? and @sabConfigData[field.inisec][field.ininame]?
        convertedValue = @convertField @sabConfigData[field.inisec][field.ininame], field
        if @validateField convertedValue, field
          @[field.name] = convertedValue
          field.loadedFromSABnzbd = true
          console.log _.sprintf('  set "%s" to "%s"', field.name, @[field.name])
  # retrieves data using http
  @getURL = (host, port, path, cb) =>
    req = http.request {host: host, port: port, path: path}, (response) ->
      str = ''
      response.on 'data', (chunk) ->
        str += chunk
      response.on 'end', () ->
        cb str
    req.on 'error', (err) ->
      cb ''
    req.end()
  # loads configuration data by using SABnzbd's api
  @assignSABConfigAPI = (cb) =>
    console.log @adjustText('reading configuration from SABnzbd using it\'s api...')

    funcs = [
      (cbx) =>
        return @getURL @sabHost, @sabPort, _.sprintf('/sabnzbd/api?mode=get_config&apikey=%s', @sabApiKey), (data) =>
          try
            data = JSON.parse(data.replace /\'/gi, '"')
            cbx null, data.misc
          catch e
            cbx null
      (cbx) =>
        return @getURL @sabHost, @sabPort, _.sprintf('/api?mode=queue&start=0&limit=0&output=json&apikey=%s', @sabApiKey), (data) =>
          try
            data = JSON.parse data
            cbx null, data.queue
          catch e
            cbx null
    ]

    async.series funcs, (err, res) =>
      if (not res[0]) or (not res[1])
        console.log @adjustText('\ni could not get the configuration from SABnzbd. maybe host/port/apikey are incorrect? is SABnzbd running?')
        process.exit 1

      field = _.find @configSchema, (s) -> s.name is 'scriptDir'
      try
        if res[0].script_dir? and res[0].script_dir isnt ''
          sDir = @appendTrailingSlash(path.resolve(res[1].my_home, res[0].script_dir))
          if @validateField sDir, field
            @scriptDir = sDir
            if field.type is 'dir' and (not _.endsWith @scriptDir, '/')
              @scriptDir += '/'
            field.loadedFromSABnzbd = true
            console.log _.sprintf('  set "scriptDir" to "%s"', @scriptDir)
      catch e
        sDir = null

      try
        dlDir = @appendTrailingSlash(path.resolve(res[1].my_home, res[0].complete_dir))
      catch e
        console.log @adjustText('\ni could not get the configuration from SABnzbd. maybe host/port/apikey are incorrect? is SABnzbd running?')
        process.exit 1

      field = _.find @configSchema, (s) -> s.name is 'downloadDir'
      if @validateField dlDir, field
        @downloadDir = dlDir
        field.loadedFromSABnzbd = true
        console.log _.sprintf('  set "downloadDir" to "%s"', @downloadDir)
        cb true
      else
        console.log @adjustText(_.sprintf '\ndirectory of completed downloads "%s" reported by SABnzbd does not exist.', dlDir)
        process.exit 1
  # prettifies text
  @adjustText = (desc, indent = 0) ->
    trimSpaces = (text) ->
      text = text.replace new RegExp("[ ]+$"), ""
      text = text.replace new RegExp("^[ ]+"), ""
      return text

    return if not desc? or desc.length is 0

    lineLimit = 80
    desc = trimSpaces desc
    lines = []

    while not (desc.length is 0)
      # determine max length for the next line
      if lines.length is 0
        maxChars = lineLimit
      else
        if not indent? then maxChars = lineLimit else maxChars = lineLimit - indent

      # break if appropriate
      if desc.length < maxChars
        lines.push _.lpad('', lineLimit - maxChars , ' ') + trimSpaces desc
        break

      # get the last whitespace where we can truncate
      l = _.chain(desc)
           .map((c, i) -> if c is ' ' then return i else return null)
           .without(null)
           .filter((i) -> i < maxChars)
           .last()
           .value()

      lines.push _.lpad('', lineLimit - maxChars ,' ') + desc[0..l]
      desc = trimSpaces desc[l..]

    return lines.join '\n'
  # takes user input for the value for a field
  @askSetting = (field, cb) ->
    desc = @adjustText _.sprintf('description: "%s"', field.desc), 'description: "'.length
    if @[field.name]?
      msg = @adjustText _.sprintf('please configure "%s" with current value "%s".\n', field.name, @[field.name]), 'please configure "'.length
      msg += desc
      question = 'new value (or enter to use current): '
    else
      msg = @adjustText _.sprintf('please configure "%s".\n', field.name), 'please configure "'.length
      msg += desc
      question = 'value: '

    console.log msg
    @rl.question question, (answer) =>
      if @[field.name]? and answer is ''
        convertedValue = @[field.name]
      else
        convertedValue = @convertField answer, field

      if @validateField convertedValue, field
        answer = convertedValue
        @[field.name] = convertedValue
        console.log ''
        cb()
      else
        console.log @adjustText('\nthe entered value is not valid. please try again...\n')
        @askSetting field, cb
  # runs the wizard for the specified stage
  @runWizard = (stage, cb) ->
    funcs = []
    for c in _.filter(@configSchema, (s) -> s.stage is stage)
      if (not c.wizardEnabled? or c.wizardEnabled) and not c.loadedFromSABnzbd?
        do (c) =>
          funcs.push (cbx) =>
            @askSetting c, () ->
              cbx(null, true)
    async.series funcs, (err, res) ->
      cb()
  # sets default settings for fields not already set
  @setDefaults = ->
    for field in @configSchema
      @[field.name] = field.default if field.default? and not @[field.name]?
  # loads SABnzbd's configuration from it's ini file
  @loadSABConfig = () =>
    try
      @sabConfigData = ini.parseSync @sabConfigFile
    catch e
      @sabConfigData = null
  # if possible, save configuration, and exit afterwards
  @trySaveAndExit = =>
    copyError = false
    replaceValue = (str, key, val) =>
      return _.map(str.split('\n'), (l) ->
        if _.startsWith l, key
          l = key + ' = \'' + val + '\''
        return l).join '\n'
    copy = =>
      cpf = (filename) =>
        dest = @scriptDir + filename
        try
          console.log _.sprintf('  copying "%s" to "%s"...', filename, dest)
          data = fs.readFileSync(@appendTrailingSlash(path.resolve(__dirname, '../sabnzbd_scripts/')) + filename).toString()

          if filename is 'sabre_settings.py'
            console.log _.sprintf('    modifying configuration of "sabre_settings.py"...')
            data = replaceValue data, 'PASSWORDS_FILE', @appendTrailingSlash(path.resolve(__dirname, '../data/')) + 'passes.json'
            data = replaceValue data, 'TAR_CONTENTS_FILE', @appendTrailingSlash(path.resolve(__dirname, '../data/')) + 'tarcontents.json'

          fs.writeFileSync dest, data
        catch e
          copyError = true
          console.log _.sprintf('    error copying "%s" to "%s".', filename, dest)
      console.log 'copying...'
      cpf 'sabre_postprocess.py'
      cpf 'sabre_unrar.py'
      cpf 'sabre_settings.py'
      cpf 'sabre_includeimage.jpg'
    save = =>
      if @saveSettings()
        console.log @adjustText('setup complete. run sabRE again to start it up, then login with a user defined in users.json.')
        process.exit 0
      else
        console.log @adjustText('an error occured saving the settings. make sure the "data" dir is writeable.')
        process.exit 1

    if @validateSettings(1) and @validateSettings(2)
      if @noPostProcess? and not @noPostProcess and @scriptDir? and @scriptDir isnt '' and fs.existsSync(@scriptDir) and @scriptDir isnt @appendTrailingSlash(path.resolve(__dirname, '../sabnzbd_scripts/'))
        @rl.question 'do you want to copy postprocessing scripts to your SABnzbd script folder? (Y/n) ', (answer) =>
          console.log ''
          if answer is '' or answer.toLowerCase() is 'y'
            copy()
            console.log ''
            if copyError
              console.log @adjustText('some python postprocessing files could not be copied. make sure the scripts are accessible by SABnzbd. also check the configuration in sabre_settings.py.\n')
          else
            console.log @adjustText('you chose to skip copying the postprocessing scripts to SABnzbd\'s postprocessing directory. make sure the scripts are in SABnzbd\'s script directory and modify constants in sabre_settings.py.\n')
          save()
      else
        save()
    else
      console.log @adjustText('some settings have not been configured, aborting...')
      process.exit 1
  # gets the path to sabnzbd.ini from user input
  @readPathToSABnzbdIni = (cb) =>
    console.log @adjustText('please supply the full absolute path to your sabnzbd.ini:')
    @rl.question "", (answer) =>
      console.log ''
      if fs.existsSync answer
        @sabConfigFile = answer
        cb()
      else
        console.log @adjustText('the given filename does not exist.\n')
        @readPathToSABnzbdIni cb
  # main setup routine
  @setup = ->
    @rl = readline.createInterface
      input: process.stdin
      output: process.stdout

    @loadSABConfig()

    runWizardOne = (cb) =>
      @runWizard 1, () =>
        @assignSABConfigAPI () =>
          console.log @adjustText('\nimportant settings have been configured.')
          cb()

    setupStageOne = (cb) =>
      if @sabConfigData?
        msg = 'it seems that SABnzbd is configured on this system.\n'
      else
        msg = 'i could not find/open sabnzbd.ini configuration file, so i cannot setup myself using info from that file. i tried looking for it at "%s". you can specify the path to sabnzbd.ini or use the manual wizard.'
        msg = _.sprintf msg, @sabConfigFile

      console.log @adjustText(msg)

      if @sabConfigData?
        @assignSABConfigFile()
        @setDefaults()

        if @validateSettings 1
          @assignSABConfigAPI () =>
            console.log @adjustText('\nmandatory settings have been configured.')
            cb()
        else
          runWizardOne cb
      else
        @rl.question 'do you want to specify the path to sabnzbd.ini now? (Y/n) ', (answer) =>
          console.log ''
          if answer is '' or answer.toLowerCase() is 'y'
            @readPathToSABnzbdIni =>
              @loadSABConfig()
              setupStageOne cb
          else
            @setDefaults()
            runWizardOne cb

    setupStageTwo = =>
      @rl.question '\ndo you want to run the wizard now to configure other settings? (Y/n) ', (answer) =>
        console.log ''
        if answer is '' or answer.toLowerCase() is 'y'
          @runWizard 2, () =>
            @trySaveAndExit()
        else
          @trySaveAndExit()

    msg = '''
          --------------------------------------------------------------------------------
          -----------------------------   welcome to sabRE   -----------------------------
          --------------------------------------------------------------------------------


          '''
    
    if @error
      msg += '''
             an error occured loading the sabRE configuration, the error was:
             %s.
             please fix settings.json and run sabRE again. if you want to recreate the file,
             just delete it and run sabRE again so the setup wizard can be used.

             '''
      console.log _.sprintf msg, @errorMsg
      process.exit 1

    msg += '''
           it seems this is the first start of the application because no configuration
           file could be found.
           
           '''
    
    console.log msg
    @rl.question 'do you want to run the configuration wizard now? (Y/n) ', (answer) =>
      console.log ''
      if answer is '' or answer.toLowerCase() is 'y'
        setupStageOne () =>
          setupStageTwo()
      else
        @trySaveAndExit()

Settings.loadSettings()

module.exports = Settings