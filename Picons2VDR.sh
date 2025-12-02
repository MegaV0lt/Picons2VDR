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
VERSION=251201  # Version des Skripts

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
declare -l SNP_NAME STYLE  # Bei Zuweisung in Kleinbuchstaben umwandeln

# Pfade festlegen
LOCATION="${SELF_PATH}/${PICONS_DIR}"          # Pfad vom GIT
BUILD_SOURCE="${LOCATION}/build-source"        # Quelldateien
BUILD_OUTPUT="${LOCATION}/build-output"        # Ausgabeordner
TEMP=$(mktemp -d --suffix=."${SELF_NAME%.*}")  # Temp-Verzeichnis
mkdir --parents "${TEMP}/cache" || { echo "Fehler beim erzeugen von ${TEMP}/cache" >&2 ; exit 1 ;}

### Funktionen
f_log(){  # Logausgabe auf Konsole oder via Logger. $1 zum kennzeichnen der Meldung.
  local msg="${*:2}"
  case "${1^^}" in
    'ERR'*) [[ -t 2 ]] && { echo -e "$msgERR ${msg:-$1}${nc}" >&2 ;} \
              || logger --tag "$SELF_NAME" --priority user.err "$@" ;;
    'WARN'*) [[ -t 1 ]] && { echo -e "$msgWRN ${msg:-$1}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    'DEBUG') [[ -t 1 ]] && { echo -e "\e[1m${msg:-$1}${nc}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    'INFO'*) [[ -t 1 ]] && { echo -e "$msgINF ${msg:-$1}" ;} || logger --tag "$SELF_NAME" "$@" ;;
    *) [[ -t 1 ]] && { echo -e "$@" ;} || logger --tag "$SELF_NAME" "$@" ;;  # Nicht angegebene
  esac
  [[ -n "$LOGFILE" ]] && echo -e "$@" 2>/dev/null >> "$LOGFILE"  # Log in Datei
}

f_trim() {  # Leerzeichen am Anfang und am Ende entfernen
  printf '%s\n' "${1#"${1%%[![:space:]]*}"}${1##*[![:space:]]}"
}

f_self_update() {  # Automatisches Update
  local branch upstream
  f_log INFO 'Starte Auto-Update…'
  cd "$SELF_PATH" || exit 1
  git fetch &>> "${LOGFILE:-/dev/null}"
  branch=$(git rev-parse --abbrev-ref HEAD)                                  # main
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}")  # origin/main
  if [[ -n "$(git diff --name-only "$upstream" "$SELF_NAME")" ]] ; then
    f_log INFO "Neue Version von $SELF_NAME gefunden! Starte Update…"
    { git pull --force
      git checkout "$branch"
      git pull --force || exit 1
    } &>> "${LOGFILE:-/dev/null}"
    f_log INFO "Starte $SELF_NAME neu…"
    cd - &>> /dev/null || exit 1  # Zurück ins alte Arbeitsverzeichnis
    exec "$SELF" "$@"
    exit 0  # Alte Version des Skripts beenden
  else
    f_log INFO 'OK. Bereits die aktuelle Version'
  fi
}

