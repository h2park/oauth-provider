cors                   = require 'cors'
raven                  = require 'raven'
morgan                 = require 'morgan'
express                = require 'express'
bodyParser             = require 'body-parser'
errorHandler           = require 'errorhandler'
meshbluHealthcheck     = require 'express-meshblu-healthcheck'
MeshbluConfig          = require 'meshblu-config'
debug                  = require('debug')('oauth-provider:server')
Router                 = require './router'
OAuth2Server           = require 'oauth2-server'
moment                 = require 'moment'
OctobluOauth           = require './models/octoblu-oauth'
AuthCodeGrant          = require './strategies/auth-code-grant'
ClientCredentialsGrant = require './strategies/client-credentials-grant'
expressVersion         = require 'express-package-version'

OAuth2Server.prototype.authCodeGrant = (check) ->
  that = @
  (req, res, next) =>
    new AuthCodeGrant that, req, res, next, check

OAuth2Server.prototype.clientCredentialsGrant = (check) ->
  that = @
  (req, res, next) =>
    new ClientCredentialsGrant that, req, res, next, check

class Server
  constructor: (options)->
    {
      @disableLogging
      @port
      @octobluBaseUrl
      @meshbluConfig
      @pepper
      @sentryDSN
    } = options
    @meshbluConfig ?= new MeshbluConfig().toJSON()

  address: =>
    @server.address()

  run: (callback) =>
    app = express()

    app.use raven.middleware.express.requestHandler @sentryDSN if @sentryDSN
    app.use raven.middleware.express.errorHandler @sentryDSN if @sentryDSN
    app.use meshbluHealthcheck()
    app.use expressVersion({format: '{"version": "%s"}'})
    app.use morgan 'dev', immediate: false unless @disableLogging
    app.use cors()
    app.use bodyParser.urlencoded limit: '1mb', extended : true
    app.use bodyParser.json limit : '1mb'

    app.options '*', cors()

    octobluOauth = new OctobluOauth {@meshbluConfig, @pepper}

    app.oauth = OAuth2Server
      model: octobluOauth
      grants: [ 'refresh_token', 'authorization_code', 'client_credentials' ]
      debug: true
      accessTokenLifetime: null
      refreshTokenLifetime: null
      authCodeLifetime: moment().add(1, 'year').unix()

    router = new Router {@meshbluConfig, @octobluBaseUrl, octobluOauth}

    router.route app

    app.use app.oauth.errorHandler()

    @server = app.listen @port, callback

  stop: (callback) =>
    @server.close callback

module.exports = Server
