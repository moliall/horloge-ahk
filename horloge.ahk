#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows(true)
CoordMode("Mouse", "Screen")

; Win + N : affiche/masque le panneau — Échap ou clic ailleurs : ferme
;
; CALENDRIER : clic sur une date = écart avec aujourd'hui, 2e clic = écart entre les deux
;              clic sur le résultat = efface — molette = change de mois — clic sur le mois = aujourd'hui
;
; SAISIE (Entrée sur un calcul = copie le résultat, flèches haut/bas = historique)
;   Calculs      50k*5   2^10   (3+4)*2   sqrt(16)   0xFF   0b1010
;   Pourcentages 150 + 20%   150 - 20%   20% de 150
;   HT / TTC     150 ht   180 ttc   100 ht 5,5%
;   Durées       10min+5000s   1h30 - 45min   5000s en min
;   Quantités    2km + 300m   3,5 Go en Mo   1500 g en kg
;   Devises      50€ en $   20 usd + 10 €   100 chf en eur
;   Bases        255 en hex   255 en bin   0xFF en dec
;   Dates        25/12   auj + 45j   demain + 2 sem   25/12 - 01/11
;   Minuteur     t 25   t 1h30 pâtes   t stop
;   Alarme       @18h30   @7h réveil
;   Autoclic     auto F6 5ms   auto F7 50ms droit x100   auto F8 10ms maintien   auto stop

; ===== Réglages =====
C_BG      := "1F1F1F"   ; fond
C_ACCENT  := "0067C0"   ; dates sélectionnées
C_RANGE   := "263548"   ; jours entre deux dates
C_TODAY   := "4CC2FF"   ; jour actuel + lignes d'état
PANEL_W   := 280        ; largeur du contenu
FADE_MS   := 120        ; durée du fondu d'ouverture
TIMER_RE  := "i)^\s*(?:t|timer|minuteur)(?:\s+(.*))?$"
ALARM_RE  := "^\s*@\s*(\d{1,2})(?:[h:](\d{2})?)?\s*(.*)$"
AUTO_RE   := "i)^\s*auto(?:\s+(.*))?$"

; ===== État =====
popup := 0, fading := false, fadeStart := 0, openTick := 0
timeTxt := 0, dateTxt := 0
calTitle := 0, calCells := [], cellDates := [], cellKeys := [], calResult := 0
calY := 0, calM := 0, selA := "", selB := ""
inputEdit := 0, resultTxt := 0, timerTxt := 0, autoTxt := 0
timerEnd := 0, timerTotal := 0, timerLabel := "", timerAt := ""
autoCfg := 0, autoOn := false, autoStopTick := 0
hist := [], histPos := 1

SetTimer(() => LoadRates(), -100)        ; taux de change au démarrage
SetTimer(LoadRates, 6 * 3600 * 1000)     ; puis toutes les 6 h

#n:: {
    Send("{Blind}{vkE8}")   ; empêche le menu Démarrer de s'ouvrir au relâchement de Win
    if StartMenuOpen() {    ; menu Démarrer / recherche déjà ouvert : on le ferme, sinon il garde le focus
        Send("{Esc}")
        Sleep(60)
    }
    TogglePopup()
}

StartMenuOpen() => WinActive("ahk_exe StartMenuExperienceHost.exe")
                || WinActive("ahk_exe SearchHost.exe")
                || WinActive("ahk_exe SearchApp.exe")

#HotIf popup && WinActive(popup)
Enter::Submit()
NumpadEnter::Submit()
Up::HistNav(-1)
Down::HistNav(1)
Escape::ClosePopup()
WheelUp::ChangeMonth(1)
WheelDown::ChangeMonth(-1)
#HotIf

TogglePopup() {
    global popup
    if popup
        ClosePopup()
    else
        OpenPopup()
}

