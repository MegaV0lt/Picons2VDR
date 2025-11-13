#!/usr/bin/env bash

# Skript zum erzeugen und verlinken der PICON-Kanallogos (Enigma2)

# Das benötigte GIT wird vom Skript lokal auf die Festplatte geladen und bei jedem Start
# automatisch aktualisiert.
# Die Dateinamen der Logos passen nicht zum VDR-Schema. Darum verwendet das Skript die
# im GIT enthaltenen index-Dateien, um die Logos mit Hilfe der 'channels.conf' dann passend
# zu verlinken.

# Die Logos werden im PNG-Format erstellt. Die Größe und den optionalen Hintergrund
# kann man in der *.conf einstellen.
# Das Skript am besten ein mal pro Woche ausführen (/etc/cron.weekly)
VERSION=251113  # Version des Skripts

# Sämtliche Einstellungen werden in der *.conf vorgenommen.
# ---> Bitte ab hier nichts mehr ändern! <---

### Variablen
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"    # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"
SELF_PATH="${SELF%/*}"
msgERR='\e[1;41m FEHLER! \e[0;1m' ; nc='\e[0m'     # Anzeige "FEHLER!"
msgINF='\e[42m \e[0m' ; msgWRN='\e[103m \e[0m'     # " " mit grünem/gelben Hintergrund
PICONS_GIT='https://github.com/picons/picons.git'  # Picon-Logos
PICONS_DIR='picons.git'                            # Ordner, wo die Picon-Kanallogos liegen (GIT)
NOT_SET='--------'                                 # Variable nicht gesetzt

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

f_trim() {  # Leerzeichen am Anfang und am Ende entfernen
  printf '%s\n' "${1#"${1%%[![:space:]]*}"}${1##*[![:space:]]}"
}

f_self_update() {  # Automatisches Update
  local branch upstream
  f_log INFO 'Starte Auto-Update…'
  cd "$SELF_PATH" || exit 1
  git fetch
  branch=$(git rev-parse --abbrev-ref HEAD)
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream})
  if [[ -n "$(git diff --name-only "$upstream" "$SELF_NAME")" ]] ; then
    f_log INFO "Neue Version von $SELF_NAME gefunden! Starte Update…"
    git pull --force
    git checkout "$branch"
    git pull --force || exit 1
    f_log INFO "Starte $SELF_NAME neu…"
    cd - || exit 1   # Zurück ins alte Arbeitsverzeichnis
    exec "$SELF" "$@"
    exit 1  # Alte Version des Skripts beenden
  else
    f_log INFO 'OK. Bereits die aktuelle Version'
  fi
}

