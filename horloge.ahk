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
;   Météo        météo   météo Rodez
;   Serveurs     statut   ping neoheberg.fr
;   Divers       ip   cours cac   mdp 20   #FF8800   rgb(255,136,0)   ts   ts 1732300000
;   Notes        note acheter du café   notes (ouvre le fichier)
;   Dev          uuid   b64 texte   b64d SGVsbG8=   sha256 texte   md5 texte   url café & thé   urld caf%C3%A9
;   Expansions   exp ;mail moi@exemple.fr   exp ;mail (supprime)   exp (ouvre la liste)   ;date   ;heure
;
; RACCOURCIS GLOBAUX (Ctrl gauche + Alt gauche) : C pipette · T OCR · P épingler · M micro
;
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
METEO_VILLE := "Saint-Dié-des-Vosges"                 ; ville de la météo du panneau
SERVERS     := ["neoheberg.fr", "dash.neoheberg.fr"]  ; sites surveillés (mettre [] pour masquer la section)

; Raccourcis globaux — <^ = Ctrl gauche, <! = Alt gauche (AltGr ne les déclenche pas), "" = désactivé
KEY_PIPETTE := "<^<!c"     ; copie la couleur sous la souris
KEY_OCR     := "<^<!t"     ; sélection d'une zone → texte copié
KEY_PIN     := "<^<!p"     ; garde la fenêtre active au premier plan
KEY_MIC     := "<^<!m"     ; coupe / réactive le micro
MIC_DEVICE  := "Microphone"  ; une partie du nom du micro (Paramètres > Son > Entrée)

; ===== État =====
popup := 0, fading := false, fadeStart := 0, openTick := 0
timeTxt := 0, dateTxt := 0
calTitle := 0, calCells := [], cellDates := [], cellKeys := [], calResult := 0
calY := 0, calM := 0, selA := "", selB := ""
inputEdit := 0, resultTxt := 0, timerTxt := 0, autoTxt := 0
timerEnd := 0, timerTotal := 0, timerLabel := "", timerAt := ""
autoCfg := 0, autoOn := false, autoStopTick := 0
hist := [], histPos := 1
DATA_DIR   := A_AppData "\horloge-ahk"
HIST_FILE  := DATA_DIR "\historique.txt"    ; historique conservé entre les redémarrages
NOTES_FILE := DATA_DIR "\notes.txt"
EXP_FILE   := DATA_DIR "\expansions.txt"
try DirCreate(DATA_DIR)
HIST_MAX  := 100

LoadHistory()

micGui := 0, pipGui := 0, expansions := Map()
LoadExpansions()
for k, fn in Map(KEY_PIPETTE, Pipette, KEY_OCR, OcrCapture, KEY_PIN, TogglePin, KEY_MIC, ToggleMic)
    if (k != "")
        try Hotkey(k, fn)

weatherTxt := 0, colorSwatch := 0, srvRows := Map()
weatherCache := "", cityCache := Map()
srvState := Map(), srvLastCheck := 0, srvPending := 0
httpPending := []

