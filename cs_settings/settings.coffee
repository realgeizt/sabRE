settings =
{
  # path to logfile
  logFile: __dirname + '/../data/log.json'
  # path to file containing users
  userFile: __dirname + '/../data/users.json'
  # use curl before enqueueing urls?
  useCurl: false
  # dir where nzb files from users get uploaded to
  nzbUploadDir: '/tmp/'
  # dir of finished sabnzb downloads
  downloadDir: '/tmp/sabnzbd/done/'
  # file with postprocessing information - needs to be the same as in sabnzbd/scripts/settings.py
  postProcessProgressFile: '/tmp/sabre_postprocessprogress'
  # path to file with unrar passes - needs to be the same as in sabnzbd/scripts/settings.py
  postProcessPasswordsFile: __dirname + '/../data/passes.json'
  # path to file with created tar contents
  tarContentsFile: __dirname + '/../data/tarcontents.json'
  # path to file containing user -> nzb mapping
  userNZBsFile: __dirname + '/../data/usernzbs.json'
  # hide queued nzbs/downloads from users that are not responsible for them
  hideOtherUsersData: false
  # information to connect to sabnzbd
  sabData:
    host: '127.0.0.1'
    port: 8080
    apiKey: 'INSERT_YOUR_SABNZBD_API_KEY_HERE'
  # information for remote authentication of users
  remoteAuth:
    enabled: false
    host: ''
    port: 80
    path: '/remoteauth/'
  # entries starting with strings from this list will be hidden from the queue
  sabHideQueue:
    ['Trying to fetch', ]
}

module.exports = settings