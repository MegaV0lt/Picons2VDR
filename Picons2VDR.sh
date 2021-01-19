#!/usr/bin/env bash

# Skript zum erzeugen und verlinken der PICON-Kanallogos (Enigma2)

# Das benötigte GIT wird vom Skript lokal auf die Festplatte geladen
# Die Dateinamen passen nicht zum VDR-Schema. Darum verwendet das Skript
# aus den im GIT enthaltenen index-Dateien, um die Logos dann passend zu verlinken.

# Die Logos werden im PNG-Format erstellt. Die Größe und den optionalen Hintergrund
# kann man in der *.conf einstellen.
# Das Skript am besten ein mal pro Woche ausführen (/etc/cron.weekly)
VERSION=210119

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
  [[ -n "$LOGFILE" ]] && echo "$*" 2>/dev/null >> "$LOGFILE"  # Log in Datei
}

f_trim() {  # Leerzeichen am Anfang und am Ende entfernen
  : "${1#"${1%%[![:space:]]*}"}"
  : "${_%"${_##*[![:space:]]}"}"
  printf '%s\n' "$_"
}

f_create-symlinks() {  # Symlinks erzeugen
  local logo_srp logo_snp
  echo '#!/bin/sh' > "${temp}/create-symlinks.sh"
  chmod 755 "${temp}/create-symlinks.sh"

  mapfile -t servicelist < "${location}/build-output/servicelist-vdr-${style}.txt"  # Liste in Array einlesen
  for line in "${servicelist[@]}" ; do
    IFS='|'
    read -r -a line_data <<< "$line" # ??? tr -d '[=*=]' \
    #serviceref=$(f_trim "${line_data[0]}")
    channel=$(f_trim "${line_data[1]//:/|}")  # Kanalname (Doppelpunkt ersetzen)
    if [[ "${TOLOWER:-ALL}" == 'ALL' ]] ; then
      servicename="${channel,,}"              # Alles in kleinbuchstaben
    else
      servicename="${channel,,[A-Z]}"         # In Kleinbuchstaben (Außer Umlaute)
    fi
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
      echo -e "$msgWRN !=> Kein Logo für $channel (SRP: ${lnk_srp[0]} | SNP: ${lnk_snp[0]}) gefunden!"
      if [[ -n "$LOGFILE" ]] ; then
        f_log "Kein Logo für $channel (SRP: ${lnk_srp[0]} | SNP: ${lnk_snp[0]}) gefunden!"
      fi
      ((nologo++)) ; continue
    fi
    if [[ "$logo_srp" != '--------' && "$logo_snp" != '--------' ]] ; then
      if [[ "$logo_srp" != "$logo_snp" ]] ; then  # Unterschiedliche Logos
        if [[ "${PREFERED_LOGO:=snp}" == 'srp' ]] ; then  # Bevorzugtes Logo verwenden
          logo_snp='--------'
        else
          logo_srp='--------'
        fi
        echo -e "$msgWRN ?=> Unterschiedliche Logos für $channel (SRP: $logo_srp | SNP: ${logo_snp}) gefunden!"
        if [[ -n "$LOGFILE" ]] ; then
          f_log "Unterschiedliche Logos für $channel (SRP: $logo_srp | SNP: ${logo_snp}) gefunden!"
        fi
        ((difflogo++))
      fi
    fi
    if [[ "$servicename" =~ / ]] ; then  # Kanal mit / im Namen
      ch_path="${servicename%/*}"        # Der Teil vor dem lezten /
      mkdir --parents "${LOGODIR}/${ch_path}"
      logos='../logos'
    fi
    if [[ "$logo_srp" != '--------' ]] ; then  #TODO: srp oder snp bevorzugen?
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

# Pfade festlegen
location="${SELF_PATH}/${PICONS_DIR}"  # Pfad vom GIT
logfile=$(mktemp --suffix=.servicelist.log)
temp=$(mktemp -d --suffix=.picons)
echo -e "$msgINF Log-Datei: $logfile"

# Benötigte Variablen prüfen
for var in CHANNELSCONF LOGODIR ; do
  [[ -z "${!var}" ]] && { echo -e "$msgERR Variable $var ist nicht gesetzt!${nc}" >&2 ; exit 1 ;}
done

# Benötigte Programme suchen
commands=(bc column find iconv ln mkdir mv printf readlink rm sed sort)
for cmd in "${commands[@]}" ; do
  if ! command -v "$cmd" &>/dev/null ; then
    missingcommands+=("$cmd")
  fi
done
if [[ -n "${missingcommands[*]}" ]] ; then
  echo -e "$msgERR Fehlende Datei(en): ${missingcommands[*]}${nc}" >&2
  exit 1
fi

# picons.git laden oder aktualisieren
cd "$SELF_PATH" || exit 1
if [[ ! -d "${PICONS_DIR}/.git" ]] ; then
  echo -e "$msgWRN $PICONS_DIR nicht gefunden!"
  echo -e "$msgINF Klone $PICONS_GIT nach $PICONS_DIR"
  echo -e "${msgINF}\n${msgINF} Zum abbrechen Strg-C drücken. Starte in 5 Sekunden…"
  sleep 5
  git clone --depth 1 "$PICONS_GIT" "$PICONS_DIR" || \
    { echo -e "$msgERR Klonen hat nicht funktioniert!" >&2 ; exit 1 ;}
else
  echo -e "$msgINF Aktualisiere Picons in $PICONS_DIR"
  cd "$PICONS_DIR" || exit 1
  git pull >> "$logfile"
  cd "$SELF_PATH" || exit 1
fi

# Stil gültig?
style="${1:-snp}"  # Vorgabe ist snp
if [[ "${style,,}" != 'srp' && "${style,,}" != 'snp' ]] ; then
  echo -e "$msgERR Unbekannter Stil!$nc" >&2
  exit 1
fi

# .index einlesen
#mapfile -t index < "${location}/build-source/${style}.index"
printf -v index '%b\n' ''  # Damit auch das erste Element gefunden wird (=~)
index+=$(<"${location}/build-source/${style}.index")

### VDR Serviceliste erzeugen
if [[ -f "$CHANNELSCONF" ]] ; then
  LC_ALL='C'  # Schnelleres suchen (=~)
  file="${location}/build-output/servicelist-vdr-${style}.txt"
  tempfile=$(mktemp --suffix=.servicelist)
  iconv -f utf-8 -t ascii//translit -c < "$CHANNELSCONF" -o "${temp}/channels.asc" 2>> "$logfile"
  mapfile -t channelnames < "${temp}/channels.asc"  # Kanalliste in ASCII
  channelnames=("${channelnames[@]%%:*}")           # Nur den Kanalnamen (Mit Provider und Kurzname)
  mapfile -t channelsconf < "$CHANNELSCONF"         # Kanalliste in Array einlesen

  for nr in "${!channelsconf[@]}" ; do
    [[ "${channelsconf[nr]:0:1}" == : ]] && { ((grp++)) ; continue ;}  # Kanalgruppe
    [[ "${channelsconf[nr]}" =~ OBSOLETE ]] && { ((obs++)) ; continue ;}  # Als 'OBSOLETE' markierter Kanal
    ((cnt++)) ; echo -ne "$msgINF Konvertiere Kanal #${cnt}"\\r
    IFS=':'
    read -r -a vdrchannel <<< "${channelsconf[nr]}"

    printf -v sid '%X' "${vdrchannel[9]}"
    printf -v tid '%X' "${vdrchannel[11]}"
    printf -v nid '%X' "${vdrchannel[10]}"

    case ${vdrchannel[3]} in
      *'W') namespace=$(bc -l <<< "scale=0 ; 3600 - ${vdrchannel[3]//[^0-9.]} * 10")
            printf -v namespace '%X' "${namespace%.*}" ;;
      *'E') namespace=$(bc -l <<< "scale=0 ; ${vdrchannel[3]//[^0-9.]} * 10")
            printf -v namespace '%X' "${namespace%.*}" ;;
       'T') namespace='EEEE' ;;
       'C') namespace='FFFF' ;;
    esac
    case ${vdrchannel[5]} in
        '0') channeltype='2' ;;
      *'=2') channeltype='1' ;;
     *'=27') channeltype='19' ;;
    esac

    unique_id="${sid}_${tid}_${nid}_${namespace}"
    serviceref="1_0_${channeltype}_${unique_id}0000_0_0_0"
    serviceref_id="${unique_id}0000"
    IFS=';'
    read -r -a channelname <<< "${vdrchannel[0]}"
    read -r -a snpchannelname <<< "${channelnames[nr]}"  # ASCII
    IFS="$OLDIFS"
    vdr_channelname="${channelname[0]%,*}"     # Kanalname ohne Kurzname
    vdr_channelname="${vdr_channelname//|/:}"  # | durch : ersetzen

    # sed -e 's/^[ \t]*//' -e 's/|//g' -e 's/^//g')
    snpchannelname[0]="${snpchannelname[0]%,*}"
    snpchannelname[0]="${snpchannelname[0]//[[:space:]]}"
    snpchannelname[0]="${snpchannelname[0]//|}"

    #logo_srp=$(grep -i -m 1 "^$unique_id" <<< "$index")  # | sed -n -e 's/.*=//p')
    #logo_srp="${logo_srp#*=}"
    re="[[:space:]]${unique_id}([^[:space:]]*)"
    [[ "$index" =~ $re ]] && { logo_srp="${BASH_REMATCH[0]#*=}" ;} || logo_srp='--------'
    #[[ -z "$logo_srp" ]] && logo_srp='--------'

    if [[ "$style" == 'snp' ]] ; then
      #snpname=$(sed -e 's/&/and/g' -e 's/*/star/g' -e 's/+/plus/g' -e 's/\(.*\)/\L\1/g' -e 's/[^a-z0-9]//g' <<< "${snpchannelname[0]}")
      snpname="${snpchannelname[0]//\&/and}" ; snpname="${snpname//'*'/star}" ; snpname="${snpname//+/plus}"
      snpname="${snpname,,}" ; snpname="${snpname//[^a-z0-9]}"
      if [[ -n "$snpname" ]] ; then
        #logo_snp=$(grep -i -m 1 "^$snpname=" <<< "$index")  # | sed -n -e 's/.*=//p')
        #logo_snp="${logo_snp#*=}"
        re="[[:space:]]${snpname}=([^[:space:]]*)"
        [[ "$index" =~ $re ]] && { logo_snp="${BASH_REMATCH[1]}" ;} || logo_snp='--------'
      else
        snpname='--------'
      fi
      #[[ -z "$logo_snp" ]] && logo_snp='--------'
      echo -e "${serviceref}\t${vdr_channelname}\t${serviceref_id}=${logo_srp}\t${snpname}=${logo_snp}" >> "$tempfile"
    else
      echo -e "${serviceref}\t${vdr_channelname}\t${serviceref_id}=${logo_srp}" >> "$tempfile"
    fi
  done
  #sort -t $'\t' -k 2,2 "$tempfile" | sed -e 's/\t/^|/g' | column -t -s $'^' | sed -e 's/|/  |  /g' > "$file"
  sort -t $'\t' -k 2,2 "$tempfile" | sed -e 's/\t/  |  /g' > "$file"
  rm "$tempfile"
  echo -e "\n$msgINF Serviceliste exportiert nach $file"