f_create_symlinks() {  # Daten für Symlinks erzeugen und Logos in Array sammeln
  local channel logo_srp logo_snp servicename
  local -a lnk_srp lnk_snp

  # 1_0_19_151A_455_1_C00000_0_0_0  DMAX HD  151A_455_1_C00000=dmaxhd-wispelutri  dmaxhd=dmaxhd
  mapfile -t < "${BUILD_OUTPUT}/servicelist-vdr-${STYLE}.txt"  # Liste in Array einlesen
  for line in "${MAPFILE[@]}" ; do
    IFS=$'\t' read -r -a line_data <<< "$line"

    channel=$(f_trim "${line_data[1]}")
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
      f_log WARN "?=> Unterschiedliche Logos für $channel gefunden! (SRP: $logo_srp | SNP: ${logo_snp})"
      if [[ "${PREFERED_LOGO:=snp}" == 'srp' ]] ; then  # Bevorzugtes Logo verwenden
        unset -v 'logo_snp'
      else
        unset -v 'logo_srp'
      fi
      ((difflogo++))
    fi

    LOGO_NAMES+=("${servicename}.png")  # VDR Logo-Name
    if [[ -n "$logo_srp" ]] ; then
      LOGO_PATHS+=(".logos/${logo_srp}.png")
      LOGO_COLLECTION+=("$logo_srp")
    elif [[ -n "$logo_snp" ]] ; then
      LOGO_PATHS+=(".logos/${logo_snp}.png")
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
printf -v SCRIPT_STARTTIME "%(%d.%m.%Y %T)T" -1
f_log INFO "=== $SELF_NAME #${VERSION} - Start (${SCRIPT_STARTTIME}) ==="
f_log INFO "   $CONFLOADED Konfiguration: ${CONFIG}"

# Benötigte Variablen prüfen
for var in CHANNELSCONF LOGODIR ; do
  [[ -z "${!var}" ]] && { f_log ERR "Variable $var ist nicht gesetzt!" ; exit 1 ;}
done
f_log INFO "   Kanal-Liste: ${CHANNELSCONF}"
f_log INFO "   Logo-Verzeichnis: ${LOGODIR}"
f_log INFO "   Log-Datei: ${LOGFILE:=/dev/null}"

# Stil gültig?
STYLE="${1:-utf8snp}"  # Vorgabe ist utf8snp
if [[ "$STYLE" != 'srp' && "$STYLE" != 'utf8snp' ]] ; then
  f_log ERR "Unbekannter Logo-Index! (${STYLE})"
  exit 1
fi
f_log INFO "   Logo-Index: ${STYLE}"

# Benötigte Programme suchen
COMMANDS=(bc find git iconv ln mv printf rm sort)
for cmd in "${COMMANDS[@]}" ; do
  type "$cmd" &>/dev/null || MISSING_COMMANDS+=("$cmd")
done
if [[ -n "${MISSING_COMMANDS[*]}" ]] ; then
  f_log ERR "Fehlende Datei(en): ${MISSING_COMMANDS[*]}"
  exit 1
fi

# Automatisches Update von Picons2VDR.sh
[[ "$AUTO_UPDATE" == 'true' ]] && f_self_update "$@"

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
  if ! git pull &>> "$LOGFILE" ; then
    f_log ERR 'Aktualisierung hat nicht funktioniert!'
    exit 1
  else
    last_logo_update="$(git log -1 --date=format:"%d.%m.%Y %T" --format="%ad")"
    f_log INFO "Letztes Update der Logos: $last_logo_update"
    cd "$SELF_PATH" || exit 1
  fi
fi

# utf8snp.index in NFC umwandeln (Bei Fehler weiter mit original Datei)
if [[ "$STYLE" == 'utf8snp' ]] ; then
  f_log INFO "Wandle utf8snp.index in UTF-8 NFC um (Verwende normalize_text.py)…"
  if command -v python3 &>/dev/null ; then
    python3 "${SELF_PATH}/normalize_text.py" -i "${BUILD_SOURCE}/utf8snp.index" -o "${TEMP}/utf8snp.nfc.index" 2>> "$LOGFILE" \
      || { f_log ERR 'Konvertierung in NFC ist fehlgeschlagen!' ;}
  else
    f_log ERR "python3 nicht gefunden, kann normalize_text.py nicht ausführen!"
  fi
  # Priorisiere die temporäre Datei, sonst vorhandene projektinterne Datei als Index verwenden
  if [[ -f "${TEMP}/utf8snp.nfc.index" ]] ; then
    INDEX_PATH="${TEMP}/utf8snp.nfc.index"
  else
    INDEX_PATH="${BUILD_SOURCE}/utf8snp.index"
  fi
else
  INDEX_PATH="${BUILD_SOURCE}/${STYLE}.index"
fi

# Index-Datei in Array einlesen
mapfile -t INDEX < "${INDEX_PATH}"

### VDR Serviceliste erzeugen
if [[ -f "$CHANNELSCONF" ]] ; then
  _LC="${LANG:-$LC_NAME}"  # Locale merken
  read -r -a ENCODING < <(encguess -u "$CHANNELSCONF" 2>> "$LOGFILE")  # Kodierung der Kanalliste ermitteln
  f_log INFO "Kodierung der Kanalliste: ${ENCODING[1]:-Unbekannt}"
  # Kanalliste in Array einlesen (UTF-8)
  mapfile -t VDR_CHANNELSCONF < <(iconv -f "${ENCODING[1]:-UTF-8}" -t UTF-8 -c < "$CHANNELSCONF" 2>> "$LOGFILE")
  f_log INFO "Erzeuge VDR Serviceliste (${STYLE})…"
  # Beispiel Eintrag VDR_CHANNELSCONF:
  # Das Erste HD;ARD:11493:HC23M5O35P0S1:S19.2E:22000:5101=27:5102=deu@3,5103=mis@3,5107=qks@3;5106=deu@106:5104;5105=deu:0:10301:1:1019:0
  for i in "${!VDR_CHANNELSCONF[@]}" ; do
    IFS=':' read -r -a VDRCHANNEL <<< "${VDR_CHANNELSCONF[i]}"
    [[ -z "${VDRCHANNEL[0]}" ]] && { ((grp++)) ; continue ;}        # Kanalgruppe
    : "${VDRCHANNEL[0]%;*}"  # Kanalname ohne Provider
    CHANNEL_NAME="${_%,*}"   # Kanalname ohne Kurzname. Nur das letzte , entfernen (NDR 90,3,;ARD NDR)
    [[ "$CHANNEL_NAME" =~ OBSOLETE ]] && { ((obs++)) ; continue ;}  # Als 'OBSOLETE' markierter Kanal
    [[ "$CHANNEL_NAME" == '.' ]] && { ((bl++)) ; continue ;}        # '.' als Kanalname

    ((cnt++))  # Zähler für verarbeitete Kanäle
    if [[ -t 1 ]] && ((cnt % 5 == 0)) ; then
      echo -ne "$msgINF Konvertiere Kanalname -> Service #${cnt}"\\r
    fi

    printf -v SID '%X' "${VDRCHANNEL[9]}"   # 10301 -> 283D
    printf -v TID '%X' "${VDRCHANNEL[11]}"  # 1019  -> 3FB
    printf -v NID '%X' "${VDRCHANNEL[10]}"  # 1     -> 1

    case ${VDRCHANNEL[3]} in  # S19.2E
      *'W') NAMESPACE=$(bc -l <<< "scale=0 ; 3600 - ${VDRCHANNEL[3]//[^0-9.]} * 10")
            printf -v NAMESPACE '%X' "${NAMESPACE%.*}" ;;
      *'E') NAMESPACE=$(bc -l <<< "scale=0 ; ${VDRCHANNEL[3]//[^0-9.]} * 10")  # 192.0
            printf -v NAMESPACE '%X' "${NAMESPACE%.*}" ;;  # C0
       'T') NAMESPACE='EEEE' ;;  # DVB-T
       'C') NAMESPACE='FFFF' ;;  # DVB-C
         *) f_log ERR "Unbekannter Namespace: ${VDRCHANNEL[3]} (${VDR_CHANNELSCONF[i]})" ; continue;;
    esac
    case ${VDRCHANNEL[5]} in  # 5101=27
        '0') CHANNELTYPE='2' ;;   # Radio
      *'=2') CHANNELTYPE='1' ;;   # MPEG-2 (SD) Alternativ 16 MPEG (SD)
     *'=27') CHANNELTYPE='19' ;;  # H.264 (HD)
     *'=36') CHANNELTYPE='1F' ;;  # H.265 (UHD)
          *) f_log ERR "Unbekannter Kanaltyp: ${VDRCHANNEL[5]} (${VDR_CHANNELSCONF[i]})" ; continue;;
    esac

    UNIQUE_ID="${SID}_${TID}_${NID}_${NAMESPACE}"  # 283D_3FB_1_C0
    SERVICEREF_ID="${UNIQUE_ID}0000"
    SERVICEREF="1_0_${CHANNELTYPE}_${SERVICEREF_ID}_0_0_0"
    VDR_CHANNELNAME="${CHANNEL_NAME//|/:}"  # '|' durch ':' ersetzen
    SNP_NAME="${VDR_CHANNELNAME//'/'}"       # Alle '/' löschen

    LC_ALL='C'  # Halbiert die Zeit beim suchen im index
    for entry in "${INDEX[@]}"; do
      # Check if entry contains unique ID (283D_3FB_1_C00000=daserstehd)
      # if [[ "$entry" == "${SERVICEREF_ID}="* ]] ; then
      if [[ "$entry" =~ ^"${SERVICEREF_ID}"=.* ]] ; then
        LOGO_SRP="${entry#*=}"
        [[ "$STYLE" == 'srp' ]] && break  # for entry
      fi

      # Check if entry contains name of the channel
      if [[ "$STYLE" == 'utf8snp' && "${entry}" == "${SNP_NAME}="* ]] ; then
        LOGO_SNP="${entry#*=}"
        break  # for entry
      fi
    done
    LC_ALL="$_LC"  # Sparcheinstellungen zurückstellen

    # Zur Serviceliste hinzufügen
    if [[ "$STYLE" == 'utf8snp' ]] ; then
      SERVICE_LIST+=("${SERVICEREF}\t${VDR_CHANNELNAME}\t${SERVICEREF_ID}=${LOGO_SRP}\t${SNP_NAME}=${LOGO_SNP}")
    else
      SERVICE_LIST+=("${SERVICEREF}\t${VDR_CHANNELNAME}\t${SERVICEREF_ID}=${LOGO_SRP}")
    fi
    # Variablen zurücksetzen
    unset -v CHANNEL_NAME VDRCHANNEL NAMESPACE CHANNELTYPE VDR_CHANNELNAME
    LOGO_SRP="$NOT_SET" ; LOGO_SNP="$NOT_SET"
    SNP_NAME=''
  done  # for i in "${!VDR_CHANNELSCONF[@]}"

  SERVICE_FILE="${BUILD_OUTPUT}/servicelist-vdr-${STYLE}.txt"
  #sort -t $'\t' -k 2,2 "$TEMPFILE" | sed -e 's/\t/^|/g' | column -t -s $'^' | sed -e 's/|/  |  /g' > "$SERVICE_FILE"
  sort --field-separator=$'\t' --key=2,2 <(printf '%b\n' "${SERVICE_LIST[@]}") 2>> "$LOGFILE" > "$SERVICE_FILE"
  f_log INFO "Serviceliste exportiert nach $SERVICE_FILE"