SetTimer(() => LoadRates(), -100)            ; taux de change au démarrage
SetTimer(LoadRates, 6 * 3600 * 1000)         ; puis toutes les 6 h
SetTimer(() => UpdatePanelWeather(), -300)   ; météo au démarrage
SetTimer(UpdatePanelWeather, 15 * 60 * 1000) ; puis toutes les 15 min
SetTimer(() => CheckServers(), -500)         ; statut des serveurs au démarrage
SetTimer(CheckServers, 2 * 60 * 1000)        ; puis toutes les 2 min

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
    global hist, histPos, weatherTxt, colorSwatch, srvRows

    popup := Gui("+AlwaysOnTop -Caption +ToolWindow")
    popup.BackColor := C_BG
    popup.MarginX := 20
    popup.MarginY := 16

    ; Heure + date
    popup.SetFont("s36 cFFFFFF", "Segoe UI Semibold")
    timeTxt := popup.AddText("xm w" PANEL_W " Center")
    popup.SetFont("s12 cB0B0B0", "Segoe UI")
    dateTxt := popup.AddText("xm y+0 w" PANEL_W " Center")
    popup.SetFont("s10 c9A9A9A", "Segoe UI")
    weatherTxt := popup.AddText("xm y+4 w" PANEL_W " Center")

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

    ; Statut des serveurs (clic = ouvrir le site)
    srvRows := Map()
    if SERVERS.Length {
        for idx, host in SERVERS {
            popup.SetFont("s10 c6A6A6A", "Segoe UI")
            dot := popup.AddText("xm y+" (idx = 1 ? 10 : 2) " w16 h20 +0x200", "●")
            popup.SetFont("s10 cE0E0E0", "Segoe UI")
            name := popup.AddText("x+4 yp w180 h20 +0x200", host)
            popup.SetFont("s10 c9A9A9A", "Segoe UI")
            ms := popup.AddText("x+0 yp w80 h20 +0x200 Right")
            for ctl in [dot, name, ms]
                ctl.OnEvent("Click", OpenSite.Bind(host))
            srvRows[host] := {dot: dot, ms: ms, key: ""}
        }
        Separator()
    }

    ; Saisie : champ "multi-ligne" utilisé sur une ligne, pour pouvoir centrer le texte verticalement
    popup.SetFont("s12 cFFFFFF", "Segoe UI")
    inputEdit := popup.AddEdit("xm y+12 w" PANEL_W " h36 -E0x200 +Multi -VScroll -HScroll -Wrap Background2A2A2A")
    inputEdit.OnEvent("Change", (*) => Preview())
    CenterEditText(inputEdit, 10)

    popup.SetFont("s10 c9A9A9A", "Segoe UI")
    resultTxt := popup.AddText("xm y+6 w" PANEL_W " Right")
    colorSwatch := popup.AddText("xp yp+1 w14 h14 Hidden Background" C_BG)
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
    RefreshWeatherUI()
    RefreshServersUI()
    if (A_TickCount - srvLastCheck > 30000)
        CheckServers()
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
    if RegExMatch(s, "i)^\s*m[ée]t[ée]o(?:\s+(.+?))?\s*$", &m) {
        city := m[1] != "" ? m[1] : METEO_VILLE
        return {t: "Entrée : météo de " city, c: "", run: () => RunWeather(city)}
    }
    if RegExMatch(s, "i)^\s*statut\s*$")
        return {t: "Entrée : vérifier les serveurs", c: "", run: RunStatus}
    if RegExMatch(s, "i)^\s*(?:ping|statut)\s+(\S+)\s*$", &m) {
        host := RegExReplace(m[1], "i)^https?://")
        return {t: "Entrée : tester " host, c: "", run: () => RunPing(host)}
    }
    if RegExMatch(s, "i)^\s*ip\s*$")
        return {t: "Entrée : IP locale et publique", c: "", run: RunIp}
    if RegExMatch(s, "i)^\s*(?:cours|bourse)\s+(\S+)\s*$", &m) {
        tk := QuoteTicker(m[1])
        return {t: "Entrée : cours de " tk, c: "", run: () => RunQuote(tk)}
    }
    if RegExMatch(s, "i)^\s*(?:mdp|pass|password)(?:\s+(\d+))?\s*$", &m) {
        n := Max(6, Min(128, m[1] != "" ? Integer(m[1]) : 16))
        return {t: "Entrée : mot de passe de " n " caractères", c: "", run: () => RunPassword(n)}
    }
    if RegExMatch(s, "i)^\s*ts(?:\s+(.+?))?\s*$", &m)
        return TsInfo(m[1])
    if RegExMatch(s, "i)^\s*note\s+(.+)$", &m) {
        txt := Trim(m[1])
        return {t: "Entrée : ajouter la note", c: "", run: () => AddNote(txt)}
    }
    if RegExMatch(s, "i)^\s*notes\s*$")
        return {t: "Entrée : ouvrir les notes (" NotesCount() ")", c: "", run: OpenNotes}
    if RegExMatch(s, "i)^\s*uuid\s*$")
        return {t: "Entrée : générer un UUID", c: "", run: RunUuid}
    if RegExMatch(s, "i)^\s*(b64d?|sha256|sha1|md5|urld?)\s+(.+)$", &m) {
        op := StrLower(m[1]), arg := m[2]
        out := op = "b64" ? B64Enc(arg) : op = "b64d" ? B64Dec(arg) : op = "url" ? UrlEncode(arg)
             : op = "urld" ? UrlDecode(arg) : HashStr(arg, StrUpper(op))
        return {t: "= " out, c: out, run: ""}
    }
    if RegExMatch(s, "i)^\s*exp(?:\s+(\S+)(?:\s+(.+))?)?\s*$", &m) {
        if (m[1] = "")
            return {t: "Entrée : ouvrir la liste des expansions (" expansions.Count ")", c: "", run: OpenExpansions}
        ab := m[1], txt := m[2]
        if (txt = "")
            return {t: expansions.Has(ab) ? "Entrée : supprimer « " ab " »" : "exp " ab " <texte>", c: ""
                  , run: () => SetExpansion(ab, "")}
        return {t: "Entrée : « " ab " » → " txt, c: "", run: () => SetExpansion(ab, txt)}
    }
    if (ci := ColorInfo(s))
        return ci
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
    global inputEdit, resultTxt, colorSwatch
    try res := Interpret(inputEdit.Value)
    catch
        res := ""
    SetIfChanged(resultTxt, IsObject(res) ? res.t : "")
    if (IsObject(res) && res.HasOwnProp("color")) {
        colorSwatch.Opt("Background" res.color)
        colorSwatch.Visible := true
        colorSwatch.Redraw()
    } else if colorSwatch.Visible
        colorSwatch.Visible := false
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
        out := ""
        try out := fn()
        catch as e {
            resultTxt.Value := e.Message
            return
        }
        if IsObject(out) {          ; {msg} : message + saisie vidée
            inputEdit.Value := ""
            resultTxt.Value := out.msg
            return
        }
        if (out != "") {            ; l'action affiche un résultat : on garde la saisie
            resultTxt.Value := out
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
    while (hist.Length > HIST_MAX)
        hist.RemoveAt(1)
    histPos := hist.Length + 1
    SaveHistory()
}

