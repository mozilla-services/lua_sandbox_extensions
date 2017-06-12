-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "jose"
assert(jose.version() == "0.0.1", jose.version())

local payload = string.rep("The quick brown fox jumps over the lazy dog", 100)

-- RSA 4096 public and private params, without CRT params
local rsa = [[
{
  "kty": "RSA",
  "e": "AQAB",
  "n": "vlbWUA9HUDHB5MDotmXObtE_Y4zKtGNtmPHUy_xkp_fSr0BxNdSOUzvzoAhK3sxTqpzVujKC245RHJ84Hhbl-KDj-n7Ee8EV3nKpnsqiBgHyc3rBpxpIi0J8kYmpiPGXu7k4xnCWCeiu_gfFGzvPdLHzlV7WOfYIHvymtbS7WOyTQLBgDjUKfHdJzH75vogy35h_mEcS-pde-EIi7u4OqD3bNW7iLbf2JVLtSNUYNCMMu23GsOEcBAsdf4QMq5gU-AEFK4Aib8mSPi_tXoohembr-JkzByRAkHbdzoGXssj0EHESt4reDfY8enVo5ACKmzbqlIJ1jmPVV6EKPBPzcQiN9dUA43xei2gmRAswdUKnexVPAPFPfKMpLqr24h1e7jHFBQL23-QqZX-gASbEDiYa9GusSY4kRn80hZRqCq4sgIRVEiu3ofjVdo4YzzESAkmfgFayUThhakqP82_wr9_Uc2vw3ZtlaTC_0LY70ne9yTy3SD3yEOa649nOTBfSh156YGtxvaHHidFojVHpPHBmjGAlak--mONHXHn00l_CVivUcuBqIGcZXRfiO6YwVDH_4ZTVzAkDov1C-4SNJK0XKeIwvGSspaSQrTmH_pT66L7tIhdZLTMVMh2ahnInVZP2G_-motugLq-x962JLQuLLeuh_r_Rk4VHZYhOgoc",
  "kid": "2940921e-3646-451c-8510-971552754e74",
  "d": "oMyvxXcC4icHDQBEGUOswEYabTmWTgrpnho_kg0p5BUjclbYzYdCreKqEPqwdcTcsfhJP0JI9r8mmy2PtSvXINKbhxXtXDdlCEaKMdIySyz97L06OLelrbB_mFxaU4z2iOsToeGff8OJgqaByF4hBw8HH5u9E75cYgFDvaJv29IRHMdkftwkfb4xJIfo6SQbBnbI5Ja22-lhnA4TgRKwY0XOmTeR8NnHIwUJ3UvZZMJvkTBOeUPT7T6OrxmZsqWKoXILMhLQBOyfldXbjNDZM5UbqSuTxmbD_MfO3xTwWWQXfIRqMZEpw1XRBguGj4g9kJ82Ujxcn-yLYbp08QhR0ijBY13HzFVMZ2jxqckrvp3uYgfJjcCN9QXZ6qlv40s_vJRRgv4wxdDc035eoymqGQby0UnDTmhijRV_-eAJQvdl3bv-R5dH9IzhxoJA8xAqZfVtlehPuGaXDAsa4pIWSg9hZkMdDEjW15g3zTQi3ba8_MfmnKuDe4GXYBjrH69z7epxbhnTmKQ-fZIxboA9sYuJHj6pEGT8D485QmrnmLjvqmQUzcxnpU6E3awksTp_HeBYLLbmrv4DPGNyVri2yPPTTRrNBtbWkuvEGVnMhvL2ed9uqLSnH8zOfgWqstqjxadxKADidYEZzmiYfEjYTDZGd9VDIUdKNGHWGFRB7UE",
  "p": "6VtjaNMD_VKTbs7sUQk-qjPTn6mCI8_3loqrOOy32b1G0HfIzCijuV-L7g7RxmMszEEfEILxRpJnOZRehN8etsIEuCdhU6VAdhBsBH5hIA9ZtX8GIs0sPrhc4kzPiwJ6JcLytUc6HCTICf2FIU7SI8I17-p53d35VItYiC1sGLZ2yN61VoKYNTncUSwboP2zXmGv4FPB5wQogryA_bEn-1U12FFSRd75Ku9GAEVxbTk3OaQqYgqfo9LnAWvunTDu31D4uyC6rze77NCo8UguqCpFjvF0ihOryQI6C3d0e8kxcM1vJbMvZNfrDN65btzqWi4m-CnqGYkl6BXQtS5UVw",
  "q": "0M7h_gtxoVoNPLRjYA5zBUD8qmyWiAzjloFOrDRLJwiD4OPHgImUx2WPTiSCjouvGqwfJh1jEEryJV_d0e4iVGyKYbFeXfzadwYXXR2jK4QwO1V_JDHI7HUYwNl6qzZqATi2zNKunPgIwY55gWBKjP2aUvPUBAcTeCsUPvrN_SajPVfc2wSlA2TvEnjmweNvgSTNqtBlMpmpwvEb9WXfv4pl3BfRvoTk3VR4icyvl-PLFedp2y0Fs0aQ4LRQ2ZMKWyGQEam_uAoa1tXrRJ_yQRvtWm1K8GpRZGKwN3TvtAg649PxQ7tJ8cvh3BwQROJyQBZDrlR04wqvDK4SNezlUQ"
}]]