else
  f_log ERR "$CHANNELSCONF nicht gefunden!"
  exit 1
fi

# Bildkomprimierung prüfen
if command -v pngquant &>/dev/null ; then
  pngquant='pngquant'
  f_log INFO 'Bildkomprimierung (pngquant) aktiviert!'
else
  pngquant='cat'
  f_log WARN 'Bildkomprimierung deaktiviert! "pngquant" installieren!'
fi
# Bildkonvertierung prüfen
if command -v convert &>/dev/null ; then
  f_log INFO 'ImageMagick (convert) gefunden!'
else
  f_log ERR 'ImageMagick (convert) nicht gefunden! "ImageMagick" installieren!'
  exit 1
fi
# SVG-Konverter prüfen
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
  f_log INFO "Überprüfe $STYLE Index…"
  "${LOCATION}/resources/tools/check-index.sh" "$BUILD_SOURCE" "$STYLE"
  f_log INFO 'Überprüfe logos…'
  "${LOCATION}/resources/tools/check-logos.sh" "${BUILD_SOURCE}/logos"
fi

# Array's für Symlinks und Logos erstellen
f_log INFO 'Erzeuge Symlinks und Logosammlung…'
f_create_symlinks  # Array's 'LOGO_PATHS', 'LOGO_NAMES' und 'LOGO_COLLECTION' erstellen

