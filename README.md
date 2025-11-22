# Picons2VDR
Picons für den VDR

Skript zum erzeugen und verlinken der PICON-Kanallogos (Enigma2)

Die Dateinamen der Picons passen nicht zum VDR-Schema. Darum verwendet das Skript die im GIT enthaltenen index-Dateien (srp.index und tf8snp.index), um die Logos dann mit hilfe der "channels.conf" vom VDR passend zu verlinken.

Das benötigte GIT (https://github.com/picons/picons.git) wird vom Skript lokal in einem Unterordner auf die Festplatte geladen und bei jedem Start automatisch aktualisiert.

Das Sktipt selbst kann via 'AUTO_UPDATE=true' ebenfalls automatisch aktualisiert werden.

Im VDR-Logoverzeichnis wird ein Ordner ".logos" angelegt, der die vom Skript erzeugten Kanallogos enthält.
Es werden Symlinks erstellt, die dem VDR-Schema entsprechen.

Vorgabe für das Skript ist utf8snp. Die Logos werden im entsprechenden Index gesucht. Es ist möglich, dass der Index Logos im SRP oder SNP-Format enthält. Falls im 'utf8snp'-Modus zuerst das SRP-Logo gefunden wird und zusätzlich das SNP-Logo, dann wird das vorgegebene (PREFERED_LOGO) Logo verwendet.

Die Logos können mit Hintergrundgrafik erstellt werden. Die Größe und der Stil sind einstellbar. Liste der Hintergründe (picons.git/build-source/backgrounds):

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