LoadHistory() {
    global hist, histPos
    if !FileExist(HIST_FILE)
        return
    try {
        for line in StrSplit(FileRead(HIST_FILE, "UTF-8"), "`n", "`r")
            if (Trim(line) != "")
                hist.Push(line)
    }
    while (hist.Length > HIST_MAX)
        hist.RemoveAt(1)
    histPos := hist.Length + 1
}

SaveHistory() {
    global hist
    try {
        SplitPath(HIST_FILE, , &dir)
        DirCreate(dir)
        out := ""
        for line in hist
            out .= line "`n"
        f := FileOpen(HIST_FILE, "w", "UTF-8")
        f.Write(out)
        f.Close()
    }
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
LoadRates() => HttpReq("GET", "https://open.er-api.com/v6/latest/EUR", RatesCb)

RatesCb(status, body, ms) {
    pos := InStr(body, '"rates"')
    if (status != 200 || !pos || !InStr(body, '"success"'))
        return
    while (pos := RegExMatch(body, '"([A-Z]{3})"\s*:\s*([\d.eE+-]+)', &m, pos)) {
        Calc.SetCurrency(m[1], Float(m[2]))
        pos += StrLen(m[0])
    }
}

; ================= Requêtes web non bloquantes =================
; cb(status, body, ms) — status = 0 si erreur ou délai dépassé
HttpReq(method, url, cb, timeout := 6000) {
    global httpPending
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open(method, url, true)
        req.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) horloge-ahk")
        req.Send()
    } catch {
        cb.Call(0, "", 0)
        return
    }
    httpPending.Push({req: req, cb: cb, t0: A_TickCount, timeout: timeout})
    SetTimer(HttpPoll, 50)
}

HttpPoll() {
    global httpPending
    i := httpPending.Length
    while (i >= 1) {
        p := httpPending[i]
        done := false, status := 0, body := ""
        try {
            if p.req.WaitForResponse(0) {
                done := true
                status := p.req.Status
                body := p.req.ResponseText
            }
        } catch
            done := true
        if (!done && A_TickCount - p.t0 > p.timeout) {
            try p.req.Abort()
            done := true
        }
        if done {
            httpPending.RemoveAt(i)
            try p.cb.Call(status, body, A_TickCount - p.t0)
        }
        i--
    }
    if !httpPending.Length
        SetTimer(HttpPoll, 0)
}

ShowResult(txt) {
    global popup, resultTxt
    if popup
        resultTxt.Value := txt
}

UrlEncode(str) {
    buf := Buffer(StrPut(str, "UTF-8"))
    StrPut(str, buf, "UTF-8")
    out := ""
    Loop buf.Size - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}

; ================= Météo (Open-Meteo, sans compte) =================
; cb(texte, nomDeVille) — texte vide si échec
FetchWeather(city, cb) {
    global cityCache
    key := StrLower(Trim(city))
    if cityCache.Has(key) {
        ForecastWeather(cityCache[key], cb)
        return
    }
    HttpReq("GET", "https://geocoding-api.open-meteo.com/v1/search?count=1&language=fr&name=" UrlEncode(city)
          , GeoCb.Bind(key, cb))
}