# Konvertierung der Logos
LOGO_COUNT="${#LOGO_COLLECTION[@]}"
[[ ! -d "${LOGODIR}/.logos" ]] && { mkdir --parents "${LOGODIR}/.logos" || exit 1 ;}

RESOLUTION="${LOGO_CONF[0]:=220x132}"      # Hintergrundgröße
RESIZE="${LOGO_CONF[1]:=200x112}"          # Logogröße
LOGO_TYPE="${LOGO_CONF[2]:=dark}"          # Typ (dark/light)
BACKGROUND="${LOGO_CONF[3]:=transparent}"  # Hintergrund (transparent/blue/...)

# Hintergrund vorhanden?
if [[ ! -f "${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png" ]] ; then
  f_log WARN "Hintergrund fehlt! (${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png)"
fi

### Logos erzeugen
f_log INFO "Erzeuge Logos: Größe Hintergrund/Logo:${RESOLUTION}/${RESIZE}, Typ: ${LOGO_TYPE} auf ${BACKGROUND}…"
for logoname in "${LOGO_COLLECTION[@]}" ; do
  ((currentlogo++))
  [[ -t 1 ]] && echo -ne "$msgINF Konvertiere Logo: ${currentlogo}/${LOGO_COUNT}"\\r

  if [[ -f "${BUILD_SOURCE}/logos/${logoname}.${LOGO_TYPE}.png" || -f "${BUILD_SOURCE}/logos/${logoname}.${LOGO_TYPE}.svg" ]] ; then
    logotype="$LOGO_TYPE"
  else
    logotype='default'
  fi

  # SVG-Datei vorhanden?
  if [[ -f "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" ]] ; then
    ((svg++))
    [[ "${LOGODIR}/.logos/${logoname}.png" -nt "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" ]] && continue  # Nur erstellen wenn neuer
    logo="${TEMP}/cache/${logoname}.${logotype}.png"
    if [[ ! -f "$logo" ]] ; then
      "${svgconverter[@]}" "${logo}" "${BUILD_SOURCE}/logos/${logoname}.${logotype}.svg" &>> "$LOGFILE" \
        || { f_log ERR "SVG-Konvertierung für ${logoname}.${logotype}.svg fehlgeschlagen!" ; continue ;}
    fi
  else
    ((png++))
    logo="${BUILD_SOURCE}/logos/${logoname}.${logotype}.png"
    [[ "${LOGODIR}/.logos/${logoname}.png" -nt "$logo" ]] && continue  # Nur erstellen wenn neuer
  fi

  # TODO: Add reflection (https://legacy.imagemagick.org/Usage/advanced/#reflections)
  # Erstelle optimiertes Logo inklusive Hintergrund
  if [[ "$pngquant" == 'pngquant' ]] ; then
    # pngquant mit Qualitäts-/Geschwindigkeitsoptionen, Metadaten entfernen
    convert "${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png" \
      \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$RESIZE" -gravity center -extent "$RESOLUTION" +repage \) \
      -layers merge - 2>> "$LOGFILE" \
      | "$pngquant" --quality=60-90 --speed=3 --skip-if-larger --strip - 2>> "$LOGFILE" > "${LOGODIR}/.logos/${logoname}.png"
  else
    # Fallback (kein pngquant installiert): einfach durchreichen
    convert "${BUILD_SOURCE}/backgrounds/${RESOLUTION}/${BACKGROUND}.png" \
      \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$RESIZE" -gravity center -extent "$RESOLUTION" +repage \) \
      -layers merge - 2>> "$LOGFILE" \
      | "$pngquant" - 2>> "$LOGFILE" > "${LOGODIR}/.logos/${logoname}.png"
  fi

  # Prüfe Exit-Codes der Pipeline (convert | pngquant)
  ret_convert=${PIPESTATUS[0]:-1}
  ret_png=${PIPESTATUS[1]:-1}
  if [[ $ret_convert -ne 0 || $ret_png -ne 0 ]] ; then
    f_log ERR "Bildgenerierung/Optimierung fehlgeschlagen für ${logoname} (convert=${ret_convert}, pngquant=${ret_png})"
    continue
  fi

  ((N_LOGO++))
