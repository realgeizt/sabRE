# dependencies
fs = require 'fs'

# project dependencies
settings = require './settings'
logger = require './logger'

class Functions
  # load users from json file
  @getUsers = ->
    data = {}
    try
      data = JSON.parse fs.readFileSync(settings.userFile, 'utf8')
    catch e
      logger.error 'functions.getUsers(): ' + e
    return data
  # load passes from json file
  @getPasses = ->
    pwds = []
    try
      pwds = JSON.parse fs.readFileSync(settings.postProcessPasswordsFile, 'utf8')
    return pwds
  # write passes back to the file
  @writePasses = (passes) ->
    fs.writeFileSync settings.postProcessPasswordsFile, JSON.stringify(passes)
    fs.chmodSync(settings.postProcessPasswordsFile, '666')
  # get tar content information from json file
  @getTarContents = ->
    contents = []
    try
      contents = JSON.parse fs.readFileSync(settings.tarContentsFile, 'utf8')
    return contents
  # write tar content information back to the file
  @writeTarContents = (contents) ->
    fs.writeFileSync settings.tarContentsFile, JSON.stringify(contents)
  # get user nzb information from json file
  @getUserNZBs = ->
    userNZBs = []
    try
      userNZBs = JSON.parse fs.readFileSync(settings.userNZBsFile, 'utf8')
    return userNZBs
  # write user nzb information back to the file
  @writeUserNZBs = (userNZBs) ->
    fs.writeFileSync settings.userNZBsFile, JSON.stringify(userNZBs)
  # get filesize as string
  @filesize = (a) ->
    e = Math.log(a) / Math.log(1e3) | 0
    return (a / Math.pow(1e3, e)).toFixed(1) + ' ' + ((if e then 'kMGTPEZY'[--e] + 'B' else 'Bytes'))
  # clone an object
  @clone = (obj) ->
    if not obj? or typeof obj isnt 'object'
      return obj

    if obj instanceof Date
      return new Date(obj.getTime())

    if obj instanceof RegExp
      flags = ''
      flags += 'g' if obj.global?
      flags += 'i' if obj.ignoreCase?
      flags += 'm' if obj.multiline?
      flags += 'y' if obj.sticky?
      return new RegExp(obj.source, flags)

    newInstance = new obj.constructor()

    for key of obj
      newInstance[key] = @clone obj[key]

    return newInstance

module.exports = Functions