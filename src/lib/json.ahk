; Minimal JSON reader for AHK v2. JSON.Parse returns Map for objects,
; Array for arrays, String for strings, Number for numbers, true/false for
; booleans, and "" for null. Throws on malformed input. Read-only: the suite
; only needs to parse Chrome's Bookmarks file, so there is no serializer.

class JSON {
    static Parse(text) => JSONParser(text).Parse()
}

class JSONParser {
    __New(text) {
        this.s := text
        this.i := 1
        this.n := StrLen(text)
    }

    Parse() {
        this.Ws()
        v := this.Value()
        this.Ws()
        if this.i <= this.n
            throw Error("JSON: trailing data at pos " this.i)
        return v
    }

    Ws() {
        while this.i <= this.n {
            c := SubStr(this.s, this.i, 1)
            if c = " " || c = "`t" || c = "`n" || c = "`r"
                this.i++
            else
                break
        }
    }

    Value() {
        switch SubStr(this.s, this.i, 1) {
            case "{": return this.Obj()
            case "[": return this.Arr()
            case '"': return this.Str()
            case "t", "f": return this.Bool()
            case "n": return this.Null()
            default: return this.Num()
        }
    }

    Obj() {
        m := Map()
        this.i++
        this.Ws()
        if SubStr(this.s, this.i, 1) = "}" {
            this.i++
            return m
        }
        loop {
            this.Ws()
            key := this.Str()
            this.Ws()
            if SubStr(this.s, this.i, 1) != ":"
                throw Error("JSON: expected ':' at pos " this.i)
            this.i++
            this.Ws()
            m[key] := this.Value()
            this.Ws()
            c := SubStr(this.s, this.i, 1)
            this.i++
            if c = "}"
                return m
            if c != ","
                throw Error("JSON: expected ',' or '}' at pos " (this.i - 1))
        }
    }

    Arr() {
        a := []
        this.i++
        this.Ws()
        if SubStr(this.s, this.i, 1) = "]" {
            this.i++
            return a
        }
        loop {
            this.Ws()
            a.Push(this.Value())
            this.Ws()
            c := SubStr(this.s, this.i, 1)
            this.i++
            if c = "]"
                return a
            if c != ","
                throw Error("JSON: expected ',' or ']' at pos " (this.i - 1))
        }
    }

    Str() {
        if SubStr(this.s, this.i, 1) != '"'
            throw Error("JSON: expected string at pos " this.i)
        this.i++
        out := ""
        loop {
            c := SubStr(this.s, this.i, 1)
            if c = ""
                throw Error("JSON: unterminated string")
            this.i++
            if c = '"'
                return out
            if c != "\" {
                out .= c
                continue
            }
            e := SubStr(this.s, this.i, 1)
            this.i++
            switch e {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    code := Integer("0x" SubStr(this.s, this.i, 4))
                    this.i += 4
                    ; Combine a UTF-16 surrogate pair into one code point.
                    if code >= 0xD800 && code <= 0xDBFF && SubStr(this.s, this.i, 2) = "\u" {
                        lo := Integer("0x" SubStr(this.s, this.i + 2, 4))
                        this.i += 6
                        code := 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
                    }
                    out .= Chr(code)
                default:
                    throw Error("JSON: bad escape \\" e)
            }
        }
    }

    Bool() {
        if SubStr(this.s, this.i, 4) = "true" {
            this.i += 4
            return true
        }
        if SubStr(this.s, this.i, 5) = "false" {
            this.i += 5
            return false
        }
        throw Error("JSON: bad literal at pos " this.i)
    }

    Null() {
        if SubStr(this.s, this.i, 4) = "null" {
            this.i += 4
            return ""
        }
        throw Error("JSON: bad literal at pos " this.i)
    }

    Num() {
        start := this.i
        while this.i <= this.n && InStr("0123456789+-.eE", SubStr(this.s, this.i, 1))
            this.i++
        numStr := SubStr(this.s, start, this.i - start)
        if numStr = ""
            throw Error("JSON: unexpected char at pos " start)
        return numStr + 0
    }
}
