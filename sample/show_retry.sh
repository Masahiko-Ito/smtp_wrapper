#! /bin/sh
#
# This part of smtp_wrapper-0.2 is distributed under GNU General Public License.
#
# show today's retry mail
#
# ex. cat /var/log/maillog | show_retry.sh
#
date=`date +'%b %d' | sed -e 's/  *0/ /'`
#
cat $* |\
sed -e 's/  */ /g' |\
grep -i "^${date} .*smtp_filter.*:MAIL FROM:" |\
cut -d: -f5- |\
sort |\
uniq -d
