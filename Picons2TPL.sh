#!/usr/bin/env bash

# Skript zum erzeugen von *.tpl für die OSCam Weboberfläche

# Das benötigte GIT wird vom Skript lokal auf die Festplatte geladen und bei jedem Start
# automatisch aktualisiert.

# Das Skript am besten ein mal pro Woche ausführen (/etc/cron.weekly)
VERSION=211014

# Sämtliche Einstellungen werden in der *.conf vorgenommen.
# ---> Bitte ab hier nichts mehr ändern! <---

### Variablen
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"
SELF_PATH="${SELF%/*}"
msgERR='\e[1;41m FEHLER! \e[0;1m' ; nc='\e[0m'  # Anzeige "FEHLER!"
msgINF='\e[42m \e[0m' ; msgWRN='\e[103m \e[0m'  # " " mit grünem/gelben Hintergrund
PICONS_GIT='https://github.com/picons/picons.git'  # Picon-Logos
PICONS_DIR='picons.git'  # Ordner, wo die Picon-Kanallogos liegen (GIT)

### Funktionen
f_log(){  # Logausgabe auf Konsole oder via Logger. $1 zum kennzeichnen der Meldung.
  local msg="${*:2}"
  case "${1^^}" in
    'ERR'*|'FATAL') [[ -t 2 ]] && { echo -e "$msgERR ${msg:-$1}${nc}" ;} \
                      || logger --tag "$SELF_NAME" --priority user.err "$@" ;;
    'WARN'*) [[ -t 1 ]] && { echo -e "$msgWRN ${msg:-$1}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    'DEBUG') [[ -t 1 ]] && { echo -e "\e[1m${msg:-$1}${nc}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    'INFO'*) [[ -t 1 ]] && { echo -e "$msgINF ${msg:-$1}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    *) [[ -t 1 ]] && { echo -e "$@" ;} || logger --tag "$SELF_NAME" "$@" ;;  # Nicht angegebene
  esac
  [[ -n "$LOGFILE" ]] && printf '%(%d.%m.%Y %T)T: %b\n' -1 "$*" 2>/dev/null >> "$LOGFILE"  # Log in Datei
}

f_self_update() {  # Automatisches Update
  local BRANCH UPSTREAM
  f_log INFO 'Starte Auto-Update…'
  cd "$SELF_PATH" || exit 1
  git fetch
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream})
  if [[ -n "$(git diff --name-only "$UPSTREAM" "$SELF_NAME")" ]] ; then
    f_log INFO "Neue Version von $SELF_NAME gefunden! Starte Update…"
    git pull --force
    git checkout "$BRANCH"
    git pull --force || exit 1
    f_log INFO "Starte $SELF_NAME neu…"
    cd - || exit 1   # Zürück ins alte Arbeitsverzeichnisr
    exec "$SELF" "$@"
    exit 1  # Alte Version des Skripts beenden
  else
    f_log INFO 'OK. Bereits die aktuelle Version'
  fi
}

### Start
SCRIPT_TIMING[0]=$SECONDS  # Startzeit merken (Sekunden)

# Testen, ob Konfiguration angegeben wurde (-c …)
while getopts ":c:" opt ; do
  case "$opt" in
    c) CONFIG="$OPTARG"
       if [[ -f "$CONFIG" ]] ; then  # Konfig wurde angegeben und existiert
         source "$CONFIG" ; CONFLOADED='Angegebene' ; break
       else
         f_log ERR "Die angegebene Konfigurationsdatei fehlt! (\"${CONFIG}\")"
         exit 1
       fi ;;
    ?) ;;
  esac
done

# Konfigurationsdatei laden [Wenn Skript=logos.sh Konfig=logos.conf]
if [[ -z "$CONFLOADED" ]] ; then  # Konfiguration wurde noch nicht geladen
  # Suche Konfig im aktuellen Verzeichnis, im Verzeichnis des Skripts und im eigenen etc
  CONFIG_DIRS=('.' "${SELF%/*}" "${HOME}/etc" "${0%/*}") ; CONFIG_NAME="${SELF_NAME%.*}.conf"
  for dir in "${CONFIG_DIRS[@]}" ; do
    CONFIG="${dir}/${CONFIG_NAME}"
    if [[ -f "$CONFIG" ]] ; then
      source "$CONFIG" ; CONFLOADED='Gefundene'
      break  # Die erste gefundene Konfiguration wird verwendet
    fi
  done
  if [[ -z "$CONFLOADED" ]] ; then  # Konfiguration wurde nicht gefunden
    f_log ERR "Keine Konfigurationsdatei gefunden! (\"${CONFIG_DIRS[*]}\")"
    exit 1
  fi
fi

