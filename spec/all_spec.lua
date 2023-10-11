local newcaptchastore = require "captchastore"

describe("lua-captchastore", function()
  it("should work", function()
    os.execute("rm -rf /tmp/captchas /tmp/test.db")
    os.execute("mkdir -p /tmp/captchas")
    local store = newcaptchastore("/tmp/test.db", "/tmp/captchas", 5)

    local token, image, answer

    token, image, answer = store:get()
    assert.are.equal(true, store:verify(token, answer))

    token, image, answer = store:get()
    assert.are.same({false, store.ETOKEN}, {store:verify(-1, answer)})

    token, image, answer = store:get()
    assert.are.same({false, store.EWRONG}, {store:verify(token, "thisiswrong")})

    store:refresh()
    assert.are.equal(true, store:verify(token, answer))
    store:refresh()
    assert.are.same({false, store.ETOKEN}, {store:verify(token, answer)})
  end)
end)