GeoCb(key, cb, status, body, ms) {
    global cityCache
    if (status != 200 || !RegExMatch(body, '"latitude":\s*(-?[\d.]+)', &la) || !RegExMatch(body, '"longitude":\s*(-?[\d.]+)', &lo)) {
        cb.Call("", "")
        return
    }
    nm := ""
    RegExMatch(body, '"name":\s*"([^"]+)"', &nm)
    c := {lat: la[1], lon: lo[1], name: nm ? nm[1] : key}
    cityCache[key] := c
    ForecastWeather(c, cb)
}

ForecastWeather(c, cb) {
    url := "https://api.open-meteo.com/v1/forecast?latitude=" c.lat "&longitude=" c.lon
         . "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"
    HttpReq("GET", url, (status, body, ms) => cb.Call(ParseWeather(status, body), c.name))
}

ParseWeather(status, body) {
    cur := InStr(body, '"current":')
    if (status != 200 || !cur)
        return ""
    if (!RegExMatch(body, '"temperature_2m":\s*(-?[\d.]+)', &t, cur) || !RegExMatch(body, '"weather_code":\s*(\d+)', &w, cur))
        return ""
    d := WeatherDesc(Integer(w[1]))
    out := d[1] "  " Round(t[1]) "°  " d[2]
    if (RegExMatch(body, '"temperature_2m_max":\s*\[\s*(-?[\d.]+)', &mx) && RegExMatch(body, '"temperature_2m_min":\s*\[\s*(-?[\d.]+)', &mn))
        out .= "  ·  " Round(mn[1]) "° / " Round(mx[1]) "°"
    return out
}

WeatherDesc(code) {
    if (code = 0)
        return ["☀", "Ensoleillé"]
    if (code = 1)
        return ["🌤", "Peu nuageux"]
    if (code = 2)
        return ["⛅", "Nuageux"]
    if (code = 3)
        return ["☁", "Couvert"]
    if (code = 45 || code = 48)
        return ["🌫", "Brouillard"]
    if (code >= 51 && code <= 57)
        return ["🌦", "Bruine"]
    if (code >= 61 && code <= 67)
        return ["🌧", "Pluie"]
    if (code >= 71 && code <= 77)
        return ["❄", "Neige"]
    if (code >= 80 && code <= 82)
        return ["🌦", "Averses"]
    if (code = 85 || code = 86)
        return ["🌨", "Averses de neige"]
    if (code >= 95)
        return ["⛈", "Orage"]
    return ["", "—"]
}

UpdatePanelWeather() => FetchWeather(METEO_VILLE, PanelWeatherCb)

PanelWeatherCb(txt, name) {
    global weatherCache
    if (txt != "")
        weatherCache := txt
    RefreshWeatherUI()
}

RefreshWeatherUI() {
    global popup, weatherTxt, weatherCache
    if popup
        SetIfChanged(weatherTxt, weatherCache)
}

RunWeather(city) {
    FetchWeather(city, (txt, name) => ShowResult(txt != "" ? name "  ·  " txt : "Ville introuvable ou météo indisponible"))
    return "Météo de " city "…"
}

; ================= Statut des serveurs =================
CheckServers(cb := 0) {
    global srvPending, srvLastCheck
    if !SERVERS.Length {
        if cb
            cb.Call()
        return
    }
    srvLastCheck := A_TickCount
    srvPending := SERVERS.Length
    for host in SERVERS
        HttpReq("HEAD", "https://" host, ServerCb.Bind(host, cb), 5000)
}

ServerCb(host, cb, status, body, ms) {
    global srvState, srvPending
    srvState[host] := {ok: status >= 200 && status < 500, ms: ms, code: status}
    srvPending--
    RefreshServersUI()
    if (srvPending <= 0 && cb)
        cb.Call()
}

RefreshServersUI() {
    global popup, srvRows, srvState
    if !popup
        return
    for host, row in srvRows {
        if !srvState.Has(host) {
            color := "6A6A6A", label := "…"
        } else {
            st := srvState[host]
            color := st.ok ? "4CAF50" : "E05050"
            label := st.ok ? st.ms " ms" : st.code ? "HTTP " st.code : "hors ligne"
        }
        key := color "|" label
        if (row.key = key)
            continue
        row.key := key
        row.dot.SetFont("c" color)
        row.dot.Redraw()
        row.ms.Value := label
    }
}

ServerSummary() {
    down := ""
    up := 0
    for host in SERVERS {
        if (srvState.Has(host) && srvState[host].ok)
            up++
        else
            down .= (down = "" ? "" : ", ") host
    }
    return down != "" ? "Hors ligne : " down : "Tout est en ligne (" up "/" SERVERS.Length ")"
}

RunStatus(*) {
    if !SERVERS.Length
        return "Aucun serveur configuré (SERVERS en haut du script)"
    CheckServers(() => ShowResult(ServerSummary()))
    return "Vérification des serveurs…"
}

