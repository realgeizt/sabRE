# dependencies
winston = require('winston')

# project dependencies
settings = require './settings'

loggers = [ new winston.transports.Console { colorize: true } ]

if settings.loaded
  loggers.push new winston.transports.File({ filename: settings.logFile })

logger = new winston.Logger({ transports: loggers })

module.exports = logger