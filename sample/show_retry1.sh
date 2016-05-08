#! /bin/sh
#
# This part of smtp_wrapper is distributed under GNU General Public License.
#
# show today's retry mail
#
# ex. cat /var/log/maillog | show_retry1.sh
#
PATH="/usr/local/smtp_wrapper:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"; export PATH
tmp="/tmp"
#----------------------------------------------------------------- 
#
# ������Ρ����������ƤΥ�����������ݤ���Ƥ���IP���⡢
# INTERVAL�����ꤷ���ÿ��ʾ�ֳ֤�����ƥ����������Ƥ�
# ��ʪ��ɽ�����롣
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
# ������Ρ�IP��ޤ��(����|����)��å����������[1]
cat $* |\
sed -e 's/  */ /g' |\
egrep -i "^${date} .*smtp_wrapper.*rejected by|^${date} .*smtp_wrapper.*child start" >${tmp}/show_retry1.1.$$.tmp
#
# ���ե�å���������и������IP����С��Խ�[2]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i 'child start' |\
sed -e 's/^.*IP=//;s/(.*$//' |\
sort |\
uniq -c |\
grep -v  '^ *1 ' |\
sort >${tmp}/show_retry1.2.$$.tmp
#
# ���ݥ�å���������и������IP����С��Խ�[3]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i 'rejected by' |\
sed -e 's/^.*IP=//;s/).*$//' |\
sort |\
uniq -c |\
sort >${tmp}/show_retry1.3.$$.tmp
#
# ���ղ���ȵ��ݲ����������(�Ĥޤ괰���˵��ݤ���Ƥ���)IP�����[4]
join -t "," ${tmp}/show_retry1.2.$$.tmp ${tmp}/show_retry1.3.$$.tmp |\
sed -e 's/^ *//' |\
cut -d ' ' -f 2 |\
sort >${tmp}/show_retry1.4.$$.tmp
#
# ���ݥ�å������δֳ֤�INTERVAL�ðʾ��IP��С��Խ�[5]
cat ${tmp}/show_retry1.1.$$.tmp |\
grep -i "smtp_wrapper.*rejected by" |\
sed -e 's/smtp_wrapper:.*IP=//;s/).*$//;s/:/ /g' |\
sort -t ' ' +6 -7 +2 -5 |\
#
# In : May 23 11 10 04 lib100 61.211.239.162
#
awk 'BEGIN{
	FS = " ";
	ip = "";
	rapid = "";
	interval = ENVIRON["INTERVAL"]
}
{
	if (ip == ""){
		time = ($3 * 3600) + ($4 * 60) + $5
		ip = $7;
		rapid = "";
	}else{
		if (ip == $7){
			time_next = ($3 * 3600) + ($4 * 60) + $5
			if (rapid == "YES"){
				/* do nothing */;
			}else{
				if ((time_next - time) < interval){
					rapid = "YES";
				}else{
					rapid = "NO";
				}
			}
			time = time_next;
		}else{
			if (rapid == "NO"){
				print ip;
			}
			time = ($3 * 3600) + ($4 * 60) + $5
			ip = $7;
			rapid = "";
		}
	}
}
END{
	if (rapid == "NO"){
		print ip;
	}
}' >${tmp}/show_retry1.5.$$.tmp
#
# [4][5]�ޥå��󥰤��ơ����Ƥμ��դ�INTERVAL�ðʾ�δֳ֤ǵ��ݤ���Ƥ���IP�����[6]
join ${tmp}/show_retry1.4.$$.tmp ${tmp}/show_retry1.5.$$.tmp >${tmp}/show_retry1.6.$$.tmp
#
# [6]��DNS�հ���̤��ղä���ɽ��
for i in `cat ${tmp}/show_retry1.6.$$.tmp`
do
	echo -n $i " : "
	host $i
done
#
rm -f ${tmp}/show_retry1.*.$$.tmp
