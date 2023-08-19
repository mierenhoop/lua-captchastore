local captchastore = require "captchastore"

describe("lua-captchastore", function()
  it("should work", function()
    local store = captchastore.new("/tmp/test.db", "/tmp", 5)

    local token, image, answer = store:get()

    assert.are.equal(true, store:verify(token, answer))
    assert.are.same({false, store.ETOKEN}, {store:verify(-1, answer)})
    assert.are.same({false, store.EWRONG}, {store:verify(token, "wrong")})

    store:refresh()
    assert.are.equal(true, store:verify(token, answer))
    store:refresh()
    assert.are.same({false, store.ETOKEN}, {store:verify(token, answer)})
  end)
end)
