# configuration
settings = require '../settings/settings'

# dependencies
fs = require 'fs'

if (typeof String::startsWith != 'function')
  String::startsWith = (str) ->
    return this.slice(0, str.length) == str

if (typeof String::endsWith != 'function')
  String::endsWith = (str) ->
    return this.slice(-str.length) == str

class Functions
  # load users from json file
  @getUsers = ->
    data = {}
    try
      data = JSON.parse fs.readFileSync(settings.userFile, 'utf8')
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
  # get tar content information from json file
  @getTarContents = ->
    contents = []
    try
      contents = JSON.parse fs.readFileSync(settings.tarContentsFile, 'utf8')
    catch e
      console.log '!!!TAR CONTENTS FILE NOT FOUND!!!'
      console.log e
    return contents
  # write tar content information back to the file
  @writeTarContents = (contents) ->
    fs.writeFileSync settings.tarContentsFile, JSON.stringify(contents)
  # get filesize as string
  @filesize = (a) ->
    e = Math.log(a) / Math.log(1e3) | 0
    return (a / Math.pow(1e3, e)).toFixed(1) + " " + ((if e then "kMGTPEZY"[--e] + "B" else "Bytes"))

module.exports = Functions