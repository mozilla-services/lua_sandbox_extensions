# JOSE Module

## Overview
A lua wrapper for cjose, a C library implementing Javascript Object Signing and
Encryption (JOSE).

## Module

### Example Usage
```lua
require "jose"
```
### Functions

#### version
```lua
require "jose"
local v = jose.version()
-- v == "0.0.1"
```

Returns a string with the version of the cjose wrapper.

*Arguments*
- none

*Return*
- version (string) Semantic version

#### header
```lua
require "jose"
local hdr = jose.header({alg = "HS256"})
```

Instantiates a new header object.

*Arguments*
- values (table) String key/value pairs to add to the header

*Return*
- header (userdata) header object

#### jwk_import
```lua
require "jose"
local jwk = jose.jwk_import([{"kty":"oct", "k":"GawgguFyGrWKav7AX4VKUg"}]])
```

Instantiates a new JWK given a JSON document representation conforming to JSON
Web Key (JWK) IETF ID draft-ietf-jose-json-web-key.

*Arguments*
- json (string) A JSON string conforming to the Jose JWK specification

*Return*
- jwk (userdata) JSON Web Key or throws on error

#### jws_import
```lua
require "jose"
local jws = jose.jws_import(cs)
```

Creates a new JWS object from the given JWS compact serialization.

*Arguments*
- cs (string) A JWS in compact serialized form

*Return*
- jws (userdata) JSON Web Signature or throws on error

#### jws_sign
```lua
require "jose"
local hdr = jose.header({alg = "HS256"})
local jws = jose.jws_sign(jwk, "data to sign", hdr)
```

Creates a new JWS by signing the given plaintext within the given header and
JWK.

*Arguments*
- jwk (userdata) The key to use for signing the JWS
- plaintext (string) The plaintext to be signed as the JWS payload.
- header (userdata) Protected headers, must contain at least `alg` to use for
signing see: [Algorithm](https://github.com/cisco/cjose/blob/master/src/header.c#L13)

*Return*
- jws (userdata) JSON Web Signature or throws on error

#### jwe_import
```lua
require "jose"
local jws = jose.jwe_import(cs)
```

Creates a new JWE object from the given JWE compact serialization.

*Arguments*
- cs (string) a JWE in compact serialized form

*Return*
- jwe (userdata) JSON Web Encryption or throws on error

#### jwe_encrypt
```lua
require "jose"
local hdr = jose.header({alg = "RSA-OAEP", enc ="A256GCM"})
local jws = jose.jwe_encrypt(jwk, "data to encrypt", hdr)
```

Creates a compact serialization of the given JWE object.

*Arguments*
- jwk (userdata) The key to use for signing the JWS
- plaintext (string) The plaintext to be encrypted in the JWE payload
- header (userdata) - Protected headers, must contain at least `alg` and
`enc` values

*Return*
- jwe (userdata) JSON Web Encryption or throws on error

### Header Methods

#### get
```lua
local hdr = jose.header({alg = "RSA-OAEP", enc ="A256GCM"})
local v = hdr:get("alg")
-- v == "RSA-OAEP"
```
Retrieves the value of the requested header attribute from the header object.

*Arguments*
- name (string) Attribute name

*Return*
- value (string) Attribute value or NIL

### JWS Methods

#### verify
```lua
local ok = jws:verify(jwk)
```
Verifies the JWS object using the given JWK.

*Arguments*
- jwk (userdata) The key to use for verification

*Return*
- ok (bool) True on success

#### export
```lua
local cs = jws:export()
```
Creates a compact serialization of the given JWS object.

*Arguments*
- none

*Return*
- cs (string) Compact serialization of this JWS or throws on error

#### plaintext
```lua
local txt = jws:plaintext()
```
Returns the plaintext data of the JWS payload.

*Arguments*
- none

*Return*
- plaintext (string) Text of the JWS or throws on error

#### header
```lua
local hdr = jws:header()
```
Returns the protected header of the JWS payload.

*Arguments*
- none

*Return*
- header (userdata) Protected JWS header

### JWE Methods

#### export
```lua
local cs = jwe:export()
```
Creates a compact serialization of the given JWE object.

*Arguments*
- none

*Return*
- cs (string) Compact serialization of this JWE or throws on error

#### decrypt
```lua
local txt = jwe:decrypt(jwk)
```
Decrypts the JWE object using the given JWK. Returns the plaintext data of the
JWE payload.

*Arguments*
- jwk (userdata) The key to use for signing the JWS

*Return*
- plaintext (string) The decrypted content or throws on error

#### header
```lua
local hdr = jwe:header()
```
Returns the protected header of the JWE object.

*Arguments*
- none

*Return*
- header (userdata) Protected JWE header