f_create_symlinks() {  # Symlinks erzeugen und Logos in Array sammeln
  local channel logo_srp logo_snp servicename
  local -a lnk_srp lnk_snp

  # 1_0_19_151A_455_1_C00000_0_0_0  DMAX HD  151A_455_1_C00000=dmaxhd-wispelutri  dmaxhd=dmaxhd
  mapfile -t < "${BUILD_OUTPUT}/servicelist-vdr-${STYLE}.txt"  # Liste in Array einlesen
  for line in "${MAPFILE[@]}" ; do
    IFS=$'\t' read -r -a line_data <<< "$line"

    channel=$(f_trim "${line_data[1]//:/|}")     # ':' durch '|' ersetzen
    case "${TOLOWER^^}" in
      'A-Z') servicename="${channel,,[A-Z]}" ;;  # In Kleinbuchstaben (Außer Umlaute)
      'FALSE') servicename="$channel" ;;         # Nicht umwandeln
      *) servicename="${channel,,}" ;;           # Alles in kleinbuchstaben
    esac

    IFS='=' read -r -a lnk_srp <<< "$(f_trim "${line_data[2]}")"
    logo_srp="${lnk_srp[1]//${NOT_SET}}"  # Platzhalter entfernen
    IFS='=' read -r -a lnk_snp <<< "$(f_trim "${line_data[3]}")"
    if [[ -n "${lnk_snp[0]//${NOT_SET}}" ]] ; then  # Nur wenn Name konvertiert werden konnte
      logo_snp="${lnk_snp[1]//${NOT_SET}}"  # Platzhalter entfernen
    fi

    if [[ -z "$logo_srp" && -z "$logo_snp" ]] ; then  # Kein Logo
      f_log WARN "!=> Kein Logo für $channel (SRP: ${lnk_srp[0]} | SNP: ${lnk_snp[0]}) gefunden!"
      ((nologo++)) ; continue
    fi

    if [[ -n "$logo_srp" && -n "$logo_snp" && "$logo_srp" != "$logo_snp" ]] ; then  # Unterschiedliche Logos
      f_log WARN "?=> Unterschiedliche Logos für $channel (SRP: $logo_srp | SNP: ${logo_snp}) gefunden!"
      if [[ "${PREFERED_LOGO:=snp}" == 'srp' ]] ; then  # Bevorzugtes Logo verwenden
        unset -v 'logo_snp'
      else
        unset -v 'logo_srp'
      fi
      ((difflogo++))
    fi

    if [[ -n "$logo_srp" ]] ; then
      LOGO_NAMES+=("${servicename}.png")
      LOGO_PATHS+=("logos/${logo_srp}.png")
      LOGO_COLLECTION+=("$logo_srp")
    elif [[ -n "$logo_snp" ]] ; then
      LOGO_NAMES+=("${servicename}.png")
      LOGO_PATHS+=("logos/${logo_snp}.png")
      LOGO_COLLECTION+=("$logo_snp")
    fi
  done
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
LOCATION="${SELF_PATH}/${PICONS_DIR}"    # Pfad vom GIT
BUILD_SOURCE="${LOCATION}/build-source"  # Quelldateien
BUILD_OUTPUT="${LOCATION}/build-output"  # Ausgabeordner
logfile=$(mktemp --suffix=.servicelist.log)
temp=$(mktemp -d --suffix=.picons)
f_log INFO "Log-Datei: $logfile"

# Benötigte Variablen prüfen
for var in CHANNELSCONF LOGODIR ; do
  [[ -z "${!var}" ]] && { f_log ERR "Variable $var ist nicht gesetzt!" ; exit 1 ;}
done

# Benötigte Programme suchen
COMMANDS=(bc column find git iconv ln mkdir mv printf readlink rm sed sort)
for cmd in "${COMMANDS[@]}" ; do
  type "$cmd" &>/dev/null || MISSING_COMMANDS+=("$cmd")
done
if [[ -n "${MISSING_COMMANDS[*]}" ]] ; then
  f_log ERR "Fehlende Datei(en): ${MISSING_COMMANDS[*]}"
  exit 1
fi

# picons.git laden oder aktualisieren
cd "$SELF_PATH" || exit 1
if [[ ! -d "${PICONS_DIR}/.git" ]] ; then
  f_log WARN "$PICONS_DIR nicht gefunden!"
  f_log INFO "Klone $PICONS_GIT nach $PICONS_DIR"
  if [[ -t 1 ]] ; then
    f_log INFO "=> Zum abbrechen Strg-C drücken => Starte in 5 Sekunden…"
    sleep 5
  fi
  git clone --depth 1 "$PICONS_GIT" "$PICONS_DIR" \
    || { f_log ERR 'Klonen hat nicht funktioniert!' ; exit 1 ;}
else
  f_log INFO "Aktualisiere Picons in ${PICONS_DIR}…"
  cd "$PICONS_DIR" || exit 1
  if ! git pull &>> "$logfile" ; then
    f_log ERR 'Aktualisierung hat nicht funktioniert!'
    exit 1
  else
    last_logo_update="$(git log -1 --date=format:"%d.%m.%Y %T" --format="%ad")"
    f_log INFO "Letztes Update der Logos: $last_logo_update"
    cd "$SELF_PATH" || exit 1
  fi
fi

# Stil gültig?
STYLE="${1:-snp}"  # Vorgabe ist snp
if [[ "${STYLE,,}" != 'srp' && "${STYLE,,}" != 'snp' ]] ; then
  f_log ERR "Unbekannter Stil! (${STYLE})"
  exit 1
fi

