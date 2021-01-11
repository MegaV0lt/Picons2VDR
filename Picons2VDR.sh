#!/bin/bash

# Skript zum erzeugen und verlinken der PICON-Kanallogos (Enigma2)

# Das benötigte GIT wird vom Skript lokal auf die Festplatte geladen
# Ziel ist in der *.conf einstellbar

# Die Dateinamen passen nicht zum VDR-Schema. Darum verwendet das Skript
# aus den im GIT enthaltenen index-Dateien, um die Logos dann passend zu verlinken.

# Die Logos werden im PNG-Format erstellt. Die Größe und den optionalen Hintergrund
# kann man in der *.conf einstellen.
# Das Skript am besten ein mal pro Woche ausführen (/etc/cron.weekly)
VERSION=210109

# Sämtliche Einstellungen werden in der *.conf vorgenommen.
# ---> Bitte ab hier nichts mehr ändern! <---

### Variablen
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"
SELF_PATH="${SELF%/*}"
printf -v RUNDATE '%(%d.%m.%Y %R)T' -1  # Aktuelles Datum und Zeit
msgERR='\e[1;41m FEHLER! \e[0;1m' ; nc='\e[0m'  # Anzeige "FEHLER!"
msgINF='\e[42m \e[0m' ; msgWRN='\e[103m \e[0m'  # " " mit grünem/gelben Hintergrund
PICONS_GIT='https://github.com/picons/picons.git'  # Picon-Logos
PICONS_DIR='picons.git'  # Ordner, wo die Picon-Kanallogos liegen (GIT)
OLDIFS="$IFS"

### Funktionen
f_log() {  # Gibt die Meldung auf der Konsole und im Syslog aus
  [[ -n "$LOGGER" ]] && { "$LOGGER" --stderr --tag "$SELF_NAME" "$*" ;} || echo "$*"
  [[ -n "$LOGFILE" ]] && echo "$*" 2 >/dev/null >> "$LOGFILE"  # Log in Datei
}

f_trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"  # Leerzeichen am Anang entfernen
  var="${var%"${var##*[![:space:]]}"}"  # Leerzeichen am Ende entfernen
  printf '%s' "$var"
}

