; Minimal JSON reader for AHK v2. JSON.Parse returns Map for objects,
; Array for arrays, String for strings, Number for numbers, true/false for
; booleans, and "" for null. Throws on malformed input. Read-only: the suite
; only needs to parse Chrome's Bookmarks file, so there is no serializer.
; Tokens are regex-matched in place; per-char SubStr on a property copied the text.

class JSON {
    static Parse(text) {
        pos := 1
        v := JSON.Value(&text, &pos)
        RegExMatch(text, "\G[ \t\n\r]*+", &m, pos)
        if pos + m.Len <= StrLen(text)
            throw Error("JSON: trailing data at pos " (pos + m.Len))
        return v
    }

    static Value(&s, &pos) {
        static re := 'S)\G[ \t\n\r]*+(?:\{(*MARK:o)|\[(*MARK:a)'
            . '|"([^"\\]*+(?:\\.[^"\\]*+)*+)"(*MARK:s)'
            . '|true(*MARK:t)|false(*MARK:f)|null(*MARK:n)'
            . '|(-?(?:0|[1-9]\d*+)(?:\.\d++)?(?:[eE][+-]?\d++)?)(*MARK:d))'
        if !RegExMatch(s, re, &m, pos)
            throw Error("JSON: unexpected char at pos " pos)
        pos += m.Len
        switch m.Mark, true {
            case "o": return JSON.Obj(&s, &pos)
            case "a": return JSON.Arr(&s, &pos)
            case "s": return JSON.Unescape(m[1])
            case "t": return true
            case "f": return false
            case "n": return ""
            default: return Number(m[2])
        }
    }

    static Obj(&s, &pos) {
        obj := Map()
        if RegExMatch(s, "S)\G[ \t\n\r]*+\}", &e, pos) {
            pos += e.Len
            return obj
        }
        loop {
            if !RegExMatch(s, 'S)\G[ \t\n\r]*+"([^"\\]*+(?:\\.[^"\\]*+)*+)"[ \t\n\r]*+:', &k, pos)
                throw Error("JSON: expected key at pos " pos)
            pos += k.Len
            obj[JSON.Unescape(k[1])] := JSON.Value(&s, &pos)
            if !RegExMatch(s, "S)\G[ \t\n\r]*+([,}])", &d, pos)
                throw Error("JSON: expected ',' or '}' at pos " pos)
            pos += d.Len
            if d[1] = "}"
                return obj
        }
    }

    static Arr(&s, &pos) {
        arr := []
        if RegExMatch(s, "S)\G[ \t\n\r]*+\]", &e, pos) {
            pos += e.Len
            return arr
        }
        loop {
            arr.Push(JSON.Value(&s, &pos))
            if !RegExMatch(s, "S)\G[ \t\n\r]*+([,\]])", &d, pos)
                throw Error("JSON: expected ',' or ']' at pos " pos)
            pos += d.Len
            if d[1] = "]"
                return arr
        }
    }

    static Unescape(str) {
        if !InStr(str, "\")
            return str
        out := "", i := 1
        while j := InStr(str, "\", true, i) {
            out .= SubStr(str, i, j - i)
            c := SubStr(str, j + 1, 1)
            i := j + 2
            switch c, true {
                case '"', "\", "/": out .= c
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    if !RegExMatch(str, "\G[0-9a-fA-F]{4}", &h, i)
                        throw Error("JSON: bad \u escape")
                    code := Integer("0x" h[0]), i += 4
                    ; Combine a UTF-16 surrogate pair into one code point.
                    if code >= 0xD800 && code <= 0xDBFF && RegExMatch(str, "i)\G\\u(d[c-f][0-9a-f]{2})", &lo, i) {
                        code := 0x10000 + ((code - 0xD800) << 10) + (Integer("0x" lo[1]) - 0xDC00)
                        i += 6
                    }
                    out .= Chr(code)
                default:
                    throw Error("JSON: bad escape \" c)
            }
        }
        return out SubStr(str, i)
    }
}