RunPing(host) {
    HttpReq("HEAD", "https://" host
          , (status, body, ms) => ShowResult(status ? host " répond en " ms " ms (HTTP " status ")" : host " ne répond pas")
          , 6000)
    return "Test de " host "…"
}

OpenSite(host, *) => Run("https://" host)

; ================= IP =================
RunIp(*) {
    loc := "?"
    for a in SysGetIPAddresses()
        if !(a ~= "^(127\.|169\.254\.)") {
            loc := a
            break
        }
    HttpReq("GET", "https://api.ipify.org", (status, body, ms) => IpCb(loc, status, body))
    return "Locale " loc "  ·  publique…"
}

IpCb(loc, status, body) {
    pub := Trim(body)
    if (status != 200 || !(pub ~= "^[\d.:a-fA-F]+$")) {
        ShowResult("Locale " loc "  ·  publique introuvable")
        return
    }
    A_Clipboard := pub
    ShowResult("Locale " loc "  ·  Publique " pub "  ·  copiée")
}

; ================= Cours de bourse (Yahoo Finance) =================
QuoteTicker(t) {
    static alias := Map("cac", "^FCHI", "cac40", "^FCHI", "sp500", "^GSPC", "nasdaq", "^IXIC"
                      , "dow", "^DJI", "dax", "^GDAXI", "btc", "BTC-EUR", "eth", "ETH-EUR")
    l := StrLower(t)
    return alias.Has(l) ? alias[l] : StrUpper(t)
}

RunQuote(tk) {
    HttpReq("GET", "https://query1.finance.yahoo.com/v8/finance/chart/" UrlEncode(tk) "?range=1d&interval=1d"
          , (status, body, ms) => QuoteCb(tk, status, body))
    return "Cours de " tk "…"
}

QuoteCb(tk, status, body) {
    if (status != 200 || !RegExMatch(body, '"regularMarketPrice":\s*(-?[\d.]+)', &pr)) {
        ShowResult("Cours introuvable : " tk)
        return
    }
    price := Float(pr[1])
    cu := "", pc := ""
    RegExMatch(body, '"currency":\s*"([A-Z]+)"', &cu)
    RegExMatch(body, '"chartPreviousClose":\s*([\d.]+)', &pc)
    txt := tk "  " FmtMoney(price) (cu ? " " cu[1] : "")
    if pc {
        chg := (price / Float(pc[1]) - 1) * 100
        txt .= "  " (chg >= 0 ? "▲ +" : "▼ ") FmtNum(Round(chg, 2)) " %"
    }
    ShowResult(txt)
}

; ================= Mot de passe =================
RunPassword(n) {
    static chars := "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*?-_=+"
    buf := Buffer(n)
    DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", buf, "UInt", n, "UInt", 2)   ; aléatoire cryptographique
    pwd := ""
    Loop n
        pwd .= SubStr(chars, Mod(NumGet(buf, A_Index - 1, "UChar"), StrLen(chars)) + 1, 1)
    A_Clipboard := pwd
    return pwd "  ·  copié"
}

; ================= Couleurs =================
ColorInfo(s) {
    if RegExMatch(s, "^\s*#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\s*$", &m) {
        hx := m[1]
        if (StrLen(hx) = 3)
            hx := SubStr(hx, 1, 1) SubStr(hx, 1, 1) SubStr(hx, 2, 1) SubStr(hx, 2, 1) SubStr(hx, 3, 1) SubStr(hx, 3, 1)
        r := Integer("0x" SubStr(hx, 1, 2)), g := Integer("0x" SubStr(hx, 3, 2)), b := Integer("0x" SubStr(hx, 5, 2))
        hsl := RgbToHsl(r, g, b)
        rgb := "rgb(" r ", " g ", " b ")"
        return {t: rgb "  ·  hsl(" hsl[1] ", " hsl[2] "%, " hsl[3] "%)", c: rgb, run: "", color: StrUpper(hx)}
    }
    if RegExMatch(s, "i)^\s*rgb\s*\(?\s*(\d{1,3})\s*[,;\s]\s*(\d{1,3})\s*[,;\s]\s*(\d{1,3})\s*\)?\s*$", &m) {
        r := Integer(m[1]), g := Integer(m[2]), b := Integer(m[3])
        if (r > 255 || g > 255 || b > 255)
            return ""
        hx := Format("{:02X}{:02X}{:02X}", r, g, b)
        hsl := RgbToHsl(r, g, b)
        return {t: "#" hx "  ·  hsl(" hsl[1] ", " hsl[2] "%, " hsl[3] "%)", c: "#" hx, run: "", color: hx}
    }
    return ""
}