f_log INFO "==> $SELF_NAME #${VERSION} - Start…"
f_log INFO "$CONFLOADED Konfiguration: ${CONFIG}"

[[ "$AUTO_UPDATE" == 'true' ]] && f_self_update "$@"

# Pfade festlegen
location="${SELF_PATH}/${PICONS_DIR}"  # Pfad vom GIT
logfile=$(mktemp --suffix=.servicelist.log)
temp=$(mktemp -d --suffix=.picons)
f_log INFO "Log-Datei: $logfile"

# Benötigte Programme suchen
commands=(mkdir mv printf readlink rm)
for cmd in "${commands[@]}" ; do
  command -v "$cmd" &>/dev/null || missingcommands+=("$cmd")
done
if [[ -n "${missingcommands[*]}" ]] ; then
  f_log ERR "Fehlende Datei(en): ${missingcommands[*]}"
  exit 1
fi

# picons.git laden oder aktualisieren
cd "$SELF_PATH" || exit 1
if [[ ! -d "${PICONS_DIR}/.git" ]] ; then
  f_log WARN "$PICONS_DIR nicht gefunden!"
  f_log INFO "Klone $PICONS_GIT nach $PICONS_DIR"
  f_log INFO "=> Zum abbrechen Strg-C drücken => Starte in 5 Sekunden…"
  sleep 5
  git clone --depth 1 "$PICONS_GIT" "$PICONS_DIR" \
    || { f_log ERR 'Klonen hat nicht funktioniert!' ; exit 1 ;}
else
  f_log INFO "Aktualisiere Picons in ${PICONS_DIR}…"
  cd "$PICONS_DIR" || exit 1
  git pull &>> "$logfile"
  cd "$SELF_PATH" || exit 1
fi

# .index einlesen
mapfile -t index < "${location}/build-source/srp.index"  # EF10_421_1_C00000=rtlhd

# Liste der Logos und ID's erstellen
declare -A sidlogo  # Assoziatives Array
for line in "${index[@]}" ; do
  [[ ! "$line" =~ _C00000 ]] && continue  # Nur Astra (19,2° Ost)
  sid="${line%%_*}"                       # EF10
  until [[ "${#sid}" -eq 4 ]] ; do
    sid="0${sid}"                         # Mit 0 auffüllen (000A)
  done
  if [[ "${sidlogo[$sid]+_}" ]] ; then
    f_log WARN "SRVID: $sid bereits verwendet von ${sidlogo[$sid]}"
    ((dsid++))
  else
    sidlogo[$sid]="${line##*=}"           # In Array speichern (rtlhd)
    #echo "sidlogo: ${sidlogo[$sid]} $sid"
  fi
done

### Icons mit Hintergrund erstellen ###

logfile=$(mktemp --suffix=.picons.log)
f_log INFO "Log-Datei: $logfile"

if command -v pngquant &>/dev/null ; then
  pngquant='pngquant'
  f_log INFO 'Bildkomprimierung aktiviert!'
else
  pngquant='cat'
  f_log WARN 'Bildkomprimierung deaktiviert! "pngquant" installieren!'
fi

if command -v convert &>/dev/null ; then
  f_log INFO 'ImageMagick gefunden!'
else
  f_log ERR 'ImageMagick nicht gefunden! "ImageMagick" installieren!'
  exit 1
fi

: "${SVGCONVERTER:=rsvg}"  # Vorgabe ist rsvg
if command -v inkscape &>/dev/null && [[ "${SVGCONVERTER,,}" == 'inkscape' ]] ; then
  svgconverter='inkscape -w 850 --without-gui --export-area-drawing --export-png='
  f_log INFO 'Verwende Inkscape als SVG-Konverter!'
elif command -v rsvg-convert &>/dev/null && [[ "${SVGCONVERTER,,}" = 'rsvg' ]] ; then
  svgconverter=('rsvg-convert' -w 1000 --keep-aspect-ratio --output)
  f_log INFO 'Verwende rsvg als SVG-Konverter!'
else
  f_log ERR "SVG-Konverter: ${SVGCONVERTER} nicht gefunden!"
  exit 1
fi

# Einfache Prüfung der Quellen
if [[ -t 1 ]] ; then
  f_log INFO 'Überprüfe srp Index…'
  "$location/resources/tools/check-index.sh" "$location/build-source" snp
  f_log INFO 'Überprüfe logos…'
  "$location/resources/tools/check-logos.sh" "$location/build-source/logos"
fi

# Konvertierung der Logos
logocount="${#sidlogo[@]}"
mkdir --parents "${temp}/cache" || { echo "Fehler beim erzeugen von ${temp}/cache" >&2 ; exit 1 ;}
oscamtpl="${location}/build-output/oscam-tpl"
[[ ! -d "${oscamtpl}/logos" ]] && { mkdir --parents "${oscamtpl}/logos" || exit 1 ;}