f_create-symlinks() {  # Symlinks erzeugen
  local logo_srp logo_snp
  echo '#!/bin/sh' > "${temp}/create-symlinks.sh"
  chmod 755 "${temp}/create-symlinks.sh"

  mapfile -t servicelist < "$location"/build-output/servicelist-vdr-"$style".txt  # Liste in Array einlesen
  for line in "${servicelist[@]}" ; do
    IFS='|'
    read -r -a line_data <<< "$line" # ??? tr -d '[=*=]' \
    #serviceref=$(f_trim "${line_data[0]}")
    servicename=$(f_trim "${line_data[1]//:/|}")  # Kanalname (Doppelpunkt ersetzen)
    link_srp=$(f_trim "${line_data[2]}")
    link_snp=$(f_trim "${line_data[3]}")

    IFS='='
    read -r -a lnk_srp <<< "$link_srp"
    logo_srp="${lnk_srp[1]}"
    read -r -a lnk_snp <<< "$link_snp"
    logo_snp="${lnk_snp[1]}"
    #snpname="${lnk_snp[0]}"
    IFS="$OLDIFS"

    if [[ "$logo_srp" == '--------' && "$logo_snp" == '--------' ]] ; then
      echo -e "$msgWRN Kein Logo für $servicename (${link_srp[*]} | ${link_snp[*]}) gefunden!"
      if [[ -n "$LOGFILE" ]] ; then
        echo "Kein Logo für $servicename (${link_srp} | ${link_snp}) gefunden!"  2>/dev/null >> "$LOGFILE"
      fi
      ((nologo++)) ; continue
    fi
    if [[ "$servicename" =~ / ]] ; then  # Kanal mit / im Namen
      ch_path="${servicename%/*}"        # Der Teil vor dem lezten /
      mkdir --parents "${LOGODIR}/${ch_path}"
      logos='../logos'
    fi
    if [[ "$logo_srp" != '--------' ]] ; then
      echo "ln -s -f \"${logos:-logos}/${logo_srp}.png\" \"${servicename}.png\"" >> "${temp}/create-symlinks.sh"
      logocollection+=("$logo_srp")
    fi
    if [[ "$style" == 'snp' && "$logo_snp" != '--------' ]] ; then
      echo "ln -s -f \"${logos:-logos}/${logo_snp}.png\" \"${servicename}.png\"" >> "${temp}/create-symlinks.sh"
      logocollection+=("$logo_snp")
    fi
    unset -v 'logos'
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
         f_log "Fehler! Die angegebene Konfigurationsdatei fehlt! (\"${CONFIG}\")"
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
    f_log "Fehler! Keine Konfigurationsdatei gefunden! (\"${CONFIG_DIRS[*]}\")"
    exit 1
  fi
fi

f_log "==> $RUNDATE - $SELF_NAME #${VERSION} - Start..."
f_log "$CONFLOADED Konfiguration: ${CONFIG}"

### Pfade festlegen
location="${SELF_PATH}/${PICONS_DIR}"     # Pfad vom GIT
logfile=$(mktemp --suffix=.servicelist.log)
temp=$(mktemp -d --suffix=.picons)
echo -e "$msgINF Log-Datei: $logfile"

### Benötigte Programme suchen
commands=(sed grep column sort find rm iconv printf)
commands+=(bc mkdir mv ln readlink)
for cmd in "${commands[@]}" ; do
  if ! command -v "$cmd" &> /dev/null ; then
    missingcommands+=("$cmd")
  fi
done
if [[ -n "${missingcommands[*]}" ]] ; then
  echo -e "$msgERR Fehlende Datei(en): ${missingcommands[*]}${nc}"
  exit 1
fi

### Pfad mit Leerzeichen?
re='[[:space:]]+'
if [[ "$location" =~ $re ]]; then
  echo -e "$msgERR Pfad enthält Leerzeichen. Bitte Pfad ohne Leerzeichen verwenden!$nc"
  exit 1
fi

### picons.git laden oder aktualisieren
cd "$SELF_PATH" || exit 1
if [[ ! -d "${PICONS_DIR}/.git" ]] ; then
  echo -e "$msgWRN $PICONS_DIR nicht gefunden!"
  echo -e "$msgINF Klone $PICONS_GIT nach $PICONS_DIR"
  echo -e "${msgINF}\n${msgINF} Zum abbrechen Strg-C drücken. Starte in 5 Sekunden…"
  sleep 5
  git clone "$PICONS_GIT" "$PICONS_DIR" || \
    { echo -e "$msgERR Klonen hat nicht funktioniert!" ; exit 1 ;}
else
  echo -e "$msgINF Aktualisiere Picons in $PICONS_DIR"
  cd "$PICONS_DIR" || exit 1
  git pull >> "$logfile"
  cd "$SELF_PATH" || exit 1
fi

### Stil gültig?
style='snp'
if [[ "$style" != 'srp' && "$style" != 'snp' ]] ; then
  echo -e "$msgERR Unbekannter Stil!$nc"
  exit 1
fi

### .index einlesen
#mapfile -t index < "${location}/build-source/${style}.index"
index=$(<"${location}/build-source/${style}.index")

### VDR Serviceliste erzeugen
if [[ -f "$CHANNELSCONF" ]] ; then
  file="${location}/build-output/servicelist-vdr-${style}.txt"
  tempfile=$(mktemp --suffix=.servicelist)
  iconv -f utf-8 -t ascii//translit -c < "$CHANNELSCONF" -o "${temp}/channels.asc" 2>> "$logfile"
  mapfile -t channelnames < "${temp}/channels.asc"  # Kanalliste in ASCII
  channelnames=("${channelnames[@]%%:*}")  # Nur den Kanalnamen (Mit Provider und Kurzname)
  mapfile -t channelsconf < "$CHANNELSCONF"  # Kanalliste in Array einlesen

  for nr in "${!channelsconf[@]}" ; do
    [[ "${channelsconf[nr]:0:1}" == : ]] && continue    # Kanalgruppe
    [[ "${channelsconf[nr]}" =~ OBSOLETE ]] && continue   # Als 'OBSOLETE' markierter Kanal
    ((cnt++)) ; echo -ne "$msgINF VDR: Konvertiere Kanal #${cnt}"\\r
    IFS=':'
    read -r -a vdrchannel <<< "${channelsconf[nr]}"

    printf -v sid '%X' "${vdrchannel[9]}"
    printf -v tid '%X' "${vdrchannel[11]}"
    printf -v nid '%X' "${vdrchannel[10]}"

    case ${vdrchannel[3]} in
      *'W') namespace=$(bc -l <<< "scale=0 ; 3600 - ${vdrchannel[3]//[^0-9.]}*10")
            printf -v namespace '%X' "${namespace%.*}" ;;
      *'E') namespace=$(bc -l <<< "scale=0 ; ${vdrchannel[3]//[^0-9.]}*10")
            printf -v namespace '%X' "${namespace%.*}" ;;
       'T') namespace='EEEE' ;;
       'C') namespace='FFFF' ;;
    esac
    case ${vdrchannel[5]} in
        '0') channeltype='2' ;;
      *'=2') channeltype='1' ;;
     *'=27') channeltype='19' ;;
    esac

    #unique_id=$(sed -e 's/.*/\U&\E/' <<< "${sid}_${tid}_${nid}_${namespace}") ???
    unique_id="${sid}_${tid}_${nid}_${namespace}"  # In Großbuchstaben
    serviceref="1_0_${channeltype}_${unique_id}0000_0_0_0"
    serviceref_id="${unique_id}0000"
    IFS=';'
    read -r -a channelname <<< "${vdrchannel[0]}"
    read -r -a snpchannelname <<< "${channelnames[nr]}"  # ASCII
    IFS="$OLDIFS"
    vdr_channelname="${channelname[0]%,*}"       # Kanalname ohne Kurzname
    vdr_channelname="${vdr_channelname,,[A-Z]}"  # In Kleinbuchstaben (Außer Umlaute)
    vdr_channelname="${vdr_channelname//|/:}"    # | durch : ersetzen

    #channelname[0]=$(iconv -f utf-8 -t ascii//translit <<< "${channelname[0]%,*}" 2>> "$logfile") #\
      #| sed -e 's/^[ \t]*//' -e 's/|//g' -e 's/^//g')
    snpchannelname[0]="${snpchannelname[0]%,*}"
    snpchannelname[0]="${snpchannelname[0]//[[:space:]]}"
    snpchannelname[0]="${snpchannelname[0]//|}"

    logo_srp=$(grep -i -m 1 "^$unique_id" <<< "$index")  # | sed -n -e 's/.*=//p')
    logo_srp="${logo_srp#*=}"
    [[ -z "$logo_srp" ]] && logo_srp='--------'

    if [[ "$style" == 'snp' ]] ; then
      #snpname=$(sed -e 's/&/and/g' -e 's/*/star/g' -e 's/+/plus/g' -e 's/\(.*\)/\L\1/g' -e 's/[^a-z0-9]//g' <<< "${snpchannelname[0]}")
      snpname="${snpchannelname[0]//\&/and}" ; snpname="${snpname//'*'/star}" ; snpname="${snpname//+/plus}"
      snpname="${snpname,,}" ; snpname="${snpname//[^a-z0-9]}"
      if [[ -n "$snpname" ]] ; then
        logo_snp=$(grep -i -m 1 "^$snpname=" <<< "$index")  # | sed -n -e 's/.*=//p')
        logo_snp="${logo_snp#*=}"
      else
        snpname='--------'
      fi
      [[ -z "$logo_snp" ]] && logo_snp='--------'
      echo -e "${serviceref}\t${vdr_channelname}\t${serviceref_id}=${logo_srp}\t${snpname}=${logo_snp}" >> "$tempfile"
    else
      #echo -e "${serviceref}\t${channelname[0]}\t${serviceref_id}=${logo_srp}" >> "$tempfile"
      echo -e "${serviceref}\t${vdr_channelname}\t${serviceref_id}=${logo_srp}" >> "$tempfile"
    fi
  done
  #sort -t $'\t' -k 2,2 "$tempfile" | sed -e 's/\t/^|/g' | column -t -s $'^' | sed -e 's/|/  |  /g' > "$file"
  sort -t $'\t' -k 2,2 "$tempfile" | sed -e 's/\t/  |  /g' > "$file"
  rm "$tempfile"
  echo -e "\n$msgINF VDR: Exportiert nach $file"