# .index einlesen
#mapfile -t INDEX < "${BUILD_SOURCE}/${STYLE}.index"
printf -v INDEX '%b\n' ''  # Damit auch das erste Element gefunden wird (=~)
INDEX+=$(<"${BUILD_SOURCE}/${STYLE}.index")

### VDR Serviceliste erzeugen
if [[ -f "$CHANNELSCONF" ]] ; then
  _LANG="${LANG:-LC_NAME}"  # LC merken
  TEMPFILE=$(mktemp --suffix=.servicelist)
  read -r -a ENCODING < <(encguess -u "$CHANNELSCONF")
  f_log INFO "Encoding der Kanalliste: ${ENCODING[1]:-unbekannt}"
  # Kanalliste in ASCII umwandeln
  #* Funktioniert nicht bei Buchstaben wie ΑαΒβΓγΔδ (Griechisch)
  #mapfile -t CHANNELNAMES < <(LC_CTYPE='de_DE.UTF-8' iconv -f "${ENCODING[1]:-UTF-8}" -t ASCII//TRANSLIT -c < "$CHANNELSCONF" 2>> "$logfile")
  mapfile -t CHANNELNAMES < <(iconv -f "${ENCODING[1]:-UTF-8}" -t ASCII//TRANSLIT -c < "$CHANNELSCONF" 2>> "$logfile")
  for i in "${!CHANNELNAMES[@]}"; do
    CHANNELNAMES[i]=${CHANNELNAMES[i]%%:*}  # Kanalname mit Kurzname und Provider
    CHANNELNAMES[i]=${CHANNELNAMES[i]%%;*}  # Kanalname ohne Provider
    CHANNELNAMES[i]=${CHANNELNAMES[i]%%,*}  # Kanalname ohne Kurzname
  done
  mapfile -t VDR_CHANNELSCONF < "$CHANNELSCONF"  # Kanalliste in Array einlesen
  [[ "${#CHANNELNAMES[@]}" -ne "${#VDR_CHANNELSCONF[@]}" ]] && \
    { f_log ERR 'Kanalliste und Kanalnamen unterschiedlich!' ; exit 1 ;}

  for i in "${!CHANNELNAMES[@]}" ; do
    [[ -z "${CHANNELNAMES[i]}" ]] && { ((grp++)) ; continue ;}           # Kanalgruppe
    [[ "${CHANNELNAMES[i]}" =~ OBSOLETE ]] && { ((obs++)) ; continue ;}  # Als 'OBSOLETE' markierter Kanal
    [[ "${CHANNELNAMES[i]}" == '.' ]] && { ((bl++)) ; continue ;}        # '.' als Kanalname
    if [[ -t 1 ]] ; then
      ((cnt++))
      if ((cnt % 10 == 0)) ; then
        echo -ne "$msgINF Konvertiere Kanalname -> Service #${cnt}"\\r
      fi
    fi

    IFS=':' read -r -a VDRCHANNEL <<< "${VDR_CHANNELSCONF[i]}"

    printf -v SID '%X' "${VDRCHANNEL[9]}"
    printf -v TID '%X' "${VDRCHANNEL[11]}"
    printf -v NID '%X' "${VDRCHANNEL[10]}"

    case ${VDRCHANNEL[3]} in
      *'W') NAMESPACE=$(bc -l <<< "scale=0 ; 3600 - ${VDRCHANNEL[3]//[^0-9.]} * 10")
            printf -v NAMESPACE '%X' "${NAMESPACE%.*}" ;;
      *'E') NAMESPACE=$(bc -l <<< "scale=0 ; ${VDRCHANNEL[3]//[^0-9.]} * 10")
            printf -v NAMESPACE '%X' "${NAMESPACE%.*}" ;;
       'T') NAMESPACE='EEEE' ;;
       'C') NAMESPACE='FFFF' ;;
         *) f_log ERR "Unbekannter Namespace: ${VDRCHANNEL[3]} (${VDR_CHANNELSCONF[i]})" ; continue;;
    esac
    case ${VDRCHANNEL[5]} in
        '0') CHANNELTYPE='2' ;;   # Radio
      *'=2') CHANNELTYPE='1' ;;   # MPEG-2 (SD) Alternativ 16 MPEG (SD)
     *'=27') CHANNELTYPE='19' ;;  # H.264 (HD)
     *'=36') CHANNELTYPE='1F' ;;  # H.265 (UHD)
          *) f_log ERR "Unbekannter Kanaltyp: ${VDRCHANNEL[5]} (${VDR_CHANNELSCONF[i]})" ; continue;;
    esac

    UNIQUE_ID="${SID}_${TID}_${NID}_${NAMESPACE}"
    SERVICEREF_ID="${UNIQUE_ID}0000"
    SERVICEREF="1_0_${CHANNELTYPE}_${SERVICEREF_ID}_0_0_0"
    IFS=';' read -r -a REPLY <<< "${VDRCHANNEL[0]}"
    : "${REPLY[0]%,*}"           # Kanalname ohne Kurzname
    VDR_CHANNELNAME="${_//|/:}"  # | durch : ersetzen

    LC_ALL='C'  # Halbiert die Zeit beim suchen im index
    #LOGO_SRP=$(grep -i -m 1 "^$UNIQUE_ID" <<< "$INDEX" | sed -n -e 's/.*=//p')
    re="[[:space:]]${UNIQUE_ID}([^[:space:]]*)"
    [[ "$INDEX" =~ $re ]] && { LOGO_SRP="${BASH_REMATCH[0]#*=}" ;} || LOGO_SRP="$NOT_SET"

    if [[ "$STYLE" == 'snp' ]] ; then
      #IFS=';' read -r -a REPLY <<< "${CHANNELNAMES[i]}"  # ASCII
      # sed -e 's/^[ \t]*//' -e 's/|//g' -e 's/^//g')
      : "${CHANNELNAMES[i]//\&/and}" ; : "${_//'*'/star}" ; : "${_//+/plus}"  # Zeichen ersetzen (&,*,+)
      : "${_,,}" ; SNPNAME="${_//[^a-z0-9]}"                        # In Kleinbuchstaben und nur a-z0-9
      if [[ -n "$SNPNAME" ]] ; then
        #LOGO_SNP=$(grep -i -m 1 "^$SNPNAME=" <<< "$INDEX" | sed -n -e 's/.*=//p')
        re="[[:space:]]${SNPNAME}=([^[:space:]]*)"
        [[ "$INDEX" =~ $re ]] && { LOGO_SNP="${BASH_REMATCH[1]}" ;} || LOGO_SNP="$NOT_SET"
      else
        SNPNAME="$NOT_SET"
      fi
      LC_ALL="$_LANG"  # Sparcheinstellungen zurückstellen
      echo -e "${SERVICEREF}\t${VDR_CHANNELNAME}\t${SERVICEREF_ID}=${LOGO_SRP}\t${SNPNAME}=${LOGO_SNP}" >> "$TEMPFILE"
    else
      LC_ALL="$_LANG"  # Sparcheinstellungen zurückstellen
      echo -e "${SERVICEREF}\t${VDR_CHANNELNAME}\t${SERVICEREF_ID}=${LOGO_SRP}" >> "$TEMPFILE"
    fi
  done

  SERVICE_FILE="${BUILD_OUTPUT}/servicelist-vdr-${STYLE}.txt"
  #sort -t $'\t' -k 2,2 "$TEMPFILE" | sed -e 's/\t/^|/g' | column -t -s $'^' | sed -e 's/|/  |  /g' > "$SERVICE_FILE"
  #sort --field-separator=$'\t' --key=2,2 "$TEMPFILE" | sed -e 's/\t/  |  /g' > "$SERVICE_FILE"
  sort --field-separator=$'\t' --key=2,2 "$TEMPFILE" > "$SERVICE_FILE"
  rm "$TEMPFILE"
  [[ -t 1 ]] && echo -e '\n'
  f_log INFO "Serviceliste exportiert nach $SERVICE_FILE"