; ================= Construction =================
BuildGui() {
    global popup, timeTxt, dateTxt, calTitle, calCells, cellDates, cellKeys, calResult
    global calY, calM, selA, selB, inputEdit, resultTxt, timerTxt, autoTxt
    global hist, histPos

    popup := Gui("+AlwaysOnTop -Caption +ToolWindow")
    popup.BackColor := C_BG
    popup.MarginX := 20
    popup.MarginY := 16

    ; Heure + date
    popup.SetFont("s36 cFFFFFF", "Segoe UI Semibold")
    timeTxt := popup.AddText("xm w" PANEL_W " Center")
    popup.SetFont("s12 cB0B0B0", "Segoe UI")
    dateTxt := popup.AddText("xm y+0 w" PANEL_W " Center")

    Separator()

    ; Calendrier : en-tête
    popup.SetFont("s11 cFFFFFF", "Segoe UI Semibold")
    prev := popup.AddText("xm y+8 w40 h28 Center +0x200", "‹")
    calTitle := popup.AddText("x+0 yp w200 h28 Center +0x200")
    next := popup.AddText("x+0 yp w40 h28 Center +0x200", "›")
    for ev in ["Click", "DoubleClick"] {
        prev.OnEvent(ev, (*) => ChangeMonth(-1))
        next.OnEvent(ev, (*) => ChangeMonth(1))
        calTitle.OnEvent(ev, (*) => GoToday())
    }

    popup.SetFont("s9 c8A8A8A", "Segoe UI")
    for i, j in ["lu", "ma", "me", "je", "ve", "sa", "di"]
        popup.AddText((i = 1 ? "xm y+4" : "x+0 yp") " w40 h20 Center", j)

    ; Grille 6 x 7
    popup.SetFont("s10 cE0E0E0", "Segoe UI")
    calCells := [], cellDates := [], cellKeys := []
    Loop 42 {
        opt := Mod(A_Index - 1, 7) = 0 ? "xm y+" (A_Index = 1 ? 2 : 0) : "x+0 yp"
        ctl := popup.AddText(opt " w40 h28 Center +0x200 Background" C_BG)
        ctl.OnEvent("Click", CellClick.Bind(A_Index))
        ctl.OnEvent("DoubleClick", CellClick.Bind(A_Index))
        calCells.Push(ctl), cellDates.Push(""), cellKeys.Push("")
    }
    popup.SetFont("s10 cB0B0B0", "Segoe UI")
    calResult := popup.AddText("xm y+6 w" PANEL_W " Center")
    calResult.OnEvent("Click", (*) => ClearSel())

    Separator()

    ; Saisie : champ "multi-ligne" utilisé sur une ligne, pour pouvoir centrer le texte verticalement
    popup.SetFont("s12 cFFFFFF", "Segoe UI")
    inputEdit := popup.AddEdit("xm y+12 w" PANEL_W " h36 -E0x200 +Multi -VScroll -HScroll -Wrap Background2A2A2A")
    inputEdit.OnEvent("Change", (*) => Preview())
    CenterEditText(inputEdit, 10)

    popup.SetFont("s10 c9A9A9A", "Segoe UI")
    resultTxt := popup.AddText("xm y+6 w" PANEL_W " Right")
    timerTxt := popup.AddText("xm y+4 w" PANEL_W " c" C_TODAY)
    timerTxt.OnEvent("Click", (*) => StopTimer())
    autoTxt := popup.AddText("xm y+2 w" PANEL_W " c" C_TODAY)
    autoTxt.OnEvent("Click", (*) => AutoRemove())

    popup.OnEvent("Escape", (*) => ClosePopup())

    ; Coins arrondis façon Windows 11
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", popup.Hwnd, "Int", 33, "Int*", 2, "Int", 4)

    calY := Integer(A_Year), calM := Integer(A_Mon)
    selA := "", selB := ""
    histPos := hist.Length + 1
    RenderCalendar()
    UpdateClock()
    RefreshTimerUI()
    RefreshAutoUI()
}

