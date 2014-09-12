app = angular.module 'webapp', []

app.directive 'inputfile', -> 
  restrict: 'E'
  template: "<div><input type='file'></input></div>"
  replace: true
  scope:
    model: '=ngModel'
  link: (scope, el, attrs) ->
    div = el.find('div')
    div.attr 'class', attrs.class
    div.attr 'style', attrs.style
    scope.model = null
    input = el.find('input')
    input.bind 'change', (e) ->
      files = e.target.files
      scope.$apply ->
        scope.model = {}
        scope.model.resource = files?[0] or null
        scope.model.name = scope.model.resource?.name or null
        scope.model.type = scope.model.resource?.type or null

app.controller 'UICtrl', ($scope, $rootScope, $http) ->
  # variables
  login = getJSONCookie('login')
  timer = null

  # scope variables
  $scope.auth = { ok: false, err: false, loggingin: false}
  $scope.sendstate = {err: false, success: false, sending: false}
  $scope.fileapi = true if window.File && window.FileReader && window.FileList && window.Blob
  $scope.sabdata = { running: true }
  $scope.appbusy = true
  $scope.authRequired = authRequired

  # try logging in with supplied user/pass
  $scope.login = (user, pass) ->
    return if !user? or !pass?

    $scope.auth = { ok: false, err: false, loggingin: true}

    $http.post('/login', {user: user, pass: pass}).success (data, status, headers, config) ->
      login = {user: user, pass: pass}
      setJSONCookie 'login', login, 10
      refreshOnce (win) ->
        $scope.auth = { ok: true, err: false, loggingin: false}
        $scope.appbusy = false
    .error (data, status, headers, config) ->
      $scope.auth = { ok: false, err: true, loggingin: false}
      $scope.appbusy = false
      delCookie 'login'

  if not $scope.authRequired
    $scope.login 'anonymous', ''

  # called to upload nzb file
  $scope.sendNZB = ->
    return if !$scope.file || $scope.sendstate.sending || !$scope.sabdata.running

    $scope.sendstate = {err: false, success: false, sending: true}

    fr = new FileReader()
    fr.onload = ->
      oldfile = $scope.file.name
      $http.post('/nzb', _.extend(login, {nzbdata: fr.result, nzbname: $scope.file.name, flac2mp3: $scope.flac2mp3})).success (data, status, headers, config) ->
        $scope.sendstate = {err: false, success: true, sending: false}
        if oldfile is $scope.file.name
          $scope.file = null
        refreshOnce()
      .error (data, status, headers, config) ->
        $scope.sendstate = {err: true, success: false, sending: false}
    fr.readAsText $scope.file.resource

  # called to add nzb url
  $scope.sendNZBUrl = ->
    return if !$scope.nzburl || $scope.sendstate.sending || !$scope.sabdata.running

    $scope.sendstate = {err: false, success: false, sending: true}

    oldurl = $scope.nzburl
    $http.post('/nzburl', _.extend(login, {nzburl: $scope.nzburl, flac2mp3: $scope.flac2mp3})).success (data, status, headers, config) ->
      $scope.sendstate = {err: false, success: true, sending: false}
      if oldurl is $scope.nzburl
        $scope.nzburl = ''
      refreshOnce()
    .error (data, status, headers, config) ->
      $scope.sendstate = {err: true, success: false, sending: false}

  # called to send a pass to extract rar files
  $scope.sendNZBPass = ->
    return if !$scope.nzbpass || $scope.sendstate.sending || !$scope.sabdata.running

    $scope.sendstate = {err: false, success: false, sending: true}

    oldpass = $scope.nzbpass
    $http.post('/nzbpass', _.extend(login, {nzbpass: $scope.nzbpass})).success((data, status, headers, config) ->
      $scope.sendstate = {err: false, success: true, sending: false}
      if oldpass is $scope.nzbpass
        $scope.nzbpass = null
      refreshOnce()
    ).error((data, status, headers, config) ->
      $scope.sendstate = {err: true, success: false, sending: false}
    )

  # starts a timer that refreshes the view
  refresh = ->
    timer = setTimeout () ->
      if $scope.auth.ok
        $http.post('/sabdata', login).success (data, status, headers, config) ->
          if not _.isEqual $scope.sabdata, data
            $scope.sabdata = data
          refresh()
        .error (data, status, headers, config) ->
          $scope.sabdata = {running: false}
          refresh()
    , 3000

  # refreshes the view immediately
  refreshOnce = (cb) ->
    clearTimeout timer if timer?
    $http.post('/sabdata', login).success (data, status, headers, config) ->
      if not _.isEqual $scope.sabdata, data
        $scope.sabdata = data
      refresh()
      cb true if cb?
    .error (data, status, headers, config) ->
      $scope.sabdata = {running: false}
      refresh()
      cb false if cb?

  # login the user
  if login
    $scope.login login.user, login.pass
  else
    $scope.appbusy = false

  # start the refresh timer
  refresh()

setJSONCookie = (cname, cobj, exdays) ->
  d = new Date()
  d.setTime(d.getTime() + (exdays * 24 * 60 *60 * 1000))
  expires = "expires=" + d.toGMTString()
  document.cookie = encodeURIComponent(cname) + "=" + encodeURIComponent(JSON.stringify(cobj)) + "; " + expires

delCookie = (cname) ->
  d = new Date(0)
  expires = "expires=" + d.toGMTString()
  document.cookie = encodeURIComponent(cname) + "=; " + expires

getJSONCookie = (cname) ->
  name = encodeURIComponent(cname) + "="
  ca = document.cookie.split(';')
  for i in [0..ca.length - 1]
    c = ca[i].trim()
    return JSON.parse(decodeURIComponent(c.substring(name.length, c.length))) if c.indexOf(name) is 0
  return null
