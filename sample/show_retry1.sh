#! /bin/sh
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# show today's retry mail
#
# ex. cat /var/log/maillog | show_retry1.sh
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"; export PATH
#----------------------------------------------------------------- 
#
# smtp_filter1.sh�˵��ݤ���Ƥ���IP���⡢INTERVAL�����ꤷ���ÿ���
# ��ֳ֤�����ƥ����������Ƥ���ʪ��ɽ�����롣
#
# RFC2821(Simple Mail Transfer Protocol)
#
# 4.5.4.1 ������ά 
#
# ��������ΰ���ؤ����������Ԥ����塢���饤����ȤϺ������ٱ䤵��
# �ʤ���Фʤ�ʤ�(MUST)�����̤ˤ��κ����δֳ֤Ͼ��ʤ��Ȥ� 30 ʬ��
# ����٤�(SHOULD)������������ǽ�θ����� SMTP ���饤����Ȥ������
# ������ˤϡ�������٤ǽ������ά��ͭ�פ����� 
#
INTERVAL=`expr 30 \* 60`; export INTERVAL
#
date=`date +'%b %d' | sed -e 's/  *0/ /'`
#
# In : May 23 10:59:35 lib100 smtp_wrapper: [25403] 450 This message was rejected according to site policy(rejected by ip_filter. IP=60.236.0.5)(SL18)
#
cat $* |\
sed -e 's/  */ /g' |\
grep -i "^${date} .*smtp_wrapper.*reject" |\
egrep -v 'rejected by rapidly access' |\
sed -e 's/smtp_wrapper:.*IP=//;s/).*$//;s/:/ /g' |\
sort -t ' ' +6 -7 +2 -5 |\
#
# In : May 23 11 10 04 lib100 61.211.239.162
#
awk 'BEGIN{
	FS = " ";
	ip = "";
	interval = ENVIRON["INTERVAL"]
}
{
	if (ip == ""){
		time = ($3 * 3600) + ($4 * 60) + $5
		ip = $7;
		print ip;
	}else{
		if (ip == $7){
			time_next = ($3 * 3600) + ($4 * 60) + $5
			if ((time_next - time) > interval){
				print $7;
			}
			time = time_next;
		}else{
			time = ($3 * 3600) + ($4 * 60) + $5
			ip = $7;
			print ip;
		}
	}
}
END{
}' |\
sort |\
uniq -d >/tmp/show_retry1.1.$$.tmp
#
for i in `cat /tmp/show_retry1.1.$$.tmp`
do
	echo -n $i " : "
	host $i
done
#
rm -f /tmp/show_retry1.*.$$.tmp
