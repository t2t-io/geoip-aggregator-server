#!/usr/bin/env lsc -cj
#

# Known issue:
#   when executing the `package.ls` directly, there is always error
#   "/usr/bin/env: lsc -cj: No such file or directory", that is because `env`
#   doesn't allow space.
#
#   More details are discussed on StackOverflow:
#     http://stackoverflow.com/questions/3306518/cannot-pass-an-argument-to-python-with-usr-bin-env-python
#
#   The alternative solution is to add `envns` script to /usr/bin directory
#   to solve the _no space_ issue.
#
#   Or, you can simply type `lsc -cj package.ls` to generate `package.json`
#   quickly.
#

# package.json
#
name: \geoip-aggregator-server

author:
  name: \yagamy
  email: \yagamy@t2t.io

description: 'A simple REST server to aggregate API responses from several GeoIP service providers'

version: \0.0.1

repository:
  type: \git
  url: ''

engines:
  node: \8.12.0

dependencies:
  colors: \*
  async: \*
  lodash: \*
  yargs: \*
  request: \*
  express: \*
  mkdirp: \*
  prettyjson: \*
  \moment-timezone : \*
  \body-parser : \*

keywords: <[geoip aggregator]>

license: \MIT