done

cd "$LOGODIR" || exit 1

f_log INFO 'Erstelle symbolische Links für Kanallogos…'
[[ ${#LOGO_NAMES[@]} -eq ${#LOGO_PATHS[@]} ]] || f_log ERR "Anzahl der Logos stimmt nicht überein!"
# Logos verlinken
for i in "${!LOGO_NAMES[@]}"; do
  logo_name="${LOGO_NAMES[i]}"  # Name des Logos (VDR)
  logo_path="${LOGO_PATHS[i]}"  # Linkziel (Erzeugtes Logo in .logos)

  if [[ "$logo_name" =~ / ]] ; then  # Kanalname enthält '/'
    ch_path="${logo_name%/*}"        # Pfad des Kanals
    mkdir --parents "./${ch_path}" || f_log ERR "Ordner ${LOGODIR}/${ch_path} konnte nicht erstellt werden!"
    logo_path="../${logo_path}"  # Pfad zum Logo (../.logos/...)
  fi

  if [[ -f "${LOGO_PATHS[i]}" ]] ; then  # Symlink erstellen
    ln --symbolic --force "$logo_path" "$logo_name" 2>> "$LOGFILE" \
      || f_log ERR "Symlink für $logo_name konnte nicht erstellt werden!"
  else
    f_log WARN "Logo ${LOGO_COLLECTION[i]} für $logo_name nicht gefunden!"
  fi
done

# Eigentümer und Berechtigungen setzen
chown --no-dereference --recursive "${LOGO_USER:-vdr}:${LOGO_GROUP:-vdr}" "$LOGODIR" 2>> "$LOGFILE" \
  || f_log ERR "Eigentümer/Gruppe ${LOGO_USER:-vdr}:${LOGO_GROUP:-vdr} konnte nicht gesetzt werden!"
chmod --recursive 644 "${LOGODIR}"/*.png 2>> "$LOGFILE" \
  || f_log ERR "Berechtigungen für ${LOGODIR} konnten nicht gesetzt werden!"

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
if [[ -d "$LOGODIR" && "$LOGODIR" != '/' ]] ; then
  { find "$LOGODIR" -xtype l -delete        # Alte (defekte) Symlinks löschen
    find "$LOGODIR" -type d -empty -delete  # Leere Verzeichnisse löschen
  } &>> "$LOGFILE"
fi
[[ -d "$TEMP" && "$TEMP" != '/' ]] && rm --recursive "$TEMP"

# Statistik anzeigen
f_log INFO "Kanallogos (${STYLE}) wurden erstellt!"
[[ "$nologo" -gt 0 ]] && f_log "==> Kanäle ohne Logo: ${nologo}/${cnt}"
[[ "$difflogo" -gt 0 ]] && f_log "==> Kanäle mit unterschiedlichen Logos: $difflogo (Vorgabe: ${PREFERED_LOGO})"
[[ "$grp" -gt 0 || "$obs" -gt 0 || "$bl" -gt 0 ]] && { f_log "==> Übersprungene Einträge: Kanalgruppen: ${grp:-0}, 'OBSOLETE': ${obs:-0}, '.': ${bl:-0}" ;}
# Anzahl von Logos im picoins.git zählen
mapfile -t < <(ls -1 "${BUILD_SOURCE}/logos/"*.png "${BUILD_SOURCE}/logos/"*.svg 2>/dev/null)
: "${#MAPFILE[@]}" ; total_logos="${_:-?}"
f_log "==> Verwendete Logos: $((svg + png))/${total_logos} ($svg im SVG- und $png im PNG-Format)"
f_log "==> ${N_LOGO:-0} neue(s) oder aktualisierte(s) Logo(s) erstellt"
SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
f_log "==> Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"

if [[ -f "$LOGFILE" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat --format=%s "$LOGFILE" 2>/dev/null)"
  [[ $FILESIZE -gt $MAXLOGSIZE ]] && mv --force "$LOGFILE" "${LOGFILE}.old"
fi

exit 0  # Ende des Skripts