RgbToHsl(r, g, b) {
    r /= 255, g /= 255, b /= 255
    mx := Max(r, g, b), mn := Min(r, g, b), l := (mx + mn) / 2
    if (mx = mn)
        return [0, 0, Round(l * 100)]
    d := mx - mn
    sat := l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    hue := mx = r ? (g - b) / d + (g < b ? 6 : 0) : mx = g ? (b - r) / d + 2 : (r - g) / d + 4
    return [Round(hue * 60), Round(sat * 100), Round(l * 100)]
}

; ================= Timestamps Unix =================
; ts → maintenant · ts 1732300000 → date · ts 25/12/2026 18:00 → timestamp
TsInfo(arg) {
    off := Round(DateDiff(A_Now, A_NowUTC, "Seconds") / 60) * 60
    arg := Trim(arg)
    if (arg = "") {
        n := DateDiff(A_NowUTC, "19700101000000", "Seconds")
        return {t: "= " n "  (maintenant)", c: String(n), run: ""}
    }
    if RegExMatch(arg, "^\d{9,13}$") {
        n := Integer(arg)
        if (StrLen(arg) >= 12)
            n := n // 1000                      ; millisecondes
        d := DateAdd("19700101000000", n + off, "Seconds")
        return {t: "= " Capitalize(FormatTime(d, "ddd d MMM yyyy  HH:mm:ss")), c: FormatTime(d, "dd/MM/yyyy HH:mm:ss"), run: ""}
    }
    if RegExMatch(arg, "^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2})[:h](\d{2})(?::(\d{2}))?)?$", &m) {
        loc := Format("{:04}{:02}{:02}{:02}{:02}{:02}", Integer(m[3]), Integer(m[2]), Integer(m[1]), N0(m[4]), N0(m[5]), N0(m[6]))
        if !IsTime(loc)
            throw Error("date invalide")
        n := DateDiff(loc, "19700101000000", "Seconds") - off
        return {t: "= " n, c: String(n), run: ""}
    }
    throw Error("format : ts, ts 1732300000 ou ts 25/12/2026 18:00")
}

N0(v) => v = "" ? 0 : Integer(v)

; ================= Notes rapides =================
AddNote(txt) {
    try FileAppend(FormatTime(, "dd/MM/yyyy HH:mm") "  " txt "`n", NOTES_FILE, "UTF-8")
    catch
        return {msg: "Impossible d'écrire la note"}
    return {msg: "Note ajoutée (" NotesCount() ")"}
}

NotesCount() {
    if !FileExist(NOTES_FILE)
        return 0
    n := 0
    for line in StrSplit(FileRead(NOTES_FILE, "UTF-8"), "`n", "`r")
        if (Trim(line) != "")
            n++
    return n
}

OpenNotes(*) {
    if !FileExist(NOTES_FILE)
        return {msg: "Aucune note pour l'instant (note <texte>)"}
    Run(NOTES_FILE)
    return {msg: ""}
}

; ================= UUID / encodages / empreintes =================
RunUuid(*) {
    g := Buffer(16)
    DllCall("ole32\CoCreateGuid", "Ptr", g)
    sb := Buffer(78)
    DllCall("ole32\StringFromGUID2", "Ptr", g, "Ptr", sb, "Int", 39)
    id := StrLower(Trim(StrGet(sb), "{}"))
    A_Clipboard := id
    return id "  ·  copié"
}

Utf8Buf(str, &n) {
    n := StrPut(str, "UTF-8") - 1
    buf := Buffer(n + 1)
    StrPut(str, buf, "UTF-8")
    return buf
}

B64Enc(str) {
    buf := Utf8Buf(str, &n)
    if !n
        return ""
    sz := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", n, "UInt", 0x40000001, "Ptr", 0, "UInt*", &sz)
    out := Buffer(sz * 2)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", n, "UInt", 0x40000001, "Ptr", out, "UInt*", &sz)
    return StrGet(out)
}

B64Dec(str) {
    str := Trim(str)
    sz := 0
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", str, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &sz, "Ptr", 0, "Ptr", 0)
        throw Error("base64 invalide")
    buf := Buffer(sz + 1, 0)
    DllCall("crypt32\CryptStringToBinaryW", "Str", str, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &sz, "Ptr", 0, "Ptr", 0)
    return StrGet(buf, sz, "UTF-8")
}