else
  echo -e "$msgERR $CHANNELSCONF nicht gefunden!${nc}" >&2
  exit 1
fi

### Icons mit Hintergrund erstellen ###

logfile=$(mktemp --suffix=.picons.log)
echo -e "$msgINF Log-Datei: $logfile"

if command -v pngquant &>/dev/null ; then
  pngquant='pngquant'
  echo -e "$msgINF Bildkomprimierung aktiviert!"
else
  pngquant='cat'
  echo -e "$msgWRN Bildkomprimierung deaktiviert! \"pngquant\" installieren!"
  f_log "Bildkomprimierung deaktiviert! \"pngquant\" installieren!"
fi

if command -v convert &>/dev/null ; then
  echo -e "$msgINF ImageMagick gefunden!"
else
  echo -e "$msgERR ImageMagick nicht gefunden! \"ImageMagick\" installieren!" >&2
  exit 1
fi

: SVGCONVERTER="${SVGCONVERTER:=rsvg}"  # Vorgabe ist rsvg
if command -v inkscape &>/dev/null && [[ "${SVGCONVERTER,,}" == 'inkscape' ]] ; then
  svgconverter='inkscape -w 850 --without-gui --export-area-drawing --export-png='
  echo -e "$msgINF Verwende Inkscape als SVG-Konverter!"