else
  echo -e "$msgERR VDR: $CHANNELSCONF nicht gefunden!$nc"
  exit 1
fi

### Build icons ###

### Setup locations
logfile=$(mktemp --suffix=.picons.log)
echo -e "$msgINF Log-Datei: $logfile"

if command -v pngquant &> /dev/null ; then
  pngquant='pngquant'
  echo -e "$msgINF Bildkomprimierung aktiviert!"
else
  pngquant='cat'
  echo -e "$msgWRN Bildkomprimierung deaktiviert! \"pngquant\" installieren!"
fi

if command -v convert &> /dev/null ; then
  echo -e "$msgINF ImageMagick gefunden!"
else
  echo -e "$msgERR ImageMagick nicht gefunden! \"imagemagick\" installieren!"
  exit 1
fi

: SVGCONVERTER="${SVGCONVERTER:=rsvg}"  # Vorgabe ist rsvg
if command -v inkscape &> /dev/null && [[ "$SVGCONVERTER" == 'inkscape' ]] ; then
  svgconverter='inkscape -w 850 --without-gui --export-area-drawing --export-png='
  echo -e "$msgINF Verwende inkscape als SVG-Konverter!"
elif command -v rsvg-convert &> /dev/null && [[ "$SVGCONVERTER" = 'rsvg' ]] ; then
  svgconverter=('rsvg-convert' -w 1000 --keep-aspect-ratio --output)
  echo -e "$msgINF Verwende rsvg als SVG-Konverter!"
else
  echo -e "$msgERR SVG-Konverter: ${SVGCONVERTER} nicht gefunden!$nc"
  exit 1
fi