resolution="${LOGO_CONF[0]:=100x60}"   # Hintergrundgröße
resize="${LOGO_CONF[1]:=95x55}"        # Logogröße
type="${LOGO_CONF[2]:=dark}"           # Typ (dark/light)
background="${LOGO_CONF[3]:=transparent}"  # Hintergrund (transparent/blue/...)

f_log INFO "Erzeuge Logos: ${resolution}-${resize}.${type}.on.${background}…"
for sid in "${!sidlogo[@]}" ; do
  echo "SID: $sid => ${sidlogo[$sid]}"
  logoname="${sidlogo[$sid]}"  # rtlhd
  #sid="$key"                  # EF10
  ((currentlogo++))
  #[[ -t 1 ]] && echo -ne "$msgINF Konvertiere Logo: ${currentlogo}/${logocount}"\\r

  if [[ -f "${location}/build-source/logos/${logoname}.${type}.png" || -f "${location}/build-source/logos/${logoname}.${type}.svg" ]] ; then
    logotype="$type"
  else
    logotype='default'
  fi

  echo "--> ${logoname}.${logotype} [${sid}]" >> "$logfile"

  if [[ -f "${location}/build-source/logos/${logoname}.${logotype}.svg" ]] ; then
    ((svg++))
    if [[ "${location}/build-source/logos/${logoname}.${logotype}.svg" -nt "${oscamtpl}/logos/${logoname}.png" ]] ; then
      logo="${temp}/cache/${logoname}.${logotype}.png"
      if [[ ! -f "$logo" ]] ; then
        "${svgconverter[@]}" "${logo}" "${location}/build-source/logos/${logoname}.${logotype}.svg" &>> "$logfile"
      fi
    fi
  else
    ((png++))
    logo="${location}/build-source/logos/${logoname}.${logotype}.png"
    #[[ "${oscamtpl}/logos/${logoname}.png" -nt "$logo" ]] && \
    #  { f_log "Überspringe ${logoname}.png" ; continue ;}  # Nur erstellen wenn neuer
  fi

  # Hintergrund vorhanden?
  if [[ ! -f "${location}/build-source/backgrounds/${resolution}/${background}.png" ]] ; then
    f_log WARN "Hintergrund fehlt! (${location}/build-source/backgrounds/${resolution}/${background}.png)"
  fi

  # Erstelle Logo mit Hintergrund
  if [[ "$logo" -nt "${oscamtpl}/logos/${logoname}.png" ]] ; then  # Nur wenn neuer
    convert "${location}/build-source/backgrounds/${resolution}/${background}.png" \
      \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$resize" -gravity center -extent "$resolution" +repage \) \
      -layers merge - 2>> "$logfile" > "${oscamtpl}/logos/${logoname}.png"
    ((N_LOGO++))
  fi

  # Konvertiern in TPL (IC_CAID_SRVID.tpl)
  cd "${oscamtpl}/logos" || exit 1
  tplfile="IC_0000_${sid}.tpl"
  #f_log "Erstelle ${tplfile}…"
  echo "TPL: $tplfile Name: $logoname"
  if [[ "${oscamtpl}/logos/${logoname}.png" -nt "../${tplfile}" ]] ; then
    { echo -n 'data:image/png;base64,'
      convert "${oscamtpl}/logos/${logoname}.png" PNG32:- \
        | "$pngquant" - 2>> "$logfile" \
        | base64 -i -w 0
    } > "../${tplfile}"  # -resize '100x60'
  fi
  # Zusätzlicher symling
  ln --symbolic "${oscamtpl}/logos/${logoname}.png" "${tplfile%.*}.png" &>/dev/null
done

[[ -d "$temp" ]] && rm --recursive "$temp"

f_log INFO "Erzeuge Archiv: ${resolution}-${resize}.${type}.on.${background}.tar.xz…"
cd "$oscamtpl"
tar --create --auto-compress --file="${resolution}-${resize}.${type}.on.${background}.tar.xz" IC_0000*.tpl

f_log INFO "Erstellen von Logos beendet!"

# Statistik anzeigen
f_log "==> $((svg + png)) Logos: $svg im SVG-Format und $png im PNG-Format"
f_log "==> ${N_LOGO:-0} neue(s) oder aktualisierte(s) Logo(s)"
f_log "==> SRVID's: ${#sidlogo[@]} - Mehrfach verwendete ignorierte SRVID's: $dsid"
SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
f_log "==> Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"

if [[ -e "$LOGFILE" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat --format=%s "$LOGFILE")"
  [[ $FILESIZE -gt $MAXLOGSIZE ]] && mv --force "$LOGFILE" "${LOGFILE}.old"
fi

exit 0