elif command -v rsvg-convert &>/dev/null && [[ "${SVGCONVERTER,,}" = 'rsvg' ]] ; then
  svgconverter=('rsvg-convert' -w 1000 --keep-aspect-ratio --output)
  echo -e "$msgINF Verwende rsvg als SVG-Konverter!"
else
  echo -e "$msgERR SVG-Konverter: ${SVGCONVERTER} nicht gefunden!$nc" >&2
  exit 1
fi

# Prüfen ob Serviceliste existiert
for file in "$location"/build-output/servicelist-*-"$style".txt ; do
  if [[ ! -f "$file" ]] ; then
    echo -e "$msgERR Keine $style Serviceliste gefunden!$nc" >&2
    exit 1
  fi
done

# Einfache Prüfung der Quellen
if [[ $- == *i* ]] ; then
  echo -e "$msgINF Überprüfe index…"
  "$location/resources/tools/check-index.sh" "$location/build-source srp"
  "$location/resources/tools/check-index.sh" "$location/build-source snp"

  echo -e "$msgINF Überprüfe logos…"
  "$location/resources/tools/check-logos.sh" "$location/build-source/logos"
fi

# Datei 'create-symlinks.sh' erstellen
echo -e "$msgINF Erzeuge Datei \"create-symlinks.sh\"…"
f_create-symlinks