local symetric = [[{"kty":"oct", "k":"GawgguFyGrWKav7AX4VKUg"}]]

local jwk = jose.jwk_import(rsa)
local sjwk = jose.jwk_import(symetric)
local hdr = jose.header({alg = "RSA-OAEP", enc = "A256GCM"})
local chdr = jose.header({alg = "RSA-OAEP", enc = "A256GCM", zip="DEF"})
local xhdr = jose.header({alg = "RSA-OAEP", enc = "A256GCM", zip="XXX"}) -- unknown compression ignored
local bad = jose.header({alg = "foo", enc = "A256GCM"})

local construction_errors = {
    {fn = jose.jwk_import, args = {}        , err ="bad argument #0 to '?' (incorrect number of arguments)"},
    {fn = jose.jwk_import, args = {true}    , err ="bad argument #1 to '?' (string expected, got boolean)"},
    {fn = jose.jwk_import, args = {"foo"}   , err ="file: jwk.c line: 1555 function: cjose_jwk_import message: invalid argument"},

    {fn = jose.jwe_import, args = {}        , err ="bad argument #0 to '?' (incorrect number of arguments)"},
    {fn = jose.jwe_import, args = {true}    , err ="bad argument #1 to '?' (string expected, got boolean)"},
    {fn = jose.jwe_import, args = {"not cs"}, err ="file: base64.c line: 111 function: _decode message: invalid argument"},

    {fn = jose.jwe_encrypt, args = {}       , err ="bad argument #0 to '?' (incorrect number of arguments)"},
    {fn = jose.jwe_encrypt, args = {true, payload, hdr},
        err ="bad argument #1 to '?' (mozsvc.jose.jwk expected, got boolean)"},
    {fn = jose.jwe_encrypt, args = {jwk, nil, hdr}
        , err ="bad argument #2 to '?' (string expected, got nil)"},
    {fn = jose.jwe_encrypt, args = {jwk, payload, true},
        err = "bad argument #3 to '?' (mozsvc.jose.hdr expected, got boolean)"},
    {fn = jose.jwe_encrypt, args = {jwk, payload, bad},
        err ="file: jwe.c line: 179 function: _cjose_jwe_validate_hdr message: invalid argument"},

    {fn = jose.jws_import, args = {}        , err ="bad argument #0 to '?' (incorrect number of arguments)"},
    {fn = jose.jws_import, args = {true}    , err ="bad argument #1 to '?' (string expected, got boolean)"},
    {fn = jose.jws_import, args = {"not cs"}, err ="file: jws.c line: 778 function: cjose_jws_import message: invalid argument"},


    {fn = jose.jws_sign, args = {}          , err ="bad argument #0 to '?' (incorrect number of arguments)"},
    {fn = jose.jws_sign, args = {true, payload, "HS256"},
        err ="bad argument #1 to '?' (mozsvc.jose.jwk expected, got boolean)"},
    {fn = jose.jws_sign, args = {jwk, nil, "HS256"},
        err ="bad argument #2 to '?' (string expected, got nil)"},
    {fn = jose.jws_sign, args = {jwk, payload, true},
        err = "bad argument #3 to '?' (mozsvc.jose.hdr expected, got boolean)"},
    {fn = jose.jws_sign, args = {jwk, payload, bad},
        err = "file: jws.c line: 112 function: _cjose_jws_validate_hdr message: invalid argument"},
}

