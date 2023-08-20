# lua-captchastore: All-in-one captcha handling library

Just copy captchastore.lua into your source tree.

Tested on Linux with Lua 5.3, will probably work on other Unix systems, will probably NOT work on Windows.

Dependencies:
* lsqlite3
* ImageMagick's `convert` in `$PATH`

## Usage

```lua
local newcaptchastore = require "captchastore"

-- Initialize a capchastore with 200 cached captchas.
local store = newcaptchastore("captchas.db", 200)

-- Get a cached captcha.
local token, imagepath, correct_answer = store:get()

-- Give the user the image with `imagepath`,
-- then let the user send back `token` and their answer.

local user_answer = ...

-- Verify the user's answer
local is_correct, err = store:verify(token, answer)
if is_correct then -- Captcha completed
elseif err == store.EWRONG then -- The wrong answer is provided
elseif err == store.ETOKEN then -- The token does not exists anymore, request a new captcha
end
```

This project neither been licensed nor thoroughly tested yet, use at your own discretion.