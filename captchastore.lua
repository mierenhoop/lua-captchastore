-- captchastore.lua

local lsqlite3 = require "lsqlite3"

--TODO: change assert to if err ~= nil then ...

---@class captchastore
---@field dbname string
---@field imagedir string
---@field amount integer
local store = {}
store.__index = store

store.ETOKEN = "captchastore: token does not exist"
store.EWRONG = "captchastore: provided answer is not correct"

---@param dbname string path to the cookiestore cache database
---@param amount integer? defaults to 100. Amount of new captcha generated
---@returns captchastore
function store.new(dbname, imagedir, amount)
  assert(dbname and imagedir)
  local self = setmetatable({}, store)

  self.dbname = dbname
  self.imagedir = imagedir
  self.amount = amount or 100

  -- TODO: maybe use to-be-closed to make sure it will be closed
  -- also maybe have some db abstractions OR only support lsqlite3 v0.9.6+
  local db = self:opendb()

  assert(db:exec [[
  CREATE TABLE IF NOT EXISTS token(captcha_id);
  CREATE TABLE IF NOT EXISTS captcha(image, answer, mark, uses);
  ]] == lsqlite3.OK)

  assert(db:close() == lsqlite3.OK)

  self:refresh()

  return self
end

local function prep(db, sql, ...)
  local stmt = db:prepare(sql)
  if not stmt then error(db:errmsg()) end
  if stmt:bind_values(...) ~= lsqlite3.OK then
    error(db:errmsg())
  end
  return stmt
end

local function exec(db, sql)
  if db:exec(sql) ~= lsqlite3.OK then error(db:errmsg()) end
end

local function urow(db, sql, ...)
  local stmt = prep(db, sql, ...)
  local rows = table.pack(stmt:urows()(stmt))
  stmt:finalize()
  return table.unpack(rows)
end

local function transaction(db, f)
  exec(db, "BEGIN TRANSACTION;")

  local ok, err = pcall(f)
  if not ok then
    exec(db, "ROLLBACK;")
    error(err)
  end

  exec(db, "COMMIT;")
end


---@private
function store:opendb()
  local db = assert(lsqlite3.open(self.dbname))
  db:busy_timeout(1000)
  exec(db, [[
  PRAGMA journal_mode=WAL;
  PRAGMA synchronous=NORMAL;
  ]])

  return db
end

---Get a random cached captcha
---@return integer token ID which refers to a captcha
---@return string image path of the captcha image file
---@return string answer answer for the captcha
function store:get()
  local db = self:opendb()
  local token, captcha_id, image, answer

  transaction(db, function()
    token, captcha_id = urow(db, [[
    INSERT INTO token
    SELECT rowid FROM captcha
    WHERE NOT mark
    ORDER BY uses ASC, RANDOM()
    LIMIT 1
    RETURNING rowid, captcha_id
    ]])
  end)
  assert(db:close() == lsqlite3.OK)
  return token, image, answer
end

---Verify if the captcha has been solved
---@param token integer
---@param answer string
---@return boolean, string? # one of the following error codes
--- - `self.ETOKEN`
--- - `self.EWRONG`
function store:verify(token, answer)
  answer = string.upper(answer)

  local db = self:opendb()

  local prov, ans, captcha_id = urow(db, [[
  SELECT ?, answer, captcha_id
  FROM token
  INNER JOIN captcha ON captcha.rowid = captcha_id
  WHERE token.rowid = ?
  ]], answer, token)
  assert(db:close() == lsqlite3.OK)

  if not ans then return false, store.ETOKEN end

  if prov == ans then
    urow(db, [[
    DELETE FROM token WHERE captcha_id = ?
    ]], captcha_id)
    urow(db, [[
    UPDATE captcha SET uses = uses + 1 WHERE rowid = ?
    ]], captcha_id)
    return true
  else
    return false, store.EWRONG
  end
end

---Refresh the captcha cache, marks the old ones for removal,
---they will still work until the next refresh, but will not be given out.
function store:refresh()
  --regen captchas
  local db = self:opendb()

  local oldfiles = {}

  for file in db:urows [[
    SELECT image FROM captcha
    WHERE mark = 1
    ]] do
    oldfiles[#oldfiles + 1] = file
  end

  transaction(db, function()
    exec(db, [[
    DELETE FROM captcha WHERE mark = 1;
    UPDATE captcha SET mark = 1;
    DELETE FROM token WHERE captcha_id NOT IN (SELECT rowid FROM captcha);
    ]])

    local dir = self.imagedir
    local sep = string.sub(self.imagedir, -1, -1)
    if sep ~= "/" and sep ~= "\\" then dir = dir .. "/" end
    for i = 1, self.amount do
      local captcha_id = urow(db, [[
      INSERT INTO captcha VALUES (NULL, NULL, 0, 0)
      RETURNING rowid]])
      local imagefile = dir .. captcha_id .. ".png"
      local answer = store.generate(imagefile)
      urow(db, [[
      UPDATE captcha
      SET image = ?, answer = ?
      WHERE rowid = ?]], imagefile, answer, captcha_id)
    end
  end)

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
$outfile
]]

---@private
function store.generate(name)
  local o = {}
  o.rotate = false
  o.skew = true
  o.angle = 40
  o.font = "Helvetica"
  o.pointsize = 40
  o.textcolor = "black"
  o.bordercolor = "black"
  o.undercolor = "white"
  o.outfile = name

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

    local orr = (o.rotate and "rotate " .. r or "") .. (o.skew and " skewX " .. s or "")

    local bx, by = 150 + 1.1 * x, 40 + 2 * y

    o["xx" .. i] = x
    o["yy" .. i] = y
    o["or" .. i] = orr
    o["cc" .. i] = char
    o["bx" .. i] = bx
    o["by" .. i] = by
  end

  local rdr = assert(io.popen(string.gsub("2>&1 " .. cmd, "%${?(%w+)}?", o), "r"))
  local out = rdr:read("*a")
  if out ~= "" then error("captchastore: generating captcha causes error: " .. out) end

  return table.concat(chars)
end

return store.new
