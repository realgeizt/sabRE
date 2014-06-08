# configuration
settings = require '../settings/settings'

# dependencies
winston = require('winston')

logger = new winston.Logger({
    transports: [
      # log to console
      new winston.transports.Console({ colorize: true }),
      # log to file
      new winston.transports.File({ filename: settings.logFile})
    ]
  })

module.exports = logger