for i, v in ipairs(construction_errors) do
    local ok, err = pcall(v.fn, unpack(v.args))
    if err ~= v.err then error(string.format("error test %d failed %s\n", i, err)) end
end

local zip = xhdr:get("zip")
assert(zip == "XXX", zip)

local jwe = jose.jwe_encrypt(jwk, payload, hdr)
local dpayload = jwe:decrypt(jwk)
assert(dpayload == payload, dpayload)
local thdr = jwe:header()
local alg = thdr:get("alg")
assert(alg == "RSA-OAEP", alg)

local epayload = jwe:export()
assert(#epayload == 6571, tostring(#epayload))
local jwe1 = jose.jwe_import(epayload)
dpayload = jwe1:decrypt(jwk)
assert(dpayload == payload, dpayload)

local ok, err = pcall(jwe.export, jwe, "foo")
if err ~= "bad argument #0 to '?' (incorrect number of arguments)" then error(string.format("%s\n", err)) end
ok, err = pcall(jwe.decrypt, jwe, "not cs")
if err ~= "bad argument #2 to '?' (mozsvc.jose.jwk expected, got string)" then error(string.format("%s\n", err)) end

jwe = jose.jwe_encrypt(jwk, payload, chdr)
dpayload = jwe:decrypt(jwk)
assert(dpayload == payload, dpayload)

epayload = jwe:export()
assert(#epayload == 958, tostring(#epayload))
jwe1 = jose.jwe_import(epayload)
dpayload = jwe1:decrypt(jwk)
assert(dpayload == payload, dpayload)

jwe = jose.jwe_encrypt(jwk, payload, xhdr)
dpayload = jwe:decrypt(jwk)
assert(dpayload == payload, dpayload)

epayload = jwe:export()
assert(#epayload == 6590, tostring(#epayload))
jwe1 = jose.jwe_import(epayload)
dpayload = jwe1:decrypt(jwk)
assert(dpayload == payload, dpayload)

local shdr = jose.header({alg = "HS256"})
local jws = jose.jws_sign(sjwk, payload, shdr)
dpayload = jws:plaintext()
assert(dpayload == payload, dpayload)
local token = jws:export()
jws = jose.jws_import(token)
assert(jws:verify(sjwk))
dpayload = jws:plaintext()
assert(dpayload == payload, dpayload)
thdr = jws:header()
alg = thdr:get("alg")
assert(alg == "HS256", alg)

local ok, err = pcall(jws.export, jws, "foo")
if err ~= "bad argument #0 to '?' (incorrect number of arguments)" then error(string.format("%s\n", err)) end
ok, err = pcall(jws.plaintext, jws, "foo")
if err ~= "bad argument #0 to '?' (incorrect number of arguments)" then error(string.format("%s\n", err)) end
ok, err = pcall(jws.verify, jws, "not cs")
if err ~= "bad argument #2 to '?' (mozsvc.jose.jwk expected, got string)" then error(string.format("%s\n", err)) end

if read_config then
    local big = string.rep("0123456789", 70000)
    jwe = jose.jwe_encrypt(jwk, big, chdr) -- exceeds the output_limit
    ok, err = pcall(jwe.decrypt, jwe, jwk)
    assert(err == "decompression failed", err)
end
