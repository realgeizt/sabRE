# dependencies
fs = require 'fs'
path = require 'path'
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
    { name: 'useCurl', desc: 'check urls with curl before enqueueing to SABnzbd?', default: false, type: 'bool' }
    { name: 'hideOtherUsersData', desc: 'when enabled, users can only see stuff they enqueued. files from other users are hidden.', default: false, type: 'bool' }
    { name: 'logFile', desc: 'file where sabRE logs into.', default: '../data/log.json', type: 'file', mustExist: false, wizardEnabled: false }
    { name: 'userFile', desc: 'sabRE\'s user/password "database".', default: '../data/users.json', type: 'file', wizardEnabled: false }
    { name: 'nzbUploadDir', desc: 'directory where uploaded .nzb files will be stored. files will be deleted after they have been enqueued.', default: '/tmp/', type: 'dir' }
    { name: 'downloadDir', desc: 'must have same value as "Completed Download Folder" in SABnzbd\'s configuration.', type: 'dir', inisec: 'misc', ininame: 'complete_dir' }
    { name: 'postProcessProgressFile', desc: 'temporary file used for communication between postprocessing script and sabRE. must point to the same file as PROGRESS_FILE in settings.py from the postprocessor.', default: '/tmp/sabre_postprocessprogress', type: 'file', mustExist: false, wizardEnabled: false }
    { name: 'postProcessPasswordsFile', desc: 'sabRE\'s password database (NOT SABnzb\'s) to extract passworded rar files. must point to the same file as PASSWORDS_FILE in settings.py from the postprocessor.', default: '../data/passes.json', type: 'file', mustExist: false, wizardEnabled: false }
    { name: 'tarContentsFile', desc: 'file that stores contents of .tar files created by postprocessing so the contents of files can be displayed in sabRE. must point to the same file as TAR_CONTENTS_FILE in settings.py from the postprocessor.', default: '../data/tarcontents.json', type: 'file', mustExist: false, wizardEnabled: false }
    { name: 'userNZBsFile', desc: 'file that associates user accounts with downloaded nzbs. this file is important when every user should only see his own enqueued files (hideOtherUsersData == true).', default: '../data/usernzbs.json', type: 'file', mustExist: false, wizardEnabled: false }
    { name: 'sabHideQueue', default: ['Trying to fetch', ], type: 'list', wizardEnabled: false }
    { name: 'sabHost', desc: 'host/ip where SABnzbd is running on.', default: '127.0.0.1', type: 'string' }
    { name: 'sabPort', desc: 'port where SABnzbd is listening on.', default: 8080, type: 'int', inisec: 'misc', ininame: 'port' }
    { name: 'sabApiKey', desc: 'the api key of SABnzbd.', default: '', type: 'string', inisec: 'misc', ininame: 'api_key' }
    { name: 'remoteAuthEnabled', 'desc': 'make use of user authentication using a remote url?', default: false, type: 'bool' }
    { name: 'remoteAuthHost', desc: 'host where remote authentication is running.', default: '127.0.0.1', type: 'string' }
    { name: 'remoteAuthPort', desc: 'port where remote authentication is listening on.', default: 80, type: 'int' }
    { name: 'remoteAuthPath', desc: 'path for the url to the remote authentication.', default: '/remoteauth/', type: 'string' }
  ]

  # undefine previously loaded settings
  @resetSettings = ->
    for k in @loadedKeys
      @[k] = undefined
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
        if s.type is 'dir' and (not _.endsWith val, '/')
          val += '/'
        if @validateField val, s
          @[s.name] = val
          @loadedKeys.push s.name
        else
          throw 'not @validateField val, s'
      if not @validateSettings()
        throw 'not @validateSettings()'
      @loaded = true
    catch e
      @resetSettings()
      @error = true
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
  @validateSettings = ->
    for s in @configSchema
      if not @validateField @[s.name], s
        return false
    return true
  # imports some settings from sabnzbd.ini
  @loadFromSABnzbd = ->
    for field in @configSchema
      if field.inisec? and field.ininame?
        convertedValue = @convertField @sabConfigData[field.inisec][field.ininame], field
        if @validateField convertedValue, field
          @[field.name] = convertedValue
          field.loadedFromSABnzbd = true
          console.log '  set "' + field.name + '" to "' + @[field.name] + '"'
  # prettifies text... ugly, long and inefficient!
  @adjustText = (desc, indent) ->
    return if not desc? or desc.length is 0

    lines = []

    getSpaces = (d) ->
      return _.chain(d)
      .map((c, i) -> if c is ' ' then return i else return -1)
      .without(-1)
      .value()

    while not (desc.trim().length is 0)
      spaces = getSpaces desc

      if lines.length is 0
        maxChars = 80
      else
        if not indent? then maxChars = 80 else maxChars = 80 - indent

      p =
        pos: _.find(spaces, (s) -> s > maxChars)
        spaceIdx: _.indexOf(spaces, _.find(spaces, (s) -> s > maxChars)) - 1
        prevPos: spaces[_.indexOf(spaces, _.find(spaces, (s) -> s > maxChars)) - 1]

      if p.prevPos is 0
        p.prevPos = p.pos

      if not p.pos?
        if lines.length > 0
          lines.push _.lpad('', indent, ' ') + desc.trim() if not (desc.trim().length is 0)
        else
          lines.push desc.trim() if not (desc.trim().length is 0)
        break

      if (lines.length > 0) and (p.prevPos isnt p.pos)
        lines.push _.lpad('', indent, ' ') + desc[0..p.prevPos - 1].trim()
      else
        lines.push desc[0..p.prevPos - 1].trim()

      desc = desc[p.prevPos..]
      spaces.splice 0, p.spaceIdx

    return lines.join '\n'
  # takes user input for the value for a field
  @askSetting = (field, cb) ->
    desc = @adjustText 'description: "' + field.desc + '"', 'description: "'.length
    if @[field.name]?
      msg = @adjustText(_.sprintf('please configure "%s" with current value "%s".', field.name, @[field.name]), 'please configure "'.length) + '\n'
      msg += desc
      question = 'new value (or enter to use current): '
    else
      msg = @adjustText(_.sprintf('please configure "%s".', field.name), 'please configure "'.length) + '\n'
      msg += desc
      question = 'value: '

    console.log msg
    @rl.question question, (answer) =>
      console.log ''

      if @[field.name]? and answer is ''
        convertedValue = @[field.name]
      else
        convertedValue = @convertField answer, field

      if @validateField convertedValue, field
        answer = convertedValue
        @[field.name] = convertedValue
        cb()
      else
        console.log 'the entered value is not valid. please try again...'
        console.log ''
        @askSetting field, cb
  @runWizard = (sabLoaded, cb) ->
    funcs = []
    for c in @configSchema
      if (not c.wizardEnabled? or c.wizardEnabled) and not c.loadedFromSABnzbd?
        do (c) =>
          funcs.push (cbx) =>
            @askSetting c, () ->
              cbx(null, true)
    async.series funcs, (err, res) ->
      cb()
  @setDefaults = ->
    for field in @configSchema
      @[field.name] = field.default if field.default? and not @[field.name]?
  @setup = ->
    @rl = readline.createInterface
      input: process.stdin
      output: process.stdout

    sabFound = fs.existsSync @sabConfigFile
    if sabFound
      try
        @sabConfigData = ini.parseSync @sabConfigFile
        throw 'no keys found' if _.keys(@sabConfigData).length is 0
      catch e
        sabFound = false

    msg = '''
          --------------------------------------------------------------------------------
          -----------------------------   welcome to sabRE   -----------------------------
          --------------------------------------------------------------------------------


          '''
    if not @error
      if sabFound
        msg += '''
               it seems this is the first start of the application because no configuration
               file could be found. also it seems that SABnzbd is configured on this system,
               which makes it possible to setup sabRE automatically because most things can be
               read from sabnzbd.ini.

               '''
      else
        msg += '''
               it seems this is the first start of the application because no configuration
               file could be found. i could not find/open sabnzbd.ini configuration file, so i
               cannot setup myself using info from that file. i tried looking for it at
                 "%s"
               the only way to setup sabRE is by using the manual wizard.

               '''
        msg = _.sprintf msg, @sabConfigFile
    else
      msg += '''
             an error occured loading the sabRE configuration.
             please fix settings.json and run sabRE again. if you want to recreate the file,
             just delete it and run sabRE again so the setup wizard can be used.

             '''

    trySaveAndExit = =>
      if @validateSettings()
        if @saveSettings()
          console.log 'setup complete. run sabRE again to start it up, then login with a user defined'
          console.log 'defined in users.json.'
          process.exit 0
        else
          console.log 'an error occured saving the settings. make sure the "data" dir is writeable.'
          process.exit 1
      else
        console.log 'some settings have not been configured, aborting...'
        process.exit(1)

    console.log msg
    if not @error
      @rl.question "do you want to run the configuration wizard now? (Y/n) ", (answer) =>
        console.log ''
        if answer is '' or answer.toLowerCase() is 'y'
          if sabFound
            console.log 'reading from ' + @sabConfigFile + '...'
            @loadFromSABnzbd()
            @setDefaults()

            console.log ''
            if not @validateSettings()
              msg = '''
                    it seems some settings could not be read from sabnzbd.ini.
                    you need to configure them using the wizard.

                    '''
            else
              msg = '''
                    everything required has been read.
                    you can now run the wizard to configure misc settings or exit setup and then
                    restart sabRE to run it with the imported settings while using default values
                    for not-imported settings.

                    '''
            console.log msg
            @rl.question 'do you want to run the wizard now to configure other settings? (Y/n) ', (answer) =>
              console.log ''
              if answer is '' or answer.toLowerCase() is 'y'
                @runWizard true, () =>
                  trySaveAndExit()
              else
                trySaveAndExit()
          else
            @setDefaults()
            @runWizard false, () =>
              trySaveAndExit()
        else
          trySaveAndExit()
    else
      process.exit 1

Settings.loadSettings()

module.exports = Settings