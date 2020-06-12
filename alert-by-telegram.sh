#!/bin/bash
set -euo pipefail
# /etc/icinga2/scripts/service-by-telegram.sh
# Marianne M. Spiller <github@spiller.me>
# Last updated 2020-06-11
# Last tests used icinga2-2.11.2-1.buster

PROG="$(basename $0)"
HOSTNAME="$(hostname)"
TRANSPORT="curl"
unset DEBUG

if [[ -z "$(command -v $TRANSPORT)" ]]; then
	echo "$TRANSPORT not in \$PATH. Consider installing it."
	exit 1
fi

Usage() {
cat << EOF
alert-by-telegram notification script for Icinga 2 by spillerm <github@spiller.me>

The following are mandatory:
  -a ALERTTYPE (host or service)
  -d LONGDATETIME (\$icinga.long_date_time$)
  -e SERVICENAME (\$service.name$ Only if ALERTTYPE is service) # TODO, currently unused
  -l HOSTALIAS (\$host.name$)
  -n HOSTDISPLAYNAME (\$host.display_name$)
  -o SERVICEOUTPUT (\$service.output$ or \$host.output$)
  -q TELEGRAM_CHATID (\$telegram_chatid$)
  -r TELEGRAM_BOTTOKEN (\$telegram_bottoken$)
  -s SERVICESTATE (\$service.state$ or \$host.state$)
  -t NOTIFICATIONTYPE (\$notification.type$)
  -u SERVICEDISPLAYNAME (\$service.display_name$)

And these are optional:
  -4 HOSTADDRESS (\$address$)
  -6 HOSTADDRESS6 (\$address6$)
  -b NOTIFICATIONAUTHORNAME (\$notification.author$)
  -c NOTIFICATIONCOMMENT (\$notification.comment$)
  -i HAS_ICINGAWEB2 (\$icingaweb2url$, Default: unset)
  -v (\$notification_logtosyslog$, Default: false)
  -p TELEGRAM_BOT (\$telegram_bot$)
  -D DEBUG enable debug output - meant for CLI debug only
EOF
}

while getopts 4:6:a:b:c:d:e:f:hi:l:n:o:p:q:r:s:t:u:v:D opt; do
	case "$opt" in
		4) HOSTADDRESS=$OPTARG ;;
		6) HOSTADDRESS6=$OPTARG ;;
		a) ALERTTYPE=$OPTARG ;;
		b) NOTIFICATIONAUTHORNAME=$OPTARG ;;
		c) NOTIFICATIONCOMMENT=$OPTARG ;;
		d) LONGDATETIME=$OPTARG ;;
		e) SERVICENAME=$OPTARG ;;
		h) Usage; exit 0;;
		i) HAS_ICINGAWEB2=$OPTARG ;;
		l) HOSTALIAS=$OPTARG ;;
		n) HOSTDISPLAYNAME=$OPTARG ;;
		o) SERVICEOUTPUT=$OPTARG ;;
		p) TELEGRAM_BOT=$OPTARG ;;
		q) TELEGRAM_CHATID=$OPTARG ;;
		r) TELEGRAM_BOTTOKEN=$OPTARG ;;
		s) SERVICESTATE=$OPTARG ;;
		t) NOTIFICATIONTYPE=$OPTARG ;;
		u) SERVICEDISPLAYNAME=$OPTARG ;;
		v) VERBOSE=$OPTARG ;;
		D) DEBUG=1; echo -e "\n**********************************************\nWARNING: DEBUG MODE, DEACTIVATE ASAP\n**********************************************\n" ;;
		\?) echo "ERROR: Invalid option -$OPTARG" >&2
			Usage; exit 1;;
		:) echo "Missing option argument for -$OPTARG" >&2
			Usage; exit 1;;
		*) echo "Unimplemented option: -$OPTARG" >&2
			Usage; exit 1;;
	esac
done

if [[ ${ALERTTYPE-} != "host" ]] && [[ ${ALERTTYPE-} != "service" ]]; then
	Usage
	echo ""
	echo "ALERTTYPE needs to be either 'host' or 'service'!"
	exit 1
fi

if [[ $ALERTTYPE == "host" ]]; then
	echo ""
else
	if [[ -z ${SERVICENAME-} ]] || [[ -z ${SERVICEDISPLAYNAME-} ]]; then
		Usage
		exit 1
	fi
fi

if [[ -z ${LONGDATETIME-} ]]      || [[ -z ${HOSTALIAS-} ]]       || [[ -z ${HOSTDISPLAYNAME-} ]] \
	|| [[ -z ${SERVICEOUTPUT-} ]]   || [[ -z ${TELEGRAM_CHATID-} ]] || [[ -z ${TELEGRAM_BOTTOKEN-} ]] \
	|| [[ -z ${SERVICESTATE-} ]]    || [[ -z ${NOTIFICATIONTYPE-} ]]; then
	Usage
	exit 1
fi

## Build the message's subject
if [[ $ALERTTYPE == "host" ]]; then
	SUBJECT="[$NOTIFICATIONTYPE] Host $HOSTDISPLAYNAME is $SERVICESTATE!"
else
	SUBJECT="[$NOTIFICATIONTYPE] $SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE!"
fi

## Build the message itself
if [[ $ALERTTYPE == "host" ]]; then
	NOTIFICATION_MESSAGE=$(cat << EOF
<u>[$SERVICESTATE] $HOSTDISPLAYNAME ($HOSTALIAS) - at $LONGDATETIME</u>
EOF
)
else
	NOTIFICATION_MESSAGE=$(cat << EOF
<u>[$SERVICESTATE] $SERVICEDISPLAYNAME - at $LONGDATETIME</u>
<b>Host:</b> <code>$HOSTALIAS</code>
EOF
)
fi

if [[ -n "${HOSTADDRESS-}" ]]; then
	NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
<b>IPv4:</b> <code>$HOSTADDRESS</code>"
fi

if [[ -n "${HOSTADDRESS6-}" ]]; then
	NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
<b>IPv6:</b> <code>$HOSTADDRESS6</code>"
fi

NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

<b>Output:</b> <code>$SERVICEOUTPUT</code>"

## Are there any comments? Put them into the message!
if [[ -n "${NOTIFICATIONCOMMENT-}" ]] ; then
	NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

<b>Comment by $NOTIFICATIONAUTHORNAME:</b> <code>$NOTIFICATIONCOMMENT</code>"
fi

## Are we using Icinga Web 2? Put the URL into the message!
if [[ -n "${HAS_ICINGAWEB2-}" ]] ; then
	NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
<b>Get live status:</b> <code>$HAS_ICINGAWEB2/monitoring/host/show?host=$HOSTALIAS</code>"
fi

## Are we verbose? Then put a message to syslog...
if [[ "${VERBOSE-}" == "true" ]] ; then
	logger "$PROG sends $SUBJECT => Telegram Channel $TELEGRAM_BOT"
fi

## debug output or not?
if [[ -z ${DEBUG-} ]]; then
	CURLARGS="--silent --output /dev/null"
else
	CURLARGS=-v
	set -x
	echo -e "DEBUG MODE!"
fi

## And finally, send the message
/usr/bin/curl $CURLARGS \
	--data-urlencode "chat_id=${TELEGRAM_CHATID}" \
	--data-urlencode "text=${NOTIFICATION_MESSAGE}" \
	--data-urlencode "parse_mode=HTML" \
	--data-urlencode "disable_web_page_preview=true" \
	"https://api.telegram.org/bot${TELEGRAM_BOTTOKEN}/sendMessage"