HashStr(str, alg) {
    size := alg = "MD5" ? 16 : alg = "SHA1" ? 20 : 32
    buf := Utf8Buf(str, &n)
    hAlg := 0
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "WStr", alg, "Ptr", 0, "UInt", 0)
    digest := Buffer(size)
    DllCall("bcrypt\BCryptHash", "Ptr", hAlg, "Ptr", 0, "UInt", 0, "Ptr", buf, "UInt", n, "Ptr", digest, "UInt", size)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    out := ""
    Loop size
        out .= Format("{:02x}", NumGet(digest, A_Index - 1, "UChar"))
    return out
}

UrlDecode(str) {
    bytes := Buffer(StrPut(str, "UTF-8") * 3)
    n := 0, i := 1, len := StrLen(str)
    while (i <= len) {
        ch := SubStr(str, i, 1)
        if (ch = "%" && RegExMatch(SubStr(str, i + 1, 2), "^[0-9a-fA-F]{2}$")) {
            NumPut("UChar", Integer("0x" SubStr(str, i + 1, 2)), bytes, n++)
            i += 3
            continue
        }
        if (ch = "+")
            ch := " "
        tmp := Utf8Buf(ch, &cn)
        Loop cn
            NumPut("UChar", NumGet(tmp, A_Index - 1, "UChar"), bytes, n++)
        i++
    }
    return StrGet(bytes, n, "UTF-8")
}

; ================= Expansion de texte =================
; exp ;mail moi@exemple.fr  →  taper ;mail n'importe où écrit l'adresse  (\n = retour à la ligne)
LoadExpansions() {
    global expansions
    HotIf()
    Hotstring(":*:;date", (*) => SendText(FormatTime(, "dd/MM/yyyy")))
    Hotstring(":*:;heure", (*) => SendText(FormatTime(, "HH:mm")))
    if !FileExist(EXP_FILE)
        return
    for line in StrSplit(FileRead(EXP_FILE, "UTF-8"), "`n", "`r") {
        parts := StrSplit(line, "`t", , 2)
        if (parts.Length = 2 && parts[1] != "") {
            expansions[parts[1]] := parts[2]
            try Hotstring(":*T:" parts[1], StrReplace(parts[2], "\n", "`n"))
        }
    }
}

SetExpansion(ab, txt) {
    global expansions
    HotIf()
    if (txt = "") {
        if !expansions.Has(ab)
            return {msg: "« " ab " » n'existe pas"}
        expansions.Delete(ab)
        try Hotstring(":*T:" ab, , "Off")
        msg := "« " ab " » supprimé"
    } else {
        expansions[ab] := txt
        Hotstring(":*T:" ab, StrReplace(txt, "\n", "`n"), "On")
        msg := "« " ab " » → " txt
    }
    out := ""
    for k, v in expansions
        out .= k "`t" v "`n"
    try {
        f := FileOpen(EXP_FILE, "w", "UTF-8")
        f.Write(out)
        f.Close()
    }
    return {msg: msg}
}

OpenExpansions(*) {
    if !FileExist(EXP_FILE)
        return {msg: "Aucune expansion (exp `;abc texte)"}
    Run(EXP_FILE)
    return {msg: ""}
}

; ================= Raccourcis globaux =================
Tip(txt, ms := 1200) {
    ToolTip(txt)
    SetTimer(ClearTip, -ms)
}
ClearTip() => ToolTip()

; Pipette : copie la couleur du pixel sous la souris
Pipette(*) {
    global pipGui
    CoordMode("Pixel", "Screen")
    MouseGetPos(&x, &y)
    hx := SubStr(PixelGetColor(x, y), 3)
    A_Clipboard := "#" hx
    ClosePipette()
    pipGui := g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20")
    g.BackColor := "1F1F1F"
    g.MarginX := 8, g.MarginY := 6
    g.AddText("w18 h18 Background" hx)
    g.SetFont("s10 cFFFFFF", "Segoe UI")
    g.AddText("x+8 yp+1", "#" hx "  copié")
    g.Show("NA x" (x + 16) " y" (y + 16))
    SetTimer(ClosePipette, -1200)
}

ClosePipette() {
    global pipGui
    if pipGui {
        try pipGui.Destroy()
        pipGui := 0
    }
}

; Épingler : la fenêtre active reste au premier plan (même touche pour libérer)
TogglePin(*) {
    hwnd := WinExist("A")
    if (!hwnd || WinGetClass(hwnd) ~= "^(Progman|WorkerW|Shell_TrayWnd)$")
        return
    WinSetAlwaysOnTop(-1, hwnd)
    pinned := WinGetExStyle(hwnd) & 0x8
    Tip((pinned ? "📌 Épinglée : " : "Libérée : ") SubStr(WinGetTitle(hwnd), 1, 50))
}

