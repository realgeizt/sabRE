# dependencies
http = require 'http'
_ = require 'underscore'

# project dependencies
settings = require './settings'
logger = require './logger'
functions = require './functions'

class Auth
  # list of active users
  @activeUsers = []

  # middleware to authenticate a user.
  # if a user defined in settings.userFile is found everything is okay, otherwise the alternative
  # authentication strategy will be used if enabled.
  @authUser = (req, res, next) ->
    if not settings.authRequired
      req.user = 'anonymous'
      return next()

    users = functions.getUsers()

    if req.body? and req.body.user? and req.body.pass?
      # if supplied use user and pass from the request body
      user = req.body.user
      pass = req.body.pass
    else if req.cookies? and req.cookies.login?
      # otherwise try to use user and pass from cookie
      try
        user = JSON.parse(req.cookies.login).user
        pass = JSON.parse(req.cookies.login).pass

    if _.isString(user) and _.isString(pass)
      if users[user.toLowerCase()] is pass
        # the user is in the user-file with a matching password, everything is okay
        req.user = user
        Auth.authOkay req, res, next, user
      else
        # the user is not in the user-file, try authentication using the external url if settings are set
        if settings.remoteAuthEnabled and settings.remoteAuthHost isnt '' and settings.remoteAuthPath isnt '' and settings.remoteAuthPort > 0
          request = http.request {host: settings.remoteAuthHost, port: settings.remoteAuthPort, path: settings.remoteAuthPath + '?username=' + user + '&password=' + pass}, (response) ->
            str = ''
            response.on 'data', (chunk) ->
              str += chunk
            response.on 'end', () ->
              if str.trim() is 'ok'
                req.user = user
                Auth.authOkay req, res, next, user
              else
                res.send 403
          request.on 'error', (err) ->
            res.send 403
          request.end()
        else
          setTimeout () ->
            res.send 403
          , 1000
    else
      setTimeout () ->
        res.send 403
      , 1000

  # this function is called everytime a user logs in
  @authOkay = (req, res, next, user) ->
    @activeUsers = _.filter(@activeUsers, (u) -> u.time > new Date().getTime() - 120000)
    if not _.find(@activeUsers, (u) -> u.user is user)
      @activeUsers.push { user: user, time: new Date().getTime() }
      logger.info 'user "' + user + '" logged in'
    else
      _.find(@activeUsers, (u) -> u.user is user).time = new Date().getTime()
    next()

if settings.loaded
  # this function cleans up activeUsers
  setInterval () ->
    # show users that left the site
    leftUsers = _.filter(Auth.activeUsers, (u) -> u.time <= new Date().getTime() - 120000)
    for user in leftUsers
      logger.info 'user "' + user.user + '" left'
    Auth.activeUsers = _.filter(Auth.activeUsers, (u) -> u.time > new Date().getTime() - 120000)
  , 1000

module.exports = Auth