else
  f_log ERR "$CHANNELSCONF nicht gefunden!"
  exit 1
fi

### Icons mit Hintergrund erstellen ###

logfile=$(mktemp --suffix=.picons.log)
f_log INFO "Log-Datei: $logfile"

if command -v pngquant &>/dev/null ; then
  pngquant='pngquant'
  f_log INFO 'Bildkomprimierung (pngquant) aktiviert!'
else
  pngquant='cat'
  f_log WARN 'Bildkomprimierung deaktiviert! "pngquant" installieren!'
fi

if command -v convert &>/dev/null ; then
  f_log INFO 'ImageMagick (convert) gefunden!'
else
  f_log ERR 'ImageMagick (convert) nicht gefunden! "ImageMagick" installieren!'
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

# Prüfen ob Serviceliste existiert
if [[ ! -f "${BUILD_OUTPUT}/servicelist-vdr-${STYLE}.txt" ]] ; then
  f_log ERR "Keine $STYLE Serviceliste gefunden!"
  exit 1
fi

# Einfache Prüfung der Quellen
if [[ -t 1 ]] ; then
  f_log INFO 'Überprüfe snp/srp Index…'
  "${LOCATION}/resources/tools/check-index.sh" "$BUILD_SOURCE" srp
  "${LOCATION}/resources/tools/check-index.sh" "$BUILD_SOURCE" snp
  f_log INFO 'Überprüfe logos…'
  "${LOCATION}/resources/tools/check-logos.sh" "${BUILD_SOURCE}/logos"
