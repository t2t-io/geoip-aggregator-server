#!/usr/bin/env lsc
#
require! <[fs path http]>
require! <[colors yargs express prettyjson body-parser request async mkdirp]>
moment = require \moment-timezone

NG = (message, code, status, req, res) ->
  {configs} = module
  url = req.originalUrl
  result = {url, code, message, configs}
  return res.status status .json result

INFO = (message) ->
  now = moment!
  console.log "#{now.format 'MMM/DD HH:mm:ss.SSS'} [INFO] #{message}"

ERR = (message) ->
  now = moment!
  console.log "#{now.format 'MMM/DD HH:mm:ss.SSS'} [ERR ] #{message}"


GENERATE_URL_IPSTACK = (ip) ->
  {IPSTACK_SERVICE_API_TOKEN} = process.env
  return null unless IPSTACK_SERVICE_API_TOKEN?
  return do
    name: \ipstack.com
    opts:
      method: \GET
      url: "https://api.ipstack.com/#{ip}"
      qs: access_key: IPSTACK_SERVICE_API_TOKEN


GENERATE_URL_IPGEOLOCATION = (ip) ->
  {IPGEOLOCATION_SERVICE_API_TOKEN} = process.env
  return null unless IPGEOLOCATION_SERVICE_API_TOKEN?
  return do
    name: \ipgeolocation.io
    opts:
      method: \GET
      url: "https://api.ipgeolocation.io/ipgeo"
      qs: apiKey: IPGEOLOCATION_SERVICE_API_TOKEN, ip: ip


PERFORM_SERVICE = (s, done) ->
  {name, opts} = s
  (err, rsp, body) <- request opts
  if err?
    ERR err, "failed to request #{name} => #{JSON.stringify opts}"
    return done null, null
  {statusCode} = rsp
  if statusCode isnt 200
    ERR "non-200 response for requesting #{name} => #{JSON.stringify opts}"
    return done null, null
  response = body
  response = JSON.parse response if \string is typeof response
  return done null, {name, response}


FORMAT_IP_ADDRESS = (ip) -> return ip.split '.' .join '-'


class Aggregator
  (@opts) ->
    @addresses = {}
    return

  find-cache: (ip) ->
    pack = @addresses[ip]
    return null unless pack?
    return pack.data

  update-cache: (ip, data) ->
    {addresses} = self = @
    last-updated = new Date!
    addresses[ip] = pack = {last-updated, data}

  aggregate-by-ip: (ip, res) ->
    self = @
    code = 0
    message = null
    data = self.find-cache ip
    duration = 0
    return res.status 200 .json {code, message, data, duration} if data?
    services = []
    services.push GENERATE_URL_IPSTACK ip
    services.push GENERATE_URL_IPGEOLOCATION ip
    services = [ s for s in services when s? ]
    start = new Date!
    (err, results) <- async.map services, PERFORM_SERVICE
    data = { [r.name, r.response] for r in results when r? }
    duration = (new Date!) - start
    self.update-cache ip, data
    return res.status 200 .json {code, message, data, duration}

  clean-cache: ->
    {addresses} = self = @
    self.addresses = {}
    xs = [k for k, v of addresses]
    xs.sort!
    return xs


argv = global.argv = yargs
  .alias \p, \port
  .describe \p, 'port number to listen'
  .default \p, 7000
  .alias \v, \verbose
  .describe \v, 'enable verbose outputs'
  .default \v, no
  .demandOption <[port verbose]>
  .strict!
  .help!
  .argv

a = new Aggregator {}

web = express!
web.set 'trust proxy', true
web.use body-parser.json!
web.get '/by-ip/:ip', (req, res) ->
  {ip} = req.params
  INFO "/by-ip    : from #{req.ip.green} wants #{ip.yellow}"
  return a.aggregate-by-ip ip, res

web.get '/by-client', (req, res) ->
  {ip} = req
  INFO "/by-client: from #{ip.green} wants itself"
  return a.aggregate-by-ip ip, res

web.get '/clean', (req, res) ->
  data = a.clean-cache!
  code = 0
  message = null
  return res.status 200 .json {code, message, data}

HOST = \0.0.0.0
PORT = argv.port
server = http.createServer web
server.on \listening -> INFO "listening port #{HOST}:#{PORT} ..."
server.listen PORT, HOST