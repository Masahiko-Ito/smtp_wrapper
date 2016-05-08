#! /bin/sh
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# show today's retry mail
#
# ex. cat /var/log/maillog | show_retry2.sh
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"; export PATH
#-----------------------------------------------------------------
#
# smtp_filter2.sh�˵��ݤ���Ƥ���IP���⡢��ȥ饤���Ƥ���ʪ��ɽ��
# ���롣
#
date=`date +'%b %d' | sed -e 's/  *0/ /'`
#
cat $* |\
sed -e 's/  */ /g' |\
grep -i "^${date} .*smtp_filter.*:MAIL FROM:" |\
cut -d: -f5- |\
sort |\
uniq -d
