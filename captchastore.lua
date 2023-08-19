-- captchastore.lua

local lsqlite3 = require "lsqlite3"

--TODO: change assert to if err ~= nil then ...

local store = {}
store.__index = store

store.ETOKEN = "captchastore: token does not exist"
store.EWRONG = "captchastore: provided answer is not correct"

function store.new(dbname, imagedir, amount)
  assert(dbname and imagedir)
  local self = setmetatable({
    dbname = dbname,
    imagedir = imagedir,
    amount = amount or 100,
  }, store)

  -- TODO: maybe use to-be-closed to make sure it will be closed
  -- also maybe have some db abstractions OR only support lsqlite3 v0.9.6+
  local db = self:opendb()

  assert(db:exec[[
  CREATE TABLE IF NOT EXISTS token(captcha_id);
  CREATE TABLE IF NOT EXISTS captcha(image, answer, mark);
  ]] == lsqlite3.OK)

  assert(db:close() == lsqlite3.OK)

  self:refresh()

  return self
end

function store:opendb()
  local db = assert(lsqlite3.open(self.dbname))
  db:busy_timeout(1000)
  assert(db:exec[[
  PRAGMA journal_mode=WAL;
  PRAGMA synchronous=NORMAL;
  ]] == lsqlite3.OK)

  return db
end

function store:get()
  local db = self:opendb()

  local token, image
  for token, captcha_id in db:urows[[
    INSERT INTO token
    SELECT rowid FROM captcha
    WHERE NOT mark ORDER BY RANDOM() LIMIT 1
    RETURNING rowid, captcha_id
    ]] do
    local stmt, err = db:prepare[[
    SELECT image, answer
    FROM captcha
    WHERE rowid = ?
    ]]
    if not stmt then error(db:errmsg()) end
    assert(stmt:bind_values(captcha_id) == lsqlite3.OK)
    for image, answer in stmt:urows() do
      assert(db:close() == lsqlite3.OK)
      return token, image, answer
    end
    break
  end
  assert(db:close() == lsqlite3.OK)
end

function store:verify(token, answer)
  assert(token and answer)
  token = tonumber(token)
  answer = string.upper(answer)

  local db = self:opendb()

  local stmt, err = db:prepare[[
  SELECT ?, answer
  FROM token
  INNER JOIN captcha ON captcha.rowid = captcha_id
  WHERE token.rowid = ?
  ]]
  if not stmt then error(db:errmsg()) end
  assert(stmt:bind_values(answer, token) == lsqlite3.OK)
  for prov, ans in stmt:urows() do
    assert(db:close() == lsqlite3.OK)
    if prov == ans then
      return true
    else
      return false, store.EWRONG
    end
  end

  assert(db:close() == lsqlite3.OK)
  return false, store.ETOKEN

  --[[
  select captcha from token where value=token
  delete from token where value = token
  ]]
end

function store:refresh(amount)
  amount = amount or self.amount
  --regen captchas
  local db = self:opendb()

  local oldfiles = {}

  for file in db:urows[[
    SELECT image FROM captcha
    WHERE mark = 1
    ]] do
    oldfiles[#oldfiles+1] = file
  end

  assert(db:exec"BEGIN TRANSACTION" == lsqlite3.OK)

  assert(db:exec[[
  DELETE FROM captcha WHERE mark = 1;
  UPDATE captcha SET mark = 1;
  DELETE FROM token WHERE captcha_id NOT IN (SELECT rowid FROM captcha);
  ]] == lsqlite3.OK)

  local stmt, err = db:prepare"INSERT INTO captcha VALUES (?, ?, 0)"
  if not stmt then error(db:errmsg()) end
  for i = 1, amount do
    local imagefile, answer = store.generate()

    assert(stmt:bind_values(imagefile, answer) == lsqlite3.OK)
    assert(stmt:step() == lsqlite3.DONE)
    assert(stmt:reset() == lsqlite3.OK)
  end

  assert(db:exec"COMMIT" == lsqlite3.OK)

  for i = 1, #oldfiles do
    os.remove(oldfiles[i])
  end

  assert(db:close() == lsqlite3.OK)
end

-- Source: http://www.fmwconcepts.com/imagemagick/captcha/index.php

local cmd = [[
convert -size 290x70 xc:$undercolor -bordercolor $bordercolor -border 5 \
-fill black -stroke $textcolor -strokewidth 1 -font $font -pointsize $pointsize \
-draw "translate ${xx1},${yy1} $or1 gravity center text 0,0 '$cc1'" \
-draw "translate ${xx2},${yy2} $or2 gravity center text 0,0 '$cc2'" \
-draw "translate ${xx3},${yy3} $or3 gravity center text 0,0 '$cc3'" \
-draw "translate ${xx4},${yy4} $or4 gravity center text 0,0 '$cc4'" \
-draw "translate ${xx5},${yy5} $or5 gravity center text 0,0 '$cc5'" \
-draw "translate ${xx6},${yy6} $or6 gravity center text 0,0 '$cc6'" \
-fill none -strokewidth 2 \
-draw "bezier ${bx1},${by1} ${bx2},${by2} ${bx3},${by3} ${bx4},${by4}" \
-draw "polyline ${bx4},${by4} ${bx5},${by5} ${bx6},${by6}" \
png:$outfile
]] --TODO: don't hardcode png

function store.generate(o)
  o = o or {}
  o.rotate = o.rotate or false
  o.skew = o.skew or true
  o.angle = o.angle or 40
  o.font = o.font or "TimesNewRoman"
  o.pointsize = o.pointsize or 40
  o.textcolor = o.textcolor or "black"
  o.bordercolor = o.bordercolor or "black"
  o.undercolor = o.undercolor or "white"
  o.outfile = o.outfile or os.tmpname()
  o.random = o.random or math.random

  local chars = {}

  local xoff = -120
  local map = "123456789ABCDEFGHIJKLMNPQRSTUVWXYZ"
  for i = 1, 6 do
    local ind = math.random(#map)
    local char = string.sub(map, ind, ind)
    chars[i] = char

    local x = xoff + math.random(-5, 5)
    xoff = xoff + 48

    local y = math.random(-10, 10)
    local r = math.random(-o.angle, o.angle)
    local s = math.random(-o.angle, o.angle)

    local orr = (o.rotate and "rotate "..r or "") .. (o.skew and " skewX "..s or "")

    local bx, by = 150 + 1.1*x, 40 + 2*y

    o["xx"..i] = x
    o["yy"..i] = y
    o["or"..i] = orr
    o["cc"..i] = char
    o["bx"..i] = bx
    o["by"..i] = by
  end

  os.execute(string.gsub("2>/dev/null 1>&2 "..cmd, "%${?(%w+)}?", o))
  return o.outfile, table.concat(chars)
end

return store
