# Picons2VDR
Picons für den VDR

Skript zum erzeugen und verlinken der PICON-Kanallogos (Enigma2)

Das benötigte GIT (https://github.com/picons/picons.git) wird vom
Skript lokal in einem Unterordner auf die Festplatte geladen und bei
jedem Start aktualisiert.

Die Dateinamen der Picons passen nicht zum VDR-Schema. Darum verwendet das Skript
die im GIT enthaltenen index-Dateien (snp.index), um die Logos dann mit hilfe der
"channels.conf" passend zu verlinken.

Im VDR-Logoverzeichnis wird ein Ordner "logos" angelegt, der die Kanallogos enthält.
Es werden Symlinks erstellt, die dem VDR-Schema entsprechen.

Die Logos können mit Hintergrundgrafik erstellt werden. Die Größe und der Stil
sind einstellbar. Liste der Hintergründe:

_70x53:_
black, blue, reflection, transparent, white

_100x60:_
black, blue, reflection, transparent, white

_220x132:_
black, blue, reflection, transparent, white

_256x256:_
grey, reflection, transparent

_400x170:_
transparent

_400x240:_
blue, transparent

_800x450:_
transparent