fi

# Array mit Symlinks erstellen und Logos sammeln
f_log INFO 'Erzeuge Symlinks und Logosammlung…'
f_create_symlinks  # Array's 'LOGO_PATHS' und 'LOGO_COLLECTION' erstellen

# Konvertierung der Logos
LOGO_COUNT="${#LOGO_COLLECTION[@]}"
mkdir --parents "${temp}/cache" || { echo "Fehler beim erzeugen von ${temp}/cache" >&2 ; exit 1 ;}
[[ ! -d "${LOGODIR}/logos" ]] && { mkdir --parents "${LOGODIR}/logos" || exit 1 ;}

RESOLUTION="${LOGO_CONF[0]:=220x132}"      # Hintergrundgröße
RESIZE="${LOGO_CONF[1]:=200x112}"          # Logogröße
LOGO_TYPE="${LOGO_CONF[2]:=dark}"          # Typ (dark/light)
BACKGROUND="${LOGO_CONF[3]:=transparent}"  # Hintergrund (transparent/blue/...)

f_log INFO "Erzeuge Logos: ${STYLE}.${RESOLUTION}-${RESIZE}.${LOGO_TYPE}.on.${BACKGROUND}…"
for logoname in "${LOGO_COLLECTION[@]}" ; do
  ((currentlogo++))
  [[ -t 1 ]] && echo -ne "$msgINF Konvertiere Logo: ${currentlogo}/${LOGO_COUNT}"\\r

  if [[ -f "${BUILD_SOURCE}/logos/${logoname}.${LOGO_TYPE}.png" || -f "${BUILD_SOURCE}/logos/${logoname}.${LOGO_TYPE}.svg" ]] ; then
    logotype="$LOGO_TYPE"
  else
    logotype='default'
  fi

  echo "--> ${logoname}.${logotype}" >> "$logfile"

  if [[ -f "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" ]] ; then
    ((svg++))
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" ]] && continue  # Nur erstellen wenn neuer
    logo="${temp}/cache/${logoname}.${logotype}.png"
    if [[ ! -f "$logo" ]] ; then
      "${svgconverter[@]}" "${logo}" "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" &>> "$logfile"
    fi
  else
    ((png++))
    logo="${BUILD_SOURCE}/logos/${logoname}.${logotype}.png"
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "$logo" ]] && continue  # Nur erstellen wenn neuer
  fi

  # Hintergrund vorhanden?
  if [[ ! -f "${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png" ]] ; then
    f_log WARN "Hintergrund fehlt! (${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png)"
  fi

  # Erstelle optimiertes Logo mit Hintergrund
  convert "${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png" \
    \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$RESIZE" -gravity center -extent "$RESOLUTION" +repage \) \
    -layers merge - 2>> "$logfile" \
    | "$pngquant" - 2>> "$logfile" > "${LOGODIR}/logos/${logoname}.png"
  ((N_LOGO++))
done

cd "$LOGODIR" || exit 1
echo -e '\n'