# Konvertierung der Logos
logocount="${#logocollection[@]}"
mkdir --parents "${temp}/cache" || { echo "Fehler beim erzeugen von ${temp}/cache" >&2 ; exit 1 ;}
[[ ! -d "${LOGODIR}/logos" ]] && { mkdir --parents "${LOGODIR}/logos" || exit 1 ;}

resolution="${LOGO_CONF[0]:=220x132}"  # Hintergrundgröße
resize="${LOGO_CONF[1]:=200x112}"      # Logogröße
type="${LOGO_CONF[2]:=dark}"           # Typ (dark/light)
background="${LOGO_CONF[3]:=transparent}"  # Hintergrund (transparent/blue/...)

echo -e "$msgINF Erzeuge Logos: ${style}.${resolution}-${resize}.${type}.on.${background}…"
for logoname in "${logocollection[@]}" ; do
  ((currentlogo++))
  echo -ne "$msgINF Konvertiere Logo: ${currentlogo}/${logocount}"\\r

  if [[ -f "${location}/build-source/logos/${logoname}.${type}.png" || -f "${location}/build-source/logos/${logoname}.${type}.svg" ]] ; then
    logotype="$type"
  else
    logotype='default'
  fi

  echo "--> ${logoname}.${logotype}" >> "$logfile"

  if [[ -f "${location}/build-source/logos/${logoname}.${logotype}.svg" ]] ; then
    ((svg++))
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "${location}/build-source/logos/${logoname}.${logotype}.svg" ]] && continue  # Nur erstellen wenn neuer
    logo="${temp}/cache/${logoname}.${logotype}.png"
    if [[ ! -f "$logo" ]] ; then
      "${svgconverter[@]}" "${logo}" "${location}/build-source/logos/${logoname}.${logotype}.svg" &>> "$logfile"
    fi
  else
    ((png++))
    logo="${location}/build-source/logos/${logoname}.${logotype}.png"
    [[ "${LOGODIR}/logos/${logoname}.png" -nt "$logo" ]] && continue  # Nur erstellen wenn neuer
  fi

  # Hintergrund vorhanden?
  if [[ ! -f "${location}/build-source/backgrounds/${resolution}/${background}.png" ]] ; then
    echo -e "$msgWRN Hintergrund fehlt! (${location}/build-source/backgrounds/${resolution}/${background}.png)"
  fi

  # Erstelle Logo mit Hintergrund
  convert "${location}/build-source/backgrounds/${resolution}/${background}.png" \
    \( "$logo" -background none -bordercolor none -border 100 -trim -border 1% -resize "$resize" -gravity center -extent "$resolution" +repage \) \
    -layers merge - 2>> "$logfile" \
    | "$pngquant" - 2>> "$logfile" > "${LOGODIR}/logos/${logoname}.png"
  ((N_LOGO++))
done

cd "$LOGODIR" || exit 1
echo -e "\n${msgINF} Verlinke Kanallogos…"
"${temp}/create-symlinks.sh"

find "$LOGODIR" -xtype l -delete &>> "${LOGFILE:-/dev/null}"  # Alte (defekte) Symlinks löschen

if [[ -d "$temp" ]] ; then rm --recursive --force "$temp" ; fi

echo -e "$msgINF Erstellen von Logos (${style}) beendet!"

# Statistik anzeigen
[[ "$nologo" -gt 0 ]] && f_log "==> Kanäle ohne Logo: $nologo"
[[ "$difflogo" -gt 0 ]] && f_log "==> Kanäle mit unterschiedliche Logos: $difflogo (Vorgabe: ${PREFERED_LOGO})"
[[ "$obs" -gt 0 ]] && f_log "==> Als 'OBSOLETE' markierte Kanäle: $obs"
f_log "==> $((svg + png)) Logos: $svg im SVG-Format und $png im PNG-Format"
f_log "==> ${N_LOGO:-0} neue(s) oder aktualisierte(s) Logo(s) (Links zu Logos: ${logocount})"
SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
f_log "==> Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"

if [[ -e "$LOGFILE" ]] ; then  # Log-Datei umbenennen, wenn zu groß
  FILESIZE="$(stat --format=%s "$LOGFILE")"
  [[ $FILESIZE -gt $MAXLOGSIZE ]] && mv --force "$LOGFILE" "${LOGFILE}.old"
fi

exit 0