; Centre le texte d'un Edit multi-ligne (EM_SETRECT) avec une marge horizontale
CenterEditText(ctl, padX) {
    hFont := SendMessage(0x31, 0, 0, ctl)                      ; WM_GETFONT
    hdc := DllCall("GetDC", "Ptr", ctl.Hwnd, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
    tm := Buffer(64, 0)
    DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    DllCall("ReleaseDC", "Ptr", ctl.Hwnd, "Ptr", hdc)
    lineH := NumGet(tm, 0, "Int")
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", ctl.Hwnd, "Ptr", rc)
    cw := NumGet(rc, 8, "Int"), ch := NumGet(rc, 12, "Int")
    top := Max(0, (ch - lineH) // 2)
    NumPut("Int", padX, "Int", top, "Int", cw - padX, "Int", top + lineH, rc)
    SendMessage(0xB3, 0, rc.Ptr, ctl)                          ; EM_SETRECT
}

Separator() {
    global popup
    popup.AddText("xm y+12 w" PANEL_W " h1 Background3A3A3A")
}

; ================= Ouverture / fermeture =================
OpenPopup() {
    global popup, fading, fadeStart, openTick
    BuildGui()
    GetMouseWorkArea(&l, &t, &r, &b)
    popup.Show("Hide")
    WinGetPos(, , &w, &h, popup)
    WinMove(r - w - 12, b - h - 12, , , popup)
    WinSetTransparent(0, popup)
    WinShow(popup)
    WinActivate(popup)

    ; Fondu non bloquant : le panneau peut être refermé à tout moment
    fadeStart := A_TickCount
    openTick := A_TickCount
    fading := true
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    SetTimer(FadeStep, 10)

    SetTimer(UpdateClock, 250)
    SetTimer(CheckFocus, 100)
}

FadeStep() {
    global popup, fadeStart
    k := (A_TickCount - fadeStart) / FADE_MS
    if (!popup || k >= 1) {
        StopFade()
        if popup
            WinSetTransparent("Off", popup)
        return
    }
    WinSetTransparent(Round(255 * (1 - (1 - k) ** 2)), popup)
}

StopFade() {
    global fading
    if !fading
        return
    fading := false
    SetTimer(FadeStep, 0)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}

ClosePopup() {
    global popup
    if !popup
        return
    StopFade()
    SetTimer(UpdateClock, 0)
    SetTimer(CheckFocus, 0)
    p := popup
    popup := 0
    p.Destroy()
}

CheckFocus() {
    global popup, openTick
    if (!popup || WinActive(popup))
        return
    if (A_TickCount - openTick < 700) {     ; juste ouvert : on reprend le focus au lieu de fermer
        try WinActivate(popup)
        return
    }
    ClosePopup()
}

GetMouseWorkArea(&l, &t, &r, &b) {
    MouseGetPos(&mx, &my)
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (mx >= ml && mx < mr && my >= mt && my < mb) {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            return
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
}

; ================= Horloge =================
UpdateClock() {
    global popup, timeTxt, dateTxt
    if !popup
        return
    SetIfChanged(timeTxt, FormatTime(, "HH:mm:ss"))
    SetIfChanged(dateTxt, Capitalize(FormatTime(, "dddd d MMMM yyyy")))
}

; ================= Calendrier =================
RenderCalendar() {
    global popup, calTitle, calCells, cellDates, cellKeys, calY, calM, selA, selB
    if !popup
        return
    first := Format("{:04}{:02}01", calY, calM)
    offset := Mod(Integer(FormatTime(first, "WDay")) + 5, 7)   ; lundi = 0
    start := DateAdd(first, -offset, "Days")
    today := FormatTime(, "yyyyMMdd")
    month := SubStr(first, 1, 6)
    lo := selA, hi := selB
    if (lo != "" && hi != "" && lo > hi)
        t := lo, lo := hi, hi := t

    SetIfChanged(calTitle, Capitalize(FormatTime(first, "MMMM yyyy")))

    Loop 42 {
        d := SubStr(DateAdd(start, A_Index - 1, "Days"), 1, 8)
        cellDates[A_Index] := d
        inMonth := SubStr(d, 1, 6) = month
        if (d = selA || d = selB)
            bg := C_ACCENT, fg := "FFFFFF", wt := "bold"
        else if (hi != "" && d > lo && d < hi)
            bg := C_RANGE, fg := inMonth ? "E0E0E0" : "7A7A7A", wt := "norm"
        else if (d = today)
            bg := C_BG, fg := C_TODAY, wt := "bold"
        else
            bg := C_BG, fg := inMonth ? "E0E0E0" : "5A5A5A", wt := "norm"

        num := FormatTime(d, "d")
        key := num "|" bg "|" fg "|" wt
        if (cellKeys[A_Index] = key)
            continue
        cellKeys[A_Index] := key
        ctl := calCells[A_Index]
        ctl.Value := num
        ctl.Opt("Background" bg)
        ctl.SetFont("c" fg " " wt)
        ctl.Redraw()
    }
    UpdateSelInfo(today)
}

CellClick(i, *) {
    global selA, selB, cellDates
    d := cellDates[i]
    if (selA = "")
        selA := d
    else if (selB = "") {
        if (d = selA)
            selA := ""
        else
            selB := d
    } else
        selA := d, selB := ""
    RenderCalendar()
}

UpdateSelInfo(today) {
    global calResult, selA, selB
    if (selA = "") {
        txt := ""
    } else if (selB = "") {
        n := DateDiff(selA, today, "Days")
        txt := (n = 0 ? "Aujourd'hui" : n > 0 ? "Dans " Plural(n, "jour") : "Il y a " Plural(-n, "jour"))
             . "  ·  " ShortDate(selA)
    } else {
        lo := Min(selA, selB), hi := Max(selA, selB)
        txt := Plural(DateDiff(hi, lo, "Days"), "jour") "  ·  " ShortDate(lo) "  →  " ShortDate(hi)
    }
    SetIfChanged(calResult, txt)
}

ClearSel() {
    global selA, selB
    selA := "", selB := ""
    RenderCalendar()
}

ChangeMonth(delta) {
    global calY, calM
    calM += delta
    if (calM > 12)
        calM := 1, calY += 1
    else if (calM < 1)
        calM := 12, calY -= 1
    RenderCalendar()
}

GoToday() {
    global calY, calM
    calY := Integer(A_Year), calM := Integer(A_Mon)
    RenderCalendar()
}

ShortDate(d) => FormatTime(d, SubStr(d, 1, 4) = A_Year ? "d MMM" : "d MMM yyyy")
LongDate(d) => Capitalize(FormatTime(d, "dddd d MMMM yyyy"))
Plural(n, word) => n " " word (Abs(n) > 1 ? "s" : "")

; ================= Saisie multifonction =================
; Renvoie {t: aperçu, c: texte à copier, run: action à lancer sur Entrée} ou ""
Interpret(s) {
    if RegExMatch(s, AUTO_RE, &m) {
        cfg := ParseAuto(m[1])
        if !IsObject(cfg)
            return {t: autoCfg ? "Entrée : supprimer l'autoclic" : "", c: "", run: AutoRemove}
        return {t: "Entrée : autoclic  ·  " DescribeAuto(cfg), c: "", run: () => AutoSetup(cfg)}
    }
    if RegExMatch(s, TIMER_RE, &m) {
        arg := Trim(m[1])
        if (arg = "" || arg = "stop")
            return {t: timerEnd ? "Entrée : arrêter le minuteur" : "", c: "", run: StopTimer}
        p := ParseTimerArg(arg)
        return {t: "Entrée : minuteur de " FmtTimeLong(p.secs) (p.label != "" ? "  ·  " p.label : ""), c: ""
              , run: () => StartTimer(p.secs, p.label, "")}
    }
    if RegExMatch(s, ALARM_RE, &m) {
        al := ParseAlarm(m)
        return {t: "Entrée : alarme à " al.at " (dans " FmtTimeLong(al.secs) ")", c: ""
              , run: () => StartTimer(al.secs, al.label, al.at)}
    }
    r := Evaluate(s)
    if !IsObject(r)
        return ""
    return {t: "= " r.t, c: r.c, run: ""}
}

Preview() {
    global inputEdit, resultTxt
    try res := Interpret(inputEdit.Value)
    catch
        res := ""
    SetIfChanged(resultTxt, IsObject(res) ? res.t : "")
}

Submit() {
    global inputEdit, resultTxt
    s := inputEdit.Value
    try res := Interpret(s)
    catch as e {
        resultTxt.Value := e.Message
        return
    }
    if !IsObject(res)
        return
    HistPush(s)
    if res.run {
        fn := res.run
        try fn()
        catch as e {
            resultTxt.Value := e.Message
            return
        }
        inputEdit.Value := ""
        resultTxt.Value := ""
        return
    }
    A_Clipboard := StrReplace(res.c, Chr(0xA0), "")
    resultTxt.Value := res.t "  ·  copié"
}

HistPush(s) {
    global hist, histPos
    if (!hist.Length || hist[hist.Length] != s)
        hist.Push(s)
    if (hist.Length > 50)
        hist.RemoveAt(1)
    histPos := hist.Length + 1
}

HistNav(dir) {
    global hist, histPos, inputEdit
    if !hist.Length
        return
    histPos := Max(1, Min(hist.Length + 1, histPos + dir))
    val := histPos <= hist.Length ? hist[histPos] : ""
    inputEdit.Value := val
    SendMessage(0xB1, StrLen(val), StrLen(val), inputEdit)   ; curseur à la fin
    Preview()
}

Evaluate(raw) {
    s := Trim(Calc.Prep(raw))
    if (s = "" || RegExMatch(s, "^[\d.,]+$"))
        return ""

    ; 25/12 peut être une date ou une division : on calcule les deux
    dateRes := ""
    try dateRes := EvalDate(s)
    if (IsObject(dateRes) && !dateRes.ambig)
        return dateRes
    try calcRes := EvalCalc(s)
    catch as e {
        if IsObject(dateRes)
            return dateRes
        throw e
    }
    if IsObject(dateRes)
        return {t: calcRes.t "  ·  " dateRes.short, c: calcRes.c}
    return calcRes
}

EvalCalc(s) {
    ; HT / TTC
    if RegExMatch(s, "i)^(.+?)\s*(?<![a-z])(ht|ttc)(?:\s+(\d+(?:[.,]\d+)?)\s*%?)?$", &m) {
        r := Calc(m[1]).Parse()
        rate := m[3] != "" ? Float(StrReplace(m[3], ",", ".")) : 20
        if (StrLower(m[2]) = "ht")
            other := Qty(r.v * (1 + rate / 100), r.d, r.u), lbl := "TTC"
        else
            other := Qty(r.v / (1 + rate / 100), r.d, r.u), lbl := "HT"
        main := FmtValue(other)
        tva := FmtValue(Qty(Abs(other.v - r.v), r.d, r.u))
        return {t: lbl " " main "  ·  TVA " tva " (" FmtNum(rate) " %)", c: main}
    }

    ; Conversion "... en X"
    tgt := ""
    if RegExMatch(s, "i)^(.+?)\s*(?:\s(?:en|in|to)\s|->|→)\s*([a-zA-Zµ%€$£¥]+)$", &m)
        s := m[1], tgt := m[2]
    r := Calc(s).Parse()
    if (tgt != "") {
        lt := StrLower(tgt)
        if (lt = "hex" || lt = "bin" || lt = "oct" || lt = "dec") {
            out := ToBase(r, lt)
            return {t: out, c: out}
        }
        u := Calc.Unit(tgt)
        if (!u || u.d != r.d)
            throw Error("conversion impossible")
        out := u.d = "cur" ? FmtMoney(r.v / u.f) " " u.n : FmtNum(r.v / u.f) " " tgt
        return {t: out, c: out}
    }
    out := FmtValue(r)
    return {t: out, c: out}
}

; 25/12 · auj + 45j · demain + 2 sem · 25/12 - 01/11
EvalDate(s) {
    if !RegExMatch(s, "i)^(auj(?:ourd'hui)?|demain|hier|\d{1,2}/\d{1,2}(?:/\d{2,4})?)\s*(?:([+-])\s*(.+))?$", &m)
        return ""
    d1 := ParseDate(m[1], m[2] = "")
    if (d1 = "")
        return ""
    ambig := !(m[1] ~= "i)^(auj|demain|hier)")    ; jj/mm seul = peut-être une division
    today := FormatTime(, "yyyyMMdd")
    if (m[2] = "") {
        n := DateDiff(d1, today, "Days")
        rel := n = 0 ? "Aujourd'hui" : n > 0 ? "Dans " Plural(n, "jour") : "Il y a " Plural(-n, "jour")
        return {t: rel "  ·  " LongDate(d1), c: FormatTime(d1, "dd/MM/yyyy"), ambig: ambig
              , short: ShortDate(d1) " : " StrLower(SubStr(rel, 1, 1)) SubStr(rel, 2)}
    }
    d2 := ParseDate(Trim(m[3]))
    if (d2 != "") {
        if (m[2] = "+")
            return ""          ; date + date : on laisse le calcul normal (ex. 1/2 + 1/4)
        n := DateDiff(d1, d2, "Days")
        return {t: Plural(n, "jour"), c: String(n), ambig: ambig, short: "écart " Plural(n, "jour")}
    }
    r := Calc(Trim(m[3])).Parse()
    if (r.d = "")
        days := r.v
    else if (r.d = "time")
        days := r.v / 86400
    else
        throw Error("pas une durée")
    res := DateAdd(d1, Round((m[2] = "-" ? -1 : 1) * days), "Days")
    return {t: LongDate(res), c: FormatTime(res, "dd/MM/yyyy"), ambig: ambig, short: ShortDate(res)}
}

ParseDate(txt, roll := false) {
    txt := StrLower(txt)
    today := FormatTime(, "yyyyMMdd")
    if (txt ~= "^auj")
        return today
    if (txt = "demain")
        return SubStr(DateAdd(today, 1, "Days"), 1, 8)
    if (txt = "hier")
        return SubStr(DateAdd(today, -1, "Days"), 1, 8)
    if !RegExMatch(txt, "^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$", &m)
        return ""
    y := m[3] = "" ? Integer(A_Year) : Integer(m[3])
    if (y < 100)
        y += 2000
    d := Format("{:04}{:02}{:02}", y, Integer(m[2]), Integer(m[1]))
    if !IsTime(d)
        return ""
    if (roll && m[3] = "" && d < today) {         ; date passée sans année → l'an prochain
        d := Format("{:04}{:02}{:02}", y + 1, Integer(m[2]), Integer(m[1]))
        if !IsTime(d)
            return ""
    }
    return d
}

ToBase(r, base) {
    if (r.d != "" || r.v < 0 || r.v != Floor(r.v))
        throw Error("entier positif requis")
    n := Integer(r.v)
    if (base = "dec")
        return String(n)
    if (base = "hex")
        return "0x" Format("{:X}", n)
    if (base = "oct")
        return "0o" Format("{:o}", n)
    out := ""
    while (n > 0)
        out := Mod(n, 2) out, n := n // 2
    return "0b" (out = "" ? "0" : out)
}

TimerSeconds(expr) {
    r := Calc(Trim(Calc.Prep(expr))).Parse()
    if (r.d = "")
        secs := r.v * 60          ; nombre seul = minutes
    else if (r.d = "time")
        secs := r.v
    else
        throw Error("pas une durée")
    if (secs <= 0)
        throw Error("durée nulle")
    return Round(secs)
}

; "25" · "1h30 pâtes" → {secs, label}
ParseTimerArg(arg) {
    try return {secs: TimerSeconds(arg), label: ""}
    parts := StrSplit(arg, " ")
    k := parts.Length - 1
    while (k >= 1) {
        head := "", tail := ""
        for idx, w in parts
            if (idx <= k)
                head .= w " "
            else
                tail .= w " "
        try return {secs: TimerSeconds(Trim(head)), label: Trim(tail)}
        k--
    }
    throw Error("durée invalide")
}

ParseAlarm(m) {
    h := Integer(m[1]), mi := m[2] = "" ? 0 : Integer(m[2])
    if (h > 23 || mi > 59)
        throw Error("heure invalide")
    target := FormatTime(, "yyyyMMdd") Format("{:02}{:02}00", h, mi)
    if (DateDiff(target, A_Now, "Seconds") <= 0)
        target := DateAdd(target, 1, "Days")
    return {secs: DateDiff(target, A_Now, "Seconds"), label: Trim(m[3]), at: Format("{:02}:{:02}", h, mi)}
}

; ================= Minuteur / alarme =================
StartTimer(secs, label, at) {
    global timerEnd, timerTotal, timerLabel, timerAt
    timerTotal := secs, timerLabel := label, timerAt := at
    timerEnd := A_TickCount + secs * 1000
    SetTimer(TimerTick, 250)
    RefreshTimerUI()
}

StopTimer(*) {
    global timerEnd
    timerEnd := 0
    SetTimer(TimerTick, 0)
    RefreshTimerUI()
}

TimerTick() {
    global timerEnd, timerTotal, timerLabel, timerAt
    if !timerEnd
        return
    if (A_TickCount >= timerEnd) {
        title := timerAt != "" ? "Alarme " timerAt : "Minuteur"
        msg := timerLabel != "" ? timerLabel
             : timerAt != "" ? "Il est " timerAt "."
             : "Le minuteur de " FmtTimeLong(timerTotal) " est terminé."
        StopTimer()
        TrayTip(msg, title, 1)
        try SoundPlay(A_WinDir "\Media\Alarm01.wav")
        catch
            SoundBeep(880, 400)
        return
    }
    RefreshTimerUI()
}

RefreshTimerUI() {
    global popup, timerEnd, timerTxt, timerLabel, timerAt
    if !popup
        return
    txt := ""
    if timerEnd
        txt := "⏱  " FormatDuration(Ceil((timerEnd - A_TickCount) / 1000))
             . (timerAt != "" ? "  →  " timerAt : "")
             . (timerLabel != "" ? "  ·  " timerLabel : "")
    SetIfChanged(timerTxt, txt)
}

; ================= Autoclic =================
; auto <touche> [intervalle] [gauche|droit|milieu] [x<nombre>] [maintien]
ParseAuto(arg) {
    arg := Trim(arg)
    if (arg = "" || arg ~= "i)^(stop|off)$")
        return "stop"
    cfg := {key: "", ms: 100, btn: "Left", count: 0, hold: false}
    for tok in StrSplit(arg, " ") {
        if (tok = "")
            continue
        lt := StrLower(tok)
        if (lt = "droit" || lt = "right")
            cfg.btn := "Right"
        else if (lt = "milieu" || lt = "middle")
            cfg.btn := "Middle"
        else if (lt = "gauche" || lt = "left")
            cfg.btn := "Left"
        else if (lt = "maintien" || lt = "hold")
            cfg.hold := true
        else if RegExMatch(lt, "^x(\d+)$", &mm)
            cfg.count := Integer(mm[1])
        else if (ms := TryInterval(tok))
            cfg.ms := ms
        else if (GetKeyVK(tok) && !(lt ~= "^(l|r|m)button$|^wheel")) {
            if (cfg.key != "")
                throw Error("une seule touche possible")
            cfg.key := tok
        } else
            throw Error("paramètre inconnu : " tok)
    }
    if (cfg.key = "")
        throw Error("touche manquante (ex. auto F6 5ms)")
    return cfg
}

TryInterval(tok) {
    try r := Calc(Calc.Prep(tok)).Parse()
    catch
        return 0
    if (r.d = "")
        return r.v > 0 ? r.v : 0            ; nombre seul = ms
    if (r.d = "time")
        return r.v > 0 ? r.v * 1000 : 0
    return 0
}

DescribeAuto(cfg) {
    btn := cfg.btn = "Right" ? "droit" : cfg.btn = "Middle" ? "milieu" : "gauche"
    return cfg.key (cfg.hold ? " maintenu" : "") "  ·  " btn "  ·  " FmtNum(cfg.ms) " ms"
         . (cfg.count ? "  ·  ×" cfg.count : "")
}

AutoSetup(cfg) {
    global autoCfg
    AutoRemove()
    HotIf()          ; raccourci global (sinon il hérite du contexte "panneau actif" de la touche Entrée)
    if cfg.hold {
        Hotkey("*" cfg.key, AutoHoldDown, "On")
        Hotkey("*" cfg.key " up", AutoHoldUp, "On")
    } else
        Hotkey("*" cfg.key, AutoToggle, "On")
    autoCfg := cfg
    RefreshAutoUI()
}

AutoRemove(*) {
    global autoCfg, autoOn
    autoOn := false
    if autoCfg {
        HotIf()
        try Hotkey("*" autoCfg.key, "Off")
        try Hotkey("*" autoCfg.key " up", "Off")
        autoCfg := 0
    }
    RefreshAutoUI()
}

AutoToggle(*) {
    global autoOn, autoStopTick
    if (!autoOn && A_TickCount - autoStopTick < 400)
        return                                  ; même appui que celui déjà détecté par la boucle
    autoOn := !autoOn
    if autoOn {
        SetTimer(ClickLoop, -1)
        ToolTip("Autoclic activé")
        SetTimer(() => ToolTip(), -700)
    } else
        autoStopTick := A_TickCount
    RefreshAutoUI()
}

AutoHoldDown(*) {
    global autoOn
    if autoOn
        return
    autoOn := true
    SetTimer(ClickLoop, -1)
    RefreshAutoUI()
}

AutoHoldUp(*) {
    global autoOn
    autoOn := false
    RefreshAutoUI()
}

; Boucle de clics précise (QueryPerformanceCounter), réagit aux raccourcis entre deux clics
ClickLoop() {
    global autoOn, autoCfg, autoStopTick
    cfg := autoCfg
    if !cfg {
        autoOn := false
        return
    }
    SendMode("Event")          ; SendInput désactive le hook clavier pendant l'envoi → la touche d'arrêt était ratée
    SetMouseDelay(-1)
    keyWas := GetKeyState(cfg.key, "P")
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    freq := 0, nextT := 0, now := 0
    DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &nextT)
    stepT := cfg.ms * freq / 1000
    done := 0
    while autoOn {
        Click(cfg.btn)
        done++
        if (cfg.count && done >= cfg.count) {
            autoOn := false
            break
        }
        nextT += stepT
        loop {
            Sleep(-1)
            ; Lecture directe de la touche en plus du raccourci, pour que l'arrêt ne soit jamais raté
            down := GetKeyState(cfg.key, "P")
            if (cfg.hold && !down)
                autoOn := false
            else if (!cfg.hold && down && !keyWas)
                autoOn := false, autoStopTick := A_TickCount
            keyWas := down
            DllCall("QueryPerformanceCounter", "Int64*", &now)
            remMs := (nextT - now) * 1000 / freq
            if (!autoOn || remMs <= 0)
                break
            if (remMs > 2)
                DllCall("Sleep", "UInt", 1)
        }
        if (now - nextT > stepT * 5)     ; trop de retard → on se recale
            nextT := now
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if !cfg.hold {
        ToolTip("Autoclic désactivé")
        SetTimer(() => ToolTip(), -700)
    }
    RefreshAutoUI()
}

RefreshAutoUI() {
    global popup, autoTxt, autoCfg, autoOn
    if !popup
        return
    txt := autoCfg ? "🖱  " DescribeAuto(autoCfg) (autoOn ? "  ·  actif" : "") : ""
    SetIfChanged(autoTxt, txt)
}

; ================= Taux de change =================
LoadRates() {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 5000)
        req.Open("GET", "https://open.er-api.com/v6/latest/EUR", false)
        req.Send()
        body := req.ResponseText
        pos := InStr(body, '"rates"')
        if (!pos || !InStr(body, '"success"'))
            return
        while (pos := RegExMatch(body, '"([A-Z]{3})"\s*:\s*([\d.eE+-]+)', &m, pos)) {
            Calc.SetCurrency(m[1], Float(m[2]))
            pos += StrLen(m[0])
        }
    }
}

; ================= Moteur de calcul =================
Qty(v, d := "", u := "", pct := false) => {v: v, d: d, u: u, pct: pct}

class Calc {
    static Units := this.MakeUnits()
    static AutoUnits := Map(
        "len",  [["mm", 0.001], ["cm", 0.01], ["m", 1], ["km", 1000]],
        "mass", [["mg", 0.001], ["g", 1], ["kg", 1000], ["t", 1000000]],
        "vol",  [["mL", 0.001], ["cL", 0.01], ["L", 1]],
        "data", [["o", 1], ["Ko", 1024], ["Mo", 1024 ** 2], ["Go", 1024 ** 3], ["To", 1024 ** 4]]
    )

    static MakeUnits() {
        u := Map()
        Def(d, f, names*) {
            for n in names
                u[n] := {d: d, f: f}
        }
        Def("", 1000, "k")
        Def("", 1000000, "M")
        Def("", 1000000000, "Md")
        Def("", 0.01, "%")
        Def("time", 0.001, "ms")
        Def("time", 1, "s", "sec", "seconde", "secondes")
        Def("time", 60, "min", "mn", "minute", "minutes")
        Def("time", 3600, "h", "heure", "heures")
        Def("time", 86400, "j", "jour", "jours")
        Def("time", 604800, "sem", "semaine", "semaines")
        Def("len", 0.001, "mm")
        Def("len", 0.01, "cm")
        Def("len", 0.1, "dm")
        Def("len", 1, "m")
        Def("len", 1000, "km")
        Def("mass", 0.001, "mg")
        Def("mass", 1, "g")
        Def("mass", 1000, "kg")
        Def("mass", 1000000, "t")
        Def("vol", 0.001, "ml")
        Def("vol", 0.01, "cl")
        Def("vol", 0.1, "dl")
        Def("vol", 1, "l")
        Def("data", 1, "o")
        Def("data", 1024, "ko")
        Def("data", 1024 ** 2, "mo")
        Def("data", 1024 ** 3, "go")
        Def("data", 1024 ** 4, "to")
        eur := {d: "cur", f: 1, n: "EUR"}
        for n in ["eur", "€", "euro", "euros"]
            u[n] := eur
        return u
    }

    static SetCurrency(code, rate) {
        static alias := Map("USD", ["$", "dollar", "dollars"], "GBP", ["£", "livre", "livres"], "JPY", ["¥", "yen", "yens"])
        if (rate <= 0)
            return
        k := StrLower(code)
        if (this.Units.Has(k) && this.Units[k].d != "cur")
            return
        entry := {d: "cur", f: 1 / rate, n: code}
        this.Units[k] := entry
        if alias.Has(code)
            for a in alias[code]
                this.Units[a] := entry
    }

    ; Recherche exacte d'abord (M = million, m = mètre), puis en minuscules
    static Unit(name) {
        if this.Units.Has(name)
            return this.Units[name]
        l := StrLower(name)
        return this.Units.Has(l) ? this.Units[l] : 0
    }

    static Prep(s) {
        s := StrReplace(s, "×", "*")
        s := StrReplace(s, "÷", "/")
        s := StrReplace(s, "−", "-")
        return RegExReplace(s, "(\d)[ " Chr(0xA0) "](?=\d{3}(?!\d))", "$1")   ; 50 000 -> 50000
    }

    static Lex(s) {
        toks := [], i := 1, n := StrLen(s)
        while (i <= n) {
            rest := SubStr(s, i)
            if RegExMatch(rest, "^\s+", &m) {
                i += StrLen(m[0])
            } else if RegExMatch(rest, "^0[xX][0-9a-fA-F]+", &m) {
                toks.Push({t: "num", v: Integer(m[0])})
                i += StrLen(m[0])
            } else if RegExMatch(rest, "^0[bB][01]+", &m) {
                val := 0
                Loop Parse SubStr(m[0], 3)
                    val := val * 2 + Integer(A_LoopField)
                toks.Push({t: "num", v: val})
                i += StrLen(m[0])
            } else if RegExMatch(rest, "^(?:\d+(?:[.,]\d+)?|[.,]\d+)", &m) {
                toks.Push({t: "num", v: Float(StrReplace(m[0], ",", "."))})
                i += StrLen(m[0])
            } else if RegExMatch(rest, "^[a-zA-Zµéèêàûô%€$£¥]+", &m) {
                lw := StrLower(m[0])
                toks.Push((lw = "x" || lw = "de") ? {t: "op", v: "*"} : {t: "id", v: m[0]})
                i += StrLen(m[0])
            } else if InStr("+-*/^()", c := SubStr(rest, 1, 1)) {
                toks.Push({t: "op", v: c})
                i++
            } else
                throw Error("caractère inconnu")
        }
        return toks
    }

    __New(s) {
        this.toks := Calc.Lex(s)
        this.i := 1
        this.lastF := 0
    }

    Peek() => this.i <= this.toks.Length ? this.toks[this.i] : {t: "end", v: ""}

    IsOp(v) {
        p := this.Peek()
        return p.t = "op" && p.v = v
    }

    Parse() {
        if !this.toks.Length
            throw Error("vide")
        r := this.Expr()
        if (this.i <= this.toks.Length)
            throw Error("syntaxe")
        return r
    }

    Expr() {
        a := this.Term()
        loop {
            if this.IsOp("+")
                this.i++, a := Calc.Add(a, this.Term(), 1)
            else if this.IsOp("-")
                this.i++, a := Calc.Add(a, this.Term(), -1)
            else
                return a
        }
    }

    Term() {
        a := this.Unary()
        loop {
            if this.IsOp("*")
                this.i++, a := Calc.Mul(a, this.Unary())
            else if this.IsOp("/")
                this.i++, a := Calc.Div(a, this.Unary())
            else if this.IsOp("(")
                a := Calc.Mul(a, this.Unary())
            else
                return a
        }
    }

    Unary() {
        if this.IsOp("-") {
            this.i++
            a := this.Unary()
            return Qty(-a.v, a.d, a.u, a.pct)
        }
        if this.IsOp("+") {
            this.i++
            return this.Unary()
        }
        return this.Power()
    }

    Power() {
        a := this.Postfix()
        if this.IsOp("^") {
            this.i++
            b := this.Unary()
            if (a.d != "" || b.d != "")
                throw Error("puissance d'une unité")
            return Qty(a.v ** b.v)
        }
        return a
    }

    ; Nombre + unité, avec les durées accolées : 1h30, 1h 30min, 2min30
    Postfix() {
        a := this.ApplyUnit(this.Primary())
        while (a.d = "time" && this.Peek().t = "num") {
            n := this.toks[this.i].v
            this.i++
            p := this.Peek()
            u := p.t = "id" ? Calc.Unit(p.v) : 0
            if u {
                if (u.d != "time")
                    throw Error("unités incompatibles")
                this.i++
                f := u.f
            } else {
                f := this.lastF = 86400 ? 3600 : this.lastF = 3600 ? 60 : this.lastF = 60 ? 1 : 0
                if !f
                    throw Error("unité manquante")
            }
            a := Qty(a.v + n * f, "time")
            this.lastF := f
        }
        return a
    }

    ApplyUnit(a) {
        p := this.Peek()
        if (p.t != "id")
            return a
        u := Calc.Unit(p.v)
        if !u
            return a
        if (u.d != "" && a.d != "")
            throw Error("unités incompatibles")
        this.i++
        if (u.d = "time")
            this.lastF := u.f
        return this.ApplyUnit(Qty(a.v * u.f, u.d != "" ? u.d : a.d, u.d = "cur" ? u.n : a.u, p.v = "%"))
    }

    Primary() {
        if (this.i > this.toks.Length)
            throw Error("incomplet")
        p := this.toks[this.i]
        this.i++
        if (p.t = "num")
            return Qty(p.v)
        if (p.t = "op" && p.v = "(") {
            r := this.Expr()
            if this.IsOp(")")
                this.i++
            else if (this.i <= this.toks.Length)
                throw Error("parenthèse")
            return r
        }
        if (p.t = "id") {
            name := StrLower(p.v)
            if (name = "pi")
                return Qty(3.141592653589793)
            if (name = "sqrt" || name = "racine") {
                a := this.Primary()
                if (a.d != "" || a.v < 0)
                    throw Error("racine invalide")
                return Qty(Sqrt(a.v))
            }
        }
        throw Error("syntaxe")
    }

    static Add(a, b, sign) {
        if (b.pct && !a.pct)                     ; 150 + 20 %  →  180
            return Qty(a.v * (1 + sign * b.v), a.d, a.u)
        if (a.d != b.d)
            throw Error("unités incompatibles")
        return Qty(a.v + sign * b.v, a.d, a.u != "" ? a.u : b.u)
    }

    static Mul(a, b) {
        if (a.d != "" && b.d != "")
            throw Error("unités incompatibles")
        return Qty(a.v * b.v, a.d != "" ? a.d : b.d, a.u != "" ? a.u : b.u)
    }

    static Div(a, b) {
        if (b.v = 0)
            throw Error("division par zéro")
        if (a.d = b.d)
            return Qty(a.v / b.v)
        if (b.d != "")
            throw Error("unités incompatibles")
        return Qty(a.v / b.v, a.d, a.u)
    }
}

; ================= Affichage =================
FmtValue(r) {
    if (r.d = "")
        return r.pct ? FmtNum(r.v * 100) " %" : FmtNum(r.v)
    if (r.d = "time")
        return FmtTimeLong(r.v)
    if (r.d = "cur") {
        code := r.u != "" ? r.u : "EUR"
        return FmtMoney(r.v / Calc.Unit(code).f) " " code
    }
    list := Calc.AutoUnits[r.d]
    best := list[1]
    for u in list
        if (Abs(r.v) >= u[2])
            best := u
    return FmtNum(r.v / best[2]) " " best[1]
}

FmtNum(x) {
    if (x = 0)
        return "0"
    if (Abs(x) >= 1e15 || Abs(x) < 1e-6)
        return StrReplace(Format("{:.6g}", x), ".", ",")
    dec := Max(0, Min(10, 9 - Floor(Log(Abs(x)))))
    s := Format("{:." dec "f}", x)
    if InStr(s, ".")
        s := RTrim(RTrim(s, "0"), ".")
    return GroupNum(s)
}

FmtMoney(x) => GroupNum(Format("{:.2f}", x))

; "1234567.5" → "1 234 567,5"
GroupNum(s) {
    neg := SubStr(s, 1, 1) = "-"
    if neg
        s := SubStr(s, 2)
    parts := StrSplit(s, ".")
    ip := RegExReplace(parts[1], "\B(?=(\d{3})+$)", Chr(0xA0))
    return (neg ? "-" : "") ip (parts.Length > 1 ? "," parts[2] : "")
}

FmtTimeLong(sec) {
    neg := sec < 0
    sec := Abs(sec)
    if (sec < 1)
        return (neg ? "-" : "") FmtNum(sec * 1000) " ms"
    sec := Round(sec, 2)
    d := Floor(sec / 86400), sec -= d * 86400
    h := Floor(sec / 3600), sec -= h * 3600
    m := Floor(sec / 60), sec -= m * 60
    sec := Round(sec, 2)
    out := ""
    if d
        out .= d " j "
    if h
        out .= h " h "
    if m
        out .= m " min "
    if (sec > 0)
        out .= FmtNum(sec) " s"
    return (neg ? "-" : "") Trim(out)
}

FormatDuration(s) {
    h := s // 3600, m := Mod(s // 60, 60), sec := Mod(s, 60)
    return h ? Format("{}:{:02}:{:02}", h, m, sec) : Format("{:02}:{:02}", m, sec)
}

Capitalize(t) => StrUpper(SubStr(t, 1, 1)) SubStr(t, 2)

SetIfChanged(ctl, val) {
    if (ctl.Value != val)
        ctl.Value := val
}