; Micro : coupe / réactive, avec un bandeau rouge tant qu'il est coupé
ToggleMic(*) {
    global micGui
    try {
        SoundSetMute(-1, , MIC_DEVICE)
        muted := SoundGetMute(, MIC_DEVICE)
    } catch {
        Tip("Micro introuvable : change MIC_DEVICE en haut du script", 2500)
        return
    }
    if micGui {
        try micGui.Destroy()
        micGui := 0
    }
    if !muted {
        Tip("🎙 Micro réactivé")
        return
    }
    micGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20")
    micGui.BackColor := "C0392B"
    micGui.MarginX := 14, micGui.MarginY := 6
    micGui.SetFont("s10 cFFFFFF", "Segoe UI Semibold")
    micGui.AddText(, "🎙  Micro coupé")
    micGui.Show("NA Hide")
    WinGetPos(, , &w, , micGui)
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r)
    WinMove(l + (r - l - w) // 2, t + 10, , , micGui)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", micGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
    DllCall("ShowWindow", "Ptr", micGui.Hwnd, "Int", 4)     ; afficher sans voler le focus
}

; OCR : sélectionner une zone de l'écran → le texte est copié (moteur OCR intégré à Windows)
OcrCapture(*) {
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    ov.BackColor := "000000"
    ov.Show("x" vx " y" vy " w" vw " h" vh)
    WinSetTransparent(60, ov)
    box := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +Owner" ov.Hwnd)
    box.BackColor := C_TODAY
    Tip("Sélectionne une zone (Échap pour annuler)", 3000)

    ; attendre le clic
    Loop {
        if GetKeyState("Escape", "P") {
            ov.Destroy(), box.Destroy(), ToolTip()
            return
        }
        if GetKeyState("LButton", "P")
            break
        Sleep(10)
    }
    ToolTip()
    MouseGetPos(&x1, &y1)
    x := x1, y := y1, w := 0, h := 0
    ; suivre le glisser
    while GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {
            ov.Destroy(), box.Destroy()
            return
        }
        MouseGetPos(&x2, &y2)
        x := Min(x1, x2), y := Min(y1, y2), w := Abs(x2 - x1), h := Abs(y2 - y1)
        if (w > 1 && h > 1) {
            box.Show("NA x" x " y" y " w" w " h" h)
            WinSetTransparent(90, box)
        }
        Sleep(10)
    }
    ov.Destroy(), box.Destroy()
    if (w < 6 || h < 6)
        return
    Sleep(120)       ; laisser l'écran se redessiner sans le voile
    Tip("Lecture du texte…", 10000)
    txt := RunOcr(x, y, w, h)
    if (txt = "") {
        Tip("Aucun texte détecté")
        return
    }
    A_Clipboard := txt
    Tip("Texte copié (" StrLen(txt) " caractères)")
}

RunOcr(x, y, w, h) {
    ps1 := A_Temp "\horloge_ocr.ps1", out := A_Temp "\horloge_ocr.txt"
    script := '
    (
param([int]$x, [int]$y, [int]$w, [int]$h, [string]$out)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -TypeDefinition "using System.Runtime.InteropServices; public class HDpi { [DllImport(""user32.dll"")] public static extern bool SetProcessDPIAware(); }"
[HDpi]::SetProcessDPIAware() | Out-Null
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
$big = New-Object System.Drawing.Bitmap ($w * 2), ($h * 2)
$g2 = [System.Drawing.Graphics]::FromImage($big)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($bmp, 0, 0, ($w * 2), ($h * 2))
$png = Join-Path $env:TEMP "horloge_ocr.png"
$big.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like "IAsyncOperation*" -and $_.GetParameters()[0].ParameterType.Name -notlike "*Progress*" } | Select-Object -First 1
function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait() | Out-Null; $task.Result }
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sbmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$text = ""
if ($engine) {
  $res = Await ($engine.RecognizeAsync($sbmp)) ([Windows.Media.Ocr.OcrResult])
  $text = ($res.Lines | ForEach-Object { $_.Text }) -join [Environment]::NewLine
}
$stream.Dispose()
[IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding $false))
    )'
    try {
        f := FileOpen(ps1, "w", "UTF-8")
        f.Write(script)
        f.Close()
        try FileDelete(out)
        RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '" ' x ' ' y ' ' w ' ' h ' "' out '"', , "Hide")
        return FileExist(out) ? Trim(FileRead(out, "UTF-8"), " `r`n") : ""
    }
    return ""
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
