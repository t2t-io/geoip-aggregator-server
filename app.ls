#!/usr/bin/env lsc
#
require! <[fs path http]>
require! <[colors yargs express prettyjson body-parser request async mkdirp lodash]>
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
    now = moment!
    @dir = "#{now.format 'YYYYMMDD-HHmm'}"
    @counter = 0
    return

  find-cache: (ip) ->
    pack = @addresses[ip]
    return null unless pack?
    return pack.data

  update-cache: (ip, data) ->
    {addresses} = self = @
    last-updated = new Date!
    addresses[ip] = pack = {last-updated, data}
    self.save-to-disk!

  save-to-disk: ->
    {addresses, dir, counter} = self = @
    counter = counter.toString!
    uptime = Math.floor process.uptime!
    uptime = uptime.toString!
    p = "#{__dirname}/work/#{dir}/backup-#{lodash.padStart counter, 4, '0'}-#{lodash.padStart uptime, 8, '0'}.json"
    (mkdir-err) <- mkdirp path.dirname p
    return ERR "failed to save #{p} because of mkdir-err: #{mkdir-err}" if mkdir-err?
    text = JSON.stringify addresses
    (write-err) <- fs.writeFile p, text
    return ERR "failed to save #{p} because of write-err: #{write-err}" if write-err?
    return INFO "successfully flush addresses (#{text.length} bytes) to disk: #{p.yellow}"

  prettyprint-geolocation: (s, city, country, timezone) ->
    city = if city? then city.yellow else "null".gray
    country = if country? then country.cyan else "null".gray
    timezone = if timezone? then timezone.green else "null".gray
    return "#{s}:#{city},#{country},#{timezone}"

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
    info = []
    s1 = data['ipstack.com']
    s2 = data['ipgeolocation.io']
    info.push self.prettyprint-geolocation 'ipstack.com', s1.city, s1.country_code, s1.time_zone.id if s1?
    info.push self.prettyprint-geolocation 'ipgeolocation.io', s2.city, s2.country_code2, s2.time_zone.name if s2?
    info = info.join ' '
    INFO "aggregation: #{ip.red} => #{info}"
    return res.status 200 .json {code, message, data, duration}

  get-addresses: ->
    {addresses} = self = @
    xs = [k for k, v of addresses]
    xs.sort!
    return xs

  clean-cache: ->
    xs = @.get-addresses!
    @addresses = {}
    @counter = @counter + 1
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
  {site, host, instance, service} = req.query
  {ip} = req.params
  metadata = ''
  metadata = ", metadata 'site:#{site}, host:#{host}, instance:#{instance}, service:#{service}'" if site? and host? and instance? and service?
  INFO "/by-ip    : from #{req.ip.green} wants #{ip.yellow}#{metadata}"
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

web.get '/addresses', (req, res) ->
  data = a.get-addresses!
  code = 0
  message = null
  return res.status 200 .json {code, message, data}

HOST = \0.0.0.0
PORT = argv.port
server = http.createServer web
server.on \listening -> INFO "listening port #{HOST}:#{PORT} ..."
server.listen PORT, HOST