### Check if previously chosen style exists
for file in "$location"/build-output/servicelist-*-"$style".txt ; do
  if [[ ! -f "$file" ]] ; then
    echo -e "$msgERR Keine $style Serviceliste gefunden!$nc"
    exit 1
  fi
done

### Determine version number
if [[ -d "${location}/.git" ]] && command -v git &> /dev/null ; then
  cd "$location" || exit 1
  hash=$(git rev-parse --short HEAD)
  version=$(date --utc --date=@$(git show -s --format=%ct "$hash") +'%Y-%m-%d--%H-%M-%S')
  #timestamp=$(date --utc --date=@$(git show -s --format=%ct "$hash") +'%Y%m%d%H%M.%S')
else
  epoch='date --utc +%s'
  version=$(date --utc --date=@$("$epoch") +'%Y-%m-%d--%H-%M-%S')
  #timestamp=$(date --utc --date=@$("$epoch") +'%Y%m%d%H%M.%S')
fi

echo -e "$msgINF Version: $version"

### Einfache Prüfung der Quellen
if [[ $- == *i* ]] ; then
  echo -e "$msgINF Checking index…"
  "$location/resources/tools/check-index.sh" "$location/build-source srp"
  "$location/resources/tools/check-index.sh" "$location/build-source snp"

  echo -e "$msgINF Checking logos…"
  "$location/resources/tools/check-logos.sh" "$location/build-source/logos"
fi

### create-symlinks.sh erstellen
echo -e "$msgINF Erzeuge Datei \"create-symlinks.sh\"…"
f_create-symlinks

### Konvertierung der Logos
logocount="${#logocollection[@]}"
mkdir --parents "${temp}/cache" || { echo "Fehler beim erzeugen von ${temp}/cache" ; exit 1 ;}
[[ ! -d "$LOGODIR" ]] && { mkdir --parents "$LOGODIR" || exit 1 ;}

resolution="${LOGO_CONF[0]:=220x132}"
resize="${LOGO_CONF[1]:=200x112}"
type="${LOGO_CONF[2]:=dark}"
background="${LOGO_CONF[3]:=transparent}"
packagenamenoversion="${style}.${resolution}-${resize}.${type}.on.${background}"

mkdir --parents "${LOGODIR}/logos"

echo -e "$msgINF Erzeuge Logos: ${packagenamenoversion}…"
currentlogo=0
for logoname in "${logocollection[@]}" ; do
  ((currentlogo++))
  echo -ne "$msgINF Konvertiere Logo: $currentlogo/$logocount"\\r

  if [[ -f "${location}/build-source/logos/${logoname}.${type}.png" || -f "${location}/build-source/logos/${logoname}.${type}.svg" ]] ; then
    logotype="$type"
  else
    logotype='default'
  fi

  echo "${logoname}.${logotype}" >> "$logfile"

  if [[ -f "${location}/build-source/logos/${logoname}.${logotype}.svg" ]] ; then
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "${location}/build-source/logos/${logoname}.${logotype}.svg" ]] && continue  # Only convert newer ones
    logo="${temp}/cache/${logoname}.${logotype}.png"
    if [[ ! -f "$logo" ]] ; then
      "${svgconverter[@]}" "${logo}" "${location}/build-source/logos/${logoname}.${logotype}.svg" 2>> "$logfile" >> "$logfile"
    fi
  else
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "${location}/build-source/logos/${logoname}.${logotype}.png" ]] && continue  # Only convert newer ones
    logo="${location}/build-source/logos/${logoname}.${logotype}.png"
  fi

  # Erstelle Logo mit Hintergrund
  convert "${location}/build-source/backgrounds/${resolution}/${background}.png" \
    \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$resize" -gravity center -extent "$resolution" +repage \) \
    -layers merge - 2>> "$logfile" \
    | "$pngquant" - 2>> "$logfile" > "${LOGODIR}/logos/${logoname}.png"
  ((N_LOGO++))
done

cd "$LOGODIR" || exit 1
echo -e "\n${msgINF} Verlinke Logos…"
"${temp}/create-symlinks.sh"

find "$LOGODIR" -xtype l -delete >> "${LOGFILE:-/dev/null}"  # Alte (defekte) Symlinks löschen

if [[ -d "$temp" ]] ; then rm -rf "$temp" ; fi

echo -e "$msgINF Erzeugen von ${style} Logos für VDR beendet!"

[[ "$nologo" -gt 0 ]] && f_log "==> Für ${nologo} Kanäle wurde kein Logo gefunden"
f_log "==> ${N_LOGO:-0} neue oder aktualisierte Logos (Links zu Logos: ${logocount})"
SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
f_log "==> Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"

if [[ -e "$LOGFILE" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat --format=%s "$LOGFILE")"
  [[ $FILESIZE -gt $MAXLOGSIZE ]] && mv --force "$LOGFILE" "${LOGFILE}.old"
fi

exit 0
