import jester
import asyncdispatch
import tables
import strutils
import os
import json
import sequtils
import base64
import logging
var L = newConsoleLogger()
addHandler(L)

proc tableToJson(t: Table[string,string]): string =
    var str = "{"
    for x,y in t.pairs():
        str = str & $(% x) & ": " & $(% y) & ","
    str = str[0..str.high-1] & "}"
    return str

proc seqToJson(s: seq[string]): string =
  var str = "["
  for x in s:
      str = str & $(% x) & ","
  str = str[0..str.high-1] & "]"
  return str

proc readTincConf(tincConf: string): Table[string,string] =
  var confTable = initTable[string,string]()
  for line in lines(tincConf):
    if not line.isNilOrEmpty:
      var cfgParts = line.split("=")
      confTable[cfgParts[0].strip()] = cfgParts[1].strip()
  return confTable

var tincSettings = readTincConf(joinPath(getAppDir(),"qtinc.conf"))
let tincHome = tincSettings["tincHome"]
let requireAuth = tincSettings["requireAuth"]
let trusted = tincSettings["trusted"].split(",")

proc writeTincConf(tincConf: string, tincData: Table[string,string]) =
  var buffer = ""
  for key, value in tincData.pairs():
      buffer = buffer & key & " = " & value & "\n"
  writeFile(tincConf,buffer)

proc getPendingClients(network: string): seq[string] =
  var clients = newSeq[string]()
  let pending = joinPath(tincHome,network,"pending")
  for file in walkDir(pending):
    var pathParts = file.path.split(DirSep)
    if file.kind == pcFile:
      clients.insert(pathParts[pathParts.high])
  return clients

proc getExistingClients(network: string): seq[string] =
  var clients = newSeq[string]()
  let pending = joinPath(tincHome,network,"hosts")
  for file in walkDir(pending):
    var pathParts = file.path.split(DirSep)
    if file.kind == pcFile:
      clients.insert(pathParts[pathParts.high])
  return clients

proc getAllClients(network: string): seq[string] =
  return concat(getPendingClients(network),getExistingClients(network))

proc getNetworks(tincHome: string, absolutePath: bool = false): seq[string] =
  var networks = newSeq[string]()
  for kind, path in walkDir(tincHome):
    if kind == pcDir:
      if not absolutePath:
        var pathParts = path.split(DirSep)
        networks.insert(pathParts[pathParts.high])
      else:
        networks.insert(path)

  return networks

proc parseAddressFromPubkey(pubkeyLines: seq[string]): string =
  for line in pubkeyLines:
    if line.startsWith("Subnet"):
      var cfgParts = line.split("=")
      var ipParts = cfgParts[1].strip().split("/")
      return ipParts[0].strip()
  raise newException(Exception, "Could not address from file")


proc getAddressesInUse(networkPath: string): seq[string] =
  var addresses = newSeq[string]()
  for file in walkDir(networkPath):
     if file.kind == pcFile:
       addresses.insert(parseAddressFromPubkey(toSeq(lines(file.path))))
  return addresses

proc getUnusedIP(network: string): string =
  let hosts = joinPath(tincHome,network,"hosts")
  let pending = joinPath(tincHome,network,"pending")
  if not existsDir(pending):
    createDir(pending)
  let hostsIps = getAddressesInUse(hosts)
  let pendingIps = getAddressesInUse(pending)
  let inuse = concat(hostsIps,pendingIps)

  if inuse.len == 0 or inuse.len == 254:
    return "nil"
  var subnet = inuse[0].split(".")[2]
  var lastDigitsInUse = newSeq[int]()
  for ip in inuse:
    lastDigitsInUse.add(parseInt(ip.split(".")[3]))
  for i in 2..254:
    if not (i in lastDigitsInUse):
      return "10.0.$#.$#".format([subnet,$i])

proc getTincData(network: string): Table[string,string] =
  return readTincConf(joinPath(tincHome,network,"tinc.conf"))

proc networkInfo(network: string): string =
  let tincData = getTincData(network)
  var response = initTable[string,string]()
  var switch = false
  if "Mode" in tincData:
    if tincData["Mode"] == "switch":
      switch = true

  if not switch:
    response["ip"] = getUnusedIP(network)
  response["pubkey"] = encode(readFile(joinPath(tincHome,network,"hosts",tincData["Name"])))
  response["host_name"] = tincData["Name"]
  response["port"] = tincData["Port"]
  return tableToJson(response)

proc approveClient(network: string, client: string): string =
  if not (client in getPendingClients(network)):
    return """{"error":"client does not exist"}"""
  let clientPath = joinPath(tincHome,network,"pending",client)
  let hostsPath = joinPath(tincHome,network,"hosts",client)
  moveFile(clientPath,hostsPath)
  return """{"response":"success"}"""

proc joinNetwork(network: string, name: string, pubkey: string): string =
  let tincData = getTincData(network)
  if not ("Mode" in tincData) or tincData["Mode"] == "router":
    let ip = parseAddressFromPubkey(pubkey.split("\n"))
    let availableIp = getUnusedIP(network)
    if ip != availableIp:
      return """{"error":"ip mismatch or race condition, try again"}"""
  var location = ""
  if requireAuth == "yes":
    location = "pending"
  else:
    location = "hosts"
  location = joinPath(tincHome,network,location,name)
  writeFile(location,pubkey)
  return """{"requireAuth":"$#","response":"success"}""".format([$requireAuth])


routes:
  get "/":
    resp "TODO: UI"
  get "/networks":
    resp seqToJson(getNetworks(tincHome))
  get "/networks/@network/join":
    if @"network" in getNetworks(tincHome):
      resp networkInfo(@"network")
    resp """{"error": "network does not exist"}"""
  post "/networks/@network/join":
    let name = request.formData["name"].body
    debug("name: ", name)
    if name in getAllClients(@"network"):
      resp """{"error":"name already exists"}"""
    let pubkey = decode(request.formData["pubkey"].body)
    debug("pubkey ",pubkey)
    resp joinNetwork(@"network",name,pubkey)
  get "/networks/@network/pending":
    if request.ip in trusted:
      resp seqToJson(getPendingClients(@"network"))
    else:
      resp """{"error":"unauthorized"}"""
  get "/networks/@network/pending/@client/approve":
    if request.ip in trusted:
      resp approveClient(@"network",@"client")
    else:
      resp """{"error":"unauthorized"}"""

runForever()