f_log INFO 'Verlinke Kanallogos…'
[[ ${#LOGO_NAMES[@]} -eq ${#LOGO_PATHS[@]} ]] || f_log ERR "Anzahl der Logos stimmt nicht überein!"
# Logos verlinken
for i in "${!LOGO_NAMES[@]}"; do
  logo_name="${LOGO_NAMES[i]}"  # Name des Logos
  logo_path="${LOGO_PATHS[i]}"  # Linkziel (Kanalname)

  if [[ "$logo_name" =~ / ]] ; then  # Kanal mit / im Namen
    ch_path="${logo_name%/*}"        # Pfad des Kanals
    mkdir --parents "./${ch_path}" || f_log ERR "Ordner ${LOGODIR}/${ch_path} konnte nicht erstellt werden!"
    logo_path="../${logo_path}"  # Pfad zum Logo (../logos/...)
  fi

  if [[ -f "${LOGO_PATHS[i]}" ]] ; then  # Symlink erstellen
    ln --symbolic --force "$logo_path" "$logo_name" 2>> "${LOGFILE:-/dev/null}" \
      || f_log ERR "Symlink für $logo_name konnte nicht erstellt werden!"
  else
    f_log WARN "Logo $logo_name nicht gefunden!"
  fi
done

# Eigentümer und Berechtigungen setzen
chown --no-dereference --recursive "${LOGO_USER:-vdr}:${LOGO_GROUP:-vdr}" "$LOGODIR" 2> "${LOGFILE:-/dev/null}" \
  || f_log ERR "Eigentümer/Gruppe ${LOGO_USER:-vdr}:${LOGO_GROUP:-vdr} konnte nicht gesetzt werden!"
chmod --recursive 644 "${LOGODIR}"/*.png 2> "${LOGFILE:-/dev/null}" \
  || f_log ERR "Berechtigungen ${LOGODIR} konnten nicht gesetzt werden!"

# Logo History speichern
if [[ -n "$LOGO_HIST" ]] ; then
  [[ ! "$LOGO_HIST" =~ / ]] && LOGO_HIST="${BUILD_OUTPUT}/${LOGO_HIST}"
  if [[ -f "$LOGO_HIST" ]] ; then
    mapfile -t < "$LOGO_HIST"      # Vorherige Daten einlesen
    LOGO_PATHS+=("${MAPFILE[@]}")  # Aktuelle hinzufügen
  fi
  printf '%s\n' "${LOGO_PATHS[@]}" | sort --unique > "$LOGO_HIST"  # Neue DB schreiben
fi

# Aufräumen
if [[ -d "$LOGODIR" && "$LOGODIR" != "/" ]] ; then
  { find "$LOGODIR" -xtype l -delete             # Alte (defekte) Symlinks löschen
    find "$LOGODIR" -LOGO_TYPE d -empty -delete  # Leere Verzeichnisse löschen
  } &>> "${LOGFILE:-/dev/null}"
fi
[[ -d "$temp" ]] && rm --recursive "$temp"

f_log INFO "Erstellen von Logos (${STYLE}) beendet!"

# Statistik anzeigen
[[ "$nologo" -gt 0 ]] && f_log "==> $nologo Kanäle ohne Logo"
[[ "$difflogo" -gt 0 ]] && f_log "==> $difflogo Kanäle mit unterschiedlichen Logos (Vorgabe: ${PREFERED_LOGO})"
[[ "$obs" -gt 0 || "$bl" -gt 0 ]] && f_log "==> Übersprungen: 'OBSOLETE' (${obs:-0}), '.' (${bl:-0})"
f_log "==> $((svg + png)) Logos: $svg im SVG-Format und $png im PNG-Format"
f_log "==> ${N_LOGO:-0} neue(s) oder aktualisierte(s) Logo(s) (Links zu Logos: ${LOGO_COUNT})"
SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
f_log "==> Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"

if [[ -e "$LOGFILE" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat --format=%s "$LOGFILE" 2>/dev/null)"
  [[ $FILESIZE -gt $MAXLOGSIZE ]] && mv --force "$LOGFILE" "${LOGFILE}.old"
fi

exit 